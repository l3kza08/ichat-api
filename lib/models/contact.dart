import 'package:flutter/material.dart';
import 'package:ichat/models/user_status.dart'; // Import UserStatusType

class Contact {
  final String id; // uid or generated id
  final String name;
  final String lastMessage;
  final String time;
  final int unread;
  final Color avatarColor;
  final String? avatarAsset;
  final String? photoUrl;
  final String? status; // Custom status message
  final UserStatusType statusType; // New field for status type

  bool get online => statusType == UserStatusType.online;

  Contact({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.time,
    required this.unread,
    required this.avatarColor,
    this.avatarAsset,
    this.photoUrl,
    this.status,
    this.statusType = UserStatusType.offline,
  });

  factory Contact.fromMap(String id, Map<String, dynamic> m) {
    final statusTypeStr = m['statusType'] as String? ?? UserStatusType.offline.name;
    final statusType = UserStatusType.values.firstWhere(
      (e) => e.name == statusTypeStr,
      orElse: () => UserStatusType.offline,
    );
    return Contact(
      id: id,
      name: m['name'] ?? 'Unknown',
      lastMessage: m['lastMessage'] ?? '',
      time: m['time'] ?? '',
      unread: (m['unread'] ?? 0) as int,
      avatarColor:
          Colors.primaries[(m['colorIndex'] ?? 0) % Colors.primaries.length],
      avatarAsset: m['avatarAsset'],
      photoUrl: m['photoURL'],
      status: m['status'] as String?,
      statusType: statusType,
    );
  }
}
