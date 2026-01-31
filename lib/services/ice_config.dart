import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Small helper to manage ICE server configuration (STUN/TURN).
class IceConfig {
  IceConfig._();
  static final IceConfig instance = IceConfig._();

  static const _prefsKey = 'ice_servers';

  /// Returns a list suitable for `createPeerConnection` config['iceServers'].
  Future<List<Map<String, dynamic>>> getIceServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as List;
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    // default fallback
    return [
      {'urls': 'stun:stun.l.google.com:19302'},
    ];
  }

  /// Persist ICE servers (list of maps) as JSON string.
  Future<void> setIceServers(List<Map<String, dynamic>> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(servers));
    } catch (_) {}
  }
}
