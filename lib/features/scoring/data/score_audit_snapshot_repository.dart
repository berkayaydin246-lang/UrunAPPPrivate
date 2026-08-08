import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';

enum ScoreAuditTriggerSource {
  submissionApproval('submission_approval'),
  stagingApproval('staging_approval'),
  verifiedCorrection('verified_correction'),
  catalogueChange('catalogue_change'),
  controlledBackfill('controlled_backfill');

  const ScoreAuditTriggerSource(this.databaseValue);

  final String databaseValue;
}

class ScoreAuditSnapshotWriteResult {
  const ScoreAuditSnapshotWriteResult({
    required this.snapshotId,
    required this.inserted,
  });

  final String snapshotId;
  final bool inserted;
}

abstract interface class ScoreAuditSnapshotRepository {
  Future<EtiketlyScoreAuditSnapshot?> fetchCurrent(String productId);

  Future<ScoreAuditSnapshotWriteResult> insertTrusted(
    EtiketlyScoreAuditSnapshot snapshot, {
    required ScoreAuditTriggerSource triggerSource,
  });
}

class SupabaseScoreAuditSnapshotRepository
    implements ScoreAuditSnapshotRepository {
  const SupabaseScoreAuditSnapshotRepository();

  @override
  Future<EtiketlyScoreAuditSnapshot?> fetchCurrent(String productId) async {
    final response = await SupabaseService.client.rpc(
      'get_current_product_score_audit_snapshot',
      params: {'p_product_id': productId},
    );
    if (response == null) return null;
    final snapshot = EtiketlyScoreAuditSnapshot.tryFromJson(response);
    if (snapshot == null) {
      throw const FormatException('Malformed score audit snapshot response.');
    }
    return snapshot;
  }

  @override
  Future<ScoreAuditSnapshotWriteResult> insertTrusted(
    EtiketlyScoreAuditSnapshot snapshot, {
    required ScoreAuditTriggerSource triggerSource,
  }) async {
    final response = await SupabaseService.client.rpc(
      'record_product_score_audit_snapshot',
      params: {
        'p_product_id': snapshot.productId,
        'p_input_fingerprint': snapshot.inputFingerprint,
        'p_snapshot_schema_version': snapshot.schemaVersion,
        'p_score_version': snapshot.scoreVersion,
        'p_nutrition_methodology_version': snapshot.nutritionMethodologyVersion,
        'p_nutrition_transform_version': snapshot.nutritionTransformVersion,
        'p_additive_transform_version': snapshot.additiveTransformVersion,
        'p_trigger_source': triggerSource.databaseValue,
        'p_snapshot': snapshot.toJson(),
      },
    );
    final json = _asMap(response);
    final snapshotId = json?['snapshot_id'];
    final inserted = json?['inserted'];
    if (snapshotId is! String || inserted is! bool) {
      throw const FormatException('Malformed score audit write response.');
    }
    return ScoreAuditSnapshotWriteResult(
      snapshotId: snapshotId,
      inserted: inserted,
    );
  }
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) return null;
  return value.map((key, value) => MapEntry(key.toString(), value));
}
