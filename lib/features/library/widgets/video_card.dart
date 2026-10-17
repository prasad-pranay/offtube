import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:offlinetube/core/theme/app_theme.dart';
import 'package:offlinetube/data/models/video_model.dart';
import 'package:share_plus/share_plus.dart';

class VideoCard extends StatelessWidget {
  final VideoModel video;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onInfo;
  final String path;

  const VideoCard({
    super.key,
    required this.video,
    required this.onTap,
    required this.onPlay,
    required this.onDelete,
    required this.onInfo,
    required this.path,
  });

  Future<void> shareVideo(String path, String id) async {
    // final directory = await getApplicationDocumentsDirectory();

    final file = File('${path}');

    if (!await file.exists()) return;

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'video/mp4')],
        text: 'https://www.youtube.com/watch?v=$id',
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required ThemeData theme,
    bool isDestructive = false,
  }) {
    final color = isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w300,
            color: isDestructive
                ? theme.colorScheme.error
                : theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

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
                          fontWeight: FontWeight.w400,
                          fontSize: 16,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (video.author != null &&
                              video.author!.isNotEmpty) ...[
                            Flexible(
                              child: Text(
                                video.author!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.tertiary,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text("•"),
                          ),
                          Text(
                            video.formattedDownloadDate,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.tertiary,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text("•"),
                          ),
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
                  iconSize: 22,
                  tooltip: 'More options',
                  icon: Icon(
                    CupertinoIcons.ellipsis,
                    size: 21,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  color: theme.colorScheme.surface,
                  elevation: 8,
                  surfaceTintColor: const Color.fromARGB(255, 72, 72, 72),
                  constraints: const BoxConstraints(
                    minWidth: 190,
                    maxWidth: 220,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'play':
                        onPlay();
                        break;
                      case 'info':
                        onInfo();
                        break;
                      case 'share':
                        shareVideo(path, video.id);
                        break;
                      case 'delete':
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'play',
                      height: 44,
                      child: _menuItem(
                        icon: CupertinoIcons.play,
                        label: 'Play',
                        theme: theme,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'info',
                      height: 44,
                      child: _menuItem(
                        icon: CupertinoIcons.info,
                        label: 'Video details',
                        theme: theme,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      height: 44,
                      child: _menuItem(
                        icon: CupertinoIcons.arrowshape_turn_up_left,
                        label: 'Share video',
                        theme: theme,
                      ),
                    ),
                    const PopupMenuDivider(height: 8),
                    PopupMenuItem(
                      value: 'delete',
                      height: 44,
                      child: _menuItem(
                        icon: CupertinoIcons.trash,
                        label: 'Delete',
                        theme: theme,
                        isDestructive: true,
                      ),
                    ),
                  ],
                ),

                // PopupMenuButton<String>(
                //   padding: EdgeInsets.zero,
                //   icon: Icon(
                //     CupertinoIcons.ellipsis,
                //     size: 22,
                //     color: theme.textTheme.bodySmall?.color,
                //   ),
                //   color: theme.cardTheme.color,
                //   shape: RoundedRectangleBorder(
                //     borderRadius: BorderRadius.circular(16),
                //     side: BorderSide(
                //       color: theme.colorScheme.outline.withAlpha(50),
                //       width: 0.8,
                //     ),
                //   ),
                //   onSelected: (value) {
                //     switch (value) {
                //       case 'play':
                //         onPlay();
                //         break;
                //       case 'info':
                //         onInfo();
                //         break;
                //       case 'share':
                //         shareVideo(path, video.id);
                //         break;
                //       case 'delete':
                //         onDelete();
                //         break;
                //     }
                //   },
                //   itemBuilder: (context) => [
                //     const PopupMenuItem(
                //       value: 'play',
                //       child: Row(
                //         children: [
                //           Icon(Icons.play_arrow_rounded, size: 20),
                //           SizedBox(width: 10),
                //           Text('Play'),
                //         ],
                //       ),
                //     ),
                //     const PopupMenuItem(
                //       value: 'info',
                //       child: Row(
                //         children: [
                //           Icon(Icons.info_outline_rounded, size: 20),
                //           SizedBox(width: 10),
                //           Text('Video details'),
                //         ],
                //       ),
                //     ),
                //     const PopupMenuItem(
                //       value: 'share',
                //       child: Row(
                //         children: [
                //           Icon(Icons.share_rounded, size: 20),
                //           SizedBox(width: 10),
                //           Text('Share Video'),
                //         ],
                //       ),
                //     ),
                //     const PopupMenuDivider(),
                //     const PopupMenuItem(
                //       value: 'delete',
                //       child: Row(
                //         children: [
                //           Icon(
                //             Icons.delete_outline_rounded,
                //             size: 20,
                //             color: Colors.redAccent,
                //           ),
                //           SizedBox(width: 10),
                //           Text(
                //             'Delete',
                //             style: TextStyle(color: Colors.redAccent),
                //           ),
                //         ],
                //       ),
                //     ),
                //   ],
                // ),
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
