import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import '../../data/models/video_model.dart';
import 'offline_audio_handler.dart';

enum RepeatMode { off, all, one }

/// PlaybackCoordinator manages video rendering (VideoPlayerController, muted)
/// and background audio (just_audio via AudioService foreground service).
///
/// Architecture:
///   • just_audio (OfflineAudioHandler) → PRIMARY AUDIO SOURCE
///     Runs inside audio_service's foreground service → survives app backgrounding.
///   • VideoPlayerController → MUTED, renders video frames only in foreground.
///   • On app background  → VideoPlayerController is paused; just_audio keeps playing.
///   • On app resume      → VideoPlayerController seeks to just_audio position and resumes.
///   • Completion         → Detected from just_audio's processingStateStream (works in background).
class PlaybackCoordinator extends ChangeNotifier with WidgetsBindingObserver {
  static PlaybackCoordinator? _instance;
  static PlaybackCoordinator get instance =>
      _instance ??= PlaybackCoordinator._();
  PlaybackCoordinator._();

  OfflineAudioHandler? _audioHandler;
  VideoPlayerController? _videoController;

  // Playlist
  final List<VideoModel> _playlist = [];
  final List<VideoModel> _shuffledPlaylist = [];
  int _currentIndex = -1;

  // Playback settings
  bool _isShuffle = false;
  RepeatMode _repeatMode = RepeatMode.off;
  double _playbackSpeed = 1.0;

  // State
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isMiniPlayerDismissed = false;
  bool _isInitialized = false;
  bool _isAppInBackground = false;

  // Guards & Tokens
  bool _isEndHandled = false;            // prevents _onVideoEnded firing multiple times
  int _activeSwitchId = 0;               // token to discard stale async song switches
  bool _wasFullyBackgrounded = false;    // true only after paused/hidden, NOT after inactive
  Timer? _positionTicker;                // periodic UI position update from just_audio

  // ─── Getters ────────────────────────────────────────────────────────────────

  VideoPlayerController? get videoController => _videoController;
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
  bool get isMiniPlayerVisible =>
      currentVideo != null && !_isMiniPlayerDismissed;

  List<VideoModel> get _activeList =>
      _isShuffle ? _shuffledPlaylist : _playlist;

  // ─── Initialization ─────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_isInitialized) return;

    // Observe app lifecycle so we can pause/resume video rendering
    WidgetsBinding.instance.addObserver(this);

    try {
      _audioHandler = await AudioService.init(
        builder: () => OfflineAudioHandler(),
        // Keep the foreground service alive even when paused so Android doesn't
        // kill the audio service and interrupt background playback.
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.offlinetube.app.channel.audio',
          androidNotificationChannelName: 'OfflineTube Playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: false,
          androidNotificationIcon: 'mipmap/ic_launcher',
        ),
      );

      // Wire up notification bar buttons → coordinator (keeps video + state in sync)
      _audioHandler?.onSkipToNext = playNext;
      _audioHandler?.onSkipToPrevious = playPrevious;
      _audioHandler?.onPlay = play;    // notification play  → coordinator.play()
      _audioHandler?.onPause = pause;  // notification pause → coordinator.pause()

      // NOTE: We intentionally do NOT listen to playbackState for play/pause toggling.
      // The OfflineAudioHandler.play() and pause() overrides already relay notification
      // bar button presses directly. Listening here caused race conditions where the
      // AudioService state flicker during foreground sync triggered unwanted pause() calls.

      // Background-safe completion detection via just_audio stream
      _audioHandler?.player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed && !_isEndHandled) {
          _isEndHandled = true;
          _onVideoEnded();
        }
      });
    } catch (e) {
      debugPrint('AudioService init note: $e');
    }
    _isInitialized = true;
  }

  // ─── App Lifecycle ──────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Mark that we truly went to background (not just notification panel pull-down)
        _wasFullyBackgrounded = true;
        _isAppInBackground = true;
        _stopPositionTicker();
        // Pause video rendering only; just_audio keeps playing via background service
        _videoController?.pause();
        break;

      case AppLifecycleState.resumed:
        _isAppInBackground = false;
        if (_wasFullyBackgrounded) {
          // Only sync video when truly returning from background, not from
          // notification panel open/close which only fires inactive→resumed
          _wasFullyBackgrounded = false;
          if (_isPlaying) {
            _syncVideoToAudio();
          }
        }
        // Restart position ticker whenever app is visible again
        _startPositionTicker();
        break;

      case AppLifecycleState.inactive:
        // Fired when notification panel opens or during app-switch gesture.
        // Do NOT pause anything — just_audio and VideoController keep running.
        break;
    }
  }

  /// Seeks the muted VideoPlayerController to the current just_audio position
  /// and resumes video rendering when the app comes back to the foreground.
  Future<void> _syncVideoToAudio() async {
    if (_videoController == null || !_videoController!.value.isInitialized) return;
    try {
      final audioPos = _audioHandler?.player.position ?? _position;
      // Only seek if the drift is more than 1 second to avoid unnecessary stutter
      if ((audioPos - _position).abs() > const Duration(seconds: 1)) {
        await _videoController!.seekTo(audioPos);
      }
      await _videoController!.play();
      _position = _audioHandler?.player.position ?? audioPos;
      notifyListeners();
    } catch (e) {
      debugPrint('_syncVideoToAudio note: $e');
    }
  }

  // ─── Position Ticker ─────────────────────────────────────────────────────────

  /// Starts a 500 ms periodic timer that polls just_audio's current position
  /// and notifies listeners so the seek slider and time labels always refresh.
  void _startPositionTicker() {
    _positionTicker?.cancel();
    _positionTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_isPlaying || _isAppInBackground) return;
      final audioPos = _audioHandler?.player.position;
      if (audioPos != null && audioPos != _position) {
        _position = audioPos;
        notifyListeners();
      }
    });
  }

  void _stopPositionTicker() {
    _positionTicker?.cancel();
    _positionTicker = null;
  }

  // ─── Playlist ───────────────────────────────────────────────────────────────

  void loadPlaylist(List<VideoModel> videos, {int startIndex = 0}) {
    _playlist.clear();
    _playlist.addAll(videos);
    _regenerateShuffleList();

    if (_playlist.isNotEmpty) {
      final safeIndex = startIndex.clamp(0, _playlist.length - 1);
      playVideo(_playlist[safeIndex]);
    }
  }

  // ─── Core Playback ──────────────────────────────────────────────────────────

  Future<void> playVideo(VideoModel video) async {
    final int switchId = ++_activeSwitchId;
    _isEndHandled = false;
    _isMiniPlayerDismissed = false;

    // Update current index
    final foundIndex = _activeList.indexWhere((v) => v.id == video.id);
    if (foundIndex != -1) {
      _currentIndex = foundIndex;
    } else {
      _playlist.insert(0, video);
      _regenerateShuffleList();
      _currentIndex = 0;
    }

    // Tear down existing controller and stop previous audio immediately
    _videoController?.removeListener(_onVideoControllerUpdate);
    final oldVideo = _videoController;
    _videoController = null;
    oldVideo?.dispose();

    await _audioHandler?.player.pause();

    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    notifyListeners();

    final file = File(video.videoPath);
    if (!await file.exists()) {
      debugPrint('Media file not found: ${video.videoPath}');
      return;
    }

    if (switchId != _activeSwitchId) return; // Stale request cancelled by newer tap

    // Initialize Video Player for video frames
    final newVideoController = VideoPlayerController.file(file);
    try {
      await newVideoController.initialize();
    } catch (e) {
      debugPrint('VideoPlayerController initialize error: $e');
    }

    if (switchId != _activeSwitchId) {
      newVideoController.dispose();
      return;
    }

    _videoController = newVideoController;
    if (_videoController!.value.isInitialized) {
      _duration = _videoController!.value.duration;
      await _videoController!.setVolume(0.0); // Muted; audio comes from just_audio
      await _videoController!.setPlaybackSpeed(_playbackSpeed);
      _videoController!.addListener(_onVideoControllerUpdate);
    }

    // Initialize just_audio for background-safe sound
    try {
      await _audioHandler?.prepareMedia(
        id: video.id,
        title: video.title,
        author: video.author,
        videoPath: video.videoPath,
        thumbnailPath: video.thumbnailPath,
        initialPosition: Duration.zero,
      );
      await _audioHandler?.setSpeed(_playbackSpeed);
    } catch (e) {
      debugPrint('AudioHandler prepareMedia note: $e');
    }

    if (switchId != _activeSwitchId) return;

    // Start playback on both players synchronously
    _isPlaying = true;
    notifyListeners();

    try {
      await Future.wait([
        if (_videoController != null && _videoController!.value.isInitialized)
          _videoController!.play(),
        // Use .player directly to avoid re-triggering the onPlay callback loop
        if (_audioHandler != null)
          _audioHandler!.player.play(),
      ]);
    } catch (e) {
      debugPrint('Playback start error: $e');
    }

    if (switchId == _activeSwitchId) {
      // Kick off position ticker so UI refreshes every 500 ms
      _startPositionTicker();
      notifyListeners();
    }
  }

  // ─── Video Controller Listener ─────────────────────────────────────────────

  void _onVideoControllerUpdate() {
    if (_videoController == null || _isAppInBackground) return;
    final val = _videoController!.value;

    // Use just_audio position as the authoritative position since it's the real audio source.
    // Fall back to video controller position if just_audio isn't available.
    final audioPos = _audioHandler?.player.position;
    _position = (audioPos != null && audioPos > Duration.zero) ? audioPos : val.position;

    if (val.duration > Duration.zero) {
      _duration = val.duration;
    }

    notifyListeners();
  }

  void _onVideoEnded() {
    if (_repeatMode == RepeatMode.one) {
      _isEndHandled = false;
      seekTo(Duration.zero);
      play();
    } else if (_currentIndex + 1 < _activeList.length) {
      playNext();
    } else if (_repeatMode == RepeatMode.all && _activeList.isNotEmpty) {
      _currentIndex = 0;
      playVideo(_activeList[0]);
    } else {
      _isPlaying = false;
      notifyListeners();
    }
  }

  // ─── Transport Controls ─────────────────────────────────────────────────────

  Future<void> play() async {
    _isPlaying = true;
    _startPositionTicker();
    notifyListeners();

    try {
      await Future.wait([
        if (_videoController != null && _videoController!.value.isInitialized)
          _videoController!.play(),
        // Use .player directly to avoid re-triggering the onPlay callback loop
        if (_audioHandler != null)
          _audioHandler!.player.play(),
      ]);
    } catch (e) {
      debugPrint('Play error: $e');
    }
  }

  Future<void> pause() async {
    _isPlaying = false;
    _stopPositionTicker();
    notifyListeners();

    try {
      await Future.wait([
        if (_videoController != null && _videoController!.value.isInitialized)
          _videoController!.pause(),
        // Use .player directly to avoid re-triggering the onPause callback loop
        if (_audioHandler != null)
          _audioHandler!.player.pause(),
      ]);
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
    final clamped = position < Duration.zero ? Duration.zero : position;
    await _videoController?.seekTo(clamped);
    await _audioHandler?.seek(clamped);
    _position = clamped;
    notifyListeners();
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
      _currentIndex++;
      playVideo(_activeList[_currentIndex]);
    } else if (_repeatMode == RepeatMode.all) {
      _currentIndex = 0;
      playVideo(_activeList[0]);
    }
  }

  void playPrevious() {
    if (_activeList.isEmpty) return;
    if (_position.inSeconds > 3) {
      seekTo(Duration.zero);
      play();
    } else if (_currentIndex - 1 >= 0) {
      _currentIndex--;
      playVideo(_activeList[_currentIndex]);
    } else {
      seekTo(Duration.zero);
    }
  }

  // ─── Settings ───────────────────────────────────────────────────────────────

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_isShuffle) {
      _regenerateShuffleList();
      if (currentVideo != null) {
        _currentIndex = _shuffledPlaylist.indexWhere(
          (v) => v.id == currentVideo!.id,
        );
      }
    } else {
      if (currentVideo != null) {
        _currentIndex = _playlist.indexWhere((v) => v.id == currentVideo!.id);
      }
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
    _playbackSpeed = speed;
    await _videoController?.setPlaybackSpeed(speed);
    await _audioHandler?.setSpeed(speed);
    notifyListeners();
  }

  void _regenerateShuffleList() {
    _shuffledPlaylist.clear();
    _shuffledPlaylist.addAll(_playlist);
    _shuffledPlaylist.shuffle(Random());
  }

  void dismissMiniPlayer() {
    _isMiniPlayerDismissed = true;
    pause();
    notifyListeners();
  }

  void restoreMiniPlayer() {
    _isMiniPlayerDismissed = false;
    notifyListeners();
  }

  // ─── Cleanup ─────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _stopPositionTicker();
    WidgetsBinding.instance.removeObserver(this);
    _videoController?.removeListener(_onVideoControllerUpdate);
    _videoController?.dispose();
    _audioHandler?.dispose();
    super.dispose();
  }
}
