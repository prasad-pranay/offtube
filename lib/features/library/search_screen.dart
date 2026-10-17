import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:offlinetube/features/downloader/widgets/quality_selection_sheet.dart';
import 'package:offlinetube/features/library/searchSkeltons.dart';
import 'package:offlinetube/features/library/search_overlay.dart';
import 'package:offlinetube/services/extractor/extracted_video_info.dart';
import 'package:offlinetube/services/extractor/video_extractor_service.dart';
import '../../core/theme/app_theme.dart';
import '../../services/database/database_service.dart';
import '../../services/playback/playback_coordinator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SearchScreen extends StatefulWidget {
  final void Function(String? info) openChannelPage;
  final void Function(ExtractedVideoInfo? info) openStreamPage;
  final FocusNode searchFocusNode;
  const SearchScreen({
    super.key,
    required this.searchFocusNode,
    required this.openStreamPage,
    required this.openChannelPage,
  });

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  bool isSearching = false;

  final List _resultsHistory = [];
  List get resultsHistory => _resultsHistory;
  final TextEditingController _searchController = TextEditingController();

  void goBackInHistory() {
    setState(() {
      if (_suggestions.isNotEmpty) {
        _suggestions.clear();
        return;
      }
      _resultsHistory.removeLast();
      if (resultsHistory.isNotEmpty) {
        _searchController.text = resultsHistory.last[0];
      } else {
        _searchController.text = "";
      }
    });
  }

  Future<List> searchYouTube(String query) async {
    // const apiKey = 'AIzaSyCU-DpbLdYo1mgs9Jg7BBbFdk0AE_0q0dI';

    // final uri = Uri.https('www.googleapis.com', '/youtube/v3/search', {
    //   'part': 'snippet',
    //   'q': query,
    //   'type': 'video',
    //   'maxResults': '10',
    //   'regionCode': 'IN',
    //   'relevanceLanguage': 'en',
    //   'key': apiKey,
    // });

    // final response = await http.get(uri);

    // if (response.statusCode != 200) {
    //   throw Exception('YouTube API error: ${response.statusCode}');
    // }

    // final data = jsonDecode(response.body);

    // return List<Map<String, dynamic>>.from(data['items']);
    final List results = await VideoExtractorService.instance.searchQuery(
      query,
    );
    return results;
  }

  String queryText = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String formatTimeAgo(String publishedAt) {
    final date = DateTime.parse(publishedAt).toLocal();
    final now = DateTime.now();

    final difference = now.difference(date);

    if (difference.inSeconds < 60) {
      return 'Just now';
    }

    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    }

    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }

    if (difference.inDays < 30) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    }

    if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    }

    final years = (difference.inDays / 365).floor();
    return '$years ${years == 1 ? 'year' : 'years'} ago';
  }

  String formatViewCount(int views) {
    if (views >= 1000000000) {
      return '${(views / 1000000000).toStringAsFixed(1)}B';
    }
    if (views >= 1000000) {
      return '${(views / 1000000).toStringAsFixed(1)}M';
    }
    if (views >= 1000) {
      return '${(views / 1000).toStringAsFixed(1)}K';
    }
    return views.toString();
  }

  String formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }

    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  void search() async {
    final String searchQuery = _searchController.text.trim();
    final List prevRes = _resultsHistory;

    if (prevRes.isNotEmpty && searchQuery == prevRes.last[0]) {
      setState(() {
        _suggestions.clear();
      });
      return;
    }
    setState(() {
      isSearching = true;
      _suggestions.clear();
    });
    final data = await searchYouTube(searchQuery);

    setState(() {
      _resultsHistory.add([searchQuery, data]);
      isSearching = false;
    });
  }

  List<String> _suggestions = [];

  Future<void> getYoutubeSuggestions() async {
    try {
      if (queryText.trim().isEmpty) {
        setState(() {
          _suggestions.clear();
          return;
        });
      }
      ;

      final uri = Uri.parse(
        'https://suggestqueries.google.com/complete/search'
        '?client=youtube&ds=yt&q=${Uri.encodeComponent(queryText)}',
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        _suggestions.clear();
        return;
      }
      try {
        String body = response.body;

        // Remove JSONP wrapper:
        final start = body.indexOf('(');
        final end = body.lastIndexOf(')');

        if (start == -1 || end == -1) {
          _suggestions.clear();
          return;
        }

        body = body.substring(start + 1, end);

        final data = jsonDecode(body);

        setState(() {
          _suggestions = List<String>.from(
            data[1].map((item) => item[0].toString()),
          );
        });
      } catch (e) {
        print('Suggestion error: $e');
        _suggestions.clear();
        return;
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(CupertinoIcons.globe),
              SizedBox(width: 10),
              Text('Internet not available'),
            ],
          ),
        ),
      );
    }
  }

  void parentSearchCalled(String value) {
    _searchController.text = value;
    search();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Size size = MediaQuery.of(context).size;
    Widget _buildPlaceholder(BuildContext context) {
      return const Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          size: 32,
          color: AppTheme.accentColor,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 65,
        backgroundColor: theme.scaffoldBackgroundColor,
        automaticallyImplyLeading: false,
        leading: _resultsHistory.length > 1
            ? IconButton(
                onPressed: () {
                  goBackInHistory();
                },
                icon: Icon(CupertinoIcons.back),
              )
            : null,
        title: TextField(
          controller: _searchController,
          focusNode: widget.searchFocusNode,
          autofocus: true,
          onTapOutside: (event) {
            widget.searchFocusNode.unfocus();
          },
          onSubmitted: (value) => search(),
          onChanged: (value) {
            getYoutubeSuggestions();
            setState(() {
              queryText = _searchController.text.trim().toLowerCase();
            });
          },
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 15),
            hintText: 'Search...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Color(0xFF222222),
            suffixIcon: GestureDetector(
              onTap: () => setState(() {
                _searchController.text = "";
                queryText = "";
                _suggestions.clear();
                widget.searchFocusNode.requestFocus();
              }),
              child: Container(
                decoration: BoxDecoration(
                  color: Color(0xFF222222),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Icon(CupertinoIcons.xmark, size: 19),
              ),
            ),
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () {
              search();
            },
            child: Container(
              margin: EdgeInsets.only(right: 15),
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Color(0xFF222222),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(CupertinoIcons.search),
              // child: Icon(CupertinoIcons.mic),
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: DatabaseService.instance.getVideosListenable(),
        builder: (context, box, _) {
          final allVideos = DatabaseService.instance.getAllVideos();
          final videoIds = allVideos.map((e) => e.id).toList();

          final query = queryText.trim().toLowerCase();
          final filterVideo = query.isEmpty
              ? allVideos
              : allVideos.where((video) {
                  final title = video.title.toLowerCase();
                  final author = video.author!.toLowerCase();

                  return title.contains(query) || author.contains(query);
                }).toList();

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // show downloaded videos
              if (filterVideo.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final video = filterVideo[index];
                      final thumbFile = File(video.thumbnailPath);
                      final hasThumb = thumbFile.existsSync();
                      return InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          PlaybackCoordinator.instance.loadPlaylist(
                            filterVideo,
                            startIndex: index,
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Thumbnail with Duration & Progress
                            SizedBox(
                              height: 220,
                              width: size.width,
                              child: Stack(
                                children: [
                                  Container(
                                    width: size.width,
                                    color: theme.colorScheme.surface,
                                    child: hasThumb
                                        ? Image.file(
                                            thumbFile,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    _buildPlaceholder(context),
                                          )
                                        : _buildPlaceholder(context),
                                  ),
                                  // Duration badge
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withAlpha(200),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            CupertinoIcons.music_note,
                                            size: 15,
                                          ),
                                          SizedBox(width: 5),
                                          Text(
                                            video.formattedDuration,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: size.width,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 10,
                                  right: 10,
                                ),
                                child: Text(
                                  video.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w400,
                                    fontSize: 16,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                SizedBox(width: 10),
                                if (video.author != null &&
                                    video.author!.isNotEmpty) ...[
                                  Flexible(
                                    child: Text(
                                      video.author!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.tertiary,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ],
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: Text("•"),
                                ),
                                Text(
                                  video.formattedDownloadDate,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.tertiary,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: Text("•"),
                                ),
                                Text(
                                  video.formattedFileSize,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.tertiary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }, childCount: filterVideo.length),
                  ),
                ),
              // found nothing, downloaded empty, suggestion empty, result empty also
              if (!isSearching &&
                  (_resultsHistory.isEmpty ||
                      (_resultsHistory.isNotEmpty &&
                          _resultsHistory.last[1].isEmpty)) &&
                  filterVideo.isEmpty &&
                  _suggestions.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 44,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              _searchController.text.trim().isEmpty
                                  ? CupertinoIcons.search
                                  : CupertinoIcons.film,
                              size: 23,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),

                          const SizedBox(height: 20),

                          Text(
                            _searchController.text.trim().isEmpty
                                ? 'Find something to watch'
                                : 'No results found',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.6,
                              height: 1.2,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            _searchController.text.trim().isEmpty
                                ? 'Search your library or discover videos online.'
                                : 'Nothing matched "${_searchController.text.trim()}". '
                                      'Try another title or check your connection.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // suggestions page, show if not found on downloaded and should not be searching currently
              if (!isSearching &&
                  filterVideo.isEmpty &&
                  _suggestions.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final suggestion = _suggestions[index];

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          leading: const Icon(Icons.search),
                          title: Text(suggestion),
                          onTap: () {
                            _searchController.text = suggestion;
                            search();

                            setState(() {
                              _suggestions.clear();
                              widget.searchFocusNode.unfocus();
                            });
                          },
                        );
                      },
                      childCount: _suggestions.length > 10
                          ? 10
                          : _suggestions.length,
                    ),
                  ),
                ),
              // all video display herer
              if (!isSearching &&
                  (_resultsHistory.isNotEmpty &&
                      _resultsHistory.last[1].isNotEmpty) &&
                  _suggestions.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final video = _resultsHistory.last[1][index];
                        final isDownloaded = videoIds.contains(video.id);
                        final bool videoOnPlaylistAlready = PlaybackCoordinator
                            .instance
                            .onlineNextPlayList
                            .any((value) => value.id == video.id);
                        return InkWell(
                          onTap: () async {
                            widget.searchFocusNode.unfocus();

                            if (video.type == "video") {
                              final overlay = OverlayEntry(
                                builder: (context) => VideoLoadingOverlay(
                                  thumbnail: video.thumbnailUrl,
                                  title: video.title ?? 'Loading video',
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
                                final info = await VideoExtractorService
                                    .instance
                                    .extractInfo(
                                      'https://www.youtube.com/watch?v=${video.id}',
                                    );

                                if (!context.mounted) {
                                  removeOverlay();
                                  return;
                                }

                                removeOverlay();
                                widget.openStreamPage(info);
                              } catch (e, stackTrace) {
                                removeOverlay();
                                debugPrint('Failed to open stream page 1: $e');
                                debugPrintStack(stackTrace: stackTrace);

                                if (!context.mounted) return;

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not load this video'),
                                  ),
                                );
                              }
                            } else if (video.type == "channel") {
                              widget.openChannelPage(video.id);
                              // Navigator.push(
                              //   context,
                              //   MaterialPageRoute(
                              //     builder: (_) =>
                              //         ChannelPage(channelId: video.id),
                              //   ),
                              // );
                            }
                          },

                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (video.type == "channel") ...[
                                Container(
                                  margin: EdgeInsets.only(bottom: 20),
                                  decoration: BoxDecoration(
                                    color: Color(0xff180E33),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      // Channel avatar
                                      ClipOval(
                                        child: SizedBox(
                                          width: 85,
                                          height: 85,
                                          child: Image.network(
                                            video.thumbnailUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    _buildPlaceholder(context),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 16),

                                      // Channel details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              video.author,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),

                                            const SizedBox(height: 5),

                                            Text(
                                              '${video.description}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color:
                                                    theme.colorScheme.tertiary,
                                              ),
                                            ),

                                            const SizedBox(height: 12),

                                            // View channel button
                                            DecoratedBox(
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Colors.white,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 18,
                                                      vertical: 10,
                                                    ),
                                                child: Text(
                                                  'View channel',
                                                  style: TextStyle(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (video.type == "video") ...[
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Thumbnail with duration / live badge
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: SizedBox(
                                        width: size.width,
                                        height: 220,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Image.network(
                                              video.thumbnailUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => _buildPlaceholder(
                                                    context,
                                                  ),
                                            ),

                                            // Subtle bottom gradient for the badge
                                            Positioned(
                                              left: 0,
                                              right: 0,
                                              bottom: 0,
                                              height: 65,
                                              child: IgnorePointer(
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin:
                                                          Alignment.topCenter,
                                                      end: Alignment
                                                          .bottomCenter,
                                                      colors: [
                                                        Colors.transparent,
                                                        Colors.black.withValues(
                                                          alpha: 0.45,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            Positioned(
                                              right: 10,
                                              bottom: 10,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 9,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: video.isLive
                                                      ? Colors.red
                                                      : Colors.black87,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  video.isLive
                                                      ? 'LIVE'
                                                      : formatDuration(
                                                          video.durationSeconds,
                                                        ),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 14),

                                    // Video information
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // add to playlist;
                                          GestureDetector(
                                            onTap: () {
                                              if (PlaybackCoordinator
                                                  .instance
                                                  .onlineNextPlayList
                                                  .any(
                                                    (value) =>
                                                        value.id == video.id,
                                                  )) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Already in Playlist!',
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              PlaybackCoordinator.instance
                                                  .addNextOnlinePlayVideoList(
                                                    video.id,
                                                  );
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Video added to list Successfully!',
                                                  ),
                                                ),
                                              );
                                            },
                                            // aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
                                            child: CircleAvatar(
                                              radius: 21,
                                              backgroundColor:
                                                  Colors.transparent,
                                              child: Icon(
                                                videoOnPlaylistAlready
                                                    ? CupertinoIcons
                                                          .plus_square_fill_on_square_fill
                                                    : CupertinoIcons
                                                          .plus_square_on_square,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),

                                          const SizedBox(width: 12),

                                          // Title and metadata
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  video.title,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: theme
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w400,
                                                        height: 1.3,
                                                      ),
                                                ),

                                                const SizedBox(height: 3),
                                                Wrap(
                                                  children: [
                                                    GestureDetector(
                                                      onTap: () {
                                                        widget.openChannelPage(
                                                          video.channelId,
                                                        );
                                                      },
                                                      child: Text(
                                                        '@${video.author}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w300,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      ),
                                                    ),
                                                    SizedBox(width: 10),
                                                    Text(
                                                      '·',
                                                      style: TextStyle(
                                                        color: theme
                                                            .colorScheme
                                                            .tertiary,
                                                      ),
                                                    ),
                                                    SizedBox(width: 10),
                                                    Text(
                                                      '${formatViewCount(video.viewCount)} views',
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w300,
                                                            color: theme
                                                                .colorScheme
                                                                .tertiary,
                                                          ),
                                                    ),
                                                    SizedBox(width: 10),
                                                    Text(
                                                      '·',
                                                      style: TextStyle(
                                                        color: theme
                                                            .colorScheme
                                                            .tertiary,
                                                      ),
                                                    ),
                                                    SizedBox(width: 10),
                                                    Text(
                                                      '${video.uploadDate}',
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: theme
                                                                .colorScheme
                                                                .tertiary,
                                                            fontWeight:
                                                                FontWeight.w300,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),

                                          const SizedBox(width: 6),

                                          // Download action
                                          Material(
                                            color: theme
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            shape: const CircleBorder(),
                                            child: InkWell(
                                              customBorder:
                                                  const CircleBorder(),
                                              onTap: () async {
                                                if (isDownloaded) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Video already downloaded',
                                                      ),
                                                    ),
                                                  );
                                                  return;
                                                }

                                                try {
                                                  final info =
                                                      await VideoExtractorService
                                                          .instance
                                                          .extractInfo(
                                                            'https://www.youtube.com/watch?v=${video.id}',
                                                          );

                                                  if (!context.mounted) return;

                                                  showModalBottomSheet(
                                                    context: context,
                                                    isScrollControlled: true,
                                                    builder: (ctx) =>
                                                        QualitySelectionSheet(
                                                          info: info,
                                                        ),
                                                  );
                                                } catch (e) {
                                                  if (!context.mounted) return;

                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Could not load download options',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  11,
                                                ),
                                                child: Icon(
                                                  isDownloaded
                                                      ? Icons.check_rounded
                                                      : CupertinoIcons
                                                            .arrow_down,
                                                  size: 21,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 24),
                                  ],
                                ),
                              ] else if (video.type == "playlist") ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: SizedBox(
                                          width: 175,
                                          height: 105,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              if (video.thumbnailUrl.isNotEmpty)
                                                Image.network(
                                                  video.thumbnailUrl.first.url
                                                      .toString(),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      Container(
                                                        color: Colors.white12,
                                                        child: const Icon(
                                                          Icons
                                                              .video_library_outlined,
                                                          color: Colors.white54,
                                                          size: 30,
                                                        ),
                                                      ),
                                                )
                                              else
                                                Container(
                                                  color: Colors.white12,
                                                  child: const Icon(
                                                    Icons
                                                        .video_library_outlined,
                                                    color: Colors.white54,
                                                    size: 30,
                                                  ),
                                                ),

                                              Positioned(
                                                right: 0,
                                                top: 0,
                                                bottom: 0,
                                                child: Container(
                                                  width: 48,
                                                  color: Colors.black
                                                      .withValues(alpha: 0.75),
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      const Icon(
                                                        Icons
                                                            .playlist_play_rounded,
                                                        color: Colors.white,
                                                        size: 25,
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${video.videoCount}',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 12),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              video.title,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Playlist · ${video.videoCount} videos',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.tertiary,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                      childCount: _resultsHistory.isEmpty
                          ? 0
                          : _resultsHistory.last[1].length,
                    ),
                  ),
                ),
              // show loading skeltons
              if (isSearching)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      return VideoSkeleton();
                    }, childCount: 10),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
