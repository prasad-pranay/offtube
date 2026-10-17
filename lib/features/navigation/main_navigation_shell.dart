import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:offlinetube/features/library/channel_screen.dart';
import 'package:offlinetube/features/library/search_overlay.dart';
import 'package:offlinetube/features/library/search_screen.dart';
import 'package:offlinetube/features/library/stream_page.dart';
import 'package:offlinetube/features/player/mini_player.dart';
import 'package:offlinetube/services/extractor/extracted_video_info.dart';
import 'package:offlinetube/services/extractor/video_extractor_service.dart';
import '../../core/theme/app_theme.dart';
import '../../services/share/share_intent_service.dart';
import '../../services/download/download_manager.dart';
import '../library/home_screen.dart';
import '../downloader/downloads_screen.dart';
import '../downloader/add_video_modal.dart';
import '../settings/settings_screen.dart';
import '../player/mini_player_widget.dart';
import '../player/fullscreen_player_screen.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';

class MainNavigationShell extends StatefulWidget {
  final VoidCallback onThemeChanged;

  const MainNavigationShell({super.key, required this.onThemeChanged});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  ExtractedVideoInfo? _activeStream;
  final TextEditingController searchController = TextEditingController();
  String? _channelId;
  final GlobalKey<StreamVideoPageState> _streamPageKey =
      GlobalKey<StreamVideoPageState>();
  final GlobalKey<SearchScreenState> _searchPageKey =
      GlobalKey<SearchScreenState>();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  bool _handlingIncomingLink = false;

  late final List<Widget> _screens;
  final FocusNode _searchFocusNode = FocusNode();
  bool _isVideoFullscreen = false;

  @override
  void initState() {
    super.initState();
    _listenToShareIntents();
    _initDeepLinks();
    _screens = [
      HomeScreen(
        searchController: searchController,
        callSearch: () {
          setState(() {
            _currentIndex = 3;
            _searchPageKey.currentState?.parentSearchCalled(
              searchController.text,
            );
            searchController.text = "";
          });
        },
      ),
      DownloadsScreen(),
      SettingsScreen(),
      SearchScreen(
        searchFocusNode: _searchFocusNode,
        key: _searchPageKey,
        openStreamPage: (ExtractedVideoInfo? info) {
          if (!mounted) return;
          setState(() {
            _activeStream = info;
          });
        },
        openChannelPage: (String? info) {
          if (!mounted) return;
          setState(() {
            _channelId = info;
          });
        },
      ),
    ];
  }

  String normalizeYouTubeUrl(String input) {
    final uri = Uri.tryParse(input.trim());

    if (uri == null) {
      throw ArgumentError('Invalid YouTube URL');
    }

    final host = uri.host.toLowerCase();
    final isYouTube =
        host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtu.be' ||
        host.endsWith('.youtu.be');

    if (!isYouTube) {
      throw ArgumentError('Not a YouTube URL');
    }

    String? id;

    if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
      id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    } else if (uri.path == '/watch') {
      id = uri.queryParameters['v'];
    } else if (uri.pathSegments.isNotEmpty &&
        ['shorts', 'embed', 'live', 'video'].contains(uri.pathSegments.first) &&
        uri.pathSegments.length > 1) {
      id = uri.pathSegments[1];
    }

    if (id == null || !RegExp(r'^[\w-]{11}$').hasMatch(id)) {
      throw ArgumentError('Invalid YouTube video ID');
    }

    return 'https://www.youtube.com/watch?v=$id';
  }

  Future<void> _initDeepLinks() async {
    final initialUri = await _appLinks.getInitialLink();

    if (initialUri != null && mounted) {
      await _handleIncomingLink(initialUri);
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleIncomingLink(uri),
      onError: (error) {
        debugPrint('Incoming link error: $error');
      },
    );
  }

  bool _isYouTubeUrl(Uri uri) {
    const hosts = {
      'youtube.com',
      'www.youtube.com',
      'm.youtube.com',
      'music.youtube.com',
      'youtu.be',
    };

    return (uri.scheme == 'https' || uri.scheme == 'http') &&
        hosts.contains(uri.host.toLowerCase());
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    if (!_isYouTubeUrl(uri) || _handlingIncomingLink) return;

    _handlingIncomingLink = true;

    final overlay = OverlayEntry(
      builder: (context) => VideoLoadingOverlay(
        thumbnail: null,
        title: 'Loading ${uri.toString()}',
      ),
    );

    Overlay.of(context).insert(overlay);
    bool overlayRemoved = false;

    void removeOverlay() {
      if (!overlayRemoved) {
        overlayRemoved = true;
        overlay.remove();
      }
    }

    try {
      final info = await VideoExtractorService.instance.extractInfo(
        normalizeYouTubeUrl(uri.toString()),
      );

      if (!mounted) {
        removeOverlay();
        return;
      }

      removeOverlay();

      setState(() {
        _activeStream = info;
      });
    } catch (error) {
      debugPrint('Failed to open YouTube link: $error');
    } finally {
      _handlingIncomingLink = false;
      removeOverlay();
    }
  }

  void _listenToShareIntents() {
    ShareIntentService.instance.sharedUrlNotifier.addListener(() {
      final sharedUrl = ShareIntentService.instance.sharedUrlNotifier.value;
      if (sharedUrl != null && mounted) {
        _openAddVideoModal(initialUrl: sharedUrl);

        ShareIntentService.instance.clearSharedUrl();
      }
    });
  }

  void _openAddVideoModalBasic({String? initialUrl}) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AddVideoModal(initialUrl: initialUrl),
    );
  }

  void _openAddVideoModal({String? initialUrl}) async {
    final overlay = OverlayEntry(
      builder: (context) =>
          VideoLoadingOverlay(thumbnail: null, title: 'Loading $initialUrl'),
    );

    Overlay.of(context).insert(overlay);
    bool overlayRemoved = false;

    void removeOverlay() {
      if (!overlayRemoved) {
        overlayRemoved = true;
        overlay.remove();
      }
    }

    try {
      final info = await VideoExtractorService.instance.extractInfo(
        '$initialUrl',
      );

      if (!context.mounted) {
        removeOverlay();
        return;
      }

      removeOverlay();
      setState(() {
        _activeStream = info;
      });
    } catch (e, stackTrace) {
      removeOverlay();
      debugPrint('Failed to open stream page 1: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load this video')),
      );
    }
  }

  void _openFullscreenPlayer() {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, anim1, anim2) => const FullscreenPlayerScreen(),
        transitionsBuilder: (context, anim, secondaryAnim, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget _buildNavItem({
      required IconData icon,
      required IconData selectedIcon,
      required String label,
      required int index,
      int badgeCount = 0,
    }) {
      final isSelected = _currentIndex == index;

      return GestureDetector(
        onTap: () {
          if (_activeStream != null) {
            _streamPageKey.currentState?.enterMiniModeFromParent();
          }
          if (_channelId != null) {
            setState(() {
              _channelId = null;
            });
          }
          setState(() {
            _currentIndex = index;
            if (_currentIndex == 3) {
              Future.delayed(const Duration(milliseconds: 100), () {
                _searchFocusNode.requestFocus();
              });
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: theme.bottomNavigationBarTheme.backgroundColor,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    isSelected ? selectedIcon : icon,
                    size: 23,
                    color: isSelected
                        ? AppTheme.accentColor
                        : theme.appBarTheme.titleTextStyle!.color,
                  ),

                  if (badgeCount > 0)
                    Positioned(
                      right: -10,
                      top: -7,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 17,
                          minHeight: 17,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.bottomSheetTheme.backgroundColor!,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          '$badgeCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected
                      ? AppTheme.accentColor
                      : theme.appBarTheme.titleTextStyle!.color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // If keyboard is open, let the system close it first
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
          setState(() {
            _currentIndex = 0;
          });

          return;
        }

        // If channel page then go to saerch page back
        if (_channelId != null) {
          setState(() {
            _channelId = null;
          });
          return;
        }

        // if on search screen then display the back results
        if (_currentIndex == 3) {
          if (_searchPageKey.currentState != null &&
              _searchPageKey.currentState!.resultsHistory.isNotEmpty) {
            _searchPageKey.currentState!.goBackInHistory();
            return;
          }
        }

        if (_activeStream != null) {
          return;
        }
        // if not on home page then go to home page
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Current Selected Page
            IndexedStack(index: _currentIndex, children: _screens),
            if (_channelId != null) ChannelPage(channelId: _channelId!),
            if (_activeStream != null)
              StreamVideoPage(
                key: _streamPageKey,
                info: _activeStream!,
                onFullscreenChanged: (fullscreen) {
                  setState(() {
                    _isVideoFullscreen = fullscreen;
                  });
                },
                openStreamPage: (ExtractedVideoInfo? info) {
                  setState(() {
                    _activeStream = info;
                  });
                },
              ),

            // Persistent Mini Player above Bottom Navigation
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: MiniPlayerWidget(onExpand: _openFullscreenPlayer),
            ),

            if (_activeStream == null)
              MiniPlayer(
                openStreamPage: (ExtractedVideoInfo? info) {
                  setState(() {
                    _activeStream = info;
                  });
                },
              ),
          ],
        ),

        bottomNavigationBar: _isVideoFullscreen || _activeStream != null
            ? null
            : BottomAppBar(
                color:
                    theme.bottomSheetTheme.backgroundColor ??
                    theme.colorScheme.surface,
                elevation: 0,
                notchMargin: 0,
                height: 60,
                padding: EdgeInsets.zero,
                child: Container(
                  decoration: BoxDecoration(
                    // border: Border(top: BorderSide(color: Color(0xFF2B2B2D))),
                  ),
                  child: Row(
                    children: [
                      // HOME
                      Expanded(
                        child: _buildNavItem(
                          icon: CupertinoIcons.house,
                          selectedIcon: CupertinoIcons.house_fill,
                          label: 'Home',
                          index: 0,
                        ),
                      ),
                      Expanded(
                        child: _buildNavItem(
                          icon: CupertinoIcons.search,
                          selectedIcon: CupertinoIcons.search,
                          label: 'Search',
                          index: 3,
                        ),
                      ),

                      // CENTER SPACE FOR FAB
                      // const SizedBox(width: 72),
                      Expanded(
                        child: Align(
                          alignment: Alignment.center,
                          widthFactor: 1,
                          child: GestureDetector(
                            onTap: () => _openAddVideoModalBasic(),
                            child: Container(
                              margin: EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Color(0xFFffffff),
                                // color: theme.colorScheme.tertiary,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              padding: EdgeInsets.all(7),
                              child: Icon(
                                CupertinoIcons.add,
                                size: 28,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // DOWNLOADS
                      Expanded(
                        child: ListenableBuilder(
                          listenable: DownloadManager.instance,
                          builder: (context, _) {
                            final count =
                                DownloadManager.instance.activeDownloadsCount;

                            return _buildNavItem(
                              icon: CupertinoIcons.cloud_download,
                              selectedIcon: CupertinoIcons.cloud_download_fill,
                              label: 'Download',
                              index: 1,
                              badgeCount: count,
                            );
                          },
                        ),
                      ),

                      // SETTINGS
                      Expanded(
                        child: _buildNavItem(
                          icon: CupertinoIcons.settings_solid,
                          selectedIcon: CupertinoIcons.settings,
                          label: 'Settings',
                          index: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
