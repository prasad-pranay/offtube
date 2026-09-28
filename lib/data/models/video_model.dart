import 'package:intl/intl.dart';

class VideoModel {
  final String id;
  final String title;
  final String? description;
  final String? author;
  final String videoPath;
  final String thumbnailPath;
  final int durationSeconds;
  final int fileSizeBytes;
  final DateTime downloadDate;
  final DateTime? lastPlayedAt;
  final int playbackPositionSeconds;
  final double watchProgress; // 0.0 to 1.0
  final String quality;
  final bool isCompleted;

  const VideoModel({
    required this.id,
    required this.title,
    this.description,
    this.author,
    required this.videoPath,
    required this.thumbnailPath,
    required this.durationSeconds,
    required this.fileSizeBytes,
    required this.downloadDate,
    this.lastPlayedAt,
    this.playbackPositionSeconds = 0,
    this.watchProgress = 0.0,
    required this.quality,
    this.isCompleted = false,
  });

  VideoModel copyWith({
    String? id,
    String? title,
    String? description,
    String? author,
    String? videoPath,
    String? thumbnailPath,
    int? durationSeconds,
    int? fileSizeBytes,
    DateTime? downloadDate,
    DateTime? lastPlayedAt,
    int? playbackPositionSeconds,
    double? watchProgress,
    String? quality,
    bool? isCompleted,
  }) {
    return VideoModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      author: author ?? this.author,
      videoPath: videoPath ?? this.videoPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      downloadDate: downloadDate ?? this.downloadDate,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      playbackPositionSeconds:
          playbackPositionSeconds ?? this.playbackPositionSeconds,
      watchProgress: watchProgress ?? this.watchProgress,
      quality: quality ?? this.quality,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'author': author,
      'videoPath': videoPath,
      'thumbnailPath': thumbnailPath,
      'durationSeconds': durationSeconds,
      'fileSizeBytes': fileSizeBytes,
      'downloadDate': downloadDate.toIso8601String(),
      'lastPlayedAt': lastPlayedAt?.toIso8601String(),
      'playbackPositionSeconds': playbackPositionSeconds,
      'watchProgress': watchProgress,
      'quality': quality,
      'isCompleted': isCompleted,
    };
  }

  factory VideoModel.fromMap(Map<String, dynamic> map) {
    return VideoModel(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Untitled Video',
      description: map['description'] as String?,
      author: map['author'] as String?,
      videoPath: map['videoPath'] as String? ?? '',
      thumbnailPath: map['thumbnailPath'] as String? ?? '',
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      fileSizeBytes: (map['fileSizeBytes'] as num?)?.toInt() ?? 0,
      downloadDate: map['downloadDate'] != null
          ? DateTime.parse(map['downloadDate'] as String)
          : DateTime.now(),
      lastPlayedAt: map['lastPlayedAt'] != null
          ? DateTime.parse(map['lastPlayedAt'] as String)
          : null,
      playbackPositionSeconds:
          (map['playbackPositionSeconds'] as num?)?.toInt() ?? 0,
      watchProgress: (map['watchProgress'] as num?)?.toDouble() ?? 0.0,
      quality: map['quality'] as String? ?? 'Best',
      isCompleted: map['isCompleted'] as bool? ?? false,
    );
  }

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

  String get formattedFileSize {
    if (fileSizeBytes <= 0) return 'Unknown size';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = fileSizeBytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String get formattedDownloadDate {
    return DateFormat.yMMMd().format(downloadDate);
  }
}
