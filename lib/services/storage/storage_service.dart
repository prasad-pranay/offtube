import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StorageService {
  static StorageService? _instance;
  static StorageService get instance => _instance ??= StorageService._();
  StorageService._();

  late Directory _appDir;
  late Directory _videosDir;
  late Directory _thumbnailsDir;
  late Directory _tempDir;

  Directory get videosDir => _videosDir;
  Directory get thumbnailsDir => _thumbnailsDir;
  Directory get tempDir => _tempDir;

  Future<void> init() async {
    _appDir = await getApplicationDocumentsDirectory();
    
    _videosDir = Directory(p.join(_appDir.path, 'AppStorage', 'videos'));
    _thumbnailsDir = Directory(p.join(_appDir.path, 'AppStorage', 'thumbnails'));
    _tempDir = Directory(p.join(_appDir.path, 'AppStorage', 'temp'));

    await _videosDir.create(recursive: true);
    await _thumbnailsDir.create(recursive: true);
    await _tempDir.create(recursive: true);
  }

  String getVideoPath(String videoId) {
    return p.join(_videosDir.path, '$videoId.mp4');
  }

  String getThumbnailPath(String videoId) {
    return p.join(_thumbnailsDir.path, '$videoId.jpg');
  }

  Directory getTempDownloadDir(String downloadId) {
    return Directory(p.join(_tempDir.path, downloadId));
  }

  Future<void> deleteVideoFiles(String videoId) async {
    final vFile = File(getVideoPath(videoId));
    if (await vFile.exists()) {
      await vFile.delete();
    }

    final tFile = File(getThumbnailPath(videoId));
    if (await tFile.exists()) {
      await tFile.delete();
    }
  }

  Future<int> getTotalStorageUsedBytes() async {
    int totalBytes = 0;
    try {
      if (await _videosDir.exists()) {
        await for (final file in _videosDir.list(recursive: true)) {
          if (file is File) {
            totalBytes += await file.length();
          }
        }
      }
      if (await _thumbnailsDir.exists()) {
        await for (final file in _thumbnailsDir.list(recursive: true)) {
          if (file is File) {
            totalBytes += await file.length();
          }
        }
      }
    } catch (_) {}
    return totalBytes;
  }

  Future<void> clearAllStorage() async {
    try {
      if (await _videosDir.exists()) {
        await _videosDir.delete(recursive: true);
        await _videosDir.create(recursive: true);
      }
      if (await _thumbnailsDir.exists()) {
        await _thumbnailsDir.delete(recursive: true);
        await _thumbnailsDir.create(recursive: true);
      }
      if (await _tempDir.exists()) {
        await _tempDir.delete(recursive: true);
        await _tempDir.create(recursive: true);
      }
    } catch (_) {}
  }
}
