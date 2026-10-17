import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:offlinetube/features/library/search_overlay.dart';
import 'package:offlinetube/features/library/stream_page.dart';
import 'package:offlinetube/services/extractor/video_extractor_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

class ChannelPage extends StatefulWidget {
  final String channelId;

  const ChannelPage({super.key, required this.channelId});

  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final ScrollController _scrollController;

  yt.Channel? _channel;
  yt.ChannelUploadsList? _uploads;

  final List<yt.Video> _videos = [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  int _activeTab = 0;
  int _requestId = 0;

  static const _background = Color(0xFF0F0F0F);
  static const _surface = Color(0xFF1B1B1B);
  static const _muted = Color(0xFFAAAAAA);
  static const _accent = Color(0xFFFF3030);

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);
    _scrollController = ScrollController()..addListener(_onScroll);

    _tabController.addListener(_onTabChanged);

    _loadChannel();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();

    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;

    if (_activeTab != _tabController.index) {
      _activeTab = _tabController.index;
      _loadUploads();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    if (_scrollController.position.extentAfter < 500) {
      _loadMore();
    }
  }

  void onVideoTap(String thumbnail, id) async {
    final overlay = OverlayEntry(
      builder: (context) =>
          VideoLoadingOverlay(thumbnail: thumbnail, title: id),
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
        'https://www.youtube.com/watch?v=${id}',
      );

      if (!context.mounted) {
        removeOverlay();
        return;
      }

      removeOverlay();
      // await Navigator.push(
      //   context,
      //   PageRouteBuilder(
      //     opaque: false,
      //     barrierColor: Colors.transparent,
      //     transitionDuration: Duration.zero,
      //     maintainState: true,
      //     pageBuilder: (context, animation, secondaryAnimation) {
      //       return StreamVideoPage(info: info);
      //     },
      //     reverseTransitionDuration: const Duration(milliseconds: 180),
      //   ),
      // );
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

  Future<void> _loadChannel() async {
    try {
      final channel = await VideoExtractorService.instance.getChannel(
        widget.channelId,
      );

      if (!mounted) return;

      setState(() {
        _channel = channel;
      });

      await _loadUploads();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load this channel. Please try again.';
      });

      debugPrint('Channel error: $e');
    }
  }

  Future<void> _loadUploads() async {
    final request = ++_requestId;

    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = true;
      _error = null;
      _videos.clear();
      _uploads = null;
    });

    try {
      final uploads = await VideoExtractorService.instance.getChannelInfo(
        widget.channelId,
        _activeTab,
      );

      if (!mounted || request != _requestId) return;

      setState(() {
        _uploads = uploads;
        _videos.addAll(uploads);
        _hasMore = uploads.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _requestId) return;

      setState(() {
        _loading = false;
        _error = 'Could not load videos. Check your connection.';
      });

      debugPrint('Uploads error: $e');
    }
  }

  Future<void> _loadMore() async {
    if (_loading ||
        _loadingMore ||
        !_hasMore ||
        _uploads == null ||
        _activeTab == 2) {
      return;
    }

    setState(() => _loadingMore = true);

    try {
      final nextPage = await _uploads!.nextPage();

      if (!mounted) return;

      setState(() {
        if (nextPage == null || nextPage.isEmpty) {
          _hasMore = false;
        } else {
          final existingIds = _videos.map((v) => v.id).toSet();

          _videos.addAll(nextPage.where((v) => !existingIds.contains(v.id)));

          _uploads = nextPage;
        }

        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loadingMore = false);
      debugPrint('Next page error: $e');
    }
  }

  String _formatCount(int? count) {
    if (count == null) return '';

    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M subscribers';
    }

    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K subscribers';
    }

    return '$count subscribers';
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '';

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // bottomNavigationBar: BottomNavigation(currentIndex: 1),
      appBar: AppBar(
        title: Text(
          _channel != null ? '@${_channel!.title}' : 'Channel',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadChannel,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          if (_channel != null) ...[
            SliverToBoxAdapter(child: _buildBanner()),
            SliverToBoxAdapter(child: _buildChannelInfo()),
          ],

          SliverPersistentHeader(
            pinned: true,
            delegate: _TabHeaderDelegate(
              TabBar(
                controller: _tabController,
                // isScrollable: true,
                tabAlignment: TabAlignment.fill,
                indicatorColor: _accent,
                indicatorWeight: 3,
                dividerColor: Colors.white12,
                labelColor: Colors.white,
                unselectedLabelColor: _muted,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.play_rectangle, size: 18),
                        SizedBox(width: 7),
                        Text('Videos'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.bolt, size: 18),
                        SizedBox(width: 7),
                        Text('Shorts'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.info, size: 18),
                        SizedBox(width: 7),
                        Text('About'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_activeTab == 2 && _channel != null)
            SliverToBoxAdapter(child: _buildAbout())
          else if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(color: _accent)),
            )
          else if (_error != null)
            SliverFillRemaining(hasScrollBody: false, child: _buildError())
          else if (_videos.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No videos found.',
                  style: TextStyle(color: _muted),
                ),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;

                  final columns = width >= 1000
                      ? 4
                      : width >= 650
                      ? 3
                      : width >= 380
                      ? 2
                      : 1;

                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 0,
                      mainAxisSpacing: 20,
                      childAspectRatio: 1.5,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index >= _videos.length) return null;

                      return _VideoCard(
                        video: _videos[index],
                        isShort: _activeTab == 1,
                        durationFormatter: _formatDuration,
                        onTap: () {
                          onVideoTap(
                            _videos[index].thumbnails.highResUrl,
                            _videos[index].id.value,
                          );
                        },
                      );
                    }, childCount: _videos.length),
                  );
                },
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: _loadingMore
                      ? const CircularProgressIndicator(color: _accent)
                      : const SizedBox(height: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBanner() {
    final bannerUrl = _channel!.bannerUrl;
    if (bannerUrl == "") {
      return SizedBox();
    }
    return Container(
      height: 150,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: bannerUrl.isNotEmpty
          ? Image.network(
              bannerUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => const _BannerFallback(),
            )
          : const _BannerFallback(),
    );
  }

  Widget _buildChannelInfo() {
    final channel = _channel!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 43,
            backgroundColor: _surface,
            backgroundImage: channel.logoUrl.isNotEmpty
                ? NetworkImage(channel.logoUrl)
                : null,
            child: channel.logoUrl.isEmpty
                ? const Icon(
                    Icons.person_rounded,
                    color: Colors.white70,
                    size: 38,
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 7),
                if (channel.subscribersCount != null)
                  Text(
                    _formatCount(channel.subscribersCount),
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.video_library_outlined,
                      label: 'Videos',
                    ),
                    _InfoChip(
                      icon: Icons.play_circle_outline_rounded,
                      label: 'Shorts',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbout() {
    final channel = _channel!;

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'About this channel',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 22),
            _AboutRow(
              icon: Icons.person_outline_rounded,
              label: 'Channel name',
              value: channel.title,
            ),
            const SizedBox(height: 18),
            _AboutRow(
              icon: Icons.people_outline_rounded,
              label: 'Subscribers',
              value: _formatCount(channel.subscribersCount).isEmpty
                  ? 'Not available'
                  : _formatCount(channel.subscribersCount),
            ),
            const SizedBox(height: 18),
            _AboutRow(
              icon: Icons.link_rounded,
              label: 'Channel ID',
              value: channel.id.toString(),
            ),
            const SizedBox(height: 18),
            _AboutRow(
              icon: Icons.language_rounded,
              label: 'YouTube URL',
              value: channel.url,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: _muted),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadChannel,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  final yt.Video video;
  final bool isShort;
  final String Function(Duration?) durationFormatter;
  final VoidCallback onTap;

  const _VideoCard({
    required this.video,
    required this.isShort,
    required this.durationFormatter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnail = video.thumbnails.highResUrl;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isShort ? 14 : 10),
          child: Image.network(
            thumbnail,
            width: double.infinity,
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFF252525),
              child: const Icon(
                Icons.video_library_outlined,
                color: Colors.white38,
                size: 36,
              ),
            ),
          ),
        ),
        // child: Column(
        //   crossAxisAlignment: CrossAxisAlignment.start,
        //   children: [
        //     Expanded(
        //       child: Stack(
        //         fit: StackFit.expand,
        //         children: [
        //           ClipRRect(
        //             borderRadius: BorderRadius.circular(isShort ? 14 : 10),
        //             child: Image.network(
        //               thumbnail,
        //               fit: BoxFit.cover,
        //               errorBuilder: (_, __, ___) => Container(
        //                 color: const Color(0xFF252525),
        //                 child: const Icon(
        //                   Icons.video_library_outlined,
        //                   color: Colors.white38,
        //                   size: 36,
        //                 ),
        //               ),
        //             ),
        //           ),

        // if (isShort)
        //   const Positioned(
        //     top: 8,
        //     left: 8,
        //     child: _Pill(
        //       icon: Icons.play_arrow_rounded,
        //       text: 'Shorts',
        //     ),
        //   ),
        // if (!isShort && video.duration != null)
        //   Positioned(
        //     right: 8,
        //     bottom: 8,
        //     child: Container(
        //       padding: const EdgeInsets.symmetric(
        //         horizontal: 6,
        //         vertical: 4,
        //       ),
        //       decoration: BoxDecoration(
        //         color: Colors.black.withValues(alpha: 0.8),
        //         borderRadius: BorderRadius.circular(5),
        //       ),
        //       child: Text(
        //         durationFormatter(video.duration),
        //         style: const TextStyle(
        //           color: Colors.white,
        //           fontSize: 11,
        //           fontWeight: FontWeight.w600,
        //         ),
        //       ),
        //     ),
        //   ),
        //     ],
        //   ),
        // ),

        // const SizedBox(height: 10),
        // Row(
        //   crossAxisAlignment: CrossAxisAlignment.start,
        //   children: [
        //     Expanded(
        //       child: Text(
        //         video.title,
        //         maxLines: 2,
        //         overflow: TextOverflow.ellipsis,
        //         style: const TextStyle(
        //           color: Colors.white,
        //           fontSize: 13,
        //           height: 1.4,
        //           fontWeight: FontWeight.w500,
        //         ),
        //       ),
        //     ),
        //     const SizedBox(width: 6),
        //     const Icon(
        //       Icons.more_vert_rounded,
        //       color: Colors.white70,
        //       size: 19,
        //     ),
        //   ],
        // ),
        // if (video.engagement.viewCount != null) ...[
        //   const SizedBox(height: 5),
        //   Text(
        //     '${video.engagement.viewCount} views',
        //     maxLines: 1,
        //     overflow: TextOverflow.ellipsis,
        //     style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11),
        //   ),
        // ],
        //   ],
        // ),
      ),
    );
  }
}

class _BannerFallback extends StatelessWidget {
  const _BannerFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF292929), Color(0xFF181818)],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          size: 52,
          color: Colors.white24,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white70),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 2),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AboutRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 5),
              SelectableText(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _TabHeaderDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: const Color(0xFF0F0F0F), child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabHeaderDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar;
  }
}
