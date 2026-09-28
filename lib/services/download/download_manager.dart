import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../storage/storage_service.dart';
import '../database/database_service.dart';
import '../../data/models/video_model.dart';
import 'download_task_item.dart';

class DownloadManager extends ChangeNotifier {
  static DownloadManager? _instance;
  static DownloadManager get instance => _instance ??= DownloadManager._();
  DownloadManager._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
      },
    ),
  );

  final List<DownloadTaskItem> _tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  bool _isProcessingQueue = false;

  List<DownloadTaskItem> get tasks => List.unmodifiable(_tasks);

  int get activeDownloadsCount =>
      _tasks.where((t) => t.status == DownloadStatus.downloading).length;

  int get pendingDownloadsCount =>
      _tasks.where((t) => t.status == DownloadStatus.pending).length;

  DownloadTaskItem enqueueDownload({
    required String videoId,
    required String title,
    String? author,
    String? description,
    String? thumbnailUrl,
    required int durationSeconds,
    required String qualityLabel,
    required String streamUrl,
    String? formatId,
    String container = 'mp4',
    int totalBytes = 0,
  }) {
    final task = DownloadTaskItem(
      id: const Uuid().v4(),
      videoId: videoId,
      title: title,
      author: author,
      description: description,
      thumbnailUrl: thumbnailUrl,
      durationSeconds: durationSeconds,
      qualityLabel: qualityLabel,
      streamUrl: streamUrl,
      formatId: formatId,
      container: container,
      totalBytes: totalBytes,
      status: DownloadStatus.pending,
      currentStage: 'Queued',
    );

    _tasks.insert(0, task);
    notifyListeners();
    _processQueue();
    return task;
  }

  void _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      final pendingIndex =
          _tasks.indexWhere((t) => t.status == DownloadStatus.pending);
      if (pendingIndex != -1) {
        final task = _tasks[pendingIndex];
        await _executeDownload(task);
      }
    } finally {
      _isProcessingQueue = false;
      // If there are more pending tasks, continue
      if (_tasks.any((t) => t.status == DownloadStatus.pending)) {
        _processQueue();
      }
    }
  }

  Future<void> _executeDownload(DownloadTaskItem task) async {
    task.status = DownloadStatus.downloading;
    task.currentStage = 'Connecting...';
    notifyListeners();

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    final tempDir = StorageService.instance.getTempDownloadDir(task.id);
    await tempDir.create(recursive: true);
    final tempFilePath = '${tempDir.path}/media.${task.container}';
    final targetVideoPath = StorageService.instance.getVideoPath(task.videoId);
    final targetThumbPath = StorageService.instance.getThumbnailPath(task.videoId);

    try {
      // 1. Download Thumbnail if available
      if (task.thumbnailUrl != null && task.thumbnailUrl!.isNotEmpty) {
        task.currentStage = 'Saving thumbnail...';
        notifyListeners();
        try {
          await _dio.download(
            task.thumbnailUrl!,
            targetThumbPath,
            cancelToken: cancelToken,
          );
        } catch (e) {
          debugPrint('Thumbnail download note: $e');
        }
      }

      // 2. Download Media Stream
      task.currentStage = 'Downloading media stream...';
      notifyListeners();

      bool ytDownloadSuccess = false;

      // Attempt download via YouTubeExplode stream client first (bypasses 403 blocks)
      if (task.videoId.isNotEmpty) {
        try {
          ytDownloadSuccess = await _downloadViaYoutubeExplode(
            task,
            tempFilePath,
            cancelToken,
          );
        } catch (ytErr) {
          debugPrint('YouTubeExplode download stream note: $ytErr');
          ytDownloadSuccess = false;
        }
      }

      // Fallback to Dio if YouTubeExplode was not applicable or failed
      if (!ytDownloadSuccess) {
        if (cancelToken.isCancelled) {
          task.status = DownloadStatus.cancelled;
          task.currentStage = 'Cancelled';
          _cleanupTemp(tempDir);
          notifyListeners();
          return;
        }

        int lastDownloaded = 0;
        DateTime lastTime = DateTime.now();

        await _dio.download(
          task.streamUrl,
          tempFilePath,
          cancelToken: cancelToken,
          options: Options(
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': '*/*',
              'Accept-Encoding': 'identity',
            },
          ),
          onReceiveProgress: (received, total) {
            final now = DateTime.now();
            final durationMs = now.difference(lastTime).inMilliseconds;

            task.downloadedBytes = received;
            if (total > 0) {
              task.totalBytes = total;
              task.progress = (received / total).clamp(0.0, 1.0);
            } else if (task.totalBytes > 0) {
              task.progress = (received / task.totalBytes).clamp(0.0, 1.0);
            }

            if (durationMs >= 500) {
              final bytesSince = received - lastDownloaded;
              task.speedBytesPerSec = (bytesSince / (durationMs / 1000.0));
              if (task.speedBytesPerSec > 0 && total > received) {
                task.remainingSeconds =
                    ((total - received) / task.speedBytesPerSec).round();
              }
              lastDownloaded = received;
              lastTime = now;
              notifyListeners();
            }
          },
        );
      }

      // 3. Finalize and move file to permanent video path
      task.currentStage = 'Finalizing file...';
      notifyListeners();

      final tempFile = File(tempFilePath);
      if (await tempFile.exists()) {
        final targetFile = File(targetVideoPath);
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await tempFile.copy(targetVideoPath);
        await tempFile.delete();
      }

      // 4. Save to Database
      final video = VideoModel(
        id: task.videoId,
        title: task.title,
        description: task.description,
        author: task.author,
        videoPath: targetVideoPath,
        thumbnailPath: targetThumbPath,
        durationSeconds: task.durationSeconds,
        fileSizeBytes: task.downloadedBytes > 0 ? task.downloadedBytes : task.totalBytes,
        downloadDate: DateTime.now(),
        quality: task.qualityLabel,
        isCompleted: false,
      );

      await DatabaseService.instance.saveVideo(video);

      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.currentStage = 'Finished';
      notifyListeners();
    } on DioException catch (dioErr) {
      if (CancelToken.isCancel(dioErr)) {
        task.status = DownloadStatus.cancelled;
        task.currentStage = 'Cancelled';
      } else {
        task.status = DownloadStatus.failed;
        task.errorMessage = dioErr.message ?? 'Network connection error';
        task.currentStage = 'Failed';
      }
      _cleanupTemp(tempDir);
      notifyListeners();
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
      task.currentStage = 'Failed';
      _cleanupTemp(tempDir);
      notifyListeners();
    } finally {
      _cancelTokens.remove(task.id);
      _cleanupTemp(tempDir);
    }
  }

  /// Downloads media stream chunks directly using YouTubeExplode client
  Future<bool> _downloadViaYoutubeExplode(
    DownloadTaskItem task,
    String savePath,
    CancelToken cancelToken,
  ) async {
    final ytExplode = yt.YoutubeExplode();
    IOSink? fileSink;
    try {
      final manifest =
          await ytExplode.videos.streamsClient.getManifest(task.videoId);

      // Attempt to resolve matching stream info
      yt.StreamInfo? targetStream;

      if (task.formatId != null) {
        final cleanTag =
            task.formatId!.replaceAll(RegExp(r'^(muxed|video|audio)_'), '');
        final tagInt = int.tryParse(cleanTag);
        if (tagInt != null) {
          for (final s in manifest.streams) {
            if (s.tag == tagInt) {
              targetStream = s;
              break;
            }
          }
        }
      }

      if (targetStream == null) {
        if (manifest.muxed.isNotEmpty) {
          targetStream = manifest.muxed.first;
        } else if (manifest.streams.isNotEmpty) {
          targetStream = manifest.streams.first;
        }
      }

      if (targetStream == null) {
        return false;
      }

      final total = targetStream.size.totalBytes;
      if (total > 0) {
        task.totalBytes = total;
      }

      final file = File(savePath);
      final sink = file.openWrite();
      fileSink = sink;

      final stream = ytExplode.videos.streamsClient.get(targetStream);
      int received = 0;
      int lastDownloaded = 0;
      DateTime lastTime = DateTime.now();

      await for (final chunk in stream) {
        if (cancelToken.isCancelled) {
          await sink.flush();
          await sink.close();
          fileSink = null;
          return false;
        }

        sink.add(chunk);
        received += chunk.length;
        task.downloadedBytes = received;

        if (total > 0) {
          task.progress = (received / total).clamp(0.0, 1.0);
        }

        final now = DateTime.now();
        final durationMs = now.difference(lastTime).inMilliseconds;
        if (durationMs >= 500) {
          final bytesSince = received - lastDownloaded;
          task.speedBytesPerSec = (bytesSince / (durationMs / 1000.0));
          if (task.speedBytesPerSec > 0 && total > received) {
            task.remainingSeconds =
                ((total - received) / task.speedBytesPerSec).round();
          }
          lastDownloaded = received;
          lastTime = now;
          notifyListeners();
        }
      }

      await sink.flush();
      await sink.close();
      fileSink = null;
      return true;
    } finally {
      if (fileSink != null) {
        try {
          await fileSink.close();
        } catch (_) {}
      }
      ytExplode.close();
    }
  }

  Future<void> _cleanupTemp(Directory tempDir) async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  void cancelDownload(String taskId) {
    final token = _cancelTokens[taskId];
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled download');
    }
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex != -1) {
      final task = _tasks[taskIndex];
      if (task.status == DownloadStatus.pending) {
        task.status = DownloadStatus.cancelled;
        task.currentStage = 'Cancelled';
        notifyListeners();
      }
    }
  }

  void retryDownload(String taskId) {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex != -1) {
      final task = _tasks[taskIndex];
      task.status = DownloadStatus.pending;
      task.progress = 0.0;
      task.downloadedBytes = 0;
      task.errorMessage = null;
      task.currentStage = 'Retrying...';
      notifyListeners();
      _processQueue();
    }
  }

  void removeTask(String taskId) {
    cancelDownload(taskId);
    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  void clearCompleted() {
    _tasks.removeWhere((t) =>
        t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.cancelled);
    notifyListeners();
  }
}
