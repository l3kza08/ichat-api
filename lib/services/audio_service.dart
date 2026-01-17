import 'package:audioplayers/audioplayers.dart';

class AudioService {
  /// Play the login sound asset if available. Silently ignores failures.
  static Future<void> playLogin() async {
    await _playAssetWithFallback([
      'assets/audio/login.mp3',
      'audio/login.mp3',
      'login.mp3',
    ]);
  }

  /// Play the logout sound asset if available. Silently ignores failures.
  static Future<void> playLogout() async {
    await _playAssetWithFallback([
      'assets/audio/logout.mp3',
      'audio/logout.mp3',
      'logout.mp3',
    ]);
  }

  /// Play receive (incoming message) sound.
  static Future<void> playReceive() async {
    await _playAssetWithFallback([
      'assets/audio/receive.mp3',
      'audio/receive.mp3',
      'receive.mp3',
    ]);
  }

  /// Play dial (call start) sound
  static Future<void> playDial() async {
    await _playAssetWithFallback([
      'assets/audio/dial.mp3',
      'audio/dial.mp3',
      'dial.mp3',
    ]);
  }

  /// Play ringing while waiting for answer
  static Future<void> playRinging() async {
    await _playAssetWithFallback([
      'assets/audio/ringing.mp3',
      'audio/ringing.mp3',
      'ringing.mp3',
    ]);
  }

  /// Play connected / in-call sound (brief)
  static Future<void> playConnected() async {
    await _playAssetWithFallback([
      'assets/audio/connected.mp3',
      'audio/connected.mp3',
      'connected.mp3',
    ]);
  }

  /// Play hangup sound
  static Future<void> playHangup() async {
    await _playAssetWithFallback([
      'assets/audio/hangup.mp3',
      'audio/hangup.mp3',
      'hangup.mp3',
    ]);
  }

  /// Play failed call sound
  static Future<void> playCallFailed() async {
    await _playAssetWithFallback([
      'assets/audio/call_failed.mp3',
      'audio/call_failed.mp3',
      'call_failed.mp3',
    ]);
  }

  static Future<void> _playAssetWithFallback(List<String> candidates) async {
    for (final path in candidates) {
      try {
        final player = AudioPlayer();
        await player.setVolume(1.0);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.play(AssetSource(path));
        // Release after a short delay but allow playback to start.
        Future.delayed(const Duration(seconds: 2), () async {
          try {
            await player.stop();
            await player.dispose();
          } catch (_) {}
        });
        return; // success
      } catch (_) {
        // try next candidate
      }
    }
  }
}
