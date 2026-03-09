import 'package:flutter/material.dart';

class ShimmerRect extends StatefulWidget {
  final double width, height, radius;
  
  const ShimmerRect({
    super.key,
    required this.width,
    required this.height,
    this.radius = 6,
  });

  @override
  State<ShimmerRect> createState() => _ShimmerRectState();
}

class _ShimmerRectState extends State<ShimmerRect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacity = Tween(begin: 0.06, end: 0.14).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(_opacity.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}
