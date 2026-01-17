import 'package:flutter/material.dart';
import '../models/contact.dart';
import 'conversation.dart';

class ContactDetailScreen extends StatelessWidget {
  final Contact contact;
  const ContactDetailScreen({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(contact.name),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: contact.avatarColor,
              child: Text(
                contact.name[0],
                style: const TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            const SizedBox(height: 12),
            Text('Last message: ${contact.lastMessage}'),
            const SizedBox(height: 8),
            Text('Status: ${contact.online ? 'Online' : 'Offline'}'),
            const SizedBox(height: 18),
            ElevatedButton(onPressed: () {}, child: const Text('Call')),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ConversationScreen(contact: contact),
                  ),
                );
              },
              child: const Text('Message'),
            ),
          ],
        ),
      ),
    );
  }
}
