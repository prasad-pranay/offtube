import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

// import '../../services/extractor/video_extractor_service.dart';
import '../../services/extractor/extracted_video_info.dart';

// final GlobalKey miniPlayerKey = GlobalKey();

class PlayerManager extends ChangeNotifier {
  static final PlayerManager instance = PlayerManager._();

  PlayerManager._();

  VideoPlayerController? controller;
  ExtractedVideoInfo? videoInfo;

  bool isMiniPlayerVisible = false;
  bool isFullPlayerVisible = false;
  bool isLoading = false;

  Future<void> playVideo(ExtractedVideoInfo info) async {
    isLoading = true;
    notifyListeners();

    try {
      final playableFormats = info.formats.where(
        (format) =>
            format.hasVideo && format.hasAudio && format.streamUrl.isNotEmpty,
      );

      if (playableFormats.isEmpty) {
        throw Exception('No playable stream found.');
      }

      final format = playableFormats.reduce(
        (a, b) => (a.height ?? 0) > (b.height ?? 0) ? a : b,
      );

      await controller?.dispose();

      final newController = VideoPlayerController.networkUrl(
        Uri.parse(format.streamUrl),
      );

      await newController.initialize();

      controller = newController;
      videoInfo = info;

      await controller!.play();

      isLoading = false;
      isFullPlayerVisible = true;
      isMiniPlayerVisible = false;

      notifyListeners();
    } catch (e) {
      isLoading = false;
      notifyListeners();

      rethrow;
    }
  }

  void minimize() {
    isFullPlayerVisible = false;
    isMiniPlayerVisible = true;

    notifyListeners();
  }

  void maximize() {
    isMiniPlayerVisible = false;
    isFullPlayerVisible = true;

    notifyListeners();
  }

  Future<void> close() async {
    isMiniPlayerVisible = false;
    isFullPlayerVisible = false;

    await controller?.dispose();

    controller = null;
    videoInfo = null;

    notifyListeners();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}
