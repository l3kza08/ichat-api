import 'package:flutter/material.dart';
// Firestore removed; using local P2P users stream
import '../models/contact.dart';
import 'dart:io';
import '../widgets/liquid_nav.dart';
import '../widgets/loading_spinner.dart';
import '../services/p2p_service.dart';
import '../services/auth_service.dart';
import 'conversation.dart';

class ChatHome extends StatefulWidget {
  const ChatHome({super.key});

  @override
  State<ChatHome> createState() => _ChatHomeState();
}

class _ChatHomeState extends State<ChatHome> {
  int _navIndex = 2;
  void _onNavTap(int i) {
    setState(() => _navIndex = i);
  }

  Widget _buildContactsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: P2PService.instance.usersStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('Error loading users'));
        }
        if (!snap.hasData) {
          return const Center(child: LoadingSpinner());
        }
        final me = P2PService.instance.currentUser;
        final meUid = me == null ? null : me.uid as String?;
        final docs = snap.data!;
        final shown = docs
            .where((d) => (d['id'] as String?) != meUid)
            .map((d) => Contact.fromMap(d['id'] as String, d))
            .toList();
        if (shown.isEmpty) {
          return const Center(child: Text('ยังไม่มีเพื่อน เพิ่มเพื่อนเลย'));
        }
        return ListView.separated(
          itemCount: shown.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, idx) {
            final c = shown[idx];
            return ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConversationScreen(contact: c),
                ),
              ),
              leading: SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: () {
                          if (c.photoUrl != null && c.photoUrl!.isNotEmpty) {
                            final url = c.photoUrl!;
                            if (url.startsWith('file://')) {
                              final p = url.replaceFirst('file://', '');
                              final f = File(p);
                              if (f.existsSync()) {
                                return Image.file(File(p), fit: BoxFit.cover);
                              }
                            } else {
                              return Image.network(url, fit: BoxFit.cover);
                            }
                          }
                          if (c.avatarAsset != null) {
                            return Image.asset(
                              c.avatarAsset!,
                              fit: BoxFit.cover,
                            );
                          }
                          return Container(
                            color: c.avatarColor,
                            child: Center(
                              child: Text(
                                c.name[0],
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          );
                        }(),
                      ),
                    ),
                    if (c.online)
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2DD36F),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              title: Text(c.name),
              subtitle: Text(
                c.online
                    ? (c.lastMessage.isNotEmpty ? c.lastMessage : 'Online')
                    : 'Offline',
                style: TextStyle(
                  color: c.online ? Colors.green : Colors.grey,
                  fontSize: 13,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCallsTab() {
    return const Center(child: Text('No calls yet'));
  }

  Widget _buildChatsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: P2PService.instance.usersStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('Error loading users'));
        }
        if (!snap.hasData) return const Center(child: LoadingSpinner());
        final me = P2PService.instance.currentUser;
        final meUid = me == null ? null : me.uid as String?;
        final docs = snap.data!;
        final shown = docs
            .where((d) => (d['id'] as String?) != meUid)
            .map((d) => Contact.fromMap(d['id'] as String, d))
            .toList();
        if (shown.isEmpty) {
          return const Center(child: Text('ยังไม่มีเพื่อน เพิ่มเพื่อนเลย'));
        }
        return ListView.separated(
          itemCount: shown.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, idx) {
            final c = shown[idx];
            return ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConversationScreen(contact: c),
                ),
              ),
              leading: SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: () {
                          if (c.photoUrl != null && c.photoUrl!.isNotEmpty) {
                            final url = c.photoUrl!;
                            if (url.startsWith('file://')) {
                              final p = url.replaceFirst('file://', '');
                              final f = File(p);
                              if (f.existsSync()) {
                                return Image.file(File(p), fit: BoxFit.cover);
                              }
                            } else {
                              return Image.network(url, fit: BoxFit.cover);
                            }
                          }
                          return Container(
                            color: c.avatarColor,
                            child: Center(
                              child: Text(
                                c.name[0],
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          );
                        }(),
                      ),
                    ),
                    if (c.online)
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2DD36F),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  Text(
                    c.time,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              subtitle: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.lastMessage,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (c.unread > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF7A00),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${c.unread}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProfileTab() {
    return FutureBuilder<UserProfile?>(
      future: AuthService.instance.getCurrentUser(),
      builder: (context, userProfileSnap) {
        if (userProfileSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: LoadingSpinner());
        }
        if (!userProfileSnap.hasData || userProfileSnap.data == null) {
          return const Center(child: Text('Not signed in'));
        }

        final userProfile = userProfileSnap.data!;
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: P2PService.instance.usersStream(),
          builder: (context, p2pUsersSnap) {
            bool isOnline = false;
            String statusText = '';
            Map<String, dynamic>? p2pUserData;

            if (p2pUsersSnap.hasData) {
              try {
                p2pUserData = p2pUsersSnap.data!.firstWhere(
                  (u) => u['id'] == userProfile.uid,
                  orElse: () => <String, dynamic>{},
                );
                isOnline = p2pUserData['online'] ?? false;
                statusText = p2pUserData['status'] ?? 'Available';
              } catch (_) {
                // User not found in P2P stream, might be offline or just joined
              }
            }

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(48),
                    child: () {
                      if (userProfile.photoPath != null &&
                          userProfile.photoPath!.isNotEmpty) {
                        final url = userProfile.photoPath!;
                        if (url.startsWith('file://')) {
                          final p = url.replaceFirst('file://', '');
                          return Image.file(
                            File(p),
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, st) => Container(
                              width: 96,
                              height: 96,
                              color: Colors.grey,
                            ),
                          );
                        }
                        if (url.startsWith('http') || url.startsWith('https')) {
                          return Image.network(
                            url,
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, st) => Container(
                              width: 96,
                              height: 96,
                              color: Colors.grey,
                            ),
                          );
                        }
                      }
                      return Container(
                        width: 96,
                        height: 96,
                        color: Colors.grey,
                        child: Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.white,
                        ),
                      );
                    }(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    userProfile.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('@${userProfile.username}'),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: isOnline ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(statusText),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/profile'),
                    child: const Text('Edit profile'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Image.asset('assets/logo.png', height: 40), // Using app's logo
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.pushNamed(context, '/search');
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _navIndex,
        children: [
          _buildContactsTab(),
          _buildCallsTab(),
          _buildChatsTab(),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: SizedBox(
        height: 92,
        child: LiquidNav(currentIndex: _navIndex, onTap: _onNavTap),
      ),
    );
  }
}
