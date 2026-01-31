import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';

import 'package:ichat/services/p2p_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recovery_service.dart';
import 'audio_service.dart'; // Import AudioService

// A simple user model
class UserProfile {
  final String uid;
  final String name;
  final String username;
  final String? photoPath;
  final String? recoveryPhraseHash;

  UserProfile({
    required this.uid,
    required this.name,
    required this.username,
    this.photoPath,
    this.recoveryPhraseHash,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      uid: json['uid'],
      name: json['name'],
      username: json['username'],
      photoPath: json['photo'],
      recoveryPhraseHash: json['recoveryPhraseHash'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'username': username,
      'photo': photoPath,
      'recoveryPhraseHash': recoveryPhraseHash,
    };
  }
}

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  static const userProfileKey = 'user_profile';
  UserProfile? _currentUser;

  UserProfile? get currentUser => _currentUser;

  void updateCurrentUser(UserProfile newProfile) {
    _currentUser = newProfile;
    _persistCurrentUser();
  }

  Future<void> _persistCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentUser != null) {
      await prefs.setString(
        userProfileKey,
        json.encode(_currentUser!.toJson()),
      );
    } else {
      await prefs.remove(userProfileKey);
    }
  }

  Future<void> _init() async {
    if (_currentUser != null) return; // Already initialized
    final prefs = await SharedPreferences.getInstance();
    final profileString = prefs.getString(userProfileKey);
    if (profileString != null) {
      _currentUser = UserProfile.fromJson(json.decode(profileString));
      if (_currentUser != null) {
        // If an authenticated user exists locally, announce them to the P2P service.
        // This ensures their profile (including recoveryPhraseHash) is sent to the signaling server.
        await P2PService.instance.announce(_currentUser!);
      }
    }

  }

  Future<bool> isLoggedIn() async {
    await _init();
    return _currentUser != null;
  }

  Future<UserProfile?> getCurrentUser() async {
    await _init();
    return _currentUser;
  }

  Future<void> signUp({
    required String name,
    required String username,
    required String phrase,
    File? avatar,
  }) async {
    // 1. Store the recovery phrase securely
    await RecoveryService.instance.storeRecoveryPhrase(phrase);

    // Generate recovery phrase hash
    final recoveryPhraseHash = sha256.convert(utf8.encode(phrase)).toString();

    // 2. Save avatar if it exists
    String? photoPath;
    final uid = 'user_${DateTime.now().millisecondsSinceEpoch}';
    if (avatar != null) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final dest = File('${appDir.path}/avatar_$uid.jpg');
        await avatar.copy(dest.path);
        photoPath = 'file://${dest.path}';
      } catch (_) {
        // Ignore avatar saving errors
      }
    }

    // 3. Create and store user profile
    _currentUser = UserProfile(
      uid: uid,
      name: name,
      username: username,
      photoPath: photoPath,
      recoveryPhraseHash: recoveryPhraseHash, // Include the hash
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(userProfileKey, json.encode(_currentUser!.toJson()));


  }

  Future<bool> loginWithRecoveryPhrase(String phrase) async {
    final recoveryPhraseHash = sha256.convert(utf8.encode(phrase)).toString();

    // Request user profile from P2PService (which talks to signaling server)
    final userProfile =
        await P2PService.instance.requestUserProfileByRecoveryPhraseHash(recoveryPhraseHash);

    if (userProfile != null) {
      _currentUser = userProfile;
      await _persistCurrentUser(); // Persist the fetched user profile
      // Also ensure P2PService is aware of this logged-in user
      await P2PService.instance.announce(_currentUser!);
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(userProfileKey);
    await RecoveryService.instance.clearPhrase();
    await P2PService.instance.signOut();
    AudioService.playLogout();
    _currentUser = null;
  }
}
