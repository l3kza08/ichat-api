import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/webrtc_service.dart';
import '../services/p2p_service.dart';
import '../services/audio_service.dart';

class CallScreen extends StatefulWidget {
  final String convId;
  final String peerName;
  const CallScreen({super.key, required this.convId, required this.peerName});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  WebRTCService? _webrtc;
  String _status = 'Connecting...';
  String _displayName = 'Unknown';
  String? _peerPhotoUrl;
  bool _isMuted = false;
  bool _isSpeakerOn = false;

  @override
  void initState() {
    super.initState();
    _displayName = widget.peerName;
    _startCallSetup();
  }

  Future<void> _startCallSetup() async {
    try {
      _webrtc = await WebRTCService.create(
        widget.convId,
        (_) {}, // No direct data channel messages for this screen
        onRemoteStream: (s) {
          if (!mounted) return;
          setState(() => _status = 'Connected');
          try {
            AudioService.playConnected();
          } catch (_) {}
        },
      );

      // Fetch peer profile for display and determine initiator
      final myUid = P2PService.instance.currentUser?.uid ?? '';
      final parts = widget.convId.split('_');
      final peerUid = parts.firstWhere((p) => p != myUid, orElse: () => '');
      if (peerUid.isNotEmpty) {
        final doc = await P2PService.instance.getUserDoc(peerUid);
        if (!mounted) return;
        if (doc != null) {
          setState(() {
            _displayName = doc['name'] ?? widget.peerName;
            _peerPhotoUrl = doc['photoURL'] ?? '';
          });
        }
      }

      // Deterministic initiator (compare uids)
      if (myUid.isNotEmpty &&
          peerUid.isNotEmpty &&
          myUid.compareTo(peerUid) < 0) {
        await _webrtc?.startCallWithAudio();
      }
      // play dial sound
      try {
        await AudioService.playDial();
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Failed: $e');
        try {
          AudioService.playCallFailed();
        } catch (_) {}
      }
    }
  }

  Future<void> _hangUp() async {
    final nav = Navigator.of(context);
    await _webrtc?.close();
    try {
      await AudioService.playHangup();
    } catch (_) {}
    if (mounted) {
      nav.pop();
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _webrtc?.muteAudio(_isMuted);
    });
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
      // WebRTC doesn't directly control speakerphone for Flutter_webrtc this way
      // This would typically involve platform-specific code or a package like audio_manager
      // For now, it's a UI indicator.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speaker ${_isSpeakerOn ? 'on' : 'off'}')),
      );
    });
  }

  @override
  void dispose() {
    _webrtc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade900, // Dark background for call screen
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 80,
                      backgroundColor: Colors.blue.shade700,
                      backgroundImage:
                          () {
                                if (_peerPhotoUrl != null &&
                                    _peerPhotoUrl!.isNotEmpty) {
                                  final url = _peerPhotoUrl!;
                                  if (url.startsWith('file://')) {
                                    final p = url.replaceFirst('file://', '');
                                    return FileImage(File(p));
                                  }
                                  return NetworkImage(url);
                                }
                                return null;
                              }()
                              as ImageProvider?,
                      child: (_peerPhotoUrl == null || _peerPhotoUrl!.isEmpty)
                          ? const Icon(
                              Icons.person,
                              size: 80,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _displayName,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCallControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    onPressed: _toggleMute,
                    color: _isMuted
                        ? Colors.red.shade700
                        : Colors.blue.shade700,
                  ),
                  _buildCallControlButton(
                    icon: Icons.call_end,
                    label: 'Hang Up',
                    onPressed: _hangUp,
                    color: Colors.red.shade700,
                  ),
                  _buildCallControlButton(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                    label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                    onPressed: _toggleSpeaker,
                    color: _isSpeakerOn
                        ? Colors.blue.shade700
                        : Colors.blue.shade700,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Column(
      children: [
        FloatingActionButton(
          heroTag: label, // Unique tag for each FloatingActionButton
          onPressed: onPressed,
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: Icon(icon, size: 28),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
