import 'dart:ui';
import 'package:flutter/material.dart';

class VideoLoadingOverlay extends StatelessWidget {
  final String? thumbnail;
  final String title;

  const VideoLoadingOverlay({
    super.key,
    required this.thumbnail,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Blurred background
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.black.withOpacity(0.38)),
            ),
          ),

          // Center loading card
          Center(
            child: Container(
              width: MediaQuery.sizeOf(context).width * 0.82,
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              decoration: BoxDecoration(
                color: const Color(0xFF181818).withOpacity(0.94),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 40,
                    spreadRadius: 2,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: thumbnail != null
                          ? Image.network(
                              thumbnail!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Container(
                                  color: Colors.white.withOpacity(0.06),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white54,
                                    size: 42,
                                  ),
                                );
                              },
                            )
                          : Container(
                              color: Colors.white.withOpacity(0.06),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white54,
                                size: 42,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Title
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Loading indicator + text
                  const SizedBox(
                    width: 25,
                    height: 25,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    "Preparing video...",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
