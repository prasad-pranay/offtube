import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/video_model.dart';
import '../../services/database/database_service.dart';
import '../../services/playback/playback_coordinator.dart';
import '../../services/storage/storage_service.dart';
import 'widgets/video_card.dart';
import 'widgets/video_grid_card.dart';
import 'widgets/library_empty_state.dart';
import 'widgets/video_info_sheet.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenAddVideo;

  const HomeScreen({
    super.key,
    required this.onOpenAddVideo,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isGridView = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _isGridView = DatabaseService.instance.getSetting<bool>('is_grid_view', false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleView() {
    setState(() {
      _isGridView = !_isGridView;
    });
    DatabaseService.instance.setSetting('is_grid_view', _isGridView);
  }

  void _confirmDelete(BuildContext context, VideoModel video) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this video?'),
        content: Text(
          'This will permanently remove "${video.title}" and its media files from your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              await StorageService.instance.deleteVideoFiles(video.id);
              await DatabaseService.instance.deleteVideo(video.id);
              if (mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('Deleted "${video.title}"')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showVideoInfo(BuildContext context, VideoModel video) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => VideoInfoSheet(
        video: video,
        onPlay: () {
          PlaybackCoordinator.instance.playVideo(video);
        },
        onDelete: () => _confirmDelete(context, video),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Search downloaded videos...',
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
              )
            : Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.accentColor, AppTheme.accentGradientEnd],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('OfflineTube'),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
            tooltip: _isGridView ? 'Switch to List' : 'Switch to Grid',
            onPressed: _toggleView,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: DatabaseService.instance.getVideosListenable(),
        builder: (context, box, _) {
          final allVideos = DatabaseService.instance.getAllVideos();
          final filteredVideos = _searchQuery.isEmpty
              ? allVideos
              : allVideos.where((v) {
                  return v.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      (v.author?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
                }).toList();

          if (allVideos.isEmpty) {
            return LibraryEmptyState(onAddVideo: widget.onOpenAddVideo);
          }

          if (filteredVideos.isEmpty && _searchQuery.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 48,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No videos found for "$_searchQuery"',
                    style: TextStyle(
                      fontSize: 15,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            );
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Library',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${filteredVideos.length} ${filteredVideos.length == 1 ? 'video' : 'videos'} offline',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                      // Shuffle All Button
                      if (filteredVideos.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            PlaybackCoordinator.instance.loadPlaylist(filteredVideos);
                            if (!PlaybackCoordinator.instance.isShuffle) {
                              PlaybackCoordinator.instance.toggleShuffle();
                            }
                          },
                          icon: const Icon(Icons.shuffle_rounded, size: 18),
                          label: const Text('Shuffle Play'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.accentColor,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Videos List / Grid
              if (_isGridView)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.88,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final video = filteredVideos[index];
                        return VideoGridCard(
                          video: video,
                          onTap: () {
                            PlaybackCoordinator.instance.loadPlaylist(
                              filteredVideos,
                              startIndex: index,
                            );
                          },
                          onPlay: () {
                            PlaybackCoordinator.instance.loadPlaylist(
                              filteredVideos,
                              startIndex: index,
                            );
                          },
                          onDelete: () => _confirmDelete(context, video),
                          onInfo: () => _showVideoInfo(context, video),
                        );
                      },
                      childCount: filteredVideos.length,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final video = filteredVideos[index];
                        return VideoCard(
                          video: video,
                          onTap: () {
                            PlaybackCoordinator.instance.loadPlaylist(
                              filteredVideos,
                              startIndex: index,
                            );
                          },
                          onPlay: () {
                            PlaybackCoordinator.instance.loadPlaylist(
                              filteredVideos,
                              startIndex: index,
                            );
                          },
                          onDelete: () => _confirmDelete(context, video),
                          onInfo: () => _showVideoInfo(context, video),
                        );
                      },
                      childCount: filteredVideos.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
