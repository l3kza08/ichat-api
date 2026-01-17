import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'p2p_service.dart';
import 'ice_config.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

/// Basic WebRTC signaling via Firestore documents (offers/answers & ice candidates).
/// This is a lightweight helper: it creates an RTCPeerConnection, a data channel,
/// writes offer/answer to Firestore under collection `webrtc_signaling/<convId>/signals`.
class WebRTCService {
  WebRTCService._(this.convId, this.onData);

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  void Function(dynamic)? _onRemoteStream;
  StreamSubscription? _signalSub;

  final String convId;
  final void Function(Uint8List data) onData;

  static Future<WebRTCService> create(
    String convId,
    void Function(Uint8List) onData, {
    void Function(dynamic)? onRemoteStream,
  }) async {
    final s = WebRTCService._(convId, onData);
    s._onRemoteStream = onRemoteStream;
    await s._init();
    return s;
  }

  Future<void> _init() async {
    // load ICE servers dynamically to allow TURN credentials
    try {
      final ice = await IceConfig.instance.getIceServers();
      _pc = await createPeerConnection({'iceServers': ice});
    } catch (_) {
      _pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });
    }
    _pc!.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate != null) {
        _sendSignal({'type': 'ice', 'candidate': c.toMap()});
      }
    };

    // create data channel
    _dc = await _pc!.createDataChannel(
      'file',
      RTCDataChannelInit()..ordered = true,
    );
    _dc!.onMessage = (RTCDataChannelMessage m) {
      if (m.isBinary) {
        onData(m.binary);
      } else {
        // we may receive json metadata messages
        try {
          final msg = jsonDecode(m.text);
          if (msg['type'] == 'chunk') {
            // if we decide to use chunking protocol
          }
        } catch (_) {}
      }
    };
    // Accept remote-created data channels (for the answering side)
    _pc!.onDataChannel = (RTCDataChannel channel) {
      try {
        _dc = channel;
        _dc!.onMessage = (RTCDataChannelMessage m) {
          if (m.isBinary) {
            onData(m.binary);
          } else {
            try {
              final msg = jsonDecode(m.text);
              if (msg['type'] == 'chunk') {
                // handle chunks if implemented
              }
            } catch (_) {}
          }
        };
      } catch (_) {}
    };

    // Listen for remote signals via in-app signaling (P2PService messages)
    _signalSub = P2PService.instance
        .messagesStream('webrtc_signaling_$convId')
        .listen((list) async {
          for (final raw in list) {
            try {
              final data = Map<String, dynamic>.from(raw);
              final type = data['type'] as String?;
              if (type == null) continue;
              if (type == 'offer' && _pc != null) {
                final sdp = data['sdp'] as String?;
                if (sdp == null) continue;
                await _pc!.setRemoteDescription(
                  RTCSessionDescription(sdp, 'offer'),
                );
                final answer = await _pc!.createAnswer();
                await _pc!.setLocalDescription(answer);
                _sendSignal({'type': 'answer', 'sdp': answer.sdp});
              } else if (type == 'answer' && _pc != null) {
                final sdp = data['sdp'] as String?;
                if (sdp == null) continue;
                await _pc!.setRemoteDescription(
                  RTCSessionDescription(sdp, 'answer'),
                );
              } else if (type == 'ice' && _pc != null) {
                final cand = data['candidate'] as Map<String, dynamic>?;
                if (cand != null) {
                  final c = RTCIceCandidate(
                    cand['candidate'],
                    cand['sdpMid'],
                    cand['sdpMLineIndex'],
                  );
                  await _pc!.addCandidate(c);
                }
              }
            } catch (_) {}
          }
        });

    // handle remote tracks
    _pc!.onTrack = (RTCTrackEvent event) {
      try {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          try {
            _onRemoteStream?.call(_remoteStream!);
          } catch (_) {}
        }
      } catch (_) {}
    };
  }

  /// Start capturing local audio (microphone) and add tracks to the peer connection.
  Future<void> startLocalAudio() async {
    if (_localStream != null) return;
    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) return;
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      _localStream = stream;
      // add tracks
      for (var track in _localStream!.getAudioTracks()) {
        await _pc?.addTrack(track, _localStream!);
      }
    } catch (_) {}
  }

  /// Mute or unmute local audio tracks.
  Future<void> muteAudio(bool mute) async {
    try {
      for (var track in _localStream?.getAudioTracks() ?? []) {
        try {
          track.enabled = !mute;
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> createOffer() async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _sendSignal({'type': 'offer', 'sdp': offer.sdp});
  }

  /// Create an offer after ensuring local media (audio) is attached.
  Future<void> startCallWithAudio() async {
    await startLocalAudio();
    await createOffer();
  }

  void _sendSignal(Map<String, dynamic> data) {
    try {
      P2PService.instance.sendMessage('webrtc_signaling_$convId', data);
    } catch (_) {}
  }

  Future<void> sendData(Uint8List bytes) async {
    if (_dc == null) throw Exception('DataChannel not initialized');
    // For large files, chunking should be implemented; here we send whole blob (ok for small images/gifs)
    _dc!.send(RTCDataChannelMessage.fromBinary(bytes));
  }

  Future<void> close() async {
    await _signalSub?.cancel();
    await _dc?.close();
    try {
      for (var t in _localStream?.getTracks() ?? []) {
        try {
          t.stop();
        } catch (_) {}
      }
      await _localStream?.dispose();
    } catch (_) {}
    await _pc?.close();
    _dc = null;
    _pc = null;
  }
}
