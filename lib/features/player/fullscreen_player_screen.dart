import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:offlinetube/core/theme/app_theme.dart';
import 'package:offlinetube/data/models/video_model.dart';
import 'package:offlinetube/services/playback/playback_coordinator.dart';

class FullscreenPlayerScreen extends StatefulWidget {
  const FullscreenPlayerScreen({super.key});

  @override
  State<FullscreenPlayerScreen> createState() => _FullscreenPlayerScreenState();
}

class _FullscreenPlayerScreenState extends State<FullscreenPlayerScreen> {
  bool _showControls = true;
  Timer? _hideTimer;
  double _dragOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && PlaybackCoordinator.instance.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _onSpeedSelected(double speed) {
    PlaybackCoordinator.instance.setPlaybackSpeed(speed);
  }

  void _showSpeedMenu() {
    final currentSpeed = PlaybackCoordinator.instance.playbackSpeed;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Playback Speed',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            ...[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map((s) {
              return ListTile(
                title: Text(
                  '${s}x',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                trailing: currentSpeed == s
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppTheme.accentColor,
                      )
                    : null,
                onTap: () {
                  _onSpeedSelected(s);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlaybackCoordinator.instance,
      builder: (context, _) {
        final coordinator = PlaybackCoordinator.instance;
        final video = coordinator.currentVideo;
        final controller = coordinator.videoController;

        if (video == null) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: Text('No media playing')),
          );
        }

        final pos = coordinator.position;
        final dur = coordinator.duration;
        final maxDurMs = dur.inMilliseconds > 0
            ? dur.inMilliseconds.toDouble()
            : 1.0;
        final currentPosMs = pos.inMilliseconds.toDouble().clamp(0.0, maxDurMs);

        // Calculate swipe down opacity/scale
        final dragProgress = (_dragOffset / 300.0).clamp(0.0, 1.0);
        final scale = 1.0 - (dragProgress * 0.2);
        final opacity = 1.0 - (dragProgress * 0.4);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              coordinator.restoreMiniPlayer();
              Navigator.pop(context);
            }
          },
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              if (details.delta.dy > 0 || _dragOffset > 0) {
                setState(() {
                  _dragOffset = (_dragOffset + details.delta.dy).clamp(
                    0.0,
                    500.0,
                  );
                });
              }
            },
            onVerticalDragEnd: (details) {
              if (_dragOffset > 120 ||
                  (details.primaryVelocity != null &&
                      details.primaryVelocity! > 600)) {
                // Minimize player
                coordinator.restoreMiniPlayer();
                Navigator.pop(context);
              } else {
                setState(() {
                  _dragOffset = 0.0;
                });
              }
            },
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Scaffold(
                    backgroundColor: Colors.black,
                    body: SafeArea(
                      child: GestureDetector(
                        onTap: _toggleControls,
                        behavior: HitTestBehavior.opaque,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Video / Album-Art View
                            _buildVideoArea(controller, video),

                            // Controls Overlay
                            AnimatedOpacity(
                              opacity: _showControls ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 250),
                              child: IgnorePointer(
                                ignoring: !_showControls,
                                child: Container(
                                  color: Colors.black.withAlpha(120),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Top bar (Minimize, Title, Speed, Settings)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                Icons
                                                    .keyboard_arrow_down_rounded,
                                                size: 32,
                                                color: Colors.white,
                                              ),
                                              tooltip: 'Minimize',
                                              onPressed: () {
                                                coordinator.restoreMiniPlayer();
                                                Navigator.pop(context);
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    video.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  if (video.author != null)
                                                    Text(
                                                      video.author!,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withAlpha(180),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: _showSpeedMenu,
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                backgroundColor: Colors.white24,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                              child: Text(
                                                '${coordinator.playbackSpeed}x',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Center Playback Buttons (Previous, Rewind 10, Play/Pause, Forward 10, Next)
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.skip_previous_rounded,
                                              size: 36,
                                              color: Colors.white,
                                            ),
                                            onPressed: () {
                                              coordinator.playPrevious();
                                              _startHideTimer();
                                            },
                                          ),
                                          const SizedBox(width: 12),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.replay_10_rounded,
                                              size: 36,
                                              color: Colors.white,
                                            ),
                                            onPressed: () {
                                              coordinator.seekBackward();
                                              _startHideTimer();
                                            },
                                          ),
                                          const SizedBox(width: 16),
                                          Container(
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: AppTheme.accentColor,
                                            ),
                                            child: IconButton(
                                              iconSize: 44,
                                              icon: Icon(
                                                coordinator.isPlaying
                                                    ? Icons.pause_rounded
                                                    : Icons.play_arrow_rounded,
                                                color: Colors.white,
                                              ),
                                              onPressed: () {
                                                coordinator.togglePlayPause();
                                                _startHideTimer();
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.forward_10_rounded,
                                              size: 36,
                                              color: Colors.white,
                                            ),
                                            onPressed: () {
                                              coordinator.seekForward();
                                              _startHideTimer();
                                            },
                                          ),
                                          const SizedBox(width: 12),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.skip_next_rounded,
                                              size: 36,
                                              color: Colors.white,
                                            ),
                                            onPressed: () {
                                              coordinator.playNext();
                                              _startHideTimer();
                                            },
                                          ),
                                        ],
                                      ),

                                      // Bottom bar (Seekbar, Current Time, Remaining, Shuffle, Repeat)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          0,
                                          16,
                                          16,
                                        ),
                                        child: Column(
                                          children: [
                                            // Progress Slider
                                            SliderTheme(
                                              data: SliderTheme.of(context).copyWith(
                                                trackHeight: 3,
                                                thumbShape:
                                                    const RoundSliderThumbShape(
                                                      enabledThumbRadius: 6,
                                                    ),
                                                overlayShape:
                                                    const RoundSliderOverlayShape(
                                                      overlayRadius: 14,
                                                    ),
                                                activeTrackColor:
                                                    AppTheme.accentColor,
                                                inactiveTrackColor:
                                                    Colors.white24,
                                                thumbColor:
                                                    AppTheme.accentColor,
                                              ),
                                              child: Slider(
                                                value: currentPosMs,
                                                min: 0.0,
                                                max: maxDurMs,
                                                onChanged: (val) {
                                                  _startHideTimer();
                                                  coordinator.seekTo(
                                                    Duration(
                                                      milliseconds: val.toInt(),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  _formatTime(pos),
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                Row(
                                                  children: [
                                                    // Shuffle toggle
                                                    IconButton(
                                                      icon: Icon(
                                                        Icons.shuffle_rounded,
                                                        size: 20,
                                                        color:
                                                            coordinator
                                                                .isShuffle
                                                            ? AppTheme
                                                                  .accentColor
                                                            : Colors.white60,
                                                      ),
                                                      tooltip: 'Shuffle',
                                                      onPressed: () {
                                                        coordinator
                                                            .toggleShuffle();
                                                        _startHideTimer();
                                                      },
                                                    ),
                                                    // Repeat toggle
                                                    IconButton(
                                                      icon: Icon(
                                                        coordinator.repeatMode ==
                                                                RepeatMode.one
                                                            ? Icons
                                                                  .repeat_one_rounded
                                                            : Icons
                                                                  .repeat_rounded,
                                                        size: 20,
                                                        color:
                                                            coordinator
                                                                    .repeatMode !=
                                                                RepeatMode.off
                                                            ? AppTheme
                                                                  .accentColor
                                                            : Colors.white60,
                                                      ),
                                                      tooltip: 'Repeat',
                                                      onPressed: () {
                                                        coordinator
                                                            .toggleRepeatMode();
                                                        _startHideTimer();
                                                      },
                                                    ),
                                                  ],
                                                ),
                                                Text(
                                                  _formatTime(dur),
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the main video/audio display area:
  /// - Loading spinner while controller is not yet ready
  /// - Animated album art for audio-only or no-video-track files
  /// - VideoPlayer with a ValueKey for proper rebuild on controller swap
  Widget _buildVideoArea(VideoPlayerController? controller, VideoModel video) {
    // Not yet initialized — show loading spinner
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentColor),
        ),
      );
    }

    // Detect audio-only: no video track means size is 0×0 or aspect ratio is <= 0
    final size = controller.value.size;
    final isAudioOnly = size.width <= 0 || size.height <= 0;

    if (isAudioOnly) {
      return _AudioOnlyView(video: video);
    }

    // Normal video — use ValueKey so Flutter replaces the widget when
    // the controller instance changes (e.g., when skipping to next track)
    return Center(
      key: ValueKey(controller.hashCode),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  String _formatTime(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Shown when playing an audio-only file (no video track).
/// Displays the thumbnail with a pulsing glow and music note icon.
class _AudioOnlyView extends StatefulWidget {
  final VideoModel video;
  const _AudioOnlyView({required this.video});

  @override
  State<_AudioOnlyView> createState() => _AudioOnlyViewState();
}

class _AudioOnlyViewState extends State<_AudioOnlyView>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thumbFile = File(widget.video.thumbnailPath);
    final hasThumb = thumbFile.existsSync();

    return Center(
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) {
          return Transform.scale(scale: _pulseAnim.value, child: child);
        },
        child: Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white10,
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentColor.withAlpha(80),
                blurRadius: 60,
                spreadRadius: 10,
              ),
            ],
            image: hasThumb
                ? DecorationImage(
                    image: FileImage(thumbFile),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: hasThumb
              ? null
              : const Icon(
                  Icons.music_note_rounded,
                  size: 80,
                  color: AppTheme.accentColor,
                ),
        ),
      ),
    );
  }
}
