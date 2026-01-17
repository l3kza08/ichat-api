import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Simple signaling client that connects to a WebSocket server.
/// The app user must provide a signaling server URL (or run a simple server).
class SignalingService {
  final String url;
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _events =
      StreamController.broadcast();

  SignalingService(this.url);

  Stream<Map<String, dynamic>> get onMessage => _events.stream;

  void connect() {
    if (_channel != null) return;
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _channel!.stream.listen(
      (raw) {
        try {
          final m = jsonDecode(raw as String) as Map<String, dynamic>;
          _events.add(m);
        } catch (_) {}
      },
      onDone: () {
        _channel = null;
      },
      onError: (_) {
        _channel = null;
      },
    );
  }

  void send(Map<String, dynamic> data) {
    if (_channel == null) connect();
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> close() async {
    await _channel?.sink.close();
    await _events.close();
  }
}
