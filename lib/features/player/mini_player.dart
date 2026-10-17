import 'package:flutter/material.dart';
import 'package:offlinetube/services/extractor/extracted_video_info.dart';
import 'package:video_player/video_player.dart';

import 'package:offlinetube/services/playback/playback_coordinator.dart';
// import '../library/stream_page.dart';

class MiniPlayer extends StatefulWidget {
  final void Function(ExtractedVideoInfo info) openStreamPage;
  const MiniPlayer({super.key, required this.openStreamPage});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  final PlaybackCoordinator _coordinator = PlaybackCoordinator.instance;

  bool firstTouch = false;
  bool _isOpening = false;
  bool _isDragging = false;

  // Remember horizontal and vertical positions independently.
  bool _leftSide = false;
  bool _topSide = false;

  double? _left;
  double? _top;

  double _startLeft = 0;
  double _startTop = 0;
  double _deltaX = 0;
  double _deltaY = 0;

  // static const double _width = 210;
  static const double _normalHeight = 120;
  static const double _expandedHeight = 150;
  static const double _sideGap = 12;
  static const double _verticalGap = 100;

  double get _width => firstTouch ? 250 : 210;

  double get _height => firstTouch ? _expandedHeight : _normalHeight;

  double _rightPosition(double screenWidth) => screenWidth - _width - _sideGap;

  double _bottomPosition(double screenHeight) =>
      screenHeight - _height - _verticalGap;

  double _currentLeft(double screenWidth) =>
      _left ?? (_leftSide ? _sideGap : _rightPosition(screenWidth));

  double _currentTop(double screenHeight) =>
      _top ?? (_topSide ? _verticalGap : _bottomPosition(screenHeight));

  Future<void> _openPlayer(BuildContext context) async {
    if (_isOpening) return;

    final info = _coordinator.currentOnlineVideo;
    if (info == null) return;

    setState(() {
      _isOpening = true;
      firstTouch = false;
      _isDragging = false;
      _left = null;
      _top = null;
    });

    _coordinator.restoreMiniPlayer();

    try {
      widget.openStreamPage(info);
      // await Navigator.of(context).push(
      //   PageRouteBuilder(
      //     opaque: false,
      //     barrierColor: Colors.transparent,
      //     maintainState: true,
      //     transitionDuration: const Duration(milliseconds: 280),
      //     reverseTransitionDuration: const Duration(milliseconds: 220),
      //     pageBuilder: (context, animation, secondaryAnimation) {
      //       return StreamVideoPage(info: info);
      //     },
      //     transitionsBuilder: (context, animation, secondaryAnimation, child) {
      //       final curved = CurvedAnimation(
      //         parent: animation,
      //         curve: Curves.easeOutCubic,
      //         reverseCurve: Curves.easeInCubic,
      //       );

      //       return FadeTransition(opacity: curved, child: child);
      //     },
      //   ),
      // );
    } finally {
      if (mounted) {
        setState(() => _isOpening = false);
      }
    }
  }

  Future<void> _togglePlayback() async {
    try {
      await _coordinator.togglePlayPause();
    } catch (error) {
      debugPrint('Mini-player playback toggle failed: $error');
    }
  }

  void _closeMiniPlayer() {
    _coordinator.close();

    if (!mounted) return;

    setState(() {
      firstTouch = false;
      _isDragging = false;
      _left = null;
      _top = null;
    });
  }

  void _onDragStart(DragStartDetails details, Size size) {
    setState(() {
      _isDragging = true;

      _left = _currentLeft(size.width);
      _top = _currentTop(size.height);

      _startLeft = _left!;
      _startTop = _top!;

      _deltaX = 0;
      _deltaY = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details, Size size) {
    final maxLeft = size.width - _width - _sideGap;
    final maxTop = size.height - _height - _verticalGap;

    // Update position immediately; no easing or delayed animation
    // while the user's finger is moving.
    _left = ((_left ?? _startLeft) + details.delta.dx)
        .clamp(_sideGap, maxLeft)
        .toDouble();

    _top = ((_top ?? _startTop) + details.delta.dy)
        .clamp(_verticalGap, maxTop)
        .toDouble();

    _deltaX += details.delta.dx;
    _deltaY += details.delta.dy;

    setState(() {});
  }

  void _onDragEnd(DragEndDetails details, Size size) {
    final velocity = details.velocity.pixelsPerSecond;

    const threshold = 20.0;
    const velocityThreshold = 180.0;

    final horizontalMoved = _deltaX.abs() > threshold;
    final verticalMoved = _deltaY.abs() > threshold;

    final horizontalDirection = horizontalMoved ? _deltaX : velocity.dx;

    final verticalDirection = verticalMoved ? _deltaY : velocity.dy;

    final horizontalIntent =
        horizontalMoved || velocity.dx.abs() > velocityThreshold;

    final verticalIntent =
        verticalMoved || velocity.dy.abs() > velocityThreshold;

    setState(() {
      firstTouch = false;
      // Only change an axis when that swipe actually affects it.
      // This preserves the other axis when moving between edges.
      if (horizontalIntent) {
        _leftSide = horizontalDirection < 0;
      }

      if (verticalIntent) {
        _topSide = verticalDirection < 0;
      }
      // print(
      //   "yes: $_leftSide old:$_left | new:${_leftSide ? _sideGap : _rightPosition(size.width)}",
      // );
      // if (_top != null && _top! > 400 && !_topSide) {
      //   _closeMiniPlayer();
      // }

      _left = _leftSide ? _sideGap : _rightPosition(size.width);
      _top = _topSide ? _verticalGap : _bottomPosition(size.height);

      _isDragging = false;
    });
  }

  void _handleTap(BuildContext context) {
    if (_isOpening || _isDragging) return;

    if (firstTouch) {
      _openPlayer(context);
    } else {
      setState(() => firstTouch = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    return ListenableBuilder(
      listenable: _coordinator,
      builder: (context, child) {
        final info = _coordinator.currentOnlineVideo;
        final controller = _coordinator.videoController;

        if (!_coordinator.isMiniPlayerVisible ||
            info == null ||
            controller == null ||
            !controller.value.isInitialized) {
          return const SizedBox.shrink();
        }

        final aspectRatio = controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : 16 / 9;

        final left = _currentLeft(screenSize.width);
        final top = _currentTop(screenSize.height);

        return AnimatedPositioned(
          duration: _isDragging
              ? Duration.zero
              : const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          left: left,
          top: top,
          child: Material(
            elevation: _isDragging ? 14 : 8,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            color: const Color(0xFF171717),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) => _onDragStart(details, screenSize),
              onPanUpdate: (details) => _onDragUpdate(details, screenSize),
              onPanEnd: (details) => _onDragEnd(details, screenSize),
              onTap: () => _handleTap(context),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: _width,
                height: _height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The coordinator owns the controller.
                    Center(
                      child: AspectRatio(
                        aspectRatio: aspectRatio,
                        child: VideoPlayer(controller),
                      ),
                    ),

                    // Title gradient.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 6, 34, 12),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                        child: Text(
                          info.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    if (firstTouch) ...[
                      Center(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: IconButton(
                            onPressed: _togglePlayback,
                            icon: ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: controller,
                              builder: (context, value, child) {
                                return Icon(
                                  _coordinator.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 30,
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: IconButton(
                            tooltip: 'Close mini-player',
                            onPressed: _closeMiniPlayer,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        right: 8,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_full_rounded,
                                color: Colors.white,
                                size: 12,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Expand',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:video_player/video_player.dart';

// import 'package:offlinetube/services/playback/playback_coordinator.dart';
// import '../library/stream_page.dart';

// class MiniPlayer extends StatefulWidget {
//   const MiniPlayer({super.key});

//   @override
//   State<MiniPlayer> createState() => _MiniPlayerState();
// }

// class _MiniPlayerState extends State<MiniPlayer> {
//   bool firstTouch = false;
//   bool _isOpening = false;

//   final PlaybackCoordinator _coordinator = PlaybackCoordinator.instance;

//   Future<void> _openPlayer(BuildContext context) async {
//     if (_isOpening) return;

//     final info = _coordinator.currentOnlineVideo;
//     if (info == null) return;

//     setState(() {
//       _isOpening = true;
//       firstTouch = false;
//     });

//     // Hide the mini-player while opening the full player.
//     _coordinator.restoreMiniPlayer();

//     try {
//       await Navigator.push(
//         context,
//         PageRouteBuilder(
//           opaque: false,
//           barrierColor: Colors.transparent,
//           transitionDuration: Duration.zero,
//           maintainState: true,
//           pageBuilder: (context, animation, secondaryAnimation) {
//             return StreamVideoPage(info: info);
//           },
//           reverseTransitionDuration: const Duration(milliseconds: 180),
//         ),
//       );
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isOpening = false;
//         });
//       }
//     }
//   }

//   Future<void> _togglePlayback() async {
//     try {
//       await _coordinator.togglePlayPause();
//     } catch (error) {
//       debugPrint('Mini-player playback toggle failed: $error');
//     }
//   }

//   void _closeMiniPlayer() {
//     // Replace with your coordinator's close/hide method if named differently.
//     // _coordinator.isMiniPlayerVisible = false;
//     _coordinator.close();
//     setState(() {
//       firstTouch = false;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return ListenableBuilder(
//       listenable: _coordinator,
//       builder: (context, child) {
//         final info = _coordinator.currentOnlineVideo;
//         final controller = _coordinator.videoController;

//         if (!_coordinator.isMiniPlayerVisible ||
//             info == null ||
//             controller == null ||
//             !controller.value.isInitialized) {
//           return const SizedBox.shrink();
//         }

//         final aspectRatio = controller.value.aspectRatio > 0
//             ? controller.value.aspectRatio
//             : 16 / 9;

//         return Positioned(
//           right: 12,
//           bottom: 12,
//           child: Material(
//             elevation: 8,
//             borderRadius: BorderRadius.circular(14),
//             clipBehavior: Clip.antiAlias,
//             color: const Color(0xFF171717),
//             child: GestureDetector(
//               behavior: HitTestBehavior.opaque,
//               onVerticalDragEnd: (details) {
//                 final velocity = details.primaryVelocity ?? 0;

//                 setState(() {
//                   firstTouch = false;
//                 });

//                 if (velocity < -100) {
//                   _openPlayer(context);
//                 } else if (velocity > 100) {
//                   _closeMiniPlayer();
//                 }
//               },
//               onTap: () {
//                 if (firstTouch) {
//                   _openPlayer(context);
//                 } else {
//                   setState(() {
//                     firstTouch = true;
//                   });
//                 }
//               },
//               child: AnimatedContainer(
//                 duration: const Duration(milliseconds: 200),
//                 curve: Curves.easeOutCubic,
//                 width: 210,
//                 height: firstTouch ? 150 : 120,
//                 child: Stack(
//                   fit: StackFit.expand,
//                   children: [
//                     // The coordinator owns this controller.
//                     // Do not dispose it from the mini-player.
//                     Center(
//                       child: AspectRatio(
//                         aspectRatio: aspectRatio,
//                         child: VideoPlayer(controller),
//                       ),
//                     ),

//                     // Subtle title gradient for readability.
//                     Positioned(
//                       left: 0,
//                       right: 0,
//                       top: 0,
//                       child: Container(
//                         padding: const EdgeInsets.fromLTRB(8, 6, 34, 12),
//                         decoration: const BoxDecoration(
//                           gradient: LinearGradient(
//                             begin: Alignment.topCenter,
//                             end: Alignment.bottomCenter,
//                             colors: [Colors.black87, Colors.transparent],
//                           ),
//                         ),
//                         child: Text(
//                           info.title,
//                           maxLines: 1,
//                           overflow: TextOverflow.ellipsis,
//                           style: const TextStyle(
//                             color: Colors.white,
//                             fontSize: 11,
//                             fontWeight: FontWeight.w600,
//                           ),
//                         ),
//                       ),
//                     ),

//                     if (firstTouch) ...[
//                       // Play/pause is handled by the coordinator so audio
//                       // and video stay synchronized.
//                       Center(
//                         child: Container(
//                           decoration: BoxDecoration(
//                             color: Colors.black54,
//                             borderRadius: BorderRadius.circular(50),
//                           ),
//                           child: IconButton(
//                             onPressed: _togglePlayback,
//                             icon: ValueListenableBuilder<VideoPlayerValue>(
//                               valueListenable: controller,
//                               builder: (context, value, child) {
//                                 return Icon(
//                                   _coordinator.isPlaying
//                                       ? Icons.pause_rounded
//                                       : Icons.play_arrow_rounded,
//                                   color: Colors.white,
//                                   size: 30,
//                                 );
//                               },
//                             ),
//                           ),
//                         ),
//                       ),

//                       Positioned(
//                         right: 2,
//                         top: 22,
//                         child: IconButton(
//                           tooltip: 'Close mini-player',
//                           onPressed: _closeMiniPlayer,
//                           icon: const Icon(
//                             Icons.close_rounded,
//                             color: Colors.white,
//                             size: 20,
//                           ),
//                         ),
//                       ),

//                       Positioned(
//                         right: 8,
//                         bottom: 6,
//                         child: Container(
//                           padding: const EdgeInsets.symmetric(
//                             horizontal: 7,
//                             vertical: 4,
//                           ),
//                           decoration: BoxDecoration(
//                             color: Colors.black54,
//                             borderRadius: BorderRadius.circular(8),
//                           ),
//                           child: const Row(
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               Icon(
//                                 Icons.open_in_full_rounded,
//                                 color: Colors.white,
//                                 size: 12,
//                               ),
//                               SizedBox(width: 4),
//                               Text(
//                                 'Expand',
//                                 style: TextStyle(
//                                   color: Colors.white,
//                                   fontSize: 10,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ],
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }
// }
