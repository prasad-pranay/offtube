import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:offlinetube/features/library/search_overlay.dart';
import 'package:offlinetube/features/library/search_screen.dart';
import 'package:offlinetube/features/library/stream_page.dart';
import 'package:offlinetube/features/player/mini_player.dart';
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

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  bool _handlingIncomingLink = false;

  @override
  void initState() {
    super.initState();
    _listenToShareIntents();
    _initDeepLinks();
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
        uri.toString(),
      );

      if (!mounted) {
        removeOverlay();
        return;
      }

      removeOverlay();

      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => StreamVideoPage(info: info)),
      );
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
      await Navigator.push(
        context,
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: Duration.zero,
          maintainState: true,
          pageBuilder: (context, animation, secondaryAnimation) {
            return StreamVideoPage(info: info);
          },
          reverseTransitionDuration: const Duration(milliseconds: 180),
        ),
      );
    } catch (e, stackTrace) {
      removeOverlay();
      debugPrint('Failed to open stream page 1: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load this video')),
      );
    }
    // showModalBottomSheet(
    //   context: context,
    //   isScrollControlled: true,
    //   builder: (ctx) => AddVideoModal(initialUrl: initialUrl),
    // );
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

  final FocusNode _searchFocusNode = FocusNode();

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

    final screens = [
      HomeScreen(onOpenAddVideo: () => _openAddVideoModal()),
      DownloadsScreen(onAddVideo: () => _openAddVideoModal()),
      SettingsScreen(onThemeChanged: widget.onThemeChanged),
      SearchScreen(
        onOpenAddVideo: () => _openAddVideoModal(),
        focusNode: _searchFocusNode,
        goHome: () => setState(() {
          _currentIndex = 0;
        }),
      ),
    ];

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

        // If not on Home, go Home
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
            IndexedStack(index: _currentIndex, children: screens),

            // Persistent Mini Player above Bottom Navigation
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: MiniPlayerWidget(onExpand: _openFullscreenPlayer),
            ),

            MiniPlayer(),
          ],
        ),

        bottomNavigationBar: BottomAppBar(
          color: theme.bottomSheetTheme.backgroundColor,
          elevation: 0,
          notchMargin: 0,
          height: 60,
          padding: EdgeInsets.zero,
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF2B2B2D))),
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
                GestureDetector(
                  onTap: () => _openAddVideoModal(),
                  child: Container(
                    margin: EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Color(0xFF262626),
                      // color: theme.colorScheme.tertiary,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    padding: EdgeInsets.all(7),
                    child: Icon(CupertinoIcons.add, size: 28),
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
        // floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        // floatingActionButton: SizedBox(
        //   width: 67,
        //   height: 67,
        //   child: FloatingActionButton(
        //     onPressed: () => _openAddVideoModal(),
        //     backgroundColor: AppTheme.accentColor,
        //     foregroundColor: Colors.white,
        //     shape: const CircleBorder(),
        //     elevation: 4,
        //     child: const Icon(Icons.add_rounded, size: 32),
        //   ),
        // ),
      ),
    );
  }
}
