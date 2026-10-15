import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class OfflineAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  bool _calledInternally = false;
  bool _disposed = false;

  VoidCallback? onSkipToNext;
  VoidCallback? onSkipToPrevious;
  VoidCallback? onPlay;
  VoidCallback? onPause;
  void Function(Duration)? onSeek;

  StreamSubscription<PlaybackEvent>? _playbackEventSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  OfflineAudioHandler() {
    _initAudioEvents();
  }

  AudioPlayer get player => _player;

  void _initAudioEvents() {
    _playbackEventSubscription = _player.playbackEventStream.listen(
      (event) {
        final playing = _player.playing;

        final processingState =
            <ProcessingState, AudioProcessingState>{
              ProcessingState.idle: AudioProcessingState.idle,
              ProcessingState.loading: AudioProcessingState.loading,
              ProcessingState.buffering: AudioProcessingState.buffering,
              ProcessingState.ready: AudioProcessingState.ready,
              ProcessingState.completed: AudioProcessingState.completed,
            }[_player.processingState] ??
            AudioProcessingState.idle;

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
            processingState: processingState,
            playing: playing,
            updatePosition: _player.position,
            bufferedPosition: _player.bufferedPosition,
            speed: _player.speed,
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Audio playback event error: $error');
      },
    );

    _durationSubscription = _player.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (duration != null && item != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });

    _positionSubscription = _player.positionStream.listen((position) {
      // Keep notification position fresh even when playback events are sparse.
      if (_player.playing) {
        playbackState.add(
          playbackState.value.copyWith(updatePosition: position),
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Downloaded media
  // ---------------------------------------------------------------------------

  Future<void> prepareMedia({
    required String id,
    required String title,
    String? author,
    required String videoPath,
    String? thumbnailPath,
    Duration? duration,
    Duration? initialPosition,
  }) async {
    final file = File(videoPath);

    if (!await file.exists()) {
      throw Exception('Downloaded media file does not exist: $videoPath');
    }

    final item = MediaItem(
      id: id,
      title: title,
      artist: author ?? 'OfflineTube',
      album: 'Downloaded Videos',
      duration: duration,
      artUri: thumbnailPath != null && await File(thumbnailPath).exists()
          ? Uri.file(thumbnailPath)
          : null,
      extras: {'videoPath': videoPath},
    );

    try {
      await _player.setFilePath(
        videoPath,
        initialPosition: initialPosition ?? Duration.zero,
      );

      await _player.setVolume(1.0);

      mediaItem.add(item);

      final loadedDuration = _player.duration ?? duration;
      if (loadedDuration != null) {
        mediaItem.add(item.copyWith(duration: loadedDuration));
      }
    } catch (error, stackTrace) {
      debugPrint('Error preparing downloaded audio: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Online media
  // ---------------------------------------------------------------------------

  Future<void> prepareNetworkMedia({
    required String id,
    required String title,
    String? author,
    required String audioUrl,
    String? thumbnailUrl,
    Duration? duration,
    Duration initialPosition = Duration.zero,
  }) async {
    final uri = Uri.tryParse(audioUrl);

    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw Exception('Invalid online audio URL.');
    }

    final item = MediaItem(
      id: id,
      title: title,
      artist: author ?? 'Unknown',
      album: 'Online Videos',
      duration: duration,
      artUri: thumbnailUrl != null && thumbnailUrl.isNotEmpty
          ? Uri.tryParse(thumbnailUrl)
          : null,
      extras: {'sourceType': 'network', 'audioUrl': audioUrl},
    );

    try {
      await _player.stop();

      final loadedDuration = await _player.setAudioSource(
        AudioSource.uri(uri),
        initialPosition: initialPosition,
      );

      await _player.setVolume(1.0);

      mediaItem.add(item.copyWith(duration: loadedDuration ?? duration));

      debugPrint(
        'Audio loaded: processing=${_player.processingState}, '
        'duration=${_player.duration}',
      );
    } catch (error, stackTrace) {
      debugPrint('Error preparing online audio: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }
  // ---------------------------------------------------------------------------
  // Internal playback
  // ---------------------------------------------------------------------------

  /// Starts playback. The returned future may remain pending until playback
  /// completes, so callers should use unawaited() when starting playback.
  // Future<void> playInternal() async {
  //   if (_disposed) return;

  //   _calledInternally = true;
  //   try {
  //     await super.play();
  //   } finally {
  //     _calledInternally = false;
  //   }
  // }
  Future<void> playInternal() async {
    debugPrint('playInternal called');

    try {
      _calledInternally = true;

      await _player.play();

      debugPrint('Audio playback completed');
    } catch (e, st) {
      debugPrint('Audio playback failed: $e');
      debugPrintStack(stackTrace: st);
    } finally {
      _calledInternally = false;
    }
  }

  Future<void> pauseInternal() async {
    if (_disposed) return;

    _calledInternally = true;
    try {
      await _player.pause();
    } finally {
      _calledInternally = false;
    }
  }

  // ---------------------------------------------------------------------------
  // AudioService controls
  // ---------------------------------------------------------------------------

  @override
  Future<void> play() async {
    if (_calledInternally) {
      await _player.play();
      return;
    }

    if (onPlay != null) {
      onPlay!();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> pause() async {
    if (_calledInternally) {
      await _player.pause();
      return;
    }

    if (onPause != null) {
      onPause!();
    } else {
      await _player.pause();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    onSeek?.call(position);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  @override
  Future<void> skipToNext() async {
    onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    onSkipToPrevious?.call();
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _playbackEventSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _positionSubscription?.cancel();

    await _player.dispose();
  }
}

// import 'dart:io';
// import 'package:audio_service/audio_service.dart';
// import 'package:flutter/foundation.dart';
// import 'package:just_audio/just_audio.dart';

// class OfflineAudioHandler extends BaseAudioHandler with SeekHandler {
//   final AudioPlayer _player = AudioPlayer();

//   /// When true, play()/pause() directly invoke just_audio without calling
//   /// the coordinator callbacks — used by the coordinator itself to avoid loops.
//   bool _calledInternally = false;

//   /// Callbacks wired up by PlaybackCoordinator so notification bar
//   /// buttons forward to the coordinator (keeps video + state in sync).
//   VoidCallback? onSkipToNext;
//   VoidCallback? onSkipToPrevious;
//   VoidCallback? onPlay; // notification play button → coordinator.play()
//   VoidCallback? onPause; // notification pause button → coordinator.pause()
//   void Function(Duration)?
//   onSeek; // notification seek bar slider → coordinator.seekTo()

//   OfflineAudioHandler() {
//     _initAudioEvents();
//   }

//   AudioPlayer get player => _player;

//   void _initAudioEvents() {
//     // Forward just_audio playback state to the system MediaSession /
//     // notification bar so the OS always has an accurate picture.
//     _player.playbackEventStream.listen((PlaybackEvent event) {
//       final playing = _player.playing;
//       playbackState.add(
//         playbackState.value.copyWith(
//           controls: [
//             MediaControl.skipToPrevious,
//             if (playing) MediaControl.pause else MediaControl.play,
//             MediaControl.stop,
//             MediaControl.skipToNext,
//           ],
//           systemActions: const {
//             MediaAction.seek,
//             MediaAction.seekForward,
//             MediaAction.seekBackward,
//           },
//           androidCompactActionIndices: const [0, 1, 3],
//           processingState: const {
//             ProcessingState.idle: AudioProcessingState.idle,
//             ProcessingState.loading: AudioProcessingState.loading,
//             ProcessingState.buffering: AudioProcessingState.buffering,
//             ProcessingState.ready: AudioProcessingState.ready,
//             ProcessingState.completed: AudioProcessingState.completed,
//           }[_player.processingState]!,
//           playing: playing,
//           updatePosition: _player.position,
//           bufferedPosition: _player.bufferedPosition,
//           speed: _player.speed,
//         ),
//       );
//     });

//     _player.durationStream.listen((duration) {
//       if (duration != null && mediaItem.value != null) {
//         mediaItem.add(mediaItem.value!.copyWith(duration: duration));
//       }
//     });
//   }

//   Future<void> prepareMedia({
//     required String id,
//     required String title,
//     String? author,
//     required String videoPath,
//     String? thumbnailPath,
//     Duration? duration,
//     Duration? initialPosition,
//   }) async {
//     final item = MediaItem(
//       id: id,
//       title: title,
//       artist: author ?? 'OfflineTube',
//       album: 'Downloaded Videos',
//       duration: duration,
//       artUri: (thumbnailPath != null && File(thumbnailPath).existsSync())
//           ? Uri.file(thumbnailPath)
//           : null,
//       extras: {'videoPath': videoPath},
//     );

//     mediaItem.add(item);

//     try {
//       // Load file directly without calling stop(), preventing AudioService from
//       // prematurely shutting down the background foreground service on idle state.
//       final loadedDuration =
//           (initialPosition != null && initialPosition > Duration.zero)
//           ? await _player.setFilePath(
//               videoPath,
//               initialPosition: initialPosition,
//             )
//           : await _player.setFilePath(videoPath);

//       final finalDuration = loadedDuration ?? duration ?? _player.duration;
//       if (finalDuration != null) {
//         mediaItem.add(item.copyWith(duration: finalDuration));
//       }
//       await _player.setVolume(1.0);
//     } catch (e) {
//       debugPrint('Error setting file path in audio handler: $e');
//     }
//   }

//   /// Called by the coordinator to start audio playback without triggering
//   /// the onPlay callback (which would cause an infinite loop).
//   Future<void> playInternal() async {
//     _calledInternally = true;
//     try {
//       await _player.play();
//     } finally {
//       _calledInternally = false;
//     }
//   }

//   /// Called by the coordinator to pause audio without triggering the onPause
//   /// callback (which would cause an infinite loop).
//   Future<void> pauseInternal() async {
//     _calledInternally = true;
//     try {
//       await _player.pause();
//     } finally {
//       _calledInternally = false;
//     }
//   }

//   Future<void> prepareNetworkMedia({
//     required String id,
//     required String title,
//     String? author,
//     required String audioUrl,
//     String? thumbnailUrl,
//     Duration? duration,
//     Duration initialPosition = Duration.zero,
//   }) async {
//     final item = MediaItem(
//       id: id,
//       title: title,
//       artist: author ?? 'Unknown',
//       album: 'Online Videos',
//       duration: duration,
//       artUri: thumbnailUrl != null && thumbnailUrl.isNotEmpty
//           ? Uri.tryParse(thumbnailUrl)
//           : null,
//       extras: {'sourceType': 'network', 'audioUrl': audioUrl},
//     );

//     try {
//       await _player.stop();

//       mediaItem.add(item);

//       final loadedDuration = await _player.setAudioSource(
//         AudioSource.uri(Uri.parse(audioUrl)),
//         initialPosition: initialPosition,
//       );

//       final finalDuration = loadedDuration ?? duration;

//       if (finalDuration != null) {
//         mediaItem.add(item.copyWith(duration: finalDuration));
//       }

//       await _player.setVolume(1.0);
//     } catch (e, stackTrace) {
//       debugPrint('Error preparing network audio: $e');
//       debugPrintStack(stackTrace: stackTrace);
//       rethrow;
//     }
//   }

//   @override
//   Future<void> play() async {
//     // This is triggered by the notification bar play button.
//     // If the coordinator wired a callback, delegate to it so video stays in sync.
//     if (!_calledInternally && onPlay != null) {
//       onPlay!();
//     } else {
//       await _player.play();
//     }
//   }

//   @override
//   Future<void> pause() async {
//     if (!_calledInternally && onPause != null) {
//       onPause!();
//     } else {
//       await _player.pause();
//     }
//   }

//   @override
//   Future<void> seek(Duration position) async {
//     await _player.seek(position);
//     onSeek?.call(position);
//   }

//   @override
//   Future<void> stop() async {
//     await _player.stop();
//     await super.stop();
//   }

//   @override
//   Future<void> setSpeed(double speed) => _player.setSpeed(speed);

//   /// Called when user taps ⏭ in the notification / lockscreen.
//   @override
//   Future<void> skipToNext() async {
//     onSkipToNext?.call();
//   }

//   /// Called when user taps ⏮ in the notification / lockscreen.
//   @override
//   Future<void> skipToPrevious() async {
//     onSkipToPrevious?.call();
//   }

//   Future<void> dispose() async {
//     await _player.dispose();
//   }
// }
