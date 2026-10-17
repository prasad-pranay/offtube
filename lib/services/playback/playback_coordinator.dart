import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:offlinetube/services/extractor/video_extractor_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import '../../data/models/video_model.dart';
import 'offline_audio_handler.dart';
import 'package:offlinetube/services/extractor/extracted_video_info.dart';

enum RepeatMode { off, all, one }

class PlaybackCoordinator extends ChangeNotifier with WidgetsBindingObserver {
  PlaybackCoordinator._();

  static PlaybackCoordinator? _instance;

  static PlaybackCoordinator get instance =>
      _instance ??= PlaybackCoordinator._();

  OfflineAudioHandler? _audioHandler;
  VideoPlayerController? _videoController;

  ExtractedVideoInfo? _currentOnlineVideo;
  bool _isOnlinePlayback = false;

  final List<VideoModel> _playlist = [];
  final List<VideoModel> _shuffledPlaylist = [];

  int _currentIndex = -1;

  int _onlineNextPlaylistIndex = -1;
  final List<ExtractedVideoInfo> _onlineNextPlayList = [];
  List<ExtractedVideoInfo> get onlineNextPlayList => _onlineNextPlayList;
  int get onlineNextPlaylistIndex => _onlineNextPlaylistIndex;

  bool _isShuffle = false;
  RepeatMode _repeatMode = RepeatMode.off;
  double _playbackSpeed = 1.0;

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool _isMiniPlayerDismissed = false;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isAppInBackground = false;
  bool _wasFullyBackgrounded = false;
  bool _isEndHandled = false;

  int _activeSwitchId = 0;
  Timer? _positionTicker;

  VideoPlayerController? get videoController => _videoController;

  ExtractedVideoInfo? get currentOnlineVideo => _currentOnlineVideo;

  bool get isOnlinePlayback => _isOnlinePlayback;

  VideoModel? get currentVideo =>
      (_currentIndex >= 0 && _currentIndex < _activeList.length)
      ? _activeList[_currentIndex]
      : null;

  bool get isPlaying => _isPlaying;

  Duration get position => _position;

  Duration get duration => _duration;

  bool get isShuffle => _isShuffle;

  RepeatMode get repeatMode => _repeatMode;

  double get playbackSpeed => _playbackSpeed;

  bool get hasCurrentMedia =>
      _currentOnlineVideo != null || currentVideo != null;

  String? get currentMediaTitle =>
      _currentOnlineVideo?.title ?? currentVideo?.title;

  String? get currentMediaAuthor =>
      _currentOnlineVideo?.author ?? currentVideo?.author;

  String? get currentThumbnailUrl => _currentOnlineVideo?.thumbnailUrl;

  bool get isMiniPlayerVisible => hasCurrentMedia && !_isMiniPlayerDismissed;

  List<VideoModel> get _activeList =>
      _isShuffle ? _shuffledPlaylist : _playlist;

  // bool _isMiniPlayerVisible = false;

  // bool get isMiniPlayerVisible => _isMiniPlayerVisible;

  set isMiniPlayerVisible(bool value) {
    _isMiniPlayerDismissed = value;
    notifyListeners();
  }

  List<ExtractedVideoInfo> _recommendations = [];

  bool _isLoadingRecommendations = false;

  String? _recommendationsForVideoId;

  Future<void> _switchQueue = Future<void>.value();

  List<ExtractedVideoInfo> get recommendations =>
      List.unmodifiable(_recommendations);

  bool get isLoadingRecommendations => _isLoadingRecommendations;

  Future<void> loadRecommendations(ExtractedVideoInfo video) async {
    // Don't search again for the same video.
    if (_recommendationsForVideoId == video.id) return;

    _recommendationsForVideoId = video.id;
    _recommendations = [];
    _isLoadingRecommendations = true;
    notifyListeners();

    try {
      final query = '${video.title} similar songs';

      // Implement this method in your VideoExtractorService.
      final results = await VideoExtractorService.instance.searchVideos(
        query,
        limit: 10,
      );
      // Ignore stale results if the user has changed videos.
      if (_recommendationsForVideoId != video.id) return;

      _recommendations = results
          .where((result) => result.id != video.id)
          .take(10)
          .toList();
    } catch (e) {
      debugPrint('Failed to load recommendations: $e');
      _recommendations = [];
    } finally {
      if (_recommendationsForVideoId == video.id) {
        _isLoadingRecommendations = false;
        notifyListeners();
      }
    }
  }

  Future<void> addNextOnlinePlayVideoList(String id) async {
    final ExtractedVideoInfo newVideo = await VideoExtractorService.instance
        .extractInfo('https://www.youtube.com/watch?v=${id}');

    _onlineNextPlayList.add(newVideo);
  }

  Future<void> removeNextOnlinePlayVideoList(int index) async {
    _onlineNextPlayList.removeAt(index);
  }
  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (_isInitialized) return;

    // Prevent concurrent calls from creating multiple audio handlers.
    if (_isInitializing) {
      while (_isInitializing && !_isInitialized) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_isInitialized) return;
    }

    _isInitializing = true;
    WidgetsBinding.instance.addObserver(this);

    try {
      try {
        _audioHandler = await AudioService.init(
          builder: () => OfflineAudioHandler(),
          config: const AudioServiceConfig(
            androidNotificationChannelId:
                'com.offlinetube.app.channel.audio.v2',
            androidNotificationChannelName: 'OfflineTube Playback',
            androidNotificationChannelDescription:
                'OfflineTube media playback controls',
            androidStopForegroundOnPause: false,
            androidNotificationIcon: 'mipmap/ic_launcher',
          ),
        );
      } catch (e) {
        debugPrint('AudioService initialization failed: $e');
        _audioHandler = OfflineAudioHandler();
      }

      _audioHandler ??= OfflineAudioHandler();

      try {
        await Permission.notification.request();
      } catch (e) {
        debugPrint('Notification permission note: $e');
      }

      _audioHandler!.onSkipToNext = playNext;
      _audioHandler!.onSkipToPrevious = playPrevious;
      _audioHandler!.onPlay = play;
      _audioHandler!.onPause = pause;

      _audioHandler!.onSeek = (position) {
        unawaited(_videoController?.seekTo(position) ?? Future<void>.value());
        _position = position;
        notifyListeners();
      };

      _audioHandler!.player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed && !_isEndHandled) {
          _isEndHandled = true;
          _onVideoEnded();
        }
      });

      _isInitialized = true;
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> close() async {
    // Hide and dismiss the mini-player.
    _isMiniPlayerDismissed = true;

    // Stop audio playback.
    await _audioHandler?.stop();

    // Stop and dispose of the video controller.
    final controller = _videoController;
    _videoController = null;

    if (controller != null) {
      if (controller.value.isInitialized) {
        await controller.pause();
      }
      await controller.dispose();
    }

    // Clear the current media.
    _currentOnlineVideo = null;

    // Reset playback state.
    _isPlaying = false;

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Online playback
  // ---------------------------------------------------------------------------
  bool isSameVideo(String videoId) {
    return currentOnlineVideo?.id == videoId &&
        videoController != null &&
        videoController!.value.isInitialized;
  }

  Future<void> ensureOnlineVideo(
    ExtractedVideoInfo info, {
    ExtractedFormat? format,
  }) async {
    // Reuse the existing video and audio players.
    if (isSameVideo(info.id)) {
      return;
    }

    // Initialize only if this is a different video or no active
    // initialized video controller exists.
    await playOnlineVideo(info, format: format);
  }

  Future<void> playOnlineVideo(
    ExtractedVideoInfo info, {
    ExtractedFormat? format,
  }) {
    final switchId = ++_activeSwitchId;

    final task = _switchQueue.then<void>((_) async {
      if (switchId != _activeSwitchId) {
        return;
      }

      return _playOnlineVideo(switchId, info, format: format);
    });

    // Keep the queue usable even if a switch fails.
    _switchQueue = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        debugPrint('Video switch failed: $error');
      },
    );

    return task;
  }

  Future<void> _playOnlineVideo(
    int switchId,
    ExtractedVideoInfo info, {
    ExtractedFormat? format,
  }) async {
    final switchId = ++_activeSwitchId;

    await init();

    if (switchId != _activeSwitchId) return;

    final videoFormats = info.formats
        .where((f) => f.hasVideo && f.streamUrl.isNotEmpty)
        .toList();

    if (videoFormats.isEmpty) {
      throw Exception('The extractor returned no usable video streams.');
    }

    // Try the requested quality first. If it fails, try other qualities.
    videoFormats.sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));

    if (format != null && format.hasVideo && format.streamUrl.isNotEmpty) {
      videoFormats.removeWhere((f) => f.streamUrl == format.streamUrl);
      videoFormats.insert(0, format);
    }

    final audioOnlyFormats = info.formats
        .where((f) => !f.hasVideo && f.hasAudio && f.streamUrl.isNotEmpty)
        .toList();

    // Prefer audio from the same muxed stream when available, as this can
    // be more compatible than loading a separate audio-only stream.
    final audioUrls = <String>[];

    for (final videoFormat in videoFormats) {
      if (videoFormat.hasAudio && !audioUrls.contains(videoFormat.streamUrl)) {
        audioUrls.add(videoFormat.streamUrl);
      }
    }

    for (final audioFormat in audioOnlyFormats) {
      if (!audioUrls.contains(audioFormat.streamUrl)) {
        audioUrls.add(audioFormat.streamUrl);
      }
    }

    if (audioUrls.isEmpty) {
      throw Exception('The extractor returned no usable audio streams.');
    }

    _isOnlinePlayback = true;
    _currentOnlineVideo = info;
    _isMiniPlayerDismissed = false;
    _isEndHandled = false;

    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration(seconds: info.durationSeconds);

    _stopPositionTicker();

    final oldController = _videoController;
    _videoController = null;

    oldController?.removeListener(_onVideoControllerUpdate);

    try {
      await oldController?.dispose();
    } catch (e) {
      debugPrint('Previous video disposal note: $e');
    }

    try {
      await _audioHandler?.pauseInternal();
    } catch (e) {
      debugPrint('Previous audio pause note: $e');
    }

    notifyListeners();

    VideoPlayerController? successfulController;
    String? successfulAudioUrl;
    Object? lastError;
    StackTrace? lastStackTrace;

    // Retry other video qualities and audio URLs if initialization fails.
    for (final videoFormat in videoFormats) {
      if (switchId != _activeSwitchId) return;

      VideoPlayerController? candidateController;

      try {
        debugPrint('Trying video quality: ${videoFormat.qualityLabel}');
        candidateController = VideoPlayerController.networkUrl(
          Uri.parse(videoFormat.videoUrl!),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );

        await candidateController.initialize();

        if (switchId != _activeSwitchId) {
          await candidateController.dispose();
          return;
        }

        await candidateController.setVolume(0.0);
        await candidateController.setPlaybackSpeed(_playbackSpeed);

        for (final audioUrl in audioUrls) {
          if (switchId != _activeSwitchId) {
            await candidateController.dispose();
            return;
          }

          try {
            await _audioHandler!.prepareNetworkMedia(
              id: info.id,
              title: info.title,
              author: info.author,
              audioUrl: audioUrl,
              thumbnailUrl: info.thumbnailUrl,
              duration: candidateController.value.duration > Duration.zero
                  ? candidateController.value.duration
                  : (info.durationSeconds > 0
                        ? Duration(seconds: info.durationSeconds)
                        : null),
              initialPosition: Duration.zero,
            );

            successfulController = candidateController;
            successfulAudioUrl = audioUrl;
            break;
          } catch (e, st) {
            lastError = e;
            lastStackTrace = st;

            debugPrint('Audio stream failed; trying another source: $e');
          }
        }

        if (successfulController != null) {
          break;
        }

        await candidateController.dispose();
      } catch (e, st) {
        lastError = e;
        lastStackTrace = st;

        debugPrint('Video quality ${videoFormat.qualityLabel} failed: $e');

        try {
          await candidateController?.dispose();
        } catch (_) {}
      }
    }

    if (switchId != _activeSwitchId) {
      try {
        await successfulController?.dispose();
      } catch (_) {}
      return;
    }

    if (successfulController == null || successfulAudioUrl == null) {
      _isPlaying = false;
      _stopPositionTicker();
      notifyListeners();

      debugPrint('All online stream attempts failed: $lastError');

      if (lastStackTrace != null) {
        debugPrintStack(stackTrace: lastStackTrace);
      }

      throw Exception(
        'Unable to play this stream. Try another quality or refresh the video.',
      );
    }

    _videoController = successfulController;
    _videoController!.addListener(_onVideoControllerUpdate);

    _duration = _videoController!.value.duration > Duration.zero
        ? _videoController!.value.duration
        : Duration(seconds: info.durationSeconds);

    try {
      await _audioHandler!.setSpeed(_playbackSpeed);

      if (switchId != _activeSwitchId) return;

      _isPlaying = true;
      notifyListeners();
      _startPositionTicker();

      debugPrint('Starting video playback...');
      unawaited(
        _videoController!.play().catchError((Object e, StackTrace st) {
          debugPrint('Video playback error: $e');
          debugPrintStack(stackTrace: st);
        }),
      );

      debugPrint('Starting audio playback...');
      unawaited(
        _audioHandler!.playInternal().catchError((Object e, StackTrace st) {
          debugPrint('Audio playback error: $e');
          debugPrintStack(stackTrace: st);
        }),
      );
    } catch (e, st) {
      debugPrint('Online playback startup failed: $e');
      debugPrintStack(stackTrace: st);

      if (switchId == _activeSwitchId) {
        _isPlaying = false;
        _stopPositionTicker();
        notifyListeners();
      }

      rethrow;
    }

    loadRecommendations(info);
  }

  // ---------------------------------------------------------------------------
  // App lifecycle
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _wasFullyBackgrounded = true;
        _isAppInBackground = true;
        _stopPositionTicker();

        // Keep the audio service playing; pause only the video renderer.
        unawaited(_videoController?.pause() ?? Future<void>.value());
        break;

      case AppLifecycleState.resumed:
        _isAppInBackground = false;

        if (_wasFullyBackgrounded) {
          _wasFullyBackgrounded = false;
          if (_isPlaying) {
            unawaited(_syncVideoToAudio());
          }
        }

        if (_isPlaying) _startPositionTicker();
        break;

      case AppLifecycleState.inactive:
        // Do not pause for notification shade interactions.
        break;
    }
  }

  Future<void> _syncVideoToAudio() async {
    final controller = _videoController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    try {
      final audioPosition = _audioHandler?.player.position ?? _position;
      final videoPosition = controller.value.position;

      if ((audioPosition - videoPosition).abs() > const Duration(seconds: 1)) {
        await controller.seekTo(audioPosition);
      }

      if (_isPlaying) {
        await controller.play();
      }

      _position = audioPosition;
      notifyListeners();
    } catch (e) {
      debugPrint('Video synchronization note: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Position ticker
  // ---------------------------------------------------------------------------

  void _startPositionTicker() {
    _positionTicker?.cancel();

    _positionTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_isPlaying || _isAppInBackground) return;

      final audioPosition = _audioHandler?.player.position;

      if (audioPosition != null && audioPosition != _position) {
        _position = audioPosition;
        notifyListeners();
      }
    });
  }

  void _stopPositionTicker() {
    _positionTicker?.cancel();
    _positionTicker = null;
  }

  // ---------------------------------------------------------------------------
  // Local playlist
  // ---------------------------------------------------------------------------

  void loadPlaylist(List<VideoModel> videos, {int startIndex = 0}) {
    _playlist
      ..clear()
      ..addAll(videos);

    _regenerateShuffleList();

    if (_playlist.isNotEmpty) {
      final safeIndex = startIndex.clamp(0, _playlist.length - 1);
      unawaited(playVideo(_playlist[safeIndex]));
    }
  }

  Future<void> playVideo(VideoModel video) async {
    final switchId = ++_activeSwitchId;

    _isOnlinePlayback = false;
    _currentOnlineVideo = null;
    _isEndHandled = false;
    _isMiniPlayerDismissed = false;

    final foundIndex = _activeList.indexWhere((v) => v.id == video.id);

    if (foundIndex != -1) {
      _currentIndex = foundIndex;
    } else {
      _playlist.insert(0, video);
      _regenerateShuffleList();
      _currentIndex = 0;
    }

    final oldController = _videoController;
    _videoController = null;
    oldController?.removeListener(_onVideoControllerUpdate);

    try {
      await oldController?.dispose();
    } catch (e) {
      debugPrint('Previous local video disposal note: $e');
    }

    try {
      await _audioHandler?.pauseInternal();
    } catch (e) {
      debugPrint('Local audio pause note: $e');
    }

    _stopPositionTicker();
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    notifyListeners();

    await init();

    if (switchId != _activeSwitchId) return;

    final file = File(video.videoPath);

    if (!await file.exists()) {
      debugPrint('Media file not found: ${video.videoPath}');
      return;
    }

    final controller = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    try {
      await controller.initialize();

      if (switchId != _activeSwitchId) {
        await controller.dispose();
        return;
      }

      await controller.setVolume(0.0);
      await controller.setPlaybackSpeed(_playbackSpeed);

      _videoController = controller;
      _duration = controller.value.duration;
      controller.addListener(_onVideoControllerUpdate);

      await _audioHandler!.prepareMedia(
        id: video.id,
        title: video.title,
        author: video.author,
        videoPath: video.videoPath,
        thumbnailPath: video.thumbnailPath,
        duration: video.durationSeconds > 0
            ? Duration(seconds: video.durationSeconds)
            : (_duration > Duration.zero ? _duration : null),
        initialPosition: Duration.zero,
      );

      await _audioHandler!.setSpeed(_playbackSpeed);

      if (switchId != _activeSwitchId) return;

      _isPlaying = true;
      notifyListeners();
      _startPositionTicker();

      unawaited(
        controller.play().catchError((Object e, StackTrace st) {
          debugPrint('Local video playback error: $e');
        }),
      );

      unawaited(
        _audioHandler!.playInternal().catchError((Object e, StackTrace st) {
          debugPrint('Local audio playback error: $e');
        }),
      );
    } catch (e, st) {
      debugPrint('Local playback setup failed: $e');
      debugPrintStack(stackTrace: st);

      if (identical(_videoController, controller)) {
        controller.removeListener(_onVideoControllerUpdate);
        _videoController = null;
      }

      _isPlaying = false;
      _stopPositionTicker();

      try {
        await controller.dispose();
      } catch (_) {}

      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Video position and completion
  // ---------------------------------------------------------------------------

  void _onVideoControllerUpdate() {
    final controller = _videoController;

    if (controller == null || _isAppInBackground) return;

    final value = controller.value;
    final audioPosition = _audioHandler?.player.position;

    _position = (audioPosition != null && audioPosition > Duration.zero)
        ? audioPosition
        : value.position;

    if (value.duration > Duration.zero) {
      _duration = value.duration;
    }

    notifyListeners();
  }

  void _onVideoEnded() {
    if (_isOnlinePlayback) {
      _isPlaying = false;
      _stopPositionTicker();
      unawaited(_videoController?.pause() ?? Future<void>.value());
      notifyListeners();
      if (_onlineNextPlayList.isNotEmpty &&
          _onlineNextPlayList.length != _onlineNextPlaylistIndex + 1) {
        _onlineNextPlaylistIndex = _onlineNextPlaylistIndex + 1;
        ensureOnlineVideo(_onlineNextPlayList[_onlineNextPlaylistIndex]);
      }
      return;
    }

    if (_repeatMode == RepeatMode.one) {
      _isEndHandled = false;
      unawaited(seekTo(Duration.zero).then((_) => play()));
    } else if (_currentIndex + 1 < _activeList.length) {
      playNext();
    } else if (_repeatMode == RepeatMode.all && _activeList.isNotEmpty) {
      _currentIndex = 0;
      unawaited(playVideo(_activeList[0]));
    } else {
      _isPlaying = false;
      _stopPositionTicker();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Transport controls
  // ---------------------------------------------------------------------------

  Future<void> play() async {
    await init();

    _isPlaying = true;
    notifyListeners();
    _startPositionTicker();

    try {
      final controller = _videoController;

      if (controller != null && controller.value.isInitialized) {
        unawaited(
          controller.play().catchError((Object e) {
            debugPrint('Video resume error: $e');
          }),
        );
      }

      unawaited(
        _audioHandler!.playInternal().catchError((Object e) {
          debugPrint('Audio resume error: $e');
        }),
      );
    } catch (e) {
      debugPrint('Play error: $e');
    }
  }

  Future<void> pause() async {
    _isPlaying = false;
    _stopPositionTicker();
    notifyListeners();

    try {
      final controller = _videoController;

      if (controller != null && controller.value.isInitialized) {
        await controller.pause();
      }

      await _audioHandler?.pauseInternal();
    } catch (e) {
      debugPrint('Pause error: $e');
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seekTo(Duration position) async {
    var clamped = position < Duration.zero ? Duration.zero : position;

    if (_duration > Duration.zero && clamped > _duration) {
      clamped = _duration;
    }

    try {
      await _videoController?.seekTo(clamped);
      await _audioHandler?.seek(clamped);

      _position = clamped;
      notifyListeners();
    } catch (e) {
      debugPrint('Seek error: $e');
    }
  }

  Future<void> seekForward({int seconds = 10}) async {
    final target = _position + Duration(seconds: seconds);
    await seekTo(target > _duration ? _duration : target);
  }

  Future<void> seekBackward({int seconds = 10}) async {
    final target = _position - Duration(seconds: seconds);
    await seekTo(target < Duration.zero ? Duration.zero : target);
  }

  void playNext() {
    if (_activeList.isEmpty) return;

    if (_currentIndex + 1 < _activeList.length) {
      unawaited(playVideo(_activeList[_currentIndex + 1]));
    } else if (_repeatMode == RepeatMode.all) {
      unawaited(playVideo(_activeList.first));
    }
  }

  void playPrevious() {
    if (_position.inSeconds > 3) {
      unawaited(seekTo(Duration.zero).then((_) => play()));
    } else if (_currentIndex > 0 && _activeList.isNotEmpty) {
      unawaited(playVideo(_activeList[_currentIndex - 1]));
    } else {
      unawaited(seekTo(Duration.zero));
    }
  }

  // ---------------------------------------------------------------------------
  // Playback settings
  // ---------------------------------------------------------------------------

  void toggleShuffle() {
    final currentId = currentVideo?.id;

    _isShuffle = !_isShuffle;

    if (_isShuffle) {
      _regenerateShuffleList();
      if (currentId != null) {
        _currentIndex = _shuffledPlaylist.indexWhere(
          (video) => video.id == currentId,
        );
      }
    } else if (currentId != null) {
      _currentIndex = _playlist.indexWhere((video) => video.id == currentId);
    }

    notifyListeners();
  }

  void toggleRepeatMode() {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.all;
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.off;
        break;
    }

    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (speed <= 0) return;

    _playbackSpeed = speed;

    try {
      await _videoController?.setPlaybackSpeed(speed);
      await _audioHandler?.setSpeed(speed);
    } catch (e) {
      debugPrint('Playback speed update failed: $e');
    }

    notifyListeners();
  }

  void _regenerateShuffleList() {
    _shuffledPlaylist
      ..clear()
      ..addAll(_playlist)
      ..shuffle(Random());
  }

  void dismissMiniPlayer() {
    _isMiniPlayerDismissed = true;
    unawaited(pause());
    notifyListeners();
  }

  void restoreMiniPlayer() {
    _isMiniPlayerDismissed = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _stopPositionTicker();
    WidgetsBinding.instance.removeObserver(this);

    final controller = _videoController;
    _videoController = null;

    controller?.removeListener(_onVideoControllerUpdate);

    if (controller != null) {
      unawaited(controller.dispose());
    }

    final handler = _audioHandler;
    _audioHandler = null;

    if (handler != null) {
      unawaited(handler.dispose());
    }

    super.dispose();
  }
}

// import 'dart:async';
// import 'dart:io';
// import 'dart:math';
// import 'package:audio_service/audio_service.dart';
// import 'package:flutter/widgets.dart';
// import 'package:just_audio/just_audio.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:video_player/video_player.dart';
// import '../../data/models/video_model.dart';
// import 'offline_audio_handler.dart';
// import 'package:offlinetube/services/extractor/extracted_video_info.dart';

// enum RepeatMode { off, all, one }

// /// PlaybackCoordinator manages video rendering (VideoPlayerController, muted)
// /// and background audio (just_audio via AudioService foreground service).
// ///
// /// Architecture:
// ///   • just_audio (OfflineAudioHandler) → PRIMARY AUDIO SOURCE
// ///     Runs inside audio_service's foreground service → survives app backgrounding.
// ///   • VideoPlayerController → MUTED, renders video frames only in foreground.
// ///   • On app background  → VideoPlayerController is paused; just_audio keeps playing.
// ///   • On app resume      → VideoPlayerController seeks to just_audio position and resumes.
// ///   • Completion         → Detected from just_audio's processingStateStream (works in background).
// class PlaybackCoordinator extends ChangeNotifier with WidgetsBindingObserver {
//   ExtractedVideoInfo? _currentOnlineVideo;
//   bool _isOnlinePlayback = false;

//   ExtractedVideoInfo? get currentOnlineVideo => _currentOnlineVideo;

//   bool get isOnlinePlayback => _isOnlinePlayback;

//   bool get hasCurrentMedia =>
//       currentVideo != null || _currentOnlineVideo != null;

//   String? get currentMediaTitle =>
//       _currentOnlineVideo?.title ?? currentVideo?.title;

//   String? get currentMediaAuthor =>
//       _currentOnlineVideo?.author ?? currentVideo?.author;

//   String? get currentThumbnailUrl => _currentOnlineVideo?.thumbnailUrl;

//   static PlaybackCoordinator? _instance;
//   static PlaybackCoordinator get instance =>
//       _instance ??= PlaybackCoordinator._();
//   PlaybackCoordinator._();

//   OfflineAudioHandler? _audioHandler;
//   VideoPlayerController? _videoController;

//   // Playlist
//   final List<VideoModel> _playlist = [];
//   final List<VideoModel> _shuffledPlaylist = [];
//   int _currentIndex = -1;

//   // Playback settings
//   bool _isShuffle = false;
//   RepeatMode _repeatMode = RepeatMode.off;
//   double _playbackSpeed = 1.0;

//   // State
//   bool _isPlaying = false;
//   Duration _position = Duration.zero;
//   Duration _duration = Duration.zero;
//   bool _isMiniPlayerDismissed = false;
//   bool _isInitialized = false;
//   bool _isAppInBackground = false;

//   // Guards & Tokens
//   bool _isEndHandled = false; // prevents _onVideoEnded firing multiple times
//   int _activeSwitchId = 0; // token to discard stale async song switches
//   bool _wasFullyBackgrounded =
//       false; // true only after paused/hidden, NOT after inactive
//   Timer? _positionTicker; // periodic UI position update from just_audio

//   // ─── Getters ────────────────────────────────────────────────────────────────

//   VideoPlayerController? get videoController => _videoController;
//   VideoModel? get currentVideo =>
//       (_currentIndex >= 0 && _currentIndex < _activeList.length)
//       ? _activeList[_currentIndex]
//       : null;
//   bool get isPlaying => _isPlaying;
//   Duration get position => _position;
//   Duration get duration => _duration;
//   bool get isShuffle => _isShuffle;
//   RepeatMode get repeatMode => _repeatMode;
//   double get playbackSpeed => _playbackSpeed;
//   // bool get isMiniPlayerVisible =>
//   //     currentVideo != null && !_isMiniPlayerDismissed;
//   bool get isMiniPlayerVisible => hasCurrentMedia && !_isMiniPlayerDismissed;

//   Future<void> playOnlineVideo(
//     ExtractedVideoInfo info, {
//     ExtractedFormat? format,
//   }) async {
//     _isPlaying = true;
//     notifyListeners();

//     _startPositionTicker();

//     // Start both players without waiting for the entire video to finish.
//     unawaited(_videoController!.play());

//     unawaited(
//       _audioHandler!.playInternal().catchError((Object e, StackTrace st) {
//         debugPrint('Online audio playback error: $e');
//         debugPrintStack(stackTrace: st);
//       }),
//     );

//     final switchId = ++_activeSwitchId;

//     // Ensure AudioService and OfflineAudioHandler are initialized.
//     await init();

//     if (switchId != _activeSwitchId) return;

//     final playableFormats = info.formats
//         .where((f) => f.hasVideo && f.hasAudio && f.streamUrl.isNotEmpty)
//         .toList();

//     if (playableFormats.isEmpty) {
//       throw Exception('No playable video + audio stream found.');
//     }

//     // Honor the selected quality if it is a compatible muxed stream.
//     // Otherwise choose the highest available muxed resolution.
//     final selectedFormat =
//         format != null &&
//             format.hasVideo &&
//             format.hasAudio &&
//             format.streamUrl.isNotEmpty
//         ? format
//         : playableFormats.reduce(
//             (a, b) => (a.height ?? 0) >= (b.height ?? 0) ? a : b,
//           );

//     final audioFormats = info.formats
//         .where((f) => !f.hasVideo && f.hasAudio && f.streamUrl.isNotEmpty)
//         .toList();

//     // Prefer the extractor's first audio-only format if it is already
//     // ordered by audio quality. Otherwise, use the muxed stream.
//     final audioUrl = audioFormats.isNotEmpty
//         ? audioFormats.first.streamUrl
//         : selectedFormat.streamUrl;

//     _isEndHandled = false;
//     _isMiniPlayerDismissed = false;
//     _isOnlinePlayback = true;
//     _currentOnlineVideo = info;

//     // Stop and dispose the previous video.
//     _videoController?.removeListener(_onVideoControllerUpdate);
//     final oldController = _videoController;
//     _videoController = null;

//     await oldController?.dispose();
//     await _audioHandler?.pauseInternal();

//     _position = Duration.zero;
//     _duration = Duration(seconds: info.durationSeconds);
//     _isPlaying = false;

//     notifyListeners();

//     final newController = VideoPlayerController.networkUrl(
//       Uri.parse(selectedFormat.streamUrl),
//       videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
//     );

//     try {
//       debugPrint('🎬 Selected video format: ${selectedFormat.qualityLabel}');
//       debugPrint('🎬 Video URL: ${selectedFormat.streamUrl}');
//       debugPrint('🎵 Audio URL: $audioUrl');
//       debugPrint('🎬 Has video: ${selectedFormat.hasVideo}');
//       debugPrint('🎵 Has audio: ${selectedFormat.hasAudio}');
//       await newController.initialize();

//       if (switchId != _activeSwitchId) {
//         await newController.dispose();
//         return;
//       }

//       await newController.setVolume(0.0);
//       await newController.setPlaybackSpeed(_playbackSpeed);

//       _videoController = newController;
//       _duration = newController.value.duration > Duration.zero
//           ? newController.value.duration
//           : Duration(seconds: info.durationSeconds);

//       _videoController!.addListener(_onVideoControllerUpdate);

//       await _audioHandler!.prepareNetworkMedia(
//         id: info.id,
//         title: info.title,
//         author: info.author,
//         audioUrl: audioUrl,
//         thumbnailUrl: info.thumbnailUrl,
//         duration: _duration > Duration.zero ? _duration : null,
//         initialPosition: Duration.zero,
//       );

//       if (switchId != _activeSwitchId) return;

//       await _audioHandler!.setSpeed(_playbackSpeed);

//       _isPlaying = true;
//       notifyListeners();

//       await Future.wait([
//         _videoController!.play(),
//         _audioHandler!.playInternal(),
//       ]);

//       if (switchId == _activeSwitchId) {
//         _startPositionTicker();
//         notifyListeners();
//       }
//     } catch (e, stackTrace) {
//       debugPrint('❌ Online playback failed: $e');
//       debugPrintStack(stackTrace: stackTrace);

//       if (switchId == _activeSwitchId) {
//         _isPlaying = false;
//         _stopPositionTicker();

//         if (identical(_videoController, newController)) {
//           newController.removeListener(_onVideoControllerUpdate);
//           _videoController = null;
//         }

//         notifyListeners();
//       }

//       try {
//         await newController.dispose();
//       } catch (_) {}

//       rethrow;
//     }
//   }

//   List<VideoModel> get _activeList =>
//       _isShuffle ? _shuffledPlaylist : _playlist;

//   // ─── Initialization ─────────────────────────────────────────────────────────

//   Future<void> init() async {
//     if (_isInitialized) return;

//     // Observe app lifecycle so we can pause/resume video rendering
//     WidgetsBinding.instance.addObserver(this);

//     try {
//       _audioHandler = await AudioService.init(
//         builder: () => OfflineAudioHandler(),
//         // Keep the foreground service alive even when paused so Android doesn't
//         // kill the audio service and interrupt background playback.
//         config: AudioServiceConfig(
//           androidNotificationChannelId: 'com.offlinetube.app.channel.audio.v2',
//           androidNotificationChannelName: 'OfflineTube Playback',
//           androidNotificationChannelDescription:
//               'OfflineTube media playback controls',
//           androidStopForegroundOnPause: false,
//           androidNotificationIcon: 'mipmap/ic_launcher',
//         ),
//       );
//     } catch (e) {
//       debugPrint('AudioService init note: $e');
//       _audioHandler = OfflineAudioHandler();
//     }
//     _audioHandler ??= OfflineAudioHandler();

//     // Request notification permission on Android 13+ so media controls show in notification shade
//     try {
//       await Permission.notification.request();
//     } catch (e) {
//       debugPrint('Notification permission note: $e');
//     }

//     // Wire up notification bar buttons → coordinator (keeps video + state in sync)
//     _audioHandler?.onSkipToNext = playNext;
//     _audioHandler?.onSkipToPrevious = playPrevious;
//     _audioHandler?.onPlay = play; // notification play  → coordinator.play()
//     _audioHandler?.onPause = pause; // notification pause → coordinator.pause()
//     _audioHandler?.onSeek = (position) {
//       // notification seek bar slider → keep video controller & state in sync
//       _videoController?.seekTo(position);
//       _position = position;
//       notifyListeners();
//     };

//     // Background-safe completion detection via just_audio stream
//     _audioHandler?.player.processingStateStream.listen((state) {
//       if (state == ProcessingState.completed && !_isEndHandled) {
//         _isEndHandled = true;
//         _onVideoEnded();
//       }
//     });
//     _isInitialized = true;
//   }

//   // ─── App Lifecycle ──────────────────────────────────────────────────────────

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     switch (state) {
//       case AppLifecycleState.paused:
//       case AppLifecycleState.hidden:
//       case AppLifecycleState.detached:
//         // Mark that we truly went to background (not just notification panel pull-down)
//         _wasFullyBackgrounded = true;
//         _isAppInBackground = true;
//         _stopPositionTicker();
//         // Pause video rendering only; just_audio keeps playing via background service
//         _videoController?.pause();
//         break;

//       case AppLifecycleState.resumed:
//         _isAppInBackground = false;
//         if (_wasFullyBackgrounded) {
//           // Only sync video when truly returning from background, not from
//           // notification panel open/close which only fires inactive→resumed
//           _wasFullyBackgrounded = false;
//           if (_isPlaying) {
//             _syncVideoToAudio();
//           }
//         }
//         // Restart position ticker whenever app is visible again
//         _startPositionTicker();
//         break;

//       case AppLifecycleState.inactive:
//         // Fired when notification panel opens or during app-switch gesture.
//         // Do NOT pause anything — just_audio and VideoController keep running.
//         break;
//     }
//   }

//   /// Seeks the muted VideoPlayerController to the current just_audio position
//   /// and resumes video rendering when the app comes back to the foreground.
//   Future<void> _syncVideoToAudio() async {
//     if (_videoController == null || !_videoController!.value.isInitialized) {
//       return;
//     }
//     try {
//       final audioPos = _audioHandler?.player.position ?? _position;
//       final videoPos = _videoController!.value.position;

//       if ((audioPos - videoPos).abs() > const Duration(seconds: 1)) {
//         await _videoController!.seekTo(audioPos);
//       }

//       await _videoController!.play();

//       _position = audioPos;
//       notifyListeners();
//       // final audioPos = _audioHandler?.player.position ?? _position;
//       // // Only seek if the drift is more than 1 second to avoid unnecessary stutter
//       // if ((audioPos - _position).abs() > const Duration(seconds: 1)) {
//       //   await _videoController!.seekTo(audioPos);
//       // }
//       // await _videoController!.play();
//       // _position = _audioHandler?.player.position ?? audioPos;
//       // notifyListeners();
//     } catch (e) {
//       debugPrint('_syncVideoToAudio note: $e');
//     }
//   }

//   // ─── Position Ticker ─────────────────────────────────────────────────────────

//   /// Starts a 500 ms periodic timer that polls just_audio's current position
//   /// and notifies listeners so the seek slider and time labels always refresh.
//   void _startPositionTicker() {
//     _positionTicker?.cancel();
//     _positionTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
//       if (!_isPlaying || _isAppInBackground) return;
//       final audioPos = _audioHandler?.player.position;
//       if (audioPos != null && audioPos != _position) {
//         _position = audioPos;
//         notifyListeners();
//       }
//     });
//   }

//   void _stopPositionTicker() {
//     _positionTicker?.cancel();
//     _positionTicker = null;
//   }

//   // ─── Playlist ───────────────────────────────────────────────────────────────

//   void loadPlaylist(List<VideoModel> videos, {int startIndex = 0}) {
//     _playlist.clear();
//     _playlist.addAll(videos);
//     _regenerateShuffleList();

//     if (_playlist.isNotEmpty) {
//       final safeIndex = startIndex.clamp(0, _playlist.length - 1);
//       playVideo(_playlist[safeIndex]);
//     }
//   }

//   // ─── Core Playback ──────────────────────────────────────────────────────────

//   Future<void> playVideo(VideoModel video) async {
//     _isOnlinePlayback = false;
//     _currentOnlineVideo = null;

//     final int switchId = ++_activeSwitchId;
//     _isEndHandled = false;
//     _isMiniPlayerDismissed = false;

//     // Update current index
//     final foundIndex = _activeList.indexWhere((v) => v.id == video.id);
//     if (foundIndex != -1) {
//       _currentIndex = foundIndex;
//     } else {
//       _playlist.insert(0, video);
//       _regenerateShuffleList();
//       _currentIndex = 0;
//     }

//     // Tear down existing controller and stop previous audio immediately
//     _videoController?.removeListener(_onVideoControllerUpdate);
//     final oldVideo = _videoController;
//     _videoController = null;
//     oldVideo?.dispose();

//     await _audioHandler?.player.pause();

//     _position = Duration.zero;
//     _duration = Duration.zero;
//     _isPlaying = false;
//     notifyListeners();

//     final file = File(video.videoPath);
//     if (!await file.exists()) {
//       debugPrint('Media file not found: ${video.videoPath}');
//       return;
//     }

//     if (switchId != _activeSwitchId) {
//       return; // Stale request cancelled by newer tap
//     }

//     // Initialize Video Player for video frames with mixWithOthers: true
//     // so it renders video frames without fighting just_audio for system audio focus.
//     final newVideoController = VideoPlayerController.file(
//       file,
//       videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
//     );
//     try {
//       await newVideoController.initialize();
//     } catch (e) {
//       debugPrint('VideoPlayerController initialize error: $e');
//     }

//     if (switchId != _activeSwitchId) {
//       newVideoController.dispose();
//       return;
//     }

//     _videoController = newVideoController;
//     if (_videoController!.value.isInitialized) {
//       _duration = _videoController!.value.duration;
//       await _videoController!.setVolume(
//         0.0,
//       ); // Muted; audio comes from just_audio
//       await _videoController!.setPlaybackSpeed(_playbackSpeed);
//       _videoController!.addListener(_onVideoControllerUpdate);
//     }

//     // Ensure audio handler is always initialized (with fallback if needed)
//     if (_audioHandler == null) {
//       try {
//         await init();
//       } catch (e) {
//         debugPrint('playVideo audioHandler init fallback note: $e');
//       }
//       _audioHandler ??= OfflineAudioHandler();
//     }

//     // Initialize just_audio for background-safe sound
//     try {
//       await _audioHandler?.prepareMedia(
//         id: video.id,
//         title: video.title,
//         author: video.author,
//         videoPath: video.videoPath,
//         thumbnailPath: video.thumbnailPath,
//         duration: video.durationSeconds > 0
//             ? Duration(seconds: video.durationSeconds)
//             : (_duration > Duration.zero ? _duration : null),
//         initialPosition: Duration.zero,
//       );
//       await _audioHandler?.setSpeed(_playbackSpeed);
//     } catch (e) {
//       debugPrint('AudioHandler prepareMedia note: $e');
//     }

//     if (switchId != _activeSwitchId) return;

//     // Start playback on both players synchronously
//     _isPlaying = true;
//     notifyListeners();

//     try {
//       await Future.wait([
//         if (_videoController != null && _videoController!.value.isInitialized)
//           _videoController!.play(),
//         // Use playInternal() — goes through BaseAudioHandler so audio_service
//         // starts the Android foreground service and shows the media notification,
//         // but avoids triggering the onPlay callback loop back into coordinator.
//         if (_audioHandler != null) _audioHandler!.playInternal(),
//       ]);
//     } catch (e) {
//       debugPrint('Playback start error: $e');
//     }

//     if (switchId == _activeSwitchId) {
//       // Kick off position ticker so UI refreshes every 500 ms
//       _startPositionTicker();
//       notifyListeners();
//     }
//   }

//   // ─── Video Controller Listener ─────────────────────────────────────────────

//   void _onVideoControllerUpdate() {
//     if (_videoController == null || _isAppInBackground) return;
//     final val = _videoController!.value;

//     // Use just_audio position as the authoritative position since it's the real audio source.
//     // Fall back to video controller position if just_audio isn't available.
//     final audioPos = _audioHandler?.player.position;
//     _position = (audioPos != null && audioPos > Duration.zero)
//         ? audioPos
//         : val.position;

//     if (val.duration > Duration.zero) {
//       _duration = val.duration;
//     }

//     notifyListeners();
//   }

//   void _onVideoEnded() {
//     if (_isOnlinePlayback) {
//       _isPlaying = false;
//       _stopPositionTicker();
//       _videoController?.pause();
//       notifyListeners();
//       return;
//     }
//     if (_repeatMode == RepeatMode.one) {
//       _isEndHandled = false;
//       seekTo(Duration.zero);
//       play();
//     } else if (_currentIndex + 1 < _activeList.length) {
//       playNext();
//     } else if (_repeatMode == RepeatMode.all && _activeList.isNotEmpty) {
//       _currentIndex = 0;
//       playVideo(_activeList[0]);
//     } else {
//       _isPlaying = false;
//       notifyListeners();
//     }
//   }

//   // ─── Transport Controls ─────────────────────────────────────────────────────

//   Future<void> play() async {
//     _isPlaying = true;
//     _startPositionTicker();
//     notifyListeners();

//     try {
//       await Future.wait([
//         if (_videoController != null && _videoController!.value.isInitialized)
//           _videoController!.play(),
//         if (_audioHandler != null) _audioHandler!.playInternal(),
//       ]);
//     } catch (e) {
//       debugPrint('Play error: $e');
//     }
//   }

//   Future<void> pause() async {
//     _isPlaying = false;
//     _stopPositionTicker();
//     notifyListeners();

//     try {
//       await Future.wait([
//         if (_videoController != null && _videoController!.value.isInitialized)
//           _videoController!.pause(),
//         if (_audioHandler != null) _audioHandler!.pauseInternal(),
//       ]);
//     } catch (e) {
//       debugPrint('Pause error: $e');
//     }
//   }

//   Future<void> togglePlayPause() async {
//     if (_isPlaying) {
//       await pause();
//     } else {
//       await play();
//     }
//   }

//   Future<void> seekTo(Duration position) async {
//     final clamped = position < Duration.zero ? Duration.zero : position;
//     await _videoController?.seekTo(clamped);
//     await _audioHandler?.seek(clamped);
//     _position = clamped;
//     notifyListeners();
//   }

//   Future<void> seekForward({int seconds = 10}) async {
//     final target = _position + Duration(seconds: seconds);
//     await seekTo(target > _duration ? _duration : target);
//   }

//   Future<void> seekBackward({int seconds = 10}) async {
//     final target = _position - Duration(seconds: seconds);
//     await seekTo(target < Duration.zero ? Duration.zero : target);
//   }

//   void playNext() {
//     if (_activeList.isEmpty) return;
//     if (_currentIndex + 1 < _activeList.length) {
//       _currentIndex++;
//       playVideo(_activeList[_currentIndex]);
//     } else if (_repeatMode == RepeatMode.all) {
//       _currentIndex = 0;
//       playVideo(_activeList[0]);
//     }
//   }

//   void playPrevious() {
//     if (_activeList.isEmpty) return;
//     if (_position.inSeconds > 3) {
//       seekTo(Duration.zero);
//       play();
//     } else if (_currentIndex - 1 >= 0) {
//       _currentIndex--;
//       playVideo(_activeList[_currentIndex]);
//     } else {
//       seekTo(Duration.zero);
//     }
//   }

//   // ─── Settings ───────────────────────────────────────────────────────────────

//   void toggleShuffle() {
//     _isShuffle = !_isShuffle;
//     if (_isShuffle) {
//       _regenerateShuffleList();
//       if (currentVideo != null) {
//         _currentIndex = _shuffledPlaylist.indexWhere(
//           (v) => v.id == currentVideo!.id,
//         );
//       }
//     } else {
//       if (currentVideo != null) {
//         _currentIndex = _playlist.indexWhere((v) => v.id == currentVideo!.id);
//       }
//     }
//     notifyListeners();
//   }

//   void toggleRepeatMode() {
//     switch (_repeatMode) {
//       case RepeatMode.off:
//         _repeatMode = RepeatMode.all;
//         break;
//       case RepeatMode.all:
//         _repeatMode = RepeatMode.one;
//         break;
//       case RepeatMode.one:
//         _repeatMode = RepeatMode.off;
//         break;
//     }
//     notifyListeners();
//   }

//   Future<void> setPlaybackSpeed(double speed) async {
//     _playbackSpeed = speed;
//     await _videoController?.setPlaybackSpeed(speed);
//     await _audioHandler?.setSpeed(speed);
//     notifyListeners();
//   }

//   void _regenerateShuffleList() {
//     _shuffledPlaylist.clear();
//     _shuffledPlaylist.addAll(_playlist);
//     _shuffledPlaylist.shuffle(Random());
//   }

//   void dismissMiniPlayer() {
//     _isMiniPlayerDismissed = true;
//     pause();
//     notifyListeners();
//   }

//   void restoreMiniPlayer() {
//     _isMiniPlayerDismissed = false;
//     notifyListeners();
//   }

//   // ─── Cleanup ─────────────────────────────────────────────────────────────────

//   @override
//   void dispose() {
//     _stopPositionTicker();
//     WidgetsBinding.instance.removeObserver(this);
//     _videoController?.removeListener(_onVideoControllerUpdate);
//     _videoController?.dispose();
//     _audioHandler?.dispose();
//     super.dispose();
//   }
// }
