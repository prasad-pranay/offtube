class ExtractedFormat {
  final String formatId;
  final String
  qualityLabel; // e.g. "1080p", "720p", "480p", "360p", "Audio Only"
  final int? height;
  final int? fps;
  final int? sizeBytes;
  final String container; // e.g. "mp4", "webm", "m4a"
  final bool hasVideo;
  final bool hasAudio;
  final String streamUrl;
  final String? videoUrl;

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
    required this.videoUrl,
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
  final String? channelId;
  final String? uploadDate;
  final int? viewCount;
  final bool? isLive;
  final String? type;

  const ExtractedVideoInfo({
    required this.id,
    required this.url,
    required this.title,
    this.description,
    this.author,
    this.thumbnailUrl,
    this.channelId,
    this.uploadDate,
    this.viewCount,
    this.isLive,
    this.type,
    required this.durationSeconds,
    required this.formats,
  });
}

class ExtractedChannelInfo {
  final String id;
  final String url;
  final String description;
  final String author;
  final int videoCount;
  final String thumbnailUrl;
  final String type;

  const ExtractedChannelInfo({
    required this.id,
    required this.url,
    required this.description,
    required this.author,
    required this.videoCount,
    required this.thumbnailUrl,
    required this.type,
  });
}

class ExtractedPlaylistInfo {
  final String id;
  final String url;
  final String title;
  final int videoCount;
  final List thumbnailUrl;
  final String type;

  const ExtractedPlaylistInfo({
    required this.type,
    required this.id,
    required this.url,
    required this.title,
    required this.videoCount,
    required this.thumbnailUrl,
  });
}
