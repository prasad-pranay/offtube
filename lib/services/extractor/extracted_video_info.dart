class ExtractedFormat {
  final String formatId;
  final String qualityLabel; // e.g. "1080p", "720p", "480p", "360p", "Audio Only"
  final int? height;
  final int? fps;
  final int? sizeBytes;
  final String container; // e.g. "mp4", "webm", "m4a"
  final bool hasVideo;
  final bool hasAudio;
  final String streamUrl;

  const ExtractedFormat({
    required this.formatId,
    required this.qualityLabel,
    this.height,
    this.fps,
    this.sizeBytes,
    required this.container,
    required this.hasVideo,
    required this.hasAudio,
    required this.streamUrl,
  });

  String get formattedSize {
    if (sizeBytes == null || sizeBytes! <= 0) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = sizeBytes!.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }
}

class ExtractedVideoInfo {
  final String id;
  final String url;
  final String title;
  final String? description;
  final String? author;
  final String? thumbnailUrl;
  final int durationSeconds;
  final List<ExtractedFormat> formats;

  const ExtractedVideoInfo({
    required this.id,
    required this.url,
    required this.title,
    this.description,
    this.author,
    this.thumbnailUrl,
    required this.durationSeconds,
    required this.formats,
  });

  String get formattedDuration {
    final duration = Duration(seconds: durationSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
