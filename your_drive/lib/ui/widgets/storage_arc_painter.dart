import 'dart:math';
import 'package:flutter/material.dart';

/// A custom painter that draws a modern arc-style storage indicator
class StorageArcPainter extends CustomPainter {
  final double progress; // 0.0 - 1.0
  final Color trackColor;
  final List<Color> gradientColors;
  final double strokeWidth;

  StorageArcPainter({
    required this.progress,
    this.trackColor = const Color(0xFFE2E8F0),
    this.gradientColors = const [Color(0xFF4A6CF7), Color(0xFF8B5CF6)],
    this.strokeWidth = 12,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (min(size.width, size.height) / 2) - strokeWidth;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi * 0.75,
      pi * 1.5,
      false,
      trackPaint,
    );

    // Gradient arc
    final gradient = SweepGradient(
      startAngle: -pi * 0.75,
      endAngle: pi * 0.75,
      colors: gradientColors,
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi * 0.75,
      pi * 1.5 * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );

    // Glow dot at the tip
    final tipAngle = -pi * 0.75 + pi * 1.5 * progress.clamp(0.0, 1.0);
    final tipPoint = Offset(
      center.dx + radius * cos(tipAngle),
      center.dy + radius * sin(tipAngle),
    );

    final glowPaint = Paint()
      ..color = gradientColors.last.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(tipPoint, strokeWidth * 0.6, glowPaint);

    final dotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(tipPoint, strokeWidth * 0.35, dotPaint);
  }

  @override
  bool shouldRepaint(covariant StorageArcPainter old) =>
      old.progress != progress;
}

/// A widget that animates the storage arc from 0 to the target value
class AnimatedStorageArc extends StatefulWidget {
  final double progress;
  final double size;
  final String usedLabel;
  final String totalLabel;
  final List<Color> gradientColors;

  const AnimatedStorageArc({
    super.key,
    required this.progress,
    this.size = 160,
    this.usedLabel = '0 GB',
    this.totalLabel = '50 GB',
    this.gradientColors = const [Color(0xFF4A6CF7), Color(0xFF8B5CF6)],
  });

  @override
  State<AnimatedStorageArc> createState() => _AnimatedStorageArcState();
}

class _AnimatedStorageArcState extends State<AnimatedStorageArc>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedStorageArc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: StorageArcPainter(
                  progress: widget.progress * _animation.value,
                  gradientColors: widget.gradientColors,
                  strokeWidth: 10,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.usedLabel,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'of ${widget.totalLabel}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
