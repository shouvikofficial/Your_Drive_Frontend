import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class OfflineBanner extends StatefulWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner>
    with SingleTickerProviderStateMixin {
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isOffline = false;
  bool _isDismissed = false;

  late AnimationController _controller;
  late Animation<double> _sizeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _sizeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _initConnectivity();
    _subscription = Connectivity().onConnectivityChanged.listen(_update);
  }

  Future<void> _initConnectivity() async {
    _update(await Connectivity().checkConnectivity());
  }

  void _update(List<ConnectivityResult> results) {
    final offline = results.isNotEmpty && results.every((r) => r == ConnectivityResult.none);
    if (offline == _isOffline) return;
    if (!mounted) return;

    setState(() {
      _isOffline = offline;
      if (offline) _isDismissed = false; // re-show on new disconnect
    });

    if (offline && !_isDismissed) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _dismiss() {
    setState(() => _isDismissed = true);
    _controller.reverse();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Banner (Google Drive style: flat strip) ──
        SizeTransition(
          sizeFactor: _sizeAnimation,
          axisAlignment: -1,
          child: GestureDetector(
            onVerticalDragEnd: (_) => _dismiss(),
            child: Material(
              color: Colors.grey[800],
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.white70, size: 16),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'No internet connection',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _dismiss,
                        child: const Icon(Icons.close, color: Colors.white70, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Main content ──
        Expanded(child: widget.child),
      ],
    );
  }
}
