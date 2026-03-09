import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const ShimmerBox({
    Key? key,
    required this.width,
    required this.height,
    this.radius = 8,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class ShimmerFolderGrid extends StatelessWidget {
  final int count;
  final int crossAxisCount;

  const ShimmerFolderGrid({
    Key? key,
    this.count = 4,
    this.crossAxisCount = 2,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[100]!,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey[100]!),
            ),
            padding: const EdgeInsets.all(14),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 40, height: 40, radius: 12),
                Spacer(),
                ShimmerBox(width: double.infinity, height: 14),
                SizedBox(height: 8),
                ShimmerBox(width: 60, height: 10),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ShimmerFileList extends StatelessWidget {
  final int count;

  const ShimmerFileList({Key? key, this.count = 5}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey[100]!),
            ),
            child: Row(
              children: [
                const ShimmerBox(width: 48, height: 48, radius: 12),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(width: 180, height: 14),
                      SizedBox(height: 8),
                      ShimmerBox(width: 100, height: 12),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const ShimmerBox(width: 24, height: 24, radius: 12),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ShimmerFileGrid extends StatelessWidget {
  final int count;
  final int crossAxisCount;

  const ShimmerFileGrid({
    Key? key,
    this.count = 6,
    this.crossAxisCount = 3,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[100]!,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey[100]!),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: ShimmerBox(width: double.infinity, height: double.infinity, radius: 14),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(10, 0, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(width: double.infinity, height: 12),
                      SizedBox(height: 6),
                      ShimmerBox(width: 40, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
