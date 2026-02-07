import 'package:flutter/material.dart';
import 'glass_card.dart';

class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.check_circle_outline, size: 18),
              SizedBox(width: 8),
              Text("Progress completion",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Spacer(),
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.blue,
                child: Icon(Icons.arrow_forward,
                    color: Colors.white, size: 14),
              )
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: 0.63,
            minHeight: 10,
            borderRadius: BorderRadius.circular(20),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text("3 minutes",
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              Text("10 hours",
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          )
        ],
      ),
    );
  }
}
