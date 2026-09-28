import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/download/download_manager.dart';
import '../../services/download/download_task_item.dart';
import 'widgets/download_task_card.dart';

class DownloadsScreen extends StatelessWidget {
  final VoidCallback onAddVideo;

  const DownloadsScreen({
    super.key,
    required this.onAddVideo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_rounded),
            tooltip: 'Clear completed',
            onPressed: () {
              DownloadManager.instance.clearCompleted();
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: DownloadManager.instance,
        builder: (context, _) {
          final tasks = DownloadManager.instance.tasks;

          if (tasks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.cardTheme.color,
                        border: Border.all(
                          color: theme.colorScheme.outline.withAlpha(60),
                        ),
                      ),
                      child: Icon(
                        Icons.download_done_rounded,
                        size: 38,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No downloads in queue',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'All your ongoing, queued, or completed downloads will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: onAddVideo,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Start Download'),
                    ),
                  ],
                ),
              ),
            );
          }

          final activeTasks = tasks
              .where((t) =>
                  t.status == DownloadStatus.downloading ||
                  t.status == DownloadStatus.pending)
              .toList();
          final historyTasks = tasks
              .where((t) =>
                  t.status != DownloadStatus.downloading &&
                  t.status != DownloadStatus.pending)
              .toList();

          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 100),
            children: [
              if (activeTasks.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Active (${activeTasks.length})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentColor,
                    ),
                  ),
                ),
                ...activeTasks.map((t) => DownloadTaskCard(
                      task: t,
                      onCancel: () => DownloadManager.instance.cancelDownload(t.id),
                      onRetry: () => DownloadManager.instance.retryDownload(t.id),
                      onRemove: () => DownloadManager.instance.removeTask(t.id),
                    )),
                const SizedBox(height: 16),
              ],
              if (historyTasks.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Completed & History (${historyTasks.length})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ),
                ...historyTasks.map((t) => DownloadTaskCard(
                      task: t,
                      onCancel: () => DownloadManager.instance.cancelDownload(t.id),
                      onRetry: () => DownloadManager.instance.retryDownload(t.id),
                      onRemove: () => DownloadManager.instance.removeTask(t.id),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }
}
