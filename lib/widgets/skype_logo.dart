import 'package:flutter/material.dart';

class SkypeLogo extends StatelessWidget {
  final double? width;
  final double? height;

  const SkypeLogo({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    // Prefer an image asset named assets/logo.png. If missing, fall back to text.
    final w = width ?? 120.0;
    final h = height ?? 32.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/logo.png',
          width: w,
          height: h,
          fit: BoxFit.contain,
          errorBuilder: (ctx, error, stack) => Text(
            'ichat',
            style: TextStyle(
              color: Theme.of(ctx).colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: h * 0.6,
            ),
          ),
        ),
      ],
    );
  }
}
