import 'package:flutter/material.dart';

enum UserStatusType {
  online,
  offline,
  dnd, // Do Not Disturb
  away,
}

extension UserStatusExtension on UserStatusType {
  String get displayName {
    switch (this) {
      case UserStatusType.online:
        return 'Online';
      case UserStatusType.offline:
        return 'Offline';
      case UserStatusType.dnd:
        return 'Do Not Disturb';
      case UserStatusType.away:
        return 'Away';
    }
  }

  Color get color {
    switch (this) {
      case UserStatusType.online:
        return Colors.green;
      case UserStatusType.offline:
        return Colors.grey;
      case UserStatusType.dnd:
        return Colors.red;
      case UserStatusType.away:
        return Colors.orange; // Using orange for away, yellow for DND icon later
    }
  }

  IconData get icon {
    switch (this) {
      case UserStatusType.online:
        return Icons.circle; // Simple circle for online
      case UserStatusType.offline:
        return Icons.circle; // Simple circle for offline
      case UserStatusType.dnd:
        return Icons.remove; // Minus sign for DND
      case UserStatusType.away:
        return Icons.nights_stay; // Moon icon for away
    }
  }
}
