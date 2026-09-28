import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:offlinetube/core/theme/app_theme.dart';
import 'package:offlinetube/data/models/video_model.dart';

class VideoCard extends StatelessWidget {
  final VideoModel video;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onInfo;

  const VideoCard({
    super.key,
    required this.video,
    required this.onTap,
    required this.onPlay,
    required this.onDelete,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbFile = File(video.thumbnailPath);
    final hasThumb = thumbFile.existsSync();
    final Size size = MediaQuery.of(context).size;

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Thumbnail with Duration & Progress
          SizedBox(
            height: 220,
            width: size.width,
            child: Stack(
              children: [
                Container(
                  width: size.width,
                  color: theme.colorScheme.surface,
                  child: hasThumb
                      ? Image.file(
                          thumbFile,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildPlaceholder(context),
                        )
                      : _buildPlaceholder(context),
                ),
                // Duration badge
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(200),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.music_note, size: 15),
                        SizedBox(width: 5),
                        Text(
                          video.formattedDuration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 10, bottom: 25),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (video.author != null &&
                              video.author!.isNotEmpty) ...[
                            Icon(
                              CupertinoIcons.play_circle,
                              size: 13,
                              color: theme.colorScheme.tertiary,
                            ),
                            SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                video.author!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.tertiary,
                                ),
                              ),
                            ),
                            SizedBox(width: 20),
                          ],
                          Icon(
                            CupertinoIcons.calendar,
                            size: 13,
                            color: theme.colorScheme.tertiary,
                          ),
                          SizedBox(width: 5),
                          Text(
                            video.formattedDownloadDate,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.tertiary,
                            ),
                          ),
                          SizedBox(width: 20),
                          Icon(
                            Icons.hardware_outlined,
                            size: 13,
                            color: theme.colorScheme.tertiary,
                          ),
                          SizedBox(width: 5),
                          Text(
                            video.formattedFileSize,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.tertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Three dot menu
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    size: 26,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  color: theme.cardTheme.color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: theme.colorScheme.outline.withAlpha(50),
                      width: 0.8,
                    ),
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'play':
                        onPlay();
                        break;
                      case 'info':
                        onInfo();
                        break;
                      case 'delete':
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'play',
                      child: Row(
                        children: [
                          Icon(Icons.play_arrow_rounded, size: 20),
                          SizedBox(width: 10),
                          Text('Play'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'info',
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 20),
                          SizedBox(width: 10),
                          Text('Video details'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: Colors.redAccent,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Delete',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.play_circle_outline_rounded,
        size: 32,
        color: AppTheme.accentColor,
      ),
    );
  }
}
