import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/playback/playback_coordinator.dart';

class MiniPlayerWidget extends StatelessWidget {
  final VoidCallback onExpand;

  const MiniPlayerWidget({super.key, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: PlaybackCoordinator.instance,
      builder: (context, _) {
        final coordinator = PlaybackCoordinator.instance;
        final video = coordinator.currentVideo;

        if (!coordinator.isMiniPlayerVisible || video == null) {
          return const SizedBox.shrink();
        }

        final thumbFile = File(video.thumbnailPath);
        final hasThumb = thumbFile.existsSync();
        final progress = coordinator.duration.inMilliseconds > 0
            ? (coordinator.position.inMilliseconds /
                      coordinator.duration.inMilliseconds)
                  .clamp(0.0, 1.0)
            : 0.0;

        return Dismissible(
          key: const Key('mini_player_dismiss'),
          direction: DismissDirection.down,
          onDismissed: (_) {
            coordinator.dismissMiniPlayer();
          },
          child: GestureDetector(
            onTap: onExpand,
            onVerticalDragEnd: (details) {
              // Swipe up to expand
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! < -200) {
                onExpand();
              }
            },
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outline.withAlpha(60),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(
                      theme.brightness == Brightness.dark ? 80 : 30,
                    ),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Thin progress indicator on top
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 2.5,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.accentColor,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          // Thumbnail
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 60,
                              height: 42,
                              color: theme.colorScheme.surface,
                              child: hasThumb
                                  ? Image.file(thumbFile, fit: BoxFit.cover)
                                  : const Icon(
                                      Icons.play_circle_fill,
                                      color: AppTheme.accentColor,
                                      size: 24,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Title & subtitle
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  video.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_formatDuration(coordinator.position)} / ${_formatDuration(coordinator.duration)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Play / Pause button
                          IconButton(
                            icon: Icon(
                              coordinator.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 28,
                              color: AppTheme.accentColor,
                            ),
                            onPressed: () {
                              coordinator.togglePlayPause();
                            },
                          ),
                          // Close button
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                            onPressed: () {
                              coordinator.dismissMiniPlayer();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
