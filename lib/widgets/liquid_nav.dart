import 'package:flutter/material.dart';

class LiquidNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const LiquidNav({super.key, this.currentIndex = 0, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      {'icon': Icons.contacts, 'label': 'Contacts'},
      {'icon': Icons.call, 'label': 'Call'},
      {'icon': Icons.chat_bubble, 'label': 'Chat'},
      {'icon': Icons.person, 'label': 'You'},
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color.fromRGBO(0, 0, 0, 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: const Color.fromRGBO(158, 158, 158, 0.12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (i) {
                final icon = items[i]['icon'] as IconData;
                final label = items[i]['label'] as String;
                final selected = i == currentIndex;

                return GestureDetector(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFE8F7FD)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          color: selected
                              ? const Color(0xFF0078AA)
                              : Colors.black87,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: selected
                              ? const Color(0xFF0078AA)
                              : Colors.black54,
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
