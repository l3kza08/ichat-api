import 'dart:async';
import 'package:flutter/material.dart';
import '../models/contact.dart';
import '../models/user_status.dart';
import '../services/p2p_service.dart';
import '../services/auth_service.dart';
import 'conversation.dart';
import '../widgets/loading_spinner.dart'; // Ensure LoadingSpinner is available

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  Future<List<UserProfile>>? _searchFuture;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _performSearch();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchFuture = Future.value([]);
      });
      return;
    }
    setState(() {
      _searchFuture = P2PService.instance.searchUsers(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Users')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name or username',
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _searchFuture == null
                  ? const Center(child: Text('Type to search'))
                  : FutureBuilder<List<UserProfile>>(
                      future: _searchFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(child: LoadingSpinner(size: 36));
                        }
                        if (snap.hasError) {
                          return Center(child: Text('Error: ${snap.error}'));
                        }
                        final list = snap.data ?? [];
                        if (list.isEmpty) {
                          return const Center(child: Text('No users'));
                        }
                        return ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final u = list[idx];
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  u.name.isNotEmpty ? u.name[0] : '?',
                                ),
                              ),
                              title: Text(u.name),
                              subtitle: Text(u.username),
                              onTap: () {
                                final colorIndex =
                                    u.name.hashCode.abs() %
                                    Colors.primaries.length;
                                final contact = Contact(
                                  id: u.uid,
                                  name: u.name,
                                  lastMessage: '',
                                  time: '',
                                  unread: 0,
                                  avatarColor: Colors.primaries[colorIndex],
                                  photoUrl: u.photoPath,
                                  statusType: UserStatusType.offline,
                                );
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ConversationScreen(contact: contact),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
