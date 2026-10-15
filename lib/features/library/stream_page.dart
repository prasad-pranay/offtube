import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'package:offlinetube/features/library/search_overlay.dart';
import 'package:offlinetube/features/downloader/widgets/quality_selection_sheet.dart';
import 'package:offlinetube/services/extractor/extracted_video_info.dart';
import 'package:offlinetube/services/extractor/video_extractor_service.dart';
import 'package:offlinetube/services/playback/playback_coordinator.dart';

class StreamVideoPage extends StatefulWidget {
  final ExtractedVideoInfo info;
  final ExtractedFormat? format;
  final VoidCallback? onDownload;

  const StreamVideoPage({
    super.key,
    required this.info,
    this.format,
    this.onDownload,
  });

  @override
  State<StreamVideoPage> createState() => _StreamVideoPageState();
}

class _StreamVideoPageState extends State<StreamVideoPage>
    with TickerProviderStateMixin {
  final PlaybackCoordinator _coordinator = PlaybackCoordinator.instance;

  VideoPlayerController? _controller;

  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isMini = false;
  bool _isSeeking = false;
  bool _descriptionOpen = false;
  bool _isSwitchingVideo = false;

  final ValueNotifier<double> _dragProgress = ValueNotifier(0);

  Timer? _controlsTimer;

  late final AnimationController _snapController;
  late final AnimationController _dismissController;

  double _snapStart = 0;

  Duration _seekPosition = Duration.zero;

  static const double _miniWidth = 210;
  static const double _miniHeight = 120;
  static const double _miniMargin = 12;

  bool get _isDragging => _dragProgress.value > 0;

  @override
  void initState() {
    super.initState();

    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_animateSnapBack);

    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _coordinator.addListener(_onCoordinatorChanged);

    _startPlayback();
    _startControlsTimer();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _coordinator.removeListener(_onCoordinatorChanged);
    _controller?.removeListener(_onVideoChanged);

    _dragProgress.dispose();
    _snapController.dispose();
    _dismissController.dispose();

    // PlaybackCoordinator owns the video controller.
    // Do not dispose the shared controller here.

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  Future<void> _startPlayback() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      await _coordinator.ensureOnlineVideo(widget.info, format: widget.format);

      if (!mounted) return;

      _attachVideoController();

      final controller = _controller;

      if (controller == null || !controller.value.isInitialized) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'The video could not be initialized.';
        });
        return;
      }

      setState(() {
        _isLoading = false;
        _hasError = false;
      });

      _startControlsTimer();
    } catch (error, stackTrace) {
      debugPrint('Playback error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Unable to play this video. Please try again.';
      });
    }
  }

  void _attachVideoController() {
    final next = _coordinator.videoController;

    if (identical(next, _controller)) return;

    _controller?.removeListener(_onVideoChanged);
    _controller = next;
    _controller?.addListener(_onVideoChanged);
  }

  void _onCoordinatorChanged() {
    if (!mounted) return;

    final previous = _controller;
    _attachVideoController();

    if (!identical(previous, _controller)) {
      setState(() {
        if (_controller?.value.isInitialized == true) {
          _isLoading = false;
          _hasError = false;
          _errorMessage = null;
        }
      });
    } else if (_controller?.value.isInitialized == true &&
        (_isLoading || _hasError)) {
      setState(() {
        _isLoading = false;
        _hasError = false;
        _errorMessage = null;
      });
    }
  }

  void _onVideoChanged() {
    // VideoPlayer controls listen directly to the controller.
    // Avoid rebuilding the whole page on every playback position update.
  }

  Future<void> _togglePlayPause() async {
    if (_isDragging || _isMini || _isSwitchingVideo) return;

    try {
      await _coordinator.togglePlayPause();
      if (mounted) _startControlsTimer();
    } catch (error) {
      debugPrint('Toggle playback failed: $error');
    }
  }

  Future<void> _seekTo(Duration position) async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) return;

    final duration = controller.value.duration;

    final target = Duration(
      milliseconds: position.inMilliseconds
          .clamp(0, duration.inMilliseconds)
          .toInt(),
    );

    try {
      await _coordinator.seekTo(target);
    } catch (error) {
      debugPrint('Seeking failed: $error');
    }

    if (!mounted) return;

    setState(() {
      _seekPosition = target;
      _isSeeking = false;
    });

    _startControlsTimer();
  }

  Future<void> _seekRelative(int seconds) async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) return;

    await _seekTo(
      Duration(seconds: controller.value.position.inSeconds + seconds),
    );
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  void _startControlsTimer() {
    _controlsTimer?.cancel();

    if (_isFullscreen || _isMini || _isDragging) return;

    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _isMini || _isDragging) return;

      setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    if (_isMini || _isDragging) return;

    setState(() => _showControls = !_showControls);

    if (_showControls) {
      _startControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  // ---------------------------------------------------------------------------
  // Drag-to-mini-player
  // ---------------------------------------------------------------------------

  double _maximumDrag(double screenHeight, double videoHeight) {
    return (screenHeight - videoHeight - _miniHeight - _miniMargin * 2).clamp(
      1.0,
      double.infinity,
    );
  }

  void _onDragStart(DragStartDetails details) {
    if (_isFullscreen || _isMini || _isSwitchingVideo) return;

    _snapController.stop();
    _controlsTimer?.cancel();

    setState(() {
      _showControls = false;
    });
  }

  void _onDragUpdate(DragUpdateDetails details, double maxDrag) {
    if (_isFullscreen || _isMini || _isSwitchingVideo) return;

    _dragProgress.value = (_dragProgress.value + details.delta.dy).clamp(
      0.0,
      maxDrag,
    );
  }

  void _onDragEnd(DragEndDetails details, double maxDrag) {
    if (_isFullscreen || _isMini || _isSwitchingVideo) return;

    final distance = _dragProgress.value;
    final velocity = details.primaryVelocity ?? 0;

    if (distance >= maxDrag * 0.72 || velocity > 900) {
      _enterMiniMode(maxDrag);
    } else {
      _animateBack();
    }
  }

  void _animateBack() {
    _snapStart = _dragProgress.value;

    if (_snapStart <= 0) {
      _dragProgress.value = 0;
      setState(() => _showControls = true);
      _startControlsTimer();
      return;
    }

    _snapController
      ..reset()
      ..forward();
  }

  void _animateSnapBack() {
    if (!mounted) return;

    final t = Curves.easeOutCubic.transform(_snapController.value);

    _dragProgress.value = _snapStart * (1 - t);

    if (_snapController.isCompleted) {
      _dragProgress.value = 0;

      if (mounted) {
        setState(() => _showControls = true);
        _startControlsTimer();
      }
    }
  }

  void _enterMiniMode(double maxDrag) {
    _controlsTimer?.cancel();
    _snapController.stop();

    _dragProgress.value = maxDrag;

    setState(() {
      Navigator.of(context).pop();
      _showControls = false;
    });
  }

  void _expandPlayer() {
    if (!_isMini) return;

    setState(() {
      _isMini = false;
      _showControls = true;
    });

    _animateBack();
  }

  // The close button closes the page. Playback remains owned by the coordinator.
  Future<void> _closePlayer() async {
    _controlsTimer?.cancel();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------------------------
  // Fullscreen
  // ---------------------------------------------------------------------------

  Future<void> _toggleFullscreen() async {
    if (_isMini) return;

    final entering = !_isFullscreen;

    if (entering) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    if (!mounted) return;

    setState(() {
      _isFullscreen = entering;
      _showControls = true;
    });

    _startControlsTimer();
  }

  // ---------------------------------------------------------------------------
  // Download and share
  // ---------------------------------------------------------------------------

  Future<void> _download() async {
    if (widget.onDownload != null) {
      widget.onDownload!();
      return;
    }

    try {
      final info = await VideoExtractorService.instance.extractInfo(
        'https://www.youtube.com/watch?v=${widget.info.id}',
      );

      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => QualitySelectionSheet(info: info),
      );
    } catch (error) {
      debugPrint('Download setup failed: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to prepare this video for download.'),
        ),
      );
    }
  }

  Future<void> _share() async {
    try {
      await Share.share(
        '${widget.info.title}\n'
        'https://www.youtube.com/watch?v=${widget.info.id}',
      );
    } catch (error) {
      debugPrint('Share failed: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Video and controls
  // ---------------------------------------------------------------------------

  Widget _buildVideoSurface() {
    final controller = _controller;

    if (_isLoading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_hasError || controller == null || !controller.value.isInitialized) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white70,
                  size: 38,
                ),
                const SizedBox(height: 10),
                Text(
                  _errorMessage ?? 'Unable to load this video.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _startPlayback,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RepaintBoundary(child: VideoPlayer(controller));
  }

  Widget _buildControls() {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final duration = value.duration;
        final position = _isSeeking ? _seekPosition : value.position;

        final max = duration.inMilliseconds > 0
            ? duration.inMilliseconds.toDouble()
            : 1.0;

        final current = position.inMilliseconds
            .clamp(0, max.toInt())
            .toDouble();

        return AnimatedOpacity(
          opacity: _showControls && !_isDragging && !_isMini ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: IgnorePointer(
            ignoring: !_showControls || _isDragging || _isMini,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x99000000),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0x99000000),
                  ],
                  stops: [0, 0.25, 0.65, 1],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          final screenHeight = MediaQuery.sizeOf(
                            context,
                          ).height;
                          final videoHeight =
                              MediaQuery.sizeOf(context).width * 9 / 16;

                          _enterMiniMode(
                            _maximumDrag(screenHeight, videoHeight),
                          );
                        },
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          widget.info.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _share,
                        icon: const Icon(
                          Icons.share_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () => _seekRelative(-10),
                        icon: const Icon(
                          Icons.replay_10_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: _togglePlayPause,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        onPressed: () => _seekRelative(10),
                        icon: const Icon(
                          Icons.forward_10_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.5,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 4,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                          ),
                          child: Slider(
                            min: 0,
                            max: max,
                            value: current.clamp(0, max),
                            activeColor: Colors.redAccent,
                            inactiveColor: Colors.white38,
                            onChangeStart: (value) {
                              _controlsTimer?.cancel();

                              setState(() {
                                _isSeeking = true;
                                _seekPosition = Duration(
                                  milliseconds: value.round(),
                                );
                              });
                            },
                            onChanged: (value) {
                              setState(() {
                                _seekPosition = Duration(
                                  milliseconds: value.round(),
                                );
                              });
                            },
                            onChangeEnd: (value) {
                              _seekTo(Duration(milliseconds: value.round()));
                            },
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatDuration(duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: _toggleFullscreen,
                              icon: Icon(
                                _isFullscreen
                                    ? Icons.fullscreen_exit_rounded
                                    : Icons.fullscreen_rounded,
                                color: Colors.white,
                                size: 24,
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
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String two(int n) => n.toString().padLeft(2, '0');

    if (duration.inHours > 0) {
      return '${duration.inHours}:'
          '${two(duration.inMinutes.remainder(60))}:'
          '${two(duration.inSeconds.remainder(60))}';
    }

    return '${duration.inMinutes}:${two(duration.inSeconds.remainder(60))}';
  }

  // ---------------------------------------------------------------------------
  // Information and recommendations
  // ---------------------------------------------------------------------------

  Widget _buildActionButton({
    required IconData icon,
    required String? label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF252525),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 19),
              if (label != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendations() {
    return ListenableBuilder(
      listenable: _coordinator,
      builder: (context, _) {
        final recommendations = _coordinator.recommendations;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text(
                'Up next',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_coordinator.isLoadingRecommendations &&
                recommendations.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            else if (recommendations.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No recommendations available',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            else
              ...recommendations.map((video) {
                return InkWell(
                  onTap: () => _openRecommendation(video.url),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: SizedBox(
                            width: 148,
                            height: 84,
                            child: Image.network(
                              video.thumbnailUrl ?? '',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return const ColoredBox(
                                  color: Color(0xFF252525),
                                  child: Center(
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      color: Colors.white60,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                video.title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                video.author ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.more_vert,
                          color: Colors.white60,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Future<void> _openRecommendation(String url) async {
    if (_isSwitchingVideo) return;

    setState(() => _isSwitchingVideo = true);

    OverlayEntry? overlay;

    try {
      overlay = OverlayEntry(
        builder: (_) => const ColoredBox(
          color: Color(0x55000000),
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );

      Overlay.of(context).insert(overlay);

      final info = await VideoExtractorService.instance.extractInfo(url);

      if (!mounted) return;

      await _coordinator.ensureOnlineVideo(info);

      if (!mounted) return;

      _dragProgress.value = 0;

      setState(() {
        _isMini = false;
        _showControls = true;
        _isLoading = false;
        _hasError = false;
      });

      _attachVideoController();
      _startControlsTimer();
    } catch (error, stackTrace) {
      debugPrint('Failed to open recommendation: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load this video')),
        );
      }
    } finally {
      overlay?.remove();

      if (mounted) {
        setState(() => _isSwitchingVideo = false);
      }
    }
  }

  Widget _buildInformation() {
    return ColoredBox(
      color: const Color(0xFF111111),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(top: 18, bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.info.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.info.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _descriptionOpen = !_descriptionOpen;
                        });
                      },
                      child: Text(
                        widget.info.description!,
                        maxLines: _descriptionOpen ? null : 2,
                        overflow: _descriptionOpen
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: CupertinoIcons.music_note,
                          label: widget.info.author ?? 'Channel',
                          onTap: _download,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildActionButton(
                        icon: CupertinoIcons.cloud_download,
                        label: null,
                        onTap: _download,
                      ),
                      const SizedBox(width: 10),
                      _buildActionButton(
                        icon: CupertinoIcons.share,
                        label: null,
                        onTap: _share,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _buildRecommendations(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Page layout
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final fullscreen = _isFullscreen || landscape;

    final normalWidth = screen.width;
    final normalHeight = fullscreen ? screen.height : normalWidth * 9 / 16;
    final maxDrag = _maximumDrag(screen.height, normalHeight);

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isFullscreen) {
          _toggleFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight;
            final travel = _maximumDrag(screenHeight, normalHeight);

            return Stack(
              fit: StackFit.expand,
              children: [
                // Transparent while the video is being minimized.
                ValueListenableBuilder<double>(
                  valueListenable: _dragProgress,
                  builder: (context, drag, _) {
                    final progress = (drag / travel).clamp(0.0, 1.0);

                    final backgroundOpacity = _isMini ? 0.0 : 1.0 - progress;

                    return IgnorePointer(
                      ignoring: progress > 0 || _isMini,
                      child: ColoredBox(
                        color: Colors.black.withValues(
                          alpha: backgroundOpacity,
                        ),
                      ),
                    );
                  },
                ),

                // The information page stays mounted but disappears
                // as soon as the user begins dragging.
                if (!fullscreen)
                  Positioned.fill(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _dragProgress,
                      builder: (context, drag, child) {
                        final hidden = _isMini || drag > 0;

                        return IgnorePointer(
                          ignoring: hidden,
                          child: AnimatedOpacity(
                            opacity: hidden ? 0 : 1,
                            duration: const Duration(milliseconds: 80),
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        children: [
                          SizedBox(
                            height: normalHeight + (_isFullscreen ? 0 : 45),
                          ),
                          Expanded(child: _buildInformation()),
                        ],
                      ),
                    ),
                  ),

                // A single video widget is moved and resized. It is never
                // duplicated, so the same controller continues playing.
                ValueListenableBuilder<double>(
                  valueListenable: _dragProgress,
                  builder: (context, drag, _) {
                    final topOffset = _isFullscreen ? 0.0 : 45.0;
                    final progress = fullscreen || travel <= 0
                        ? 0.0
                        : (drag / travel).clamp(0.0, 1.0);

                    final mini = _isMini;

                    final width = mini
                        ? _miniWidth
                        : lerpDouble(normalWidth, _miniWidth, progress)!;

                    final height = mini
                        ? _miniHeight
                        : lerpDouble(normalHeight, _miniHeight, progress)!;

                    final left = mini
                        ? screen.width - _miniWidth - _miniMargin
                        : lerpDouble(
                            0,
                            screen.width - width - _miniMargin,
                            progress,
                          )!;

                    final top = mini
                        ? screenHeight - _miniHeight - _miniMargin
                        : lerpDouble(
                            topOffset,
                            screenHeight - _miniHeight - _miniMargin - 85,
                            progress,
                          )!;

                    return Positioned(
                      left: fullscreen ? 0 : left,
                      top: fullscreen ? 0 : top,
                      width: fullscreen ? screen.width : width,
                      height: fullscreen ? screen.height : height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: fullscreen ? null : _onDragStart,
                        onVerticalDragUpdate: fullscreen
                            ? null
                            : (details) => _onDragUpdate(details, travel),
                        onVerticalDragEnd: fullscreen
                            ? null
                            : (details) => _onDragEnd(details, travel),
                        onTap: mini ? _expandPlayer : _toggleControls,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            fullscreen ? 0 : 12 * progress,
                          ),
                          child: ColoredBox(
                            color: Colors.black,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildVideoSurface(),

                                if (!mini) _buildControls(),

                                if (mini)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Material(
                                      color: Colors.black54,
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: _closePlayer,
                                        child: const Padding(
                                          padding: EdgeInsets.all(5),
                                          child: Icon(
                                            Icons.close_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                if (mini)
                                  Positioned(
                                    bottom: 5,
                                    left: 8,
                                    right: 8,
                                    child: Text(
                                      widget.info.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black,
                                            blurRadius: 5,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// import 'dart:async';

// import 'package:flutter/cupertino.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:offlinetube/features/library/search_overlay.dart';
// import 'package:share_plus/share_plus.dart';
// import 'package:video_player/video_player.dart';
// import 'package:offlinetube/services/extractor/extracted_video_info.dart';
// import 'package:offlinetube/services/extractor/video_extractor_service.dart';
// import 'package:offlinetube/services/playback/playback_coordinator.dart';
// import 'package:offlinetube/features/downloader/widgets/quality_selection_sheet.dart';

// class StreamVideoPage extends StatefulWidget {
//   final ExtractedVideoInfo info;
//   final ExtractedFormat? format;
//   final VoidCallback? onDownload;

//   const StreamVideoPage({
//     super.key,
//     required this.info,
//     this.format,
//     this.onDownload,
//   });

//   @override
//   State<StreamVideoPage> createState() => _StreamVideoPageState();
// }

// class _StreamVideoPageState extends State<StreamVideoPage>
//     with SingleTickerProviderStateMixin {
//   final PlaybackCoordinator _coordinator = PlaybackCoordinator.instance;

//   VideoPlayerController? _controller;

//   bool _isLoading = true;
//   bool _hasError = false;
//   String? _errorMessage;

//   bool _showControls = true;
//   bool _isFullscreen = false;
//   bool _isMinimizing = false;
//   bool _isSeeking = false;

//   double _dragOffset = 0;
//   double _dragStartX = 0;
//   double _dragStartY = 0;

//   Duration _seekPosition = Duration.zero;

//   Timer? _controlsTimer;

//   late final AnimationController _minimizeAnimationController;
//   late final Animation<double> _minimizeAnimation;

//   @override
//   void initState() {
//     super.initState();

//     _minimizeAnimationController = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 280),
//     );

//     _minimizeAnimation = CurvedAnimation(
//       parent: _minimizeAnimationController,
//       curve: Curves.easeInOutCubic,
//     );

//     _coordinator.addListener(_onCoordinatorChanged);

//     _startPlayback();
//     _startControlsTimer();
//   }

//   @override
//   void dispose() {
//     _controlsTimer?.cancel();

//     _coordinator.removeListener(_onCoordinatorChanged);

//     // Do not dispose the VideoPlayerController or PlaybackCoordinator here.
//     // They are owned by PlaybackCoordinator so playback can continue
//     // after this page is closed or minimized.

//     _minimizeAnimationController.dispose();

//     SystemChrome.setPreferredOrientations([
//       DeviceOrientation.portraitUp,
//       DeviceOrientation.portraitDown,
//     ]);

//     SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

//     super.dispose();
//   }

//   // ---------------------------------------------------------------------------
//   // Playback
//   // ---------------------------------------------------------------------------

//   Future<void> _startPlayback() async {
//     try {
//       setState(() {
//         _isLoading = true;
//         _hasError = false;
//         _errorMessage = null;
//       });

//       // await _coordinator.playOnlineVideo(widget.info, format: widget.format);
//       await _coordinator.ensureOnlineVideo(widget.info, format: widget.format);

//       if (!mounted) return;

//       _attachVideoController();

//       if (_controller == null || !_controller!.value.isInitialized) {
//         setState(() {
//           _isLoading = false;
//           _hasError = true;
//           _errorMessage = 'The video could not be initialized.';
//         });
//         return;
//       }

//       setState(() {
//         _isLoading = false;
//         _hasError = false;
//       });

//       _startControlsTimer();
//     } catch (error) {
//       if (!mounted) return;

//       setState(() {
//         _isLoading = false;
//         _hasError = true;
//         _errorMessage = 'Unable to play this video. Please try again.';
//         print("error aa gya: ${error}");
//       });

//       debugPrint('StreamVideoPage playback error: $error');
//     }
//   }

//   void _attachVideoController() {
//     final nextController = _coordinator.videoController;

//     if (identical(nextController, _controller)) return;

//     _controller?.removeListener(_onVideoChanged);

//     _controller = nextController;

//     _controller?.addListener(_onVideoChanged);
//   }

//   void _onCoordinatorChanged() {
//     if (!mounted) return;

//     _attachVideoController();

//     final controller = _controller;

//     if (controller != null && controller.value.isInitialized) {
//       if (_isLoading || _hasError) {
//         setState(() {
//           _isLoading = false;
//           _hasError = false;
//           _errorMessage = null;
//         });
//       } else {
//         setState(() {});
//       }
//     } else {
//       setState(() {});
//     }
//   }

//   void _onVideoChanged() {
//     if (!mounted) return;

//     if (!_isSeeking) {
//       setState(() {});
//     }
//   }

//   Future<void> _togglePlayPause() async {
//     if (_isMinimizing) return;

//     try {
//       await _coordinator.togglePlayPause();

//       if (!mounted) return;

//       setState(() {});
//       _startControlsTimer();
//     } catch (error) {
//       debugPrint('Toggle playback failed: $error');
//     }
//   }

//   Future<void> _seekTo(Duration position) async {
//     final controller = _controller;

//     if (controller == null || !controller.value.isInitialized) return;

//     final duration = controller.value.duration;

//     final clampedPosition = Duration(
//       milliseconds: position.inMilliseconds
//           .clamp(0, duration.inMilliseconds)
//           .toInt(),
//     );

//     try {
//       // The coordinator synchronizes the video and audio players.
//       await _coordinator.seekTo(clampedPosition);
//     } catch (error) {
//       debugPrint('Seeking failed: $error');
//     }

//     if (!mounted) return;

//     setState(() {
//       _seekPosition = clampedPosition;
//       _isSeeking = false;
//     });

//     _startControlsTimer();
//   }

//   Future<void> _seekRelative(int seconds) async {
//     final controller = _controller;

//     if (controller == null || !controller.value.isInitialized) return;

//     final currentPosition = controller.value.position;

//     await _seekTo(Duration(seconds: currentPosition.inSeconds + seconds));
//   }

//   // ---------------------------------------------------------------------------
//   // Controls visibility
//   // ---------------------------------------------------------------------------

//   void _startControlsTimer() {
//     _controlsTimer?.cancel();

//     if (_isFullscreen || _isMinimizing) return;

//     _controlsTimer = Timer(const Duration(seconds: 4), () {
//       if (!mounted || _isMinimizing) return;

//       setState(() {
//         _showControls = false;
//       });
//     });
//   }

//   void _toggleControls() {
//     if (_isMinimizing) return;

//     setState(() {
//       _showControls = !_showControls;
//     });

//     if (_showControls) {
//       _startControlsTimer();
//     } else {
//       _controlsTimer?.cancel();
//     }
//   }

//   // ---------------------------------------------------------------------------
//   // Drag-down gesture and minimize animation
//   // ---------------------------------------------------------------------------

//   void _onVerticalDragStart(DragStartDetails details) {
//     if (_isFullscreen || _isMinimizing) return;

//     _dragStartX = details.globalPosition.dx;
//     _dragStartY = details.globalPosition.dy;
//   }

//   void _onVerticalDragUpdate(DragUpdateDetails details) {
//     if (_isFullscreen || _isMinimizing) return;

//     // Only allow downward dragging to minimize the player.
//     if (details.delta.dy > 0 || _dragOffset > 0) {
//       setState(() {
//         _dragOffset = (_dragOffset + details.delta.dy).clamp(0, 500);
//       });
//     }
//   }

//   Future<void> _onVerticalDragEnd(DragEndDetails details) async {
//     if (_isFullscreen || _isMinimizing) return;

//     final velocity = details.primaryVelocity ?? 0;

//     if (_dragOffset > 120 || velocity > 900) {
//       await _minimize();
//     } else {
//       setState(() {
//         _dragOffset = 0;
//       });
//     }
//   }

//   Future<void> _minimize() async {
//     if (_isMinimizing) return;

//     _controlsTimer?.cancel();

//     setState(() {
//       _isMinimizing = true;
//       _showControls = false;
//     });

//     try {
//       // Animate the page down before closing it.
//       await _minimizeAnimationController.forward();

//       if (!mounted) return;

//       // Playback continues because the coordinator and audio handler
//       // are not disposed when this page closes.
//       Navigator.of(context).pop();
//     } catch (error) {
//       debugPrint('Minimize animation failed: $error');

//       if (mounted) {
//         Navigator.of(context).pop();
//       }
//     }
//   }

//   // ---------------------------------------------------------------------------
//   // Fullscreen
//   // ---------------------------------------------------------------------------

//   Future<void> _toggleFullscreen() async {
//     if (_isMinimizing) return;

//     if (_isFullscreen) {
//       await SystemChrome.setPreferredOrientations([
//         DeviceOrientation.portraitUp,
//         DeviceOrientation.portraitDown,
//       ]);

//       await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
//     } else {
//       await SystemChrome.setPreferredOrientations([
//         DeviceOrientation.landscapeLeft,
//         DeviceOrientation.landscapeRight,
//       ]);

//       await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
//     }

//     if (!mounted) return;

//     setState(() {
//       _isFullscreen = !_isFullscreen;
//       _showControls = true;
//     });

//     _startControlsTimer();
//   }

//   // ---------------------------------------------------------------------------
//   // Download and share
//   // ---------------------------------------------------------------------------

//   Future<void> _download() async {
//     if (widget.onDownload != null) {
//       widget.onDownload!();
//       return;
//     }

//     try {
//       final info = await VideoExtractorService.instance.extractInfo(
//         'https://www.youtube.com/watch?v=${widget.info.id}',
//       );

//       if (!mounted) return;

//       await showModalBottomSheet<void>(
//         context: context,
//         isScrollControlled: true,
//         backgroundColor: Colors.transparent,
//         builder: (_) => QualitySelectionSheet(info: info),
//       );
//     } catch (error) {
//       debugPrint('Download setup failed: $error');

//       if (!mounted) return;

//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Unable to prepare this video for download.'),
//         ),
//       );
//     }
//   }

//   Future<void> _share() async {
//     try {
//       await Share.share(
//         '${widget.info.title}\n'
//         'https://www.youtube.com/watch?v=${widget.info.id}',
//       );
//     } catch (error) {
//       debugPrint('Share failed: $error');
//     }
//   }

//   // ---------------------------------------------------------------------------
//   // Helpers
//   // ---------------------------------------------------------------------------

//   String _formatDuration(Duration duration) {
//     String twoDigits(int number) => number.toString().padLeft(2, '0');

//     final hours = duration.inHours;
//     final minutes = duration.inMinutes.remainder(60);
//     final seconds = duration.inSeconds.remainder(60);

//     if (hours > 0) {
//       return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
//     }

//     return '${duration.inMinutes}:${twoDigits(seconds)}';
//   }

//   Duration get _currentPosition {
//     final controller = _controller;

//     if (controller == null || !controller.value.isInitialized) {
//       return Duration.zero;
//     }

//     return controller.value.position;
//   }

//   Duration get _currentDuration {
//     final controller = _controller;

//     if (controller == null || !controller.value.isInitialized) {
//       return Duration.zero;
//     }

//     return controller.value.duration;
//   }

//   // ---------------------------------------------------------------------------
//   // Video controls
//   // ---------------------------------------------------------------------------

//   Widget _buildVideoControls() {
//     final controller = _controller;

//     if (controller == null || !controller.value.isInitialized) {
//       return const SizedBox.shrink();
//     }

//     final position = _isSeeking ? _seekPosition : _currentPosition;
//     final duration = _currentDuration;

//     final maxMilliseconds = duration.inMilliseconds > 0
//         ? duration.inMilliseconds.toDouble()
//         : 1.0;

//     final sliderValue = position.inMilliseconds
//         .clamp(0, maxMilliseconds.toInt())
//         .toDouble();

//     final isPlaying = _coordinator.isPlaying;

//     return AnimatedOpacity(
//       opacity: _showControls ? 1 : 0,
//       duration: const Duration(milliseconds: 200),
//       child: IgnorePointer(
//         ignoring: !_showControls,
//         child: Container(
//           color: Colors.black.withValues(alpha: 0.25),
//           child: Column(
//             children: [
//               // Top bar
//               Row(
//                 children: [
//                   IconButton(
//                     onPressed: _minimize,
//                     icon: const Icon(
//                       Icons.keyboard_arrow_down_rounded,
//                       color: Colors.white,
//                       size: 32,
//                     ),
//                   ),
//                   Expanded(
//                     child: Text(
//                       widget.info.title,
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                       style: const TextStyle(
//                         color: Colors.white,
//                         fontSize: 15,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),
//                   ),
//                   IconButton(
//                     onPressed: _share,
//                     icon: const Icon(Icons.share_outlined, color: Colors.white),
//                   ),
//                 ],
//               ),

//               const Spacer(),

//               // Center playback controls
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   IconButton(
//                     onPressed: () => _seekRelative(-10),
//                     icon: const Icon(
//                       Icons.replay_10_rounded,
//                       color: Colors.white,
//                       size: 34,
//                     ),
//                   ),
//                   const SizedBox(width: 18),
//                   GestureDetector(
//                     onTap: _togglePlayPause,
//                     child: Container(
//                       width: 62,
//                       height: 62,
//                       decoration: BoxDecoration(
//                         color: Colors.white.withValues(alpha: 0.18),
//                         shape: BoxShape.circle,
//                       ),
//                       child: Icon(
//                         isPlaying
//                             ? Icons.pause_rounded
//                             : Icons.play_arrow_rounded,
//                         color: Colors.white,
//                         size: 42,
//                       ),
//                     ),
//                   ),
//                   const SizedBox(width: 18),
//                   IconButton(
//                     onPressed: () => _seekRelative(10),
//                     icon: const Icon(
//                       Icons.forward_10_rounded,
//                       color: Colors.white,
//                       size: 34,
//                     ),
//                   ),
//                 ],
//               ),

//               const Spacer(),

//               // Bottom progress controls
//               Padding(
//                 padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     SliderTheme(
//                       data: SliderTheme.of(context).copyWith(
//                         trackHeight: 3,
//                         thumbShape: const RoundSliderThumbShape(
//                           enabledThumbRadius: 5,
//                         ),
//                         overlayShape: const RoundSliderOverlayShape(
//                           overlayRadius: 12,
//                         ),
//                       ),
//                       child: Slider(
//                         min: 0,
//                         max: maxMilliseconds,
//                         value: sliderValue.clamp(0, maxMilliseconds),
//                         activeColor: Colors.redAccent,
//                         inactiveColor: Colors.white38,
//                         onChangeStart: (value) {
//                           _controlsTimer?.cancel();

//                           setState(() {
//                             _isSeeking = true;
//                             _seekPosition = Duration(
//                               milliseconds: value.round(),
//                             );
//                           });
//                         },
//                         onChanged: (value) {
//                           setState(() {
//                             _seekPosition = Duration(
//                               milliseconds: value.round(),
//                             );
//                           });
//                         },
//                         onChangeEnd: (value) {
//                           _seekTo(Duration(milliseconds: value.round()));
//                         },
//                       ),
//                     ),
//                     Row(
//                       children: [
//                         Text(
//                           _formatDuration(position),
//                           style: const TextStyle(
//                             color: Colors.white,
//                             fontSize: 12,
//                           ),
//                         ),
//                         const Spacer(),
//                         Text(
//                           _formatDuration(duration),
//                           style: const TextStyle(
//                             color: Colors.white,
//                             fontSize: 12,
//                           ),
//                         ),
//                         IconButton(
//                           visualDensity: VisualDensity.compact,
//                           onPressed: _toggleFullscreen,
//                           icon: Icon(
//                             _isFullscreen
//                                 ? Icons.fullscreen_exit_rounded
//                                 : Icons.fullscreen_rounded,
//                             color: Colors.white,
//                             size: 25,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildVideoPlayer() {
//     final controller = _controller;

//     if (_isLoading) {
//       return const Center(
//         child: CircularProgressIndicator(color: Colors.white),
//       );
//     }

//     if (_hasError || controller == null || !controller.value.isInitialized) {
//       return Center(
//         child: Padding(
//           padding: const EdgeInsets.all(24),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               const Icon(
//                 Icons.error_outline_rounded,
//                 color: Colors.white70,
//                 size: 42,
//               ),
//               const SizedBox(height: 12),
//               Text(
//                 _errorMessage ?? 'Unable to load this video.',
//                 textAlign: TextAlign.center,
//                 style: const TextStyle(color: Colors.white70),
//               ),
//               const SizedBox(height: 16),
//               ElevatedButton.icon(
//                 onPressed: _startPlayback,
//                 icon: const Icon(Icons.refresh_rounded),
//                 label: const Text('Try again'),
//               ),
//             ],
//           ),
//         ),
//       );
//     }

//     return GestureDetector(
//       behavior: HitTestBehavior.opaque,
//       onTap: _toggleControls,
//       onDoubleTapDown: (details) {
//         _dragStartX = details.localPosition.dx;
//       },
//       onDoubleTap: () {
//         final screenWidth = MediaQuery.sizeOf(context).width;

//         if (_dragStartX < screenWidth / 2) {
//           _seekRelative(-10);
//         } else {
//           _seekRelative(10);
//         }
//       },
//       child: Center(
//         child: AspectRatio(
//           aspectRatio: controller.value.aspectRatio > 0
//               ? controller.value.aspectRatio
//               : 16 / 9,
//           child: VideoPlayer(controller),
//         ),
//       ),
//     );
//   }

//   // ---------------------------------------------------------------------------
//   // Main page
//   // ---------------------------------------------------------------------------
//   bool _descriptionOpen = false;
//   @override
//   Widget build(BuildContext context) {
//     final screenSize = MediaQuery.sizeOf(context);
//     final isLandscape =
//         MediaQuery.orientationOf(context) == Orientation.landscape;

//     final shouldUseFullscreen = _isFullscreen || isLandscape;

//     Widget _buildRecommendations() {
//       return ListenableBuilder(
//         listenable: _coordinator,
//         builder: (context, child) {
//           final recommendations = _coordinator.recommendations;

//           return Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               const Padding(
//                 padding: EdgeInsets.only(top: 30, left: 10),
//                 child: Text(
//                   'Up next',
//                   style: TextStyle(
//                     color: Colors.white,
//                     fontSize: 12,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//               ),

//               if (_coordinator.isLoadingRecommendations &&
//                   recommendations.isEmpty)
//                 const Center(
//                   child: Padding(
//                     padding: EdgeInsets.all(24),
//                     child: CircularProgressIndicator(color: Colors.white),
//                   ),
//                 )
//               else if (recommendations.isEmpty)
//                 const Padding(
//                   padding: EdgeInsets.all(16),
//                   child: Text(
//                     'No recommendations available',
//                     style: TextStyle(color: Colors.white70),
//                   ),
//                 )
//               else
//                 ...recommendations.map((video) {
//                   return Material(
//                     child: InkWell(
//                       onTap: () async {
//                         final overlay = OverlayEntry(
//                           builder: (context) => VideoLoadingOverlay(
//                             thumbnail: video.thumbnailUrl,
//                             title: video.title ?? 'Loading video',
//                           ),
//                         );

//                         Overlay.of(context).insert(overlay);
//                         bool overlayRemoved = false;

//                         void removeOverlay() {
//                           if (!overlayRemoved) {
//                             overlayRemoved = true;
//                             overlay.remove();
//                           }
//                         }

//                         try {
//                           final info = await VideoExtractorService.instance
//                               .extractInfo(video.url);

//                           if (!context.mounted) {
//                             removeOverlay();
//                             return;
//                           }

//                           await _coordinator.ensureOnlineVideo(info);
//                         } catch (e, stackTrace) {
//                           debugPrint('Failed to open stream page: $e');
//                           debugPrintStack(stackTrace: stackTrace);

//                           if (context.mounted) {
//                             ScaffoldMessenger.of(context).showSnackBar(
//                               const SnackBar(
//                                 content: Text('Could not load this video'),
//                               ),
//                             );
//                           }
//                         } finally {
//                           removeOverlay();
//                         }
//                       },
//                       child: Padding(
//                         padding: const EdgeInsets.symmetric(vertical: 10.0),
//                         child: Row(
//                           children: [
//                             Image.network(
//                               width: screenSize.width / 2,
//                               height: 130,
//                               video.thumbnailUrl ?? "",
//                               fit: BoxFit.cover,
//                               errorBuilder: (_, __, ___) => Container(
//                                 width: 120,
//                                 height: 68,
//                                 color: Colors.white12,
//                                 child: const Icon(
//                                   Icons.music_note,
//                                   color: Colors.white70,
//                                 ),
//                               ),
//                             ),
//                             Container(
//                               padding: EdgeInsets.symmetric(horizontal: 10),
//                               width: screenSize.width / 2,
//                               height: 130,
//                               child: Column(
//                                 mainAxisAlignment: MainAxisAlignment.start,
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   Text(
//                                     video.title,
//                                     maxLines: 2,
//                                     overflow: TextOverflow.ellipsis,
//                                     style: const TextStyle(
//                                       color: Colors.white,
//                                       fontSize: 16,
//                                       fontWeight: FontWeight.w500,
//                                     ),
//                                   ),
//                                   SizedBox(height: 5),
//                                   Text(
//                                     video.author ?? "",
//                                     maxLines: 2,
//                                     overflow: TextOverflow.ellipsis,
//                                     style: const TextStyle(
//                                       color: Colors.white60,
//                                       fontSize: 12,
//                                     ),
//                                   ),
//                                   Expanded(child: SizedBox()),
//                                   Row(
//                                     children: [
//                                       IconButton(
//                                         onPressed: () {},
//                                         icon: Icon(
//                                           CupertinoIcons
//                                               .line_horizontal_3_decrease,
//                                         ),
//                                         color: Colors.white60,
//                                         iconSize: 20,
//                                       ),
//                                       IconButton(
//                                         onPressed: () {},
//                                         icon: Icon(
//                                           CupertinoIcons.cloud_download,
//                                         ),
//                                         color: Colors.white60,
//                                         iconSize: 20,
//                                       ),
//                                       IconButton(
//                                         onPressed: () {},
//                                         icon: Icon(CupertinoIcons.share),
//                                         color: Colors.white60,
//                                         iconSize: 20,
//                                       ),
//                                     ],
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ),
//                   );
//                 }),
//             ],
//           );
//         },
//       );
//     }

//     return PopScope(
//       canPop: true,
//       onPopInvokedWithResult: (didPop, result) {
//         if (_isFullscreen && !didPop) {
//           _toggleFullscreen();
//         }
//       },
//       child: Scaffold(
//         backgroundColor: Colors.black,
//         body: SafeArea(
//           top: !shouldUseFullscreen,
//           bottom: !shouldUseFullscreen,
//           child: AnimatedBuilder(
//             animation: _minimizeAnimation,
//             builder: (context, child) {
//               final animationValue = _minimizeAnimation.value;

//               final translateY = _isMinimizing
//                   ? animationValue * screenSize.height
//                   : _dragOffset;

//               final scale = _isMinimizing
//                   ? 1 - (animationValue * 0.08)
//                   : 1 - (_dragOffset / 5000).clamp(0.0, 0.08);

//               final opacity = _isMinimizing
//                   ? 1 - animationValue
//                   : 1 - (_dragOffset / 900).clamp(0.0, 0.35);

//               return Transform.translate(
//                 offset: Offset(0, translateY),
//                 child: Transform.scale(
//                   scale: scale,
//                   alignment: Alignment.topCenter,
//                   child: Opacity(
//                     opacity: opacity.clamp(0.0, 1.0),
//                     child: child,
//                   ),
//                 ),
//               );
//             },
//             child: GestureDetector(
//               onVerticalDragStart: _onVerticalDragStart,
//               onVerticalDragUpdate: _onVerticalDragUpdate,
//               onVerticalDragEnd: _onVerticalDragEnd,
//               child: Column(
//                 children: [
//                   // Video area
//                   Expanded(
//                     flex: shouldUseFullscreen ? 1 : 0,
//                     child: shouldUseFullscreen
//                         ? _buildFullscreenVideo()
//                         : _buildPortraitVideo(),
//                   ),

//                   if (!shouldUseFullscreen) ...[
//                     // Video information and actions
//                     Expanded(
//                       child: Container(
//                         width: double.infinity,
//                         color: const Color(0xFF111111),
//                         child: SingleChildScrollView(
//                           physics: const BouncingScrollPhysics(),
//                           padding: const EdgeInsets.only(top: 18),
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Padding(
//                                 padding: const EdgeInsets.symmetric(
//                                   horizontal: 10,
//                                 ),
//                                 child: Column(
//                                   children: [
//                                     Text(
//                                       widget.info.title,
//                                       style: const TextStyle(
//                                         color: Colors.white,
//                                         fontSize: 19,
//                                         height: 1.35,
//                                         fontWeight: FontWeight.w700,
//                                       ),
//                                     ),
//                                     const SizedBox(height: 10),

//                                     if (widget.info.description != null &&
//                                         widget
//                                             .info
//                                             .description!
//                                             .isNotEmpty) ...[
//                                       GestureDetector(
//                                         onTap: () {
//                                           setState(() {
//                                             _descriptionOpen =
//                                                 !_descriptionOpen;
//                                           });
//                                         },
//                                         child: Text(
//                                           widget.info.description!,
//                                           maxLines: _descriptionOpen ? null : 2,
//                                           overflow: _descriptionOpen
//                                               ? TextOverflow.visible
//                                               : TextOverflow.ellipsis,
//                                           style: const TextStyle(
//                                             color: Colors.white70,
//                                             fontSize: 14,
//                                             height: 1.5,
//                                           ),
//                                         ),
//                                       ),
//                                     ],
//                                     const SizedBox(height: 20),
//                                     Row(
//                                       children: [
//                                         _buildActionButton(
//                                           icon: CupertinoIcons.music_note,
//                                           label: widget.info.author ?? "A",
//                                           onTap: _download,
//                                         ),
//                                         Expanded(child: SizedBox()),
//                                         _buildActionButton(
//                                           icon: CupertinoIcons.cloud_download,
//                                           label: null,
//                                           onTap: _download,
//                                         ),
//                                         const SizedBox(width: 12),
//                                         _buildActionButton(
//                                           icon: CupertinoIcons.share,
//                                           label: null,
//                                           onTap: _share,
//                                         ),
//                                       ],
//                                     ),
//                                   ],
//                                 ),
//                               ),

//                               _buildRecommendations(),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildPortraitVideo() {
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         return SizedBox(
//           width: double.infinity,
//           child: AspectRatio(
//             aspectRatio: 16 / 9,
//             child: Stack(
//               fit: StackFit.expand,
//               children: [
//                 Container(color: Colors.black),
//                 _buildVideoPlayer(),
//                 _buildVideoControls(),
//                 if (_dragOffset > 0 && !_isMinimizing)
//                   Positioned(
//                     top: 10,
//                     right: 12,
//                     child: Opacity(
//                       opacity: (_dragOffset / 100).clamp(0.0, 1.0),
//                       child: const Icon(
//                         Icons.keyboard_arrow_down_rounded,
//                         color: Colors.white70,
//                         size: 28,
//                       ),
//                     ),
//                   ),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildFullscreenVideo() {
//     return SizedBox.expand(
//       child: Stack(
//         fit: StackFit.expand,
//         children: [
//           Container(color: Colors.black),
//           _buildVideoPlayer(),
//           _buildVideoControls(),
//         ],
//       ),
//     );
//   }

//   Widget _buildActionButton({
//     required IconData icon,
//     required String? label,
//     required VoidCallback onTap,
//   }) {
//     return Material(
//       color: const Color(0xFF252525),
//       borderRadius: BorderRadius.circular(14),
//       child: InkWell(
//         onTap: onTap,
//         borderRadius: BorderRadius.circular(14),
//         child: Padding(
//           padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Icon(icon, color: Colors.white, size: 20),
//               if (label != null) ...[
//                 const SizedBox(width: 8),
//                 Text(
//                   label,
//                   style: const TextStyle(
//                     color: Colors.white,
//                     fontWeight: FontWeight.w600,
//                   ),
//                 ),
//               ],
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
