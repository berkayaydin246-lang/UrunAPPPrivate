bool isSupabaseFunctionsUrl(String baseUrl) {
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null) return false;

  final segments = uri.pathSegments;
  for (var index = 0; index < segments.length - 1; index += 1) {
    if (segments[index] == 'functions' && segments[index + 1] == 'v1') {
      return true;
    }
  }
  return false;
}

Map<String, dynamic> buildOcrRequestHeaders({
  required String baseUrl,
  String backendApiKey = '',
  String supabaseAnonKey = '',
}) {
  final headers = <String, dynamic>{'Content-Type': 'application/json'};

  if (isSupabaseFunctionsUrl(baseUrl)) {
    final anonKey = supabaseAnonKey.trim();
    if (anonKey.isNotEmpty) {
      headers['apikey'] = anonKey;
      headers['Authorization'] = 'Bearer $anonKey';
    }
    return headers;
  }

  final directBackendKey = backendApiKey.trim();
  if (directBackendKey.isNotEmpty) {
    headers['Authorization'] = 'Bearer $directBackendKey';
  }
  return headers;
}
