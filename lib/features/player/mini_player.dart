import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/PlayerManager.dart';
import '../library/stream_page.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  bool firstTouch = false;
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlayerManager.instance,
      builder: (context, child) {
        final player = PlayerManager.instance;

        if (!player.isMiniPlayerVisible ||
            player.controller == null ||
            player.videoInfo == null) {
          return const SizedBox.shrink();
        }

        final controller = player.controller!;

        return Positioned(
          right: 12,
          bottom: 12,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                setState(() {
                  firstTouch = false;
                });
                if (velocity < 0) {
                  player.maximize();
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      opaque: false,
                      barrierColor: Colors.transparent,
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      pageBuilder: (context, animation, secondaryAnimation) {
                        return const StreamVideoPage();
                      },
                    ),
                  );
                } else if (velocity > 0) {
                  player.close();
                }
              },
              onTap: () {
                if (firstTouch) {
                  player.maximize();
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      opaque: false,
                      barrierColor: Colors.transparent,
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      pageBuilder: (context, animation, secondaryAnimation) {
                        return const StreamVideoPage();
                      },
                    ),
                  );
                  setState(() {
                    firstTouch = false;
                  });
                } else {
                  setState(() {
                    firstTouch = true;
                  });
                }
              },
              child: AnimatedContainer(
                duration: Duration(milliseconds: 200),
                height: firstTouch ? 150 : 120,
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                    if (firstTouch) ...[
                      Positioned(
                        top: 50,
                        left: 105,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: IconButton(
                            onPressed: () {
                              if (controller.value.isPlaying) {
                                controller.pause();
                              } else {
                                controller.play();
                              }
                            },
                            icon: ValueListenableBuilder(
                              valueListenable: controller,
                              builder:
                                  (context, VideoPlayerValue value, child) {
                                    return Icon(
                                      value.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                    );
                                  },
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton(
                          onPressed: player.close,
                          icon: const Icon(Icons.close),
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
