import 'package:flutter/material.dart';

class VideoSkeleton extends StatefulWidget {
  final bool isChannel;

  const VideoSkeleton({super.key, this.isChannel = false});

  @override
  State<VideoSkeleton> createState() => _VideoSkeletonState();
}

class _VideoSkeletonState extends State<VideoSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest;
    final highlightColor = theme.colorScheme.surface;

    Widget placeholder({
      double? width,
      required double height,
      double radius = 8,
    }) {
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Color.lerp(
                baseColor,
                highlightColor,
                _controller.value * 0.5,
              ),
              borderRadius: BorderRadius.circular(radius),
            ),
          );
        },
      );
    }

    if (widget.isChannel) {
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        color: const Color(0xff180E33),
        child: Row(
          children: [
            placeholder(width: 85, height: 85, radius: 50),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  placeholder(width: 150, height: 17),
                  const SizedBox(height: 10),
                  placeholder(width: double.infinity, height: 10),
                  const SizedBox(height: 6),
                  placeholder(width: 190, height: 10),
                  const SizedBox(height: 14),
                  placeholder(width: 120, height: 35, radius: 24),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Video skeleton
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thumbnail
        placeholder(width: double.infinity, height: 220, radius: 14),

        const SizedBox(height: 14),

        // Avatar, title and metadata
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              placeholder(width: 42, height: 42, radius: 50),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    placeholder(width: double.infinity, height: 14),
                    const SizedBox(height: 8),
                    placeholder(width: 190, height: 14),
                    const SizedBox(height: 10),
                    placeholder(width: 220, height: 10),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Download button placeholder
              placeholder(width: 42, height: 42, radius: 50),
            ],
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}
