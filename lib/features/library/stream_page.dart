import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:offlinetube/features/downloader/widgets/quality_selection_sheet.dart';
import 'package:offlinetube/services/PlayerManager.dart';
import 'package:offlinetube/services/database/database_service.dart';
import 'package:offlinetube/services/extractor/video_extractor_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

class StreamVideoPage extends StatefulWidget {
  const StreamVideoPage({super.key, this.onDownload});

  final VoidCallback? onDownload;

  @override
  State<StreamVideoPage> createState() => _StreamVideoPageState();
}

class _StreamVideoPageState extends State<StreamVideoPage>
    with SingleTickerProviderStateMixin {
  double _dragProgress = 0.0;
  bool _minimizing = false;

  late AnimationController _animationController;

  Timer? _controlsTimer;

  bool _showControls = true;

  // Double-tap feedback.
  String? _seekFeedback;
  IconData? _seekFeedbackIcon;
  Timer? _seekFeedbackTimer;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    final controller = PlayerManager.instance.controller;

    controller?.addListener(_videoListener);

    _startControlsTimer();
  }

  void _videoListener() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _seekFeedbackTimer?.cancel();

    PlayerManager.instance.controller?.removeListener(_videoListener);

    _animationController.dispose();

    // Make sure system UI comes back if fullscreen was used.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  // ------------------------------------------------------------
  // CONTROLS
  // ------------------------------------------------------------

  void _toggleControls() {
    if (_minimizing) return;

    setState(() {
      _showControls = !_showControls;
    });

    if (_showControls) {
      _startControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();

    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _minimizing) return;

      setState(() {
        _showControls = false;
      });
    });
  }

  void _showControlsTemporarily() {
    setState(() {
      _showControls = true;
    });

    _startControlsTimer();
  }

  // ------------------------------------------------------------
  // DOUBLE TAP SEEK
  // ------------------------------------------------------------

  Future<void> _seekRelative(Duration offset) async {
    final controller = PlayerManager.instance.controller;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final current = controller.value.position;
    final duration = controller.value.duration;

    var target = current + offset;

    if (target < Duration.zero) {
      target = Duration.zero;
    }

    if (target > duration) {
      target = duration;
    }

    await controller.seekTo(target);
  }

  Future<void> _doubleTapSeek({required bool forward}) async {
    final controller = PlayerManager.instance.controller;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    await _seekRelative(Duration(seconds: forward ? 10 : -10));

    _showSeekFeedback(forward);
    _showControlsTemporarily();
  }

  void _showSeekFeedback(bool forward) {
    _seekFeedbackTimer?.cancel();

    setState(() {
      _seekFeedback = forward ? '+10' : '-10';
      _seekFeedbackIcon = forward ? Icons.forward_10 : Icons.replay_10;
    });

    _seekFeedbackTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;

      setState(() {
        _seekFeedback = null;
        _seekFeedbackIcon = null;
      });
    });
  }

  // ------------------------------------------------------------
  // PLAY / PAUSE
  // ------------------------------------------------------------

  void _togglePlayPause() {
    final controller = PlayerManager.instance.controller;

    if (controller == null) return;

    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }

    _showControlsTemporarily();
  }

  // ------------------------------------------------------------
  // SWIPE TO MINIMIZE
  // ------------------------------------------------------------

  void _onDragUpdate(DragUpdateDetails details) {
    if (_minimizing) return;

    if (details.delta.dy <= 0) return;

    setState(() {
      _dragProgress += details.delta.dy / 450;

      _dragProgress = _dragProgress.clamp(0.0, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_minimizing) return;

    final velocity = details.primaryVelocity ?? 0;

    if (_dragProgress > 0.20 || velocity > 700) {
      _minimize();
    } else {
      _animateBack();
    }
  }

  Future<void> _animateBack() async {
    _animationController.reset();

    final animation = Tween<double>(begin: _dragProgress, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    animation.addListener(() {
      if (!mounted) return;

      setState(() {
        _dragProgress = animation.value;
      });
    });

    await _animationController.forward();
  }

  Future<void> _minimize() async {
    if (_minimizing) return;

    _minimizing = true;

    _controlsTimer?.cancel();

    _animationController.reset();

    final animation = Tween<double>(begin: _dragProgress, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    animation.addListener(() {
      if (!mounted) return;

      setState(() {
        _dragProgress = animation.value;
      });
    });

    await _animationController.forward();

    if (!mounted) return;

    PlayerManager.instance.minimize();

    Navigator.pop(context);
  }

  // ------------------------------------------------------------
  // DOWNLOAD
  // ------------------------------------------------------------

  void _download() async {
    final videoinfo = PlayerManager.instance.videoInfo;
    final info = await VideoExtractorService.instance.extractInfo(
      "https://www.youtube.com/watch?v=${videoinfo?.id}",
    );
    // Open quality selection sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => QualitySelectionSheet(info: info),
    );
    // if (widget.onDownload != null) {
    //   widget.onDownload!();
    //   return;
    // }

    // ScaffoldMessenger.of(context).showSnackBar(
    //   const SnackBar(
    //     content: Text('Download action is not connected yet.'),
    //     behavior: SnackBarBehavior.floating,
    //   ),
    // );
  }

  // ------------------------------------------------------------
  // SHARE
  // ------------------------------------------------------------

  Future<void> _share() async {
    final info = PlayerManager.instance.videoInfo;

    if (info == null) return;

    final title = info.title.trim();

    await SharePlus.instance.share(ShareParams(text: title));
  }

  // ------------------------------------------------------------
  // FULLSCREEN
  // ------------------------------------------------------------

  bool fullScreen = false;
  Future<void> _toggleFullscreen() async {
    final controller = PlayerManager.instance.controller;
    if (controller == null) return;
    setState(() {
      fullScreen = !fullScreen;
    });

    final isFullscreen =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (isFullscreen) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  // ------------------------------------------------------------
  // TIME FORMAT
  // ------------------------------------------------------------

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '$minutes:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------
  // VIDEO CONTROLS
  // ------------------------------------------------------------

  Widget _buildVideoControls(
    BuildContext context,
    VideoPlayerController controller,
  ) {
    if (!_showControls || _dragProgress > 0.05) {
      return const SizedBox.shrink();
    }

    final value = controller.value;

    final position = value.position;
    final duration = value.duration;

    final maxSeconds = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;

    final positionSeconds = position.inMilliseconds
        .clamp(0, duration.inMilliseconds)
        .toDouble();

    return Positioned.fill(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: _showControls ? 1 : 0,
        child: IgnorePointer(
          ignoring: !_showControls,
          child: Stack(
            children: [
              // Dark gradient for readability.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.35, 0.75, 1.0],
                        colors: [
                          Colors.black54,
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black87,
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Top controls.
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _minimize(),
                        child: const Padding(
                          padding: EdgeInsets.all(9),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                      ),
                    ),

                    const Spacer(),
                    if (fullScreen)
                      Text(
                        PlayerManager.instance.videoInfo?.title ?? '',
                        style: TextStyle(fontSize: 20, color: Colors.white70),
                      ),
                    const Spacer(),

                    Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _toggleFullscreen,
                        child: const Padding(
                          padding: EdgeInsets.all(9),
                          child: Icon(
                            Icons.fullscreen,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Center playback controls.
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // _ControlButton(
                    //   icon: Icons.replay_10,
                    //   onTap: () {
                    //     _doubleTapSeek(forward: false);
                    //   },
                    // ),
                    const SizedBox(width: 20),

                    _ControlButton(
                      icon: value.isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 58,
                      onTap: _togglePlayPause,
                    ),

                    const SizedBox(width: 20),

                    // _ControlButton(
                    //   icon: Icons.forward_10,
                    //   onTap: () {
                    //     _doubleTapSeek(forward: true);
                    //   },
                    // ),
                  ],
                ),
              ),

              // Bottom controls.
              Positioned(
                left: 12,
                right: 12,
                bottom: 8,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          _formatDuration(position),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Text(
                          ' / ',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        // const Spacer(),
                        // const Text(
                        //   '10s',
                        //   style: TextStyle(color: Colors.white70, fontSize: 11),
                        // ),
                      ],
                    ),

                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                      ),
                      child: Slider(
                        min: 0,
                        inactiveColor: Colors.grey,
                        max: maxSeconds,
                        value: positionSeconds,
                        onChanged: (value) {
                          controller.seekTo(
                            Duration(milliseconds: value.round()),
                          );

                          _showControlsTemporarily();
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Double-tap feedback.
              if (_seekFeedback != null)
                Positioned(
                  top: 100,
                  right: _seekFeedback == "+10" ? 10 : null,
                  left: _seekFeedback == "-10" ? 10 : null,
                  child: IgnorePointer(
                    child: AnimatedScale(
                      scale: _seekFeedback != null ? 1.0 : 0.8,
                      duration: const Duration(milliseconds: 120),
                      child: AnimatedOpacity(
                        opacity: _seekFeedback != null ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _seekFeedbackIcon,
                                color: Colors.white,
                                size: 28,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _seekFeedback!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // ACTION BUTTON
  // ------------------------------------------------------------

  Widget _actionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  final allVideos = DatabaseService.instance.getAllVideos();

  @override
  Widget build(BuildContext context) {
    final controller = PlayerManager.instance.controller;

    final videoIds = allVideos.map((e) => e.id).toList();

    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.sizeOf(context);

    final fullWidth = size.width;

    final fullHeight = fullWidth / controller.value.aspectRatio;

    // ----------------------------------------------------------
    // MINI PLAYER SIZE
    // ----------------------------------------------------------

    final miniWidth = 210.0;

    final miniHeight = miniWidth / controller.value.aspectRatio;

    final miniLeft = size.width - miniWidth - 12;

    final miniTop = size.height - miniHeight - 110;

    // ----------------------------------------------------------
    // VIDEO POSITION
    // ----------------------------------------------------------

    final videoWidth = lerpDouble(fullWidth, miniWidth, _dragProgress)!;

    final videoHeight = lerpDouble(fullHeight, miniHeight, _dragProgress)!;

    final videoLeft = lerpDouble(0, miniLeft, _dragProgress)!;

    final videoTop = lerpDouble(0, miniTop, _dragProgress)!;

    // ----------------------------------------------------------
    // PAGE FADE
    // ----------------------------------------------------------

    final pageContentOpacity = 1.0 - (_dragProgress * 1.2).clamp(0.0, 1.0);

    final borderRadius = lerpDouble(0, 12, _dragProgress)!;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // ====================================================
          // PAGE CONTENT
          // ====================================================
          if (!fullScreen)
            IgnorePointer(
              ignoring: _dragProgress > 0,
              child: Opacity(
                opacity: pageContentOpacity,
                child: Column(
                  children: [
                    SizedBox(height: fullHeight),

                    Expanded(
                      child: Container(
                        width: double.infinity,
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: 50),
                              Text(
                                PlayerManager.instance.videoInfo?.title ?? '',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),

                              const SizedBox(height: 16),

                              // ==================================
                              // DOWNLOAD / SHARE
                              // ==================================
                              Row(
                                children: [
                                  if (videoIds.contains(
                                    PlayerManager.instance.videoInfo?.id,
                                  ))
                                    _actionButton(
                                      context: context,
                                      icon: Icons.check,
                                      label: 'In Library',
                                      onTap: () {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Video is already downloaded.',
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      },
                                    ),
                                  if (!videoIds.contains(
                                    PlayerManager.instance.videoInfo?.id,
                                  ))
                                    _actionButton(
                                      context: context,
                                      icon: Icons.download_outlined,
                                      label: 'Download',
                                      onTap: _download,
                                    ),

                                  const SizedBox(width: 10),

                                  _actionButton(
                                    context: context,
                                    icon: Icons.share_outlined,
                                    label: 'Share',
                                    onTap: _share,
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              // ==================================
                              // PLAYBACK INFORMATION
                              // ==================================
                              Row(
                                children: [
                                  Icon(
                                    Icons.play_circle_outline,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),

                                  const SizedBox(width: 7),

                                  Text(
                                    _formatDuration(controller.value.duration),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),

                                  const SizedBox(width: 16),

                                  Icon(
                                    Icons.high_quality_outlined,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),

                                  const SizedBox(width: 7),

                                  Text(
                                    'Streaming',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              // ==================================
                              // DESCRIPTION / EXTRA INFO
                              // ==================================
                              Text(
                                'Now playing',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),

                              const SizedBox(height: 6),

                              Text(
                                'This video is being streamed directly and can be minimized while it continues playing.',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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

          // ====================================================
          // MOVING VIDEO
          // ====================================================
          Positioned(
            left: videoLeft,
            top: videoTop + (fullScreen ? 0 : 50),
            width: fullScreen ? size.width : videoWidth,
            height: fullScreen ? size.height : videoHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,

              // ------------------------------------------------
              // SINGLE TAP
              // ------------------------------------------------
              onTap: _toggleControls,

              // ------------------------------------------------
              // DOUBLE TAP
              // ------------------------------------------------
              onDoubleTapDown: (details) {
                final videoWidth =
                    context.size?.width ?? MediaQuery.sizeOf(context).width;

                final tapX = details.localPosition.dx;

                if (tapX < videoWidth / 2) {
                  _doubleTapSeek(forward: false);
                } else {
                  _doubleTapSeek(forward: true);
                }
              },

              // ------------------------------------------------
              // SWIPE DOWN
              // ------------------------------------------------
              onVerticalDragUpdate: (e) {
                if (fullScreen) {
                  _toggleFullscreen();
                  return;
                } else {
                  _onDragUpdate(e);
                }
              },
              onVerticalDragEnd: (e) {
                if (fullScreen) {
                  _toggleFullscreen();
                  return;
                } else {
                  _onDragEnd(e);
                }
              },

              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.black,
                  ), // VideoPlayer(controller),
                  Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  ),
                  _buildVideoControls(context, controller),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// CONTROL BUTTON
// ================================================================

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: size * 0.5),
        ),
      ),
    );
  }
}
