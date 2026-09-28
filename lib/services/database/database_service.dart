import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../data/models/video_model.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static DatabaseService get instance => _instance ??= DatabaseService._();
  DatabaseService._();

  static const String _videosBoxName = 'offline_videos';
  static const String _settingsBoxName = 'app_settings';

  Box? _videosBox;
  Box? _settingsBox;

  Future<void> init() async {
    await Hive.initFlutter();
    _videosBox = await Hive.openBox(_videosBoxName);
    _settingsBox = await Hive.openBox(_settingsBoxName);
  }

  // --- Video CRUD ---
  List<VideoModel> getAllVideos() {
    if (_videosBox == null) return [];
    final List<VideoModel> videos = [];
    for (var i = 0; i < _videosBox!.length; i++) {
      final item = _videosBox!.getAt(i);
      if (item is Map) {
        try {
          videos.add(VideoModel.fromMap(Map<String, dynamic>.from(item)));
        } catch (e) {
          debugPrint('Error parsing video from Hive: $e');
        }
      }
    }
    // Sort by downloadDate descending (newest first)
    videos.sort((a, b) => b.downloadDate.compareTo(a.downloadDate));
    return videos;
  }

  VideoModel? getVideoById(String id) {
    if (_videosBox == null) return null;
    final item = _videosBox!.get(id);
    if (item is Map) {
      return VideoModel.fromMap(Map<String, dynamic>.from(item));
    }
    return null;
  }

  Future<void> saveVideo(VideoModel video) async {
    if (_videosBox == null) return;
    await _videosBox!.put(video.id, video.toMap());
  }

  Future<void> updatePlaybackPosition(
    String id,
    int positionSeconds,
    double progress,
  ) async {
    final video = getVideoById(id);
    if (video != null) {
      final updated = video.copyWith(
        playbackPositionSeconds: positionSeconds,
        watchProgress: progress,
        lastPlayedAt: DateTime.now(),
        isCompleted: progress >= 0.95,
      );
      await saveVideo(updated);
    }
  }

  Future<void> deleteVideo(String id) async {
    if (_videosBox == null) return;
    await _videosBox!.delete(id);
  }

  Future<void> clearAllVideos() async {
    if (_videosBox == null) return;
    await _videosBox!.clear();
  }

  ValueListenable<Box> getVideosListenable() {
    return _videosBox!.listenable();
  }

  // --- Settings ---
  T getSetting<T>(String key, T defaultValue) {
    if (_settingsBox == null) return defaultValue;
    return _settingsBox!.get(key, defaultValue: defaultValue) as T;
  }

  Future<void> setSetting<T>(String key, T value) async {
    if (_settingsBox == null) return;
    await _settingsBox!.put(key, value);
  }
}
