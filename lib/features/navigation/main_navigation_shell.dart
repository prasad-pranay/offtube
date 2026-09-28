import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/share/share_intent_service.dart';
import '../../services/download/download_manager.dart';
import '../library/home_screen.dart';
import '../downloader/downloads_screen.dart';
import '../downloader/add_video_modal.dart';
import '../settings/settings_screen.dart';
import '../player/mini_player_widget.dart';
import '../player/fullscreen_player_screen.dart';

class MainNavigationShell extends StatefulWidget {
  final VoidCallback onThemeChanged;

  const MainNavigationShell({super.key, required this.onThemeChanged});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _listenToShareIntents();
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

  void _openAddVideoModal({String? initialUrl}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AddVideoModal(initialUrl: initialUrl),
    );
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final screens = [
      HomeScreen(onOpenAddVideo: () => _openAddVideoModal()),
      DownloadsScreen(onAddVideo: () => _openAddVideoModal()),
      SettingsScreen(onThemeChanged: widget.onThemeChanged),
    ];

    return Scaffold(
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
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        elevation: 0,
        backgroundColor: theme.cardTheme.color,
        indicatorColor: AppTheme.accentColor.withAlpha(40),
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home),
            selectedIcon: Icon(Icons.home, color: AppTheme.accentColor),
            label: 'Home',
          ),
          NavigationDestination(
            icon: ListenableBuilder(
              listenable: DownloadManager.instance,
              builder: (context, _) {
                final count = DownloadManager.instance.activeDownloadsCount;
                if (count > 0) {
                  return Badge(
                    label: Text('$count'),
                    backgroundColor: AppTheme.accentColor,
                    child: const Icon(Icons.download_outlined),
                  );
                }
                return const Icon(Icons.download_outlined);
              },
            ),
            selectedIcon: const Icon(
              Icons.download_rounded,
              color: AppTheme.accentColor,
            ),
            label: 'Downloads',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(
              Icons.settings_rounded,
              color: AppTheme.accentColor,
            ),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: _currentIndex < 2
          ? SizedBox(
              width: 67,
              height: 67,
              child: FloatingActionButton(
                onPressed: () => _openAddVideoModal(),
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                elevation: 4,
                child: const Icon(Icons.add_rounded, size: 32),
              ),
            )
          : null,
    );
  }
}
