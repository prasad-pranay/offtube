import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class OfflineAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  /// Callbacks wired up by PlaybackCoordinator so notification bar
  /// buttons forward to the coordinator (keeps video + state in sync).
  VoidCallback? onSkipToNext;
  VoidCallback? onSkipToPrevious;
  VoidCallback? onPlay;   // notification play button → coordinator.play()
  VoidCallback? onPause;  // notification pause button → coordinator.pause()

  OfflineAudioHandler() {
    _initAudioEvents();
  }

  AudioPlayer get player => _player;

  void _initAudioEvents() {
    // Forward just_audio playback state to the system MediaSession /
    // notification bar so the OS always has an accurate picture.
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.stop,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 3],
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
        ),
      );
    });

    _player.durationStream.listen((duration) {
      if (duration != null && mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });
  }

  Future<void> prepareMedia({
    required String id,
    required String title,
    String? author,
    required String videoPath,
    String? thumbnailPath,
    Duration? initialPosition,
  }) async {
    final item = MediaItem(
      id: id,
      title: title,
      artist: author ?? 'OfflineTube',
      album: 'Downloaded Videos',
      artUri: (thumbnailPath != null && File(thumbnailPath).existsSync())
          ? Uri.file(thumbnailPath)
          : null,
      extras: {'videoPath': videoPath},
    );

    mediaItem.add(item);

    try {
      // Stop & reset player before loading a new source to prevent decoder overlap
      await _player.stop();
      await _player.setFilePath(videoPath, initialPosition: initialPosition);
    } catch (e) {
      debugPrint('Error setting file path in audio handler: $e');
    }
  }

  @override
  Future<void> play() async {
    // If a callback is wired, let the coordinator drive both players.
    // Otherwise fall back to controlling just_audio directly.
    if (onPlay != null) {
      onPlay!();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> pause() async {
    if (onPause != null) {
      onPause!();
    } else {
      await _player.pause();
    }
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  /// Called when user taps ⏭ in the notification / lockscreen.
  @override
  Future<void> skipToNext() async {
    onSkipToNext?.call();
  }

  /// Called when user taps ⏮ in the notification / lockscreen.
  @override
  Future<void> skipToPrevious() async {
    onSkipToPrevious?.call();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
