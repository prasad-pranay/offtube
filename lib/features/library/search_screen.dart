import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:offlinetube/features/downloader/widgets/quality_selection_sheet.dart';
import 'package:offlinetube/features/library/stream_page.dart';
import 'package:offlinetube/services/PlayerManager.dart';
import 'package:offlinetube/services/extractor/video_extractor_service.dart';
import '../../core/theme/app_theme.dart';
import '../../services/database/database_service.dart';
import '../../services/playback/playback_coordinator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SearchScreen extends StatefulWidget {
  final VoidCallback onOpenAddVideo;
  final VoidCallback goHome;
  final FocusNode focusNode;
  const SearchScreen({
    super.key,
    required this.onOpenAddVideo,
    required this.goHome,
    required this.focusNode,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  // final _searchFocusNode = FocusNode();

  Future<List<Map<String, dynamic>>> searchYouTube(String query) async {
    const apiKey = 'AIzaSyCU-DpbLdYo1mgs9Jg7BBbFdk0AE_0q0dI';

    final uri = Uri.https('www.googleapis.com', '/youtube/v3/search', {
      'part': 'snippet',
      'q': query,
      'type': 'video',
      'maxResults': '10',
      'regionCode': 'IN',
      'relevanceLanguage': 'en',
      'key': apiKey,
    });

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('YouTube API error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);

    return List<Map<String, dynamic>>.from(data['items']);
  }

  List<Map<String, dynamic>> results = [];

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

  void search() async {
    final data = await searchYouTube(_searchController.text);
    List<Map<String, dynamic>> res = [];

    for (final video in data) {
      res.add({
        'id': video['id']['videoId'],
        'title': video['snippet']['title'],
        'thumbnailPath': video['snippet']['thumbnails']['high']['url'],
        'author': video['snippet']['channelTitle'],
        'publishedAt': video['snippet']['publishedAt'],
      });
    }

    setState(() {
      // results.clear();
      // results.addAll(res);
      results = List<Map<String, dynamic>>.from(res);
      resultScreen = true;
    });
  }

  bool resultScreen = false;

  List<String> _suggestions = [];

  Future<void> getYoutubeSuggestions() async {
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
        leading: IconButton(
          onPressed: () {
            widget.goHome();
          },
          icon: const Icon(CupertinoIcons.chevron_back, size: 28),
        ),
        title: TextField(
          controller: _searchController,
          focusNode: widget.focusNode,
          // autofocus: true,
          onSubmitted: (value) => search(),
          onChanged: (value) {
            getYoutubeSuggestions();
            setState(() {
              if (resultScreen) {
                resultScreen = false;
              }
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
                resultScreen = false;
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
              if (!resultScreen && filterVideo.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final video = filterVideo[index];
                      final thumbFile = File(video.thumbnailPath);
                      final hasThumb = thumbFile.existsSync();
                      return InkWell(
                        onTap: () {
                          widget.goHome();
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
                                  bottom: 25,
                                ),
                                child: Text(
                                  video.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }, childCount: filterVideo.length),
                  ),
                ),
              if (!resultScreen && filterVideo.isEmpty && _suggestions.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 44,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withAlpha(18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.search,
                              size: 38,
                              color: AppTheme.accentColor,
                            ),
                          ),

                          const SizedBox(height: 22),

                          Text(
                            'Video not found',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'This video isn’t in your downloaded library.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.tertiary,
                            ),
                          ),

                          const SizedBox(height: 20),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withAlpha(15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.search,
                                  size: 17,
                                  color: AppTheme.accentColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Press Enter to search for it',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!resultScreen &&
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
                              widget.focusNode.unfocus();
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
              if (resultScreen)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final video = results[index];
                      final isDownloaded = videoIds.contains(video['id']);
                      return InkWell(
                        onTap: () async {
                          widget.focusNode.unfocus();
                          final info = await VideoExtractorService.instance
                              .extractInfo(
                                "https://www.youtube.com/watch?v=${video['id']}",
                              );

                          await PlayerManager.instance.playVideo(info);

                          if (!context.mounted) return;

                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              opaque: false,
                              barrierColor: Colors.transparent,
                              transitionDuration: Duration.zero,
                              reverseTransitionDuration: Duration.zero,
                              pageBuilder:
                                  (context, animation, secondaryAnimation) {
                                    return const StreamVideoPage();
                                  },
                            ),
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
                                    child: Image.network(
                                      video['thumbnailPath'],
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              _buildPlaceholder(context),
                                    ),
                                  ),

                                  // Duration badge
                                  // Positioned(
                                  //   bottom: 0,
                                  //   right: 0,
                                  //   child: Container(
                                  //     margin: const EdgeInsets.symmetric(
                                  //       horizontal: 10,
                                  //       vertical: 8,
                                  //     ),
                                  //     padding: const EdgeInsets.symmetric(
                                  //       horizontal: 10,
                                  //       vertical: 3,
                                  //     ),
                                  //     decoration: BoxDecoration(
                                  //       color: Colors.black.withAlpha(200),
                                  //       borderRadius: BorderRadius.circular(10),
                                  //     ),
                                  //     child: Icon(CupertinoIcons.eye, size: 15),
                                  //   ),
                                  // ),
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
                                  bottom: 25,
                                ),
                                child: Row(
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: size.width - 70,
                                          child: Text(
                                            "${video['title']}",
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16,
                                                  height: 1.25,
                                                ),
                                          ),
                                        ),
                                        SizedBox(height: 5),
                                        Row(
                                          children: [
                                            Icon(
                                              CupertinoIcons.music_note,
                                              size: 14,
                                              color: theme.colorScheme.tertiary,
                                            ),
                                            SizedBox(width: 5),
                                            Text(
                                              "${video['author']}",
                                              style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    theme.colorScheme.tertiary,
                                              ),
                                            ),
                                            SizedBox(width: 15),
                                            Icon(
                                              CupertinoIcons.calendar,
                                              size: 14,
                                              color: theme.colorScheme.tertiary,
                                            ),
                                            SizedBox(width: 5),
                                            Text(
                                              formatTimeAgo(
                                                video['publishedAt'],
                                              ),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    theme.colorScheme.tertiary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    GestureDetector(
                                      onTap: () async {
                                        if (isDownloaded) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Padding(
                                                padding: EdgeInsets.symmetric(
                                                  vertical: 5,
                                                ),
                                                child: Text(
                                                  "Video already downloaded",
                                                ),
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        final info = await VideoExtractorService
                                            .instance
                                            .extractInfo(
                                              "https://www.youtube.com/watch?v=${video['id']}",
                                            );
                                        // Open quality selection sheet
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          builder: (ctx) =>
                                              QualitySelectionSheet(info: info),
                                        );
                                      },
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.scaffoldBackgroundColor,
                                        ),
                                        child: Icon(
                                          isDownloaded
                                              ? Icons.check
                                              : Icons.download_outlined,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }, childCount: results.length),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
