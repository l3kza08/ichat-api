import 'dart:math';
import 'dart:developer' as developer;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Simple recovery-phrase manager using `flutter_secure_storage`.
/// This implementation generates a readable token (grouped hex segments).
class RecoveryService {
  RecoveryService._();
  static final RecoveryService instance = RecoveryService._();

  static const _storageKey = 'recovery_phrase_v1';
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<String?> getStoredPhrase() async {
    return await _secure.read(key: _storageKey);
  }

  /// Store a provided recovery phrase into secure storage.
  Future<void> storeRecoveryPhrase(String phrase) async {
    await _secure.write(key: _storageKey, value: phrase);
  }

  Future<String> ensureRecoveryPhrase() async {
    final existing = await getStoredPhrase();
    if (existing != null && existing.isNotEmpty) return existing;
    final phrase = _generateReadableToken();
    await _secure.write(key: _storageKey, value: phrase);
    developer.log('New recovery phrase generated', name: 'RecoveryService');
    return phrase;
  }

  Future<void> clearPhrase() async {
    await _secure.delete(key: _storageKey);
  }

  /// Backwards-compatible alias for clearing the stored recovery phrase.
  Future<void> clearRecoveryPhrase() async {
    await clearPhrase();
  }

  String _generateReadableToken({int bytes = 12}) {
    final rnd = Random.secure();
    final buffer = List<int>.generate(bytes, (_) => rnd.nextInt(256));
    final hex = hexEncode(buffer);
    // group into 4-char chunks for readability
    final groups = <String>[];
    for (var i = 0; i < hex.length; i += 4) {
      groups.add(hex.substring(i, i + 4 > hex.length ? hex.length : i + 4));
    }
    // join into words of 3 groups separated by '-'
    final parts = <String>[];
    for (var i = 0; i < groups.length; i += 3) {
      parts.add(
        groups.sublist(i, i + 3 > groups.length ? groups.length : i + 3).join(),
      );
    }
    return parts.join('-');
  }

  String hexEncode(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
