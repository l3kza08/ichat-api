import 'package:flutter/material.dart';
import 'dart:developer' as developer;

import '../screens/call_screen.dart';

/// Global navigator key used by the app to navigate from background handlers.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Handle a generic data payload (e.g., from a notification tap).
void handleRemoteMessage(Map<String, dynamic> data) {
  try {
    _handleData(data);
  } catch (e, st) {
    developer.log('handleRemoteMessage failed: $e', error: e, stackTrace: st);
  }
}

void handleData(Map<String, dynamic> data) {
  try {
    _handleData(data);
  } catch (_) {}
}

void _handleData(Map<String, dynamic> data) {
  if (data['type'] == 'incoming_call') {
    final convId = data['conversationId'] as String?;
    final peerName = data['peerName'] as String? ?? 'Call';
    if (convId != null && navigatorKey.currentState != null) {
      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => CallScreen(convId: convId, peerName: peerName),
        ),
      );
    }
  }
}
