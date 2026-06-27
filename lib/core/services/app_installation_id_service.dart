import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kAppInstallationIdStorageKey = 'freshscan.app_installation_id';

abstract interface class AppInstallationIdStorage {
  Future<String?> readString(String key);

  Future<void> writeString(String key, String value);
}

class SharedPreferencesAppInstallationIdStorage
    implements AppInstallationIdStorage {
  const SharedPreferencesAppInstallationIdStorage();

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  @override
  Future<String?> readString(String key) async {
    return (await _prefs).getString(key);
  }

  @override
  Future<void> writeString(String key, String value) async {
    final saved = await (await _prefs).setString(key, value);
    if (!saved) {
      throw StateError('Failed to persist app installation ID');
    }
  }
}

final appInstallationIdStorageProvider = Provider<AppInstallationIdStorage>((
  ref,
) {
  return const SharedPreferencesAppInstallationIdStorage();
});

final appInstallationIdServiceProvider = Provider<AppInstallationIdService>((
  ref,
) {
  return AppInstallationIdService(
    storage: ref.watch(appInstallationIdStorageProvider),
  );
});

class AppInstallationIdService {
  AppInstallationIdService({
    required AppInstallationIdStorage storage,
    String Function()? uuidGenerator,
    String storageKey = kAppInstallationIdStorageKey,
  }) : _storage = storage,
       _uuidGenerator = uuidGenerator ?? generateUuidV4,
       _storageKey = storageKey;

  final AppInstallationIdStorage _storage;
  final String Function() _uuidGenerator;
  final String _storageKey;

  String? _cachedInstallationId;
  Future<String>? _inFlightRequest;

  Future<String> getOrCreateInstallationId() {
    final cachedInstallationId = _cachedInstallationId;
    if (cachedInstallationId != null) {
      return Future<String>.value(cachedInstallationId);
    }

    final inFlightRequest = _inFlightRequest;
    if (inFlightRequest != null) {
      return inFlightRequest;
    }

    final request = _loadOrCreateInstallationId();
    _inFlightRequest = request.whenComplete(() {
      _inFlightRequest = null;
    });
    return _inFlightRequest!;
  }

  Future<String> _loadOrCreateInstallationId() async {
    final existingValue = _normalizeStoredId(
      await _storage.readString(_storageKey),
    );
    if (existingValue != null) {
      _cachedInstallationId = existingValue;
      return existingValue;
    }

    final generatedValue = _uuidGenerator();
    await _storage.writeString(_storageKey, generatedValue);
    _cachedInstallationId = generatedValue;
    return generatedValue;
  }

  String? _normalizeStoredId(String? rawValue) {
    final trimmedValue = rawValue?.trim();
    if (trimmedValue == null || trimmedValue.isEmpty) {
      return null;
    }
    return trimmedValue;
  }
}

String generateUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));

  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hexByte(int value) => value.toRadixString(16).padLeft(2, '0');

  final buffer = StringBuffer();
  for (var index = 0; index < bytes.length; index++) {
    buffer.write(hexByte(bytes[index]));
    if (index == 3 || index == 5 || index == 7 || index == 9) {
      buffer.write('-');
    }
  }

  return buffer.toString();
}
