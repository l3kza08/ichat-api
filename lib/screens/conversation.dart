import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

// Firestore removed; using local P2P message streams from P2PService
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/contact.dart';
import '../widgets/bubble.dart';
import '../services/webrtc_service.dart';
import '../services/p2p_service.dart';
import '../widgets/loading_spinner.dart';
import 'call_screen.dart';

class ConversationScreen extends StatefulWidget {
  final Contact contact;
  const ConversationScreen({super.key, required this.contact});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _ctrl = TextEditingController();
  WebRTCService? _webrtc;
  final List<Map<String, dynamic>> _localMessages = [];
  Contact? _peerContact;
  StreamSubscription<List<Map<String, dynamic>>>? _usersSub;

  @override
  void initState() {
    super.initState();
    _setupWebRTC();
  }

  Future<void> _setupWebRTC() async {
    final me = P2PService.instance.currentUser;
    final convId = P2PService.instance.conversationIdFor(
      me?.uid ?? 'me',
      widget.contact.id,
    );
    try {
      _webrtc = await WebRTCService.create(convId, (Uint8List data) {
        _onDataReceived(data);
      });
      final myUid = me?.uid ?? '';
      // Deterministic initiator: lower uid starts offer
      if (myUid.isNotEmpty && myUid.compareTo(widget.contact.id) < 0) {
        await _webrtc?.createOffer();
      }
    } catch (_) {
      // ignore failures; we'll fallback to upload
    }
    // subscribe to users updates so we can reflect profile changes
    _usersSub = P2PService.instance.usersStream().listen((list) {
      try {
        final found = list.firstWhere(
          (m) => (m['id'] ?? m['uid'] ?? '') == widget.contact.id,
          orElse: () => {},
        );
        if (found.isNotEmpty) {
          final id = (found['id'] ?? found['uid']).toString();
          final c = Contact.fromMap(id, Map<String, dynamic>.from(found));
          if (mounted) {
            setState(() => _peerContact = c);
          }
        }
      } catch (_) {}
    });
    // fetch peer profile once immediately for faster initial display
    try {
      final doc = await P2PService.instance.getUserDoc(widget.contact.id);
      if (doc != null) {
        final c = Contact.fromMap(
          widget.contact.id,
          Map<String, dynamic>.from(doc),
        );
        if (mounted) {
          setState(() => _peerContact = c);
        }
      }
    } catch (_) {}
  }

  void _onDataReceived(Uint8List data) {
    if (!mounted) return;
    setState(() {
      _localMessages.add({
        'from': widget.contact.id,
        'imageBytes': data,
        '_ts': DateTime.now(),
      });
    });
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (x == null) return;
    final file = File(x.path);
    final bytes = await file.readAsBytes();

    final me = P2PService.instance.currentUser;
    final convId = P2PService.instance.conversationIdFor(
      me?.uid ?? 'me',
      widget.contact.id,
    );

    // Try P2P first
    if (_webrtc != null) {
      try {
        await _webrtc!.sendData(Uint8List.fromList(bytes));
        // notify peers via P2P messaging stream with small metadata (no image content)
        await P2PService.instance.sendMessage(convId, {
          'from': me?.uid ?? 'me',
          'text': '[Image sent via P2P]',
          'p2p': true,
          'meta': {'name': x.path.split('/').last, 'size': bytes.length},
        });
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sent via P2P')));
        // also add local echo
        setState(() {
          _localMessages.add({
            'from': me?.uid ?? 'me',
            'imageBytes': bytes,
            '_ts': DateTime.now(),
          });
        });
        return;
      } catch (e) {
        // fall through to upload
      }
    }

    // Fallback: upload to Firebase Storage
    try {
      final path =
          'conversations/$convId/${DateTime.now().millisecondsSinceEpoch}_${x.path.split('/').last}';
      final url = await P2PService.instance.uploadFile(path, file);
      await P2PService.instance.sendMessage(convId, {
        'from': me?.uid ?? 'me',
        'imageUrl': url,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Uploaded and sent')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _webrtc?.close();
    try {
      _usersSub?.cancel();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = P2PService.instance.currentUser;
    final convId = P2PService.instance.conversationIdFor(
      me?.uid ?? 'me',
      widget.contact.id,
    );

    final displayContact = _peerContact ?? widget.contact;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: () {
                if (displayContact.photoUrl != null &&
                    displayContact.photoUrl!.isNotEmpty) {
                  final url = displayContact.photoUrl!;
                  if (url.startsWith('file://')) {
                    final p = url.replaceFirst('file://', '');
                    final f = File(p);
                    if (f.existsSync()) {
                      return Image.file(
                        f,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, error, stack) => Container(
                          width: 40,
                          height: 40,
                          color: displayContact.avatarColor,
                          child: Center(
                            child: Text(
                              displayContact.name[0],
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      );
                    }
                  } else {
                    return Image.network(
                      url,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, error, stack) => Container(
                        width: 40,
                        height: 40,
                        color: displayContact.avatarColor,
                        child: Center(
                          child: Text(
                            displayContact.name[0],
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    );
                  }
                }
                return Container(
                  width: 40,
                  height: 40,
                  color: displayContact.avatarColor,
                  child: Center(
                    child: Text(
                      displayContact.name[0],
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
              }(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayContact.name,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: displayContact.online
                              ? Colors.green
                              : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        displayContact.online ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: displayContact.online
                              ? Colors.green
                              : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                // initiate P2P call via signaling service then open Call screen
                try {
                  P2PService.instance.callPeer(widget.contact.id);
                } catch (_) {}
                final me = P2PService.instance.currentUser;
                final convId = P2PService.instance.conversationIdFor(
                  me?.uid ?? 'me',
                  widget.contact.id,
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      convId: convId,
                      peerName: widget.contact.name,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.call, color: Colors.blue),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.more_vert, color: Colors.black54),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: P2PService.instance.messagesStream(convId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return const Center(child: LoadingSpinner());
                }
                if (snap.hasError) {
                  return const Center(child: Text('Error loading messages'));
                }
                if (!snap.hasData || snap.data!.isEmpty) {
                  return const Center(child: Text('No messages yet.'));
                }
                final docs = snap.data!
                    .map((m) {
                      final ts = m['ts'] is DateTime
                          ? m['ts'] as DateTime
                          : DateTime.now();
                      final copy = Map<String, dynamic>.from(m);
                      copy['__ts'] = ts;
                      return copy;
                    })
                    .toList()
                    .cast<Map<String, dynamic>>();

                // merge with local (P2P-only) messages
                final merged = <Map<String, dynamic>>[];
                merged.addAll(docs);
                merged.addAll(_localMessages);
                merged.sort((a, b) {
                  final ta = a['__ts'] as DateTime? ?? DateTime.now();
                  final tb = b['__ts'] as DateTime? ?? DateTime.now();
                  return ta.compareTo(tb);
                });

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  itemCount: merged.length,
                  itemBuilder: (context, idx) {
                    final d = merged[idx];
                    final isMe = d['from'] == (me?.uid ?? 'me');
                    if (d.containsKey('imageUrl')) {
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Bubble(
                          imageUrl: d['imageUrl'] as String?,
                          isMe: isMe,
                          timestamp: d['__ts'] as DateTime?,
                        ),
                      );
                    }
                    if (d.containsKey('imageBytes')) {
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Bubble(
                          imageBytes: d['imageBytes'] as Uint8List?,
                          isMe: isMe,
                          timestamp: d['__ts'] as DateTime?,
                        ),
                      );
                    }
                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Bubble(
                        text: d['text'] ?? '',
                        isMe: isMe,
                        timestamp: d['__ts'] as DateTime?,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: Theme.of(
                context,
              ).scaffoldBackgroundColor, // Use theme background color
              child: Row(
                children: [
                  IconButton(
                    onPressed: _pickAndSendImage,
                    icon: const Icon(
                      Icons.attach_file, // Changed icon for attachments
                      color: Color(0xFF00A4E0),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(
                          25,
                        ), // More rounded corners
                        border: Border.all(
                          color: Colors.grey.shade300,
                        ), // Subtle border
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: TextField(
                        controller: _ctrl,
                        decoration: const InputDecoration(
                          hintText: 'Type a message here',
                          border: InputBorder.none,
                          isDense: true, // Reduce vertical space
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 8,
                          ), // Adjust padding
                        ),
                        minLines: 1,
                        maxLines: 5, // Allow multiple lines
                        keyboardType: TextInputType.multiline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A4E0),
                      shape: BoxShape.circle,
                      boxShadow: [
                        // Add subtle shadow to send button
                        BoxShadow(
                          color: Colors.black.withAlpha(51),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: () async {
                        final txt = _ctrl.text.trim();
                        if (txt.isEmpty) return;
                        final me = P2PService.instance.currentUser;
                        // optimistic local echo so user sees message immediately
                        final localMsg = {
                          'from': me?.uid ?? 'me',
                          'text': txt,
                          '__ts': DateTime.now(),
                        };
                        setState(() {
                          _localMessages.add(localMsg);
                        });
                        // clear input and unfocus
                        _ctrl.clear();
                        FocusScope.of(context).unfocus();
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await P2PService.instance.sendMessage(convId, {
                            'from': me?.uid ?? 'me',
                            'text': txt,
                            'ts': DateTime.now(),
                          });
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Sent')),
                            );
                          }
                        } catch (e) {
                          // remove optimistic echo on failure
                          try {
                            setState(() {
                              _localMessages.remove(localMsg);
                            });
                          } catch (_) {}
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Send failed: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
