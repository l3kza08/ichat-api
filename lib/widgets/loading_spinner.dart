import 'package:flutter/material.dart';

class LoadingSpinner extends StatefulWidget {
  final double size;
  const LoadingSpinner({super.key, this.size = 48});

  @override
  State<LoadingSpinner> createState() => _LoadingSpinnerState();
}

class _LoadingSpinnerState extends State<LoadingSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return CustomPaint(
            painter: _SpinnerPainter(
              progress: _ctrl.value,
              color: Theme.of(context).primaryColor,
            ),
          );
        },
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final double progress;
  final Color color;
  _SpinnerPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    // Animate stroke width between min and max
    final strokeMax = 10.0;
    final strokeMin = 4.0;
    final strokeWidth =
        strokeMin +
        (strokeMax - strokeMin) *
            (0.5 - (0.5 * (0.5 - (0.5 - (progress - 0.5).abs()))).abs());
    paint.strokeWidth = strokeWidth;

    // Animate arc sweep
    final sweep = 2 * 3.1415926 * (0.25 + 0.5 * (0.5 - (progress - 0.5).abs()));
    final start = 2 * 3.1415926 * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter old) =>
      old.progress != progress || old.color != color;
}
