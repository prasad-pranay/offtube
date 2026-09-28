import 'package:flutter/material.dart';
import 'package:offlinetube/core/theme/app_theme.dart';
import 'package:offlinetube/services/download/download_task_item.dart';

class DownloadTaskCard extends StatelessWidget {
  final DownloadTaskItem task;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const DownloadTaskCard({
    super.key,
    required this.task,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color statusColor;
    IconData statusIcon;
    switch (task.status) {
      case DownloadStatus.downloading:
        statusColor = AppTheme.accentColor;
        statusIcon = Icons.downloading_rounded;
        break;
      case DownloadStatus.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
        break;
      case DownloadStatus.failed:
        statusColor = Colors.redAccent;
        statusIcon = Icons.error_outline_rounded;
        break;
      case DownloadStatus.paused:
        statusColor = Colors.orange;
        statusIcon = Icons.pause_circle_outline_rounded;
        break;
      case DownloadStatus.cancelled:
        statusColor = Colors.grey;
        statusIcon = Icons.cancel_outlined;
        break;
      case DownloadStatus.pending:
        statusColor = Colors.blueGrey;
        statusIcon = Icons.schedule_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withAlpha(50),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail / Icon
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 64,
                  height: 48,
                  color: theme.colorScheme.surface,
                  child: task.thumbnailUrl != null
                      ? Image.network(
                          task.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Icon(statusIcon, color: statusColor, size: 28),
                        )
                      : Icon(statusIcon, color: statusColor, size: 28),
                ),
              ),
              const SizedBox(width: 12),
              // Title & Quality
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            task.qualityLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          task.currentStage,
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Action buttons (Cancel, Retry, Delete)
              if (task.status == DownloadStatus.downloading ||
                  task.status == DownloadStatus.pending)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onCancel,
                  tooltip: 'Cancel',
                )
              else if (task.status == DownloadStatus.failed)
                IconButton(
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: AppTheme.accentColor,
                  ),
                  onPressed: onRetry,
                  tooltip: 'Retry',
                )
              else
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  onPressed: onRemove,
                  tooltip: 'Remove',
                ),
            ],
          ),
          // Progress bar & stats for downloading
          if (task.status == DownloadStatus.downloading) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress > 0 ? task.progress : null,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surface,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.accentColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(task.progress * 100).toInt()}% • ${task.formattedDownloadedSize} / ${task.formattedTotalSize}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${task.formattedSpeed} • ${task.formattedRemainingTime}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ] else if (task.status == DownloadStatus.failed &&
              task.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              task.errorMessage!,
              maxLines: 10,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }
}
