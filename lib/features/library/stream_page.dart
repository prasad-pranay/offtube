import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:offlinetube/features/downloader/widgets/quality_selection_sheet.dart';
import 'package:offlinetube/services/extractor/extracted_video_info.dart';
import 'package:offlinetube/services/extractor/video_extractor_service.dart';
import 'package:offlinetube/services/playback/playback_coordinator.dart';

class StreamVideoPage extends StatefulWidget {
  final ValueChanged<bool>? onFullscreenChanged;
  final ExtractedVideoInfo info;
  final ExtractedFormat? format;
  final VoidCallback? onDownload;
  final void Function(ExtractedVideoInfo? info) openStreamPage;

  const StreamVideoPage({
    super.key,
    required this.info,
    this.format,
    this.onDownload,
    required this.openStreamPage,
    this.onFullscreenChanged,
  });

  @override
  State<StreamVideoPage> createState() => StreamVideoPageState();
}

class StreamVideoPageState extends State<StreamVideoPage>
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

    final controller = _controller;
    if (controller != null && !controller.value.isPlaying) return;

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

  Future<void> animateDragProgress(double target) async {
    final start = _dragProgress.value;
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsedMilliseconds < 300) {
      final t = (stopwatch.elapsedMilliseconds / 300).clamp(0.0, 1.0);
      final curvedT = Curves.easeInOut.transform(t);

      _dragProgress.value = start + (target - start) * curvedT;

      await Future.delayed(const Duration(milliseconds: 16));
    }
    if (!mounted) return;

    _dragProgress.value = target;
  }

  void enterMiniModeFromParent() {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final screen = MediaQuery.sizeOf(context);
    final controller = _controller;

    final size = controller?.value.isInitialized == true
        ? controller!.value.size
        : Size.zero;

    final ratio = size.width > 0 && size.height > 0
        ? size.width / size.height
        : 16 / 9;

    final videoHeight = screen.width / ratio;
    _enterMiniMode(_maximumDrag(screenHeight, videoHeight));
  }

  void _enterMiniMode(double maxDrag) {
    _controlsTimer?.cancel();
    _snapController.stop();
    // _dragProgress.value = maxDrag;
    animateDragProgress(maxDrag);
    setState(() {
      // Navigator.of(context).pop();
      _showControls = false;
    });
    Future.delayed(Duration(milliseconds: 300), () {
      widget.openStreamPage(null);
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
    print("fullscreen called");

    final entering = !_isFullscreen;
    widget.onFullscreenChanged?.call(entering);

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

    final videoSize = controller.value.size;

    if (videoSize.width <= 0 || videoSize.height <= 0) {
      return const ColoredBox(color: Colors.black);
    }

    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: videoSize.width,
            height: videoSize.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }

  // Widget _buildVideoSurface() {
  //   final controller = _controller;

  //   if (_isLoading) {
  //     return const ColoredBox(
  //       color: Colors.black,
  //       child: Center(child: CircularProgressIndicator(color: Colors.white)),
  //     );
  //   }

  //   if (_hasError || controller == null || !controller.value.isInitialized) {
  //     return ColoredBox(
  //       color: Colors.black,
  //       child: Center(
  //         child: Padding(
  //           padding: const EdgeInsets.all(20),
  //           child: Column(
  //             mainAxisSize: MainAxisSize.min,
  //             children: [
  //               const Icon(
  //                 Icons.error_outline_rounded,
  //                 color: Colors.white70,
  //                 size: 38,
  //               ),
  //               const SizedBox(height: 10),
  //               Text(
  //                 _errorMessage ?? 'Unable to load this video.',
  //                 textAlign: TextAlign.center,
  //                 style: const TextStyle(color: Colors.white70),
  //               ),
  //               const SizedBox(height: 12),
  //               ElevatedButton.icon(
  //                 onPressed: _startPlayback,
  //                 icon: const Icon(Icons.refresh_rounded),
  //                 label: const Text('Try again'),
  //               ),
  //             ],
  //           ),
  //         ),
  //       ),
  //     );
  //   }

  //   return RepaintBoundary(child: VideoPlayer(controller));
  // }

  Widget _buildControls() {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final screenHeight = MediaQuery.sizeOf(context).height;
        final screen = MediaQuery.sizeOf(context);
        final controller = _controller;

        final size = controller?.value.isInitialized == true
            ? controller!.value.size
            : Size.zero;

        final ratio = size.width > 0 && size.height > 0
            ? size.width / size.height
            : 16 / 9;

        final videoHeight = screen.width / ratio;
        _enterMiniMode(_maximumDrag(screenHeight, videoHeight));
      },
      child: ValueListenableBuilder<VideoPlayerValue>(
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
                            if (_isFullscreen) {
                              _toggleFullscreen();
                              return;
                            }
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
                            CupertinoIcons.chevron_compact_down,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                        Expanded(
                          child: Opacity(
                            opacity: _isFullscreen ? 1 : 0,
                            child: Text(
                              widget.info.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: _isFullscreen ? 18 : 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _share,
                          icon: const Icon(
                            CupertinoIcons.arrowshape_turn_up_left,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        IconButton(
                          onPressed: _share,
                          icon: const Icon(
                            Icons.settings_outlined,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(50),
                            color: Colors.black38,
                          ),
                          child: IconButton(
                            onPressed: () => _seekRelative(-10),
                            icon: const Icon(
                              CupertinoIcons.backward_end,
                              color: Colors.white,
                              size: 25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: _togglePlayPause,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              value.isPlaying
                                  ? CupertinoIcons.pause
                                  : CupertinoIcons.play_fill,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(50),
                            color: Colors.black38,
                          ),
                          child: IconButton(
                            onPressed: () => _seekRelative(10),
                            icon: const Icon(
                              CupertinoIcons.forward_end,
                              color: Colors.white,
                              size: 25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              margin: EdgeInsets.only(left: 5),
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    _formatDuration(position),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: _isFullscreen ? 14 : 11,
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    child: Text(
                                      "/",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: _isFullscreen ? 14 : 11,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(duration),
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: _isFullscreen ? 14 : 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Container(
                              margin: EdgeInsets.only(bottom: 3, right: 5),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(50),
                                color: Colors.black54,
                              ),
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: _toggleFullscreen,
                                icon: Icon(
                                  _isFullscreen
                                      ? CupertinoIcons
                                            .arrow_down_right_arrow_up_left
                                      : CupertinoIcons
                                            .arrow_up_left_arrow_down_right,
                                  color: Colors.white,
                                  size: _isFullscreen ? 30 : 20,
                                ),
                              ),
                            ),
                          ],
                        ),

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
                            padding: _isFullscreen
                                ? EdgeInsets.only(
                                    bottom: 10,
                                    left: 15,
                                    right: 15,
                                  )
                                : EdgeInsets.zero,
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
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
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
            Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text(
                'Recommended',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w300,
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
                              Wrap(
                                children: [
                                  Text(
                                    video.author ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    child: Text("•"),
                                  ),
                                  Text(
                                    video.uploadDate ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
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
                      _buildActionButton(
                        icon: CupertinoIcons.music_note,
                        label: null,
                        onTap: () {},
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.info.author ?? 'Channel',
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          fontSize: 16,
                        ),
                      ),
                      Spacer(),
                      const SizedBox(width: 10),
                      _buildActionButton(
                        icon: CupertinoIcons.cloud_download,
                        label: null,
                        onTap: _download,
                      ),
                      const SizedBox(width: 10),
                      _buildActionButton(
                        icon: CupertinoIcons.arrowshape_turn_up_left,
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
    final controller = _controller;
    final videoSize = controller?.value.isInitialized == true
        ? controller!.value.size
        : Size.zero;

    final aspectRatio = videoSize.width > 0 && videoSize.height > 0
        ? videoSize.width / videoSize.height
        : 16 / 9;

    final normalHeight = fullscreen ? screen.height : normalWidth / aspectRatio;
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
                            screenHeight - _miniHeight - _miniMargin - 5,
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
