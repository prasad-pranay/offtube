enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

class DownloadTaskItem {
  final String id; // Unique download task ID
  final String videoId;
  final String title;
  final String? author;
  final String? description;
  final String? thumbnailUrl;
  final int durationSeconds;
  final String qualityLabel;
  final String streamUrl;
  final String? formatId;
  final String container;
  int totalBytes;
  
  // State
  int downloadedBytes;
  double progress; // 0.0 to 1.0
  double speedBytesPerSec;
  int remainingSeconds;
  DownloadStatus status;
  String currentStage; // e.g. "Downloading video", "Fetching thumbnail", "Finalizing"
  String? errorMessage;

  DownloadTaskItem({
    required this.id,
    required this.videoId,
    required this.title,
    this.author,
    this.description,
    this.thumbnailUrl,
    required this.durationSeconds,
    required this.qualityLabel,
    required this.streamUrl,
    this.formatId,
    this.container = 'mp4',
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.progress = 0.0,
    this.speedBytesPerSec = 0.0,
    this.remainingSeconds = 0,
    this.status = DownloadStatus.pending,
    this.currentStage = 'Pending',
    this.errorMessage,
  });

  String get formattedSpeed {
    if (speedBytesPerSec <= 0) return '0 KB/s';
    const suffixes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    var i = 0;
    double speed = speedBytesPerSec;
    while (speed >= 1024 && i < suffixes.length - 1) {
      speed /= 1024;
      i++;
    }
    return '${speed.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String get formattedDownloadedSize {
    return _formatSize(downloadedBytes);
  }

  String get formattedTotalSize {
    if (totalBytes <= 0) return 'Unknown size';
    return _formatSize(totalBytes);
  }

  String get formattedRemainingTime {
    if (remainingSeconds <= 0 || remainingSeconds > 86400) return '--:--';
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} remaining';
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '0 MB';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }
}
