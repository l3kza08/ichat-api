import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For formatting time

class Bubble extends StatelessWidget {
  final String? text;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final bool isMe;
  final DateTime? timestamp; // New parameter for timestamp

  const Bubble({
    super.key,
    this.text,
    this.imageUrl,
    this.imageBytes,
    required this.isMe,
    this.timestamp, // Initialize new parameter
  });

  @override
  Widget build(BuildContext context) {
    Widget messageContent;
    if (imageBytes != null) {
      messageContent = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(imageBytes!, width: 200, fit: BoxFit.cover),
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      Widget img;
      if (imageUrl!.startsWith('file://')) {
        final p = imageUrl!.replaceFirst('file://', '');
        img = Image.file(File(p), width: 200, fit: BoxFit.cover);
      } else {
        img = Image.network(imageUrl!, width: 200, fit: BoxFit.cover);
      }
      messageContent = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: img,
      );
    } else {
      messageContent = Text(
        text ?? '',
        style: TextStyle(
          color: isMe ? Colors.white : Colors.black87,
        ), // Changed text color for 'isMe' messages
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? const Color(0xFF0086C9)
              : Colors.grey.shade200, // Distinct colors
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe
                ? const Radius.circular(16)
                : const Radius.circular(4),
            bottomRight: isMe
                ? const Radius.circular(4)
                : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(26),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            messageContent,
            if (timestamp != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  DateFormat('HH:mm').format(timestamp!), // Format time
                  style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.black54,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
