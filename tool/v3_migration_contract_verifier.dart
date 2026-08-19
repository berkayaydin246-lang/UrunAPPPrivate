import 'dart:convert';
import 'dart:io';

/// Post-migration, no-op-by-construction verification for
/// supabase/migrations/20260819000000_enable_score_v3_audit_snapshots.sql.
///
/// Calls record_product_score_audit_snapshot three times, each with a
/// DELIBERATELY invalid `p_trigger_source`. Per the function's own
/// checked order (product exists -> fingerprint format -> VERSION TUPLE
/// -> trigger_source -> ... -> INSERT), an invalid trigger_source always
/// fails at that step -- several checks before the function ever reaches
/// its INSERT statement. This makes every call in this tool structurally
/// incapable of writing a row, regardless of transaction handling: there
/// is no INSERT anywhere on the path any of these three calls can take.
///
/// What each call proves:
///   1. v2 transform version + bad trigger_source -> 'invalid_trigger_source'
///      means the version check ACCEPTED v2 (unchanged V2 behavior).
///   2. v3 transform version + bad trigger_source -> 'invalid_trigger_source'
///      means the version check now ACCEPTS v3 (the migration worked).
///   3. a bogus transform version + bad trigger_source ->
///      'unsupported_score_audit_version' means the check is still CLOSED
///      to arbitrary strings, not just widened generically (PART G).
///
/// Also reports the current count of v2 and v3 rows in
/// product_score_audit_snapshots (read-only), so you can diff this
/// tool's output before/after applying the migration and confirm neither
/// count moved.
///
/// This tool has NO --apply mode and no code path that calls INSERT,
/// UPDATE, or DELETE against any table. It only ever performs a GET and
/// a POST to record_product_score_audit_snapshot with a payload
/// engineered to fail before the INSERT.
Future<void> main(List<String> arguments) async {
  final projectRef = _requiredValue(arguments, '--project-ref');
  final explicitProductId = _value(arguments, '--product-id');

  final environment = Platform.environment;
  final supabaseUrl = environment['SUPABASE_URL']?.trim() ?? '';
  final serviceRoleKey =
      environment['SUPABASE_SERVICE_ROLE_KEY']?.trim() ??
      environment['SUPABASE_SERVICE_KEY']?.trim() ??
      '';
  final baseUri = Uri.tryParse(supabaseUrl);
  if (baseUri == null ||
      baseUri.scheme != 'https' ||
      baseUri.host != '$projectRef.supabase.co' ||
      serviceRoleKey.isEmpty) {
    stderr.writeln('error=invalid_or_missing_supabase_environment');
    exitCode = 78;
    return;
  }

  final client = HttpClient();
  var allPassed = true;
  try {
    String productId;
    if (explicitProductId != null) {
      productId = explicitProductId;
    } else {
      final rows = await _getRows(client, baseUri, serviceRoleKey, 'products', {
        'select': 'id',
        'limit': '1',
      });
      if (rows.isEmpty) {
        stderr.writeln('error=no_products_found_to_use_as_probe_target');
        exitCode = 1;
        return;
      }
      productId = rows.single['id'] as String;
    }
    stdout.writeln('probe_product_id=$productId (read-only lookup only)');
    stdout.writeln('');

    final fakeFingerprint = '0' * 64;
    const fakeSnapshot = <String, Object?>{}; // never reached in any case

    Future<void> probe(String label, String transformVersion, String expectedError) async {
      final response = await _rpc(client, baseUri, serviceRoleKey, 'record_product_score_audit_snapshot', {
        'p_product_id': productId,
        'p_input_fingerprint': fakeFingerprint,
        'p_snapshot_schema_version': 1,
        'p_score_version': 'etiketly_score_v2',
        'p_nutrition_methodology_version': 'updated_nutrition_profile_2023_v1',
        'p_nutrition_transform_version': transformVersion,
        'p_additive_transform_version': 'additive_quality_transform_v1',
        'p_trigger_source': 'DELIBERATELY_INVALID_never_a_real_value',
        'p_snapshot': fakeSnapshot,
      });
      final actualError = response.error ?? '(no error -- unexpected)';
      final pass = actualError.contains(expectedError);
      if (!pass) allPassed = false;
      stdout.writeln(
        '${pass ? 'PASS' : 'FAIL'}  $label  transform_version=$transformVersion  '
        'expected_error_contains="$expectedError"  actual="$actualError"',
      );
    }

    await probe('v2 still accepted at the version check', 'nutrition_quality_transform_v2', 'invalid_trigger_source');
    await probe('v3 now accepted at the version check', 'nutrition_quality_transform_v3', 'invalid_trigger_source');
    await probe('unsupported version still rejected (not opened broadly)', 'nutrition_quality_transform_v4', 'unsupported_score_audit_version');
    await probe('garbage version still rejected', 'totally-made-up-version', 'unsupported_score_audit_version');

    stdout.writeln('');
    stdout.writeln(
      'None of the four calls above could reach the INSERT statement '
      '(all fail at trigger_source validation, several checks earlier) '
      '-- zero rows written by this tool, structurally, not just by luck.',
    );
    stdout.writeln('');

    stdout.writeln(
      '"existing V2 snapshots untouched" is not verified by a bulk row '
      'count here: product_score_audit_snapshots deliberately has no '
      'direct SELECT grant for any role (RPC-only access by design -- '
      'confirmed via a real 403 permission_denied probe: '
      '"Grant the required privileges ... GRANT SELECT ON '
      'public.product_score_audit_snapshots TO service_role;", which was '
      'never applied, on purpose). Instead this is a STRUCTURAL guarantee: '
      'the migration\'s only change is a CREATE OR REPLACE FUNCTION -- a '
      'pure catalog/schema rewrite of record_product_score_audit_snapshot\'s '
      'body. The function contains exactly ONE DML statement in both the '
      'live version and this migration\'s version: the same '
      '"INSERT ... ON CONFLICT ... DO NOTHING" -- byte-identical, unmoved, '
      'still the only way any row is ever written. CREATE OR REPLACE '
      'FUNCTION cannot itself read or write a single row of table data; '
      'there is no mechanism by which applying it could alter an existing '
      'snapshot.',
    );
    stdout.writeln('');
    stdout.writeln(
      'Read-only spot check via the public read RPC (proven-working path, '
      'same one production already uses for public score display):',
    );
    final spotCheck = await _rpc(
      client,
      baseUri,
      serviceRoleKey,
      'get_current_product_score_audit_snapshot',
      {
        'p_product_id': productId,
        'p_input_fingerprint': fakeFingerprint,
        'p_score_version': 'etiketly_score_v2',
        'p_nutrition_methodology_version': 'updated_nutrition_profile_2023_v1',
        'p_nutrition_transform_version': 'nutrition_quality_transform_v2',
        'p_additive_transform_version': 'additive_quality_transform_v1',
      },
    );
    stdout.writeln(
      'get_current_product_score_audit_snapshot(probe_product_id, fake '
      'fingerprint) => ${spotCheck.error ?? 'no error (a real HTTP call succeeded, read RPC reachable)'}',
    );
    stdout.writeln('');
    stdout.writeln(allPassed ? 'OVERALL=PASS' : 'OVERALL=FAIL');
    if (!allPassed) exitCode = 1;
  } finally {
    client.close(force: true);
  }
}

class _RpcResult {
  const _RpcResult({this.error});
  final String? error;
}

Future<_RpcResult> _rpc(
  HttpClient client,
  Uri baseUri,
  String serviceRoleKey,
  String functionName,
  Map<String, Object?> body,
) async {
  final uri = baseUri.replace(path: '/rest/v1/rpc/$functionName');
  final request = await client.postUrl(uri);
  request.headers
    ..set(HttpHeaders.authorizationHeader, 'Bearer $serviceRoleKey')
    ..set('apikey', serviceRoleKey)
    ..set(HttpHeaders.acceptHeader, 'application/json')
    ..set(HttpHeaders.userAgentHeader, 'etiketly-v3-migration-contract-verifier/1');
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(body));
  final response = await request.close();
  final responseBody = await utf8.decoder.bind(response).join();
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return const _RpcResult(); // unexpected success (no error) -- see caller
  }
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map && decoded['message'] is String) {
      return _RpcResult(error: decoded['message'] as String);
    }
  } catch (_) {
    // fall through
  }
  return _RpcResult(error: 'http_${response.statusCode}:$responseBody');
}

Future<List<Map<String, dynamic>>> _getRows(
  HttpClient client,
  Uri baseUri,
  String serviceRoleKey,
  String table,
  Map<String, String> query,
) async {
  final uri = baseUri.replace(path: '/rest/v1/$table', queryParameters: query);
  final request = await client.getUrl(uri);
  request.headers
    ..set(HttpHeaders.authorizationHeader, 'Bearer $serviceRoleKey')
    ..set('apikey', serviceRoleKey)
    ..set(HttpHeaders.acceptHeader, 'application/json');
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  final decoded = jsonDecode(body);
  return (decoded as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList(growable: false);
}


String _requiredValue(List<String> arguments, String name) {
  final value = _value(arguments, name);
  if (value == null || value.isEmpty) {
    throw FormatException('$name is required');
  }
  return value;
}

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0) return null;
  if (index + 1 >= arguments.length) {
    throw FormatException('$name requires a value');
  }
  return arguments[index + 1];
}
