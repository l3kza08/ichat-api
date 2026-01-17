import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'ice_config.dart';
import '../models/user_status.dart'; // Import UserStatusType
import 'auth_service.dart'; // Import UserProfile

/// Simple P2P service skeleton using WebRTC and a WebSocket signaling channel.
/// This is a starting point — you should adapt message formats and signaling
/// server expectations to your backend.
class P2PService {
  P2PService._() {
    connectToSignaling();
  }
  static final P2PService instance = P2PService._();

  static const String _hardcodedSignalingUrl =
      'wss://ichat-api--wrphl20.replit.app';

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  Stream<MediaStream> get onRemoteStream => _remoteStreamController.stream;

  WebSocketChannel? _signal;
  StreamSubscription? _signalSub;

  // reconnect/backoff

  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  static const int _maxReconnectDelaySeconds = 30;

  // simple in-memory + persisted messages store (conversationId -> list of messages)
  final Map<String, List<Map<String, dynamic>>> _messages = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>>
  _messageControllers = {};

  // simple presence/user map and controller
  final Map<String, Map<String, dynamic>> _users = {};
  final StreamController<List<Map<String, dynamic>>> _usersController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  // For handling single-shot requests (responses can be Map or List)
  final Map<String, Completer<dynamic>> _requestCompleters = {};

  UserProfile?
  _currentUser; // Changed type from Map<String, dynamic>? to UserProfile?
  bool _usersLoaded = false;

  Function()? onCallIncoming;

  Future<void> initializeLocalMedia({
    bool audio = true,
    bool video = true,
  }) async {
    try {
      final constraints = <String, dynamic>{
        'audio': audio,
        'video': video ? {'facingMode': 'user'} : false,
      };
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      developer.log('Local media initialized', name: 'P2PService');
    } catch (e, st) {
      developer.log(
        'Failed to get user media: $e',
        name: 'P2PService',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  // Messages API (persisted to SharedPreferences)
  Stream<List<Map<String, dynamic>>> messagesStream(String conversationId) {
    if (!_messageControllers.containsKey(conversationId)) {
      _messageControllers[conversationId] =
          StreamController<List<Map<String, dynamic>>>.broadcast();
      _messages.putIfAbsent(conversationId, () => []);
      // emit initial snapshot
      _messageControllers[conversationId]!.add(
        List.unmodifiable(_messages[conversationId]!),
      );
      // attempt to load persisted messages async
      _loadPersistedMessages(conversationId);
    }
    return _messageControllers[conversationId]!.stream;
  }

  Future<void> sendMessage(
    String conversationId,
    Map<String, dynamic> data,
  ) async {
    final list = _messages.putIfAbsent(conversationId, () => []);
    final m = Map<String, dynamic>.from(data);
    m['ts'] = DateTime.now();
    list.add(m);
    _messageControllers.putIfAbsent(
      conversationId,
      () => StreamController<List<Map<String, dynamic>>>.broadcast(),
    );
    if (!_messageControllers[conversationId]!.isClosed) {
      _messageControllers[conversationId]!.add(List.unmodifiable(list));
    }
    await _persistMessages(conversationId);
    // also send via signaling channel so remote peers receive it
    try {
      _sendSignal({
        'type': 'signal',
        'conversationId': conversationId,
        'message': m,
      });
    } catch (_) {}
  }

  Stream<List<Map<String, dynamic>>> usersStream() {
    _ensureUsersLoaded();
    return _usersController.stream;
  }

  Future<Map<String, dynamic>?> getUserDoc(String uid) async {
    await _ensureUsersLoaded();
    final u = _users[uid];
    if (u == null) return null;
    return {'uid': uid, ...u};
  }

  UserProfile? get currentUser => _currentUser;

  // New method to announce a user profile to the signaling server
  Future<void> announce(UserProfile userProfile) async {
    final userAnnounceData = userProfile.toJson();
    _sendSignal({'type': 'announce', 'user': userAnnounceData});
  }

  Future<UserProfile?> requestUserProfileByRecoveryPhraseHash(
    String hash,
  ) async {
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    final completer = Completer<Map<String, dynamic>?>();
    _requestCompleters[requestId] = completer;

    _sendSignal({
      'type': 'request_user_profile',
      'requestId': requestId,
      'recoveryPhraseHash': hash,
    });

    final response = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        developer.log(
          'Request for user profile by hash timed out.',
          name: 'P2PService',
        );
        return null;
      },
    );
    _requestCompleters.remove(requestId);

    if (response != null && response['user'] != null) {
      return UserProfile.fromJson(response['user']);
    }
    return null;
  }

  Future<List<UserProfile>> searchUsers(String query) async {
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    final completer = Completer<List<UserProfile>>();
    _requestCompleters[requestId] = completer;

    _sendSignal({
      'type': 'search_users',
      'requestId': requestId,
      'query': query,
    });

    final response = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        developer.log(
          'User search request timed out for query: $query',
          name: 'P2PService',
        );
        return [];
      },
    );
    _requestCompleters.remove(requestId);
    return response;
  }

  Future<void> setProfile(String uid, Map<String, dynamic> data) async {
    _users[uid] = {...?_users[uid], ...data};
    // keep current user snapshot in sync
    if (_currentUser != null && _currentUser!.uid == uid) {
      final updatedUserMap = {'uid': uid, ..._users[uid]!};
      _currentUser = UserProfile.fromJson(updatedUserMap);
      try {
        final prefs = await SharedPreferences.getInstance();
        prefs.setString('p2p_user', jsonEncode(_currentUser!.toJson()));
      } catch (_) {}

      // Send announce message to signaling server with updated profile
      final userAnnounceData = _currentUser!.toJson();
      _sendSignal({'type': 'announce', 'user': userAnnounceData});
    }
    _emitUsers();
    await _persistUsers();
  }

  Future<bool> deleteUserAvatar(String uid) async {
    final user = _users[uid];
    if (user == null) return false;
    final photo = user['photoURL'] as String?;
    if (photo == null || photo.isEmpty) return false;
    try {
      if (photo.startsWith('file://')) {
        final p = photo.replaceFirst('file://', '');
        final f = File(p);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    user['photoURL'] = '';
    await _persistUsers();
    _emitUsers();
    return true;
  }

  Future<void> signOut() async {
    // Send an offline announcement to the signaling server
    if (_currentUser != null) {
      _sendSignal({
        'type': 'announce',
        'user': {
          'uid': _currentUser!.uid,
          'statusType': UserStatusType.offline.name,
        },
      });
    }

    _currentUser = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('p2p_user');
    } catch (_) {}

    _emitUsers();
  }

  Future<void> _persistUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('p2p_users', jsonEncode(_users));
    } catch (_) {}
  }

  Future<void> _ensureUsersLoaded() async {
    if (_usersLoaded) return;
    _usersLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final usersRaw = prefs.getString('p2p_users');
      if (usersRaw != null) {
        final decoded = jsonDecode(usersRaw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          _users[k] = Map<String, dynamic>.from(v as Map);
        });
      }
      final rawUser = prefs.getString('p2p_user');
      if (rawUser != null) {
        try {
          _currentUser = UserProfile.fromJson(
            jsonDecode(rawUser) as Map<String, dynamic>,
          );
        } catch (_) {}
      }
      _emitUsers();
    } catch (_) {}
  }

  String conversationIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  Future<String> uploadFile(String path, File file) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final destPath = '${dir.path}/$path';
      final outFile = File(destPath);
      await outFile.parent.create(recursive: true);
      await file.copy(outFile.path);
      return 'file://${outFile.path}';
    } catch (e) {
      return 'file://${file.path}';
    }
  }

  Future<void> _createPeerConnection() async {
    // attempt to load ICE servers from signaling endpoint, fallback to prefs
    final iceServers = await _fetchIceServersFromSignaling() ??
        await IceConfig.instance.getIceServers();
    // persist fetched ICE servers for future runs
    try {
      await IceConfig.instance.setIceServers(iceServers);
    } catch (_) {}
    final config = <String, dynamic>{'iceServers': iceServers};
    final constraints = <String, dynamic>{'mandatory': {}, 'optional': []};
    _pc = await createPeerConnection(config, constraints);

    _pc?.onIceCandidate = (RTCIceCandidate candidate) {
      _sendSignal({'type': 'ice', 'candidate': candidate.toMap()});
    };

    _pc?.onAddStream = (MediaStream stream) {
      _remoteStreamController.add(stream);
    };

    if (_localStream != null) {
      _pc?.addStream(_localStream!);
    }
  }

  /// Try to GET /ice from the signaling server derived from the hardcoded URL.
  /// Returns null on failure.
  Future<List<Map<String, dynamic>>?> _fetchIceServersFromSignaling() async {
    try {
      // derive http(s) url from ws/wss signaling URL
      final ws = _hardcodedSignalingUrl;
      String base;
      if (ws.startsWith('wss://')) {
        base = ws.replaceFirst('wss://', 'https://');
      } else if (ws.startsWith('ws://')) {
        base = ws.replaceFirst('ws://', 'http://');
      } else {
        base = ws;
      }
      final uri = Uri.parse(base);
      final iceUri = uri.replace(path: '/ice');
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 6);
      final req = await httpClient.getUrl(iceUri);
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final parsed = jsonDecode(body) as Map<String, dynamic>?;
      if (parsed == null) return null;
      final servers = parsed['iceServers'] as List? ?? parsed['ice'] as List?;
      if (servers == null) return null;
      return servers.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      developer.log('Failed to fetch ICE from signaling: $e', name: 'P2PService');
      return null;
    }
  }

  void connectToSignaling() {
    _disconnectSignal();
    _reconnectAttempts = 0;
    _cancelReconnect();

    void setupChannel() {
      try {
        _signal = WebSocketChannel.connect(Uri.parse(_hardcodedSignalingUrl));
      } catch (e) {
        developer.log('Signal connect failed: $e', name: 'P2PService');
        _scheduleReconnect();
        return;
      }

      _signalSub = _signal!.stream.listen(
        (raw) async {
          developer.log('Signal recv: $raw', name: 'P2PService');
          try {
            final msg = json.decode(raw as String) as Map<String, dynamic>;
            await _handleSignalMessage(msg);
          } catch (e, st) {
            developer.log(
              'Signal parse error: $e',
              name: 'P2PService',
              error: e,
              stackTrace: st,
            );
          }
        },
        onError: (e) {
          developer.log('Signal error: $e', name: 'P2PService');
          _scheduleReconnect();
        },
        onDone: () {
          developer.log('Signal done', name: 'P2PService');
          _scheduleReconnect();
        },
      );

      // Announce current user immediately after connecting so server knows us
      try {
        if (_currentUser != null) {
          _sendSignal({'type': 'announce', 'user': _currentUser!.toJson()});
        }
      } catch (_) {}
    }

    setupChannel();
  }

  void _sendSignal(Map<String, dynamic> msg) {
    try {
      // attach sender id when available
      final enriched = Map<String, dynamic>.from(msg);
      if (_currentUser != null) {
        enriched['from'] = _currentUser!.uid;
      }
      final raw = json.encode(enriched);
      _signal?.sink.add(raw);
      developer.log('Signal send: $raw', name: 'P2PService');
    } catch (e) {
      developer.log('Signal send failed: $e', name: 'P2PService');
    }
  }

  void _scheduleReconnect() {
    _cancelReconnect();
    _reconnectAttempts += 1;
    final delaySeconds = (1 << (_reconnectAttempts - 1)).clamp(
      1,
      _maxReconnectDelaySeconds,
    );
    final delay = Duration(seconds: delaySeconds);
    developer.log(
      'Scheduling reconnect in ${delay.inSeconds}s',
      name: 'P2PService',
    );
    _reconnectTimer = Timer(delay, () {
      connectToSignaling();
    });
  }

  void _cancelReconnect() {
    try {
      _reconnectTimer?.cancel();
    } catch (_) {}
    _reconnectTimer = null;
  }

  Future<void> _handleSignalMessage(Map<String, dynamic> msg) async {
    final type = msg['type'] as String?;
    if (type == 'offer') {
      // Incoming call
      onCallIncoming?.call();
      await createPeerConnectionIfNeeded();
      final sdp = msg['sdp'] as String?;
      if (sdp != null) {
        await _pc?.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
        final answer = await _pc?.createAnswer();
        if (answer != null) {
          await _pc?.setLocalDescription(answer);
          _sendSignal({'type': 'answer', 'sdp': answer.sdp});
        }
      }
    } else if (type == 'answer') {
      final sdp = msg['sdp'] as String?;
      if (sdp != null) {
        await _pc?.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      }
    } else if (type == 'ice') {
      final candidate = msg['candidate'] as Map<String, dynamic>?;
      if (candidate != null) {
        try {
          await _pc?.addCandidate(
            RTCIceCandidate(
              candidate['candidate'] as String?,
              candidate['sdpMid'] as String?,
              candidate['sdpMLineIndex'] as int?,
            ),
          );
        } catch (e) {
          developer.log('addCandidate failed: $e', name: 'P2PService');
        }
      }
    } else if (type == 'users') {
      // server sent full users list
      final list = (msg['users'] as List?) ?? [];
      for (final e in list) {
        if (e is Map) {
          final uid = e['uid']?.toString() ?? '';
          if (uid.isNotEmpty) {
            final userData = Map<String, dynamic>.from(e);
            userData.remove('online'); // Remove old 'online' field if present
            // Default to offline if statusType is not provided by the server
            if (!userData.containsKey('statusType')) {
              userData['statusType'] = UserStatusType.offline.name;
            }
            _users[uid] = userData;
          }
        }
      }
      _emitUsers();
    } else if (type == 'announce') {
      final u = msg['user'] as Map<String, dynamic>?;
      if (u != null) {
        final uid = u['uid']?.toString() ?? '';
        if (uid.isNotEmpty) {
          final userData = Map<String, dynamic>.from(u);
          userData.remove('online'); // Remove old 'online' field if present
          // Default to offline if statusType is not provided by the server
          if (!userData.containsKey('statusType')) {
            userData['statusType'] = UserStatusType.offline.name;
          }
          _users[uid] = userData;
          _emitUsers();
        }
      }
    } else if (type == 'signal') {
      // incoming signal/message from another peer
      final conversationId = msg['conversationId'] as String? ?? '';
      final message = msg['message'] as Map<String, dynamic>?;
      if (conversationId.isNotEmpty && message != null) {
        final list = _messages.putIfAbsent(conversationId, () => []);
        final m = Map<String, dynamic>.from(message);
        m['ts'] = DateTime.now();
        list.add(m);
        _messageControllers.putIfAbsent(
          conversationId,
          () => StreamController<List<Map<String, dynamic>>>.broadcast(),
        );
        if (!_messageControllers[conversationId]!.isClosed) {
          _messageControllers[conversationId]!.add(List.unmodifiable(list));
        }
        await _persistMessages(conversationId);
      }
    } else if (type == 'user_profile_response') {
      final requestId = msg['requestId'] as String?;
      if (requestId != null && _requestCompleters.containsKey(requestId)) {
        _requestCompleters[requestId]!.complete(msg);
      }
    } else if (type == 'search_users_response') {
      final requestId = msg['requestId'] as String?;
      if (requestId != null && _requestCompleters.containsKey(requestId)) {
        final usersData = (msg['users'] as List?) ?? [];
        final userProfiles = usersData
            .map((u) => UserProfile.fromJson(u as Map<String, dynamic>))
            .toList();
        _requestCompleters[requestId]!.complete(userProfiles);
      }
    }
  }

  Future<void> createPeerConnectionIfNeeded() async {
    if (_pc == null) await _createPeerConnection();
  }

  Future<void> callPeer(String targetId) async {
    await createPeerConnectionIfNeeded();
    final offer = await _pc?.createOffer();
    if (offer != null) {
      await _pc?.setLocalDescription(offer);
      _sendSignal({'type': 'offer', 'sdp': offer.sdp, 'target': targetId});
    }
  }

  void _disconnectSignal() {
    _signalSub?.cancel();
    _signalSub = null;
    try {
      _signal?.sink.close();
    } catch (_) {}
    _signal = null;
    _cancelReconnect();
  }

  Future<void> _persistMessages(String convId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _messages[convId] ?? [];
      final serializable = list.map((m) {
        final copy = Map<String, dynamic>.from(m);
        if (copy['ts'] is DateTime) {
          copy['ts'] = (copy['ts'] as DateTime).toIso8601String();
        }
        return copy;
      }).toList();
      await prefs.setString('p2p_messages_$convId', jsonEncode(serializable));
    } catch (_) {}
  }

  Future<void> _loadPersistedMessages(String convId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString('p2p_messages_$convId');
      if (s == null) return;
      final list = (jsonDecode(s) as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        if (m['ts'] is String) {
          try {
            m['ts'] = DateTime.parse(m['ts'] as String);
          } catch (_) {
            m['ts'] = DateTime.now();
          }
        }
        return m;
      }).toList();
      _messages[convId] = list;
      _messageControllers[convId]?.add(List.unmodifiable(list));
    } catch (_) {}
  }

  void _emitUsers() {
    try {
      _usersController.add(
        _users.entries.map((e) => {'id': e.key, ...e.value}).toList(),
      );
    } catch (_) {}
  }

  Future<void> dispose() async {
    _remoteStreamController.close();
    _localStream?.dispose();
    await _pc?.close();
    _pc = null;
    _disconnectSignal();
  }
}

// Example message format expected from server (JSON):
// {"type":"offer","sdp":"...","from":"userid"}
// {"type":"answer","sdp":"..."}
// {"type":"ice","candidate":{...}}
