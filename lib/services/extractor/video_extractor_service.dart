// import 'dart:ffi';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:ytdlp_flutter/ytdlp_flutter.dart' as ytdlp;
import 'extracted_video_info.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class VideoExtractorService {
  static VideoExtractorService? _instance;
  static VideoExtractorService get instance =>
      _instance ??= VideoExtractorService._();
  VideoExtractorService._();

  final yt.YoutubeExplode _ytExplode = yt.YoutubeExplode();
  bool _ytdlpInitialized = false;

  Future<void> _ensureYtdlpInit() async {
    if (!_ytdlpInitialized) {
      try {
        await ytdlp.Ytdlp.init();
        _ytdlpInitialized = true;
      } catch (e) {
        debugPrint('ytdlp.Ytdlp.init note: $e');
      }
    }
  }

  int stringToDuration(String str) {
    if (!str.contains(':')) {
      return int.tryParse(str) ?? 0;
    }

    final value = str.split(':');

    if (value.length == 2) {
      return (int.tryParse(value[0]) ?? 0) * 60 + (int.tryParse(value[1]) ?? 0);
    }

    if (value.length == 3) {
      return (int.tryParse(value[0]) ?? 0) * 3600 +
          (int.tryParse(value[1]) ?? 0) * 60 +
          (int.tryParse(value[2]) ?? 0);
    }

    return 0;
  }

  Future<List> searchQuery(String query, {int limit = 10}) async {
    try {
      final videos = [];

      // filter: yt.TypeFilters.video,
      final results = await _ytExplode.search.searchContent(query);
      for (final video in results) {
        if (video is yt.SearchVideo) {
          videos.add(
            ExtractedVideoInfo(
              type: "video",
              channelId: video.channelId,
              uploadDate: video.uploadDate,
              viewCount: video.viewCount,
              isLive: video.isLive,
              id: video.id.value,
              url: 'https://www.youtube.com/watch?v=${video.id.value}',
              title: video.title,
              description: video.description,
              author: video.author,
              thumbnailUrl: video.thumbnails.last.url.toString(),
              durationSeconds: stringToDuration(video.duration),
              formats: const [],
            ),
          );
        } else if (video is yt.SearchChannel) {
          videos.add(
            ExtractedChannelInfo(
              type: "channel",
              id: video.id.value,
              url: 'https://www.youtube.com/channel/${video.id.value}',
              description: video.description,
              author: video.name,
              videoCount: video.videoCount,
              thumbnailUrl: video.thumbnails.last.url.toString(),
            ),
          );
        } else if (video is yt.SearchPlaylist) {
          videos.add(
            ExtractedPlaylistInfo(
              type: "playlist",
              id: video.id.value,
              url: 'https://www.youtube.com/playlist?list=${video.id.value}',
              title: video.title,
              videoCount: video.videoCount,
              thumbnailUrl: video.thumbnails,
            ),
          );
        } else {
          print('else data');
        }
      }

      if (videos.isEmpty) {
        final results = await _ytExplode.search.search(query);
        for (final video in results) {
          videos.add(
            ExtractedVideoInfo(
              type: "video",
              channelId: video.channelId.value,
              uploadDate: video.uploadDateRaw,
              viewCount: 10,
              isLive: video.isLive,
              id: video.id.value,
              url: 'https://www.youtube.com/watch?v=${video.id.value}',
              title: video.title,
              description: video.description,
              author: video.author,
              thumbnailUrl: video.thumbnails.highResUrl,
              durationSeconds: video.duration!.inSeconds,
              formats: const [],
            ),
          );
        }
        return videos;
      } else {
        return videos;
      }
    } catch (e, stackTrace) {
      debugPrint('Video search failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      try {
        final videos = [];
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

        for (final video in data['items']) {
          videos.add(
            ExtractedVideoInfo(
              type: "video",
              channelId: video["snippet"]["channel123"],
              uploadDate: video["snippet"]["publishedAt"],
              viewCount: 0,
              isLive: video['snippet']['liveBroadcastContent'] == 'live',
              id: video["id"]["videoId"],
              url: 'https://www.youtube.com/watch?v=${video['id']['videoId']}',
              title: video["snippet"]["title"],
              description: video["snippet"]["description"],
              author: video["snippet"]["channelTitle"],
              thumbnailUrl: video["snippet"]["thumbnails"]["high"]["url"],
              durationSeconds: 0,
              formats: const [],
            ),
          );
        }
        return videos;
      } catch (error) {
        debugPrint("Internet not avalable: No search");
        // ScaffoldMessenger.of(context).showSnackBar(
        //   const SnackBar(
        //     content: Row(
        //       children: [
        //         Icon(CupertinoIcons.globe),
        //         SizedBox(width: 10),
        //         Text('Internet not available'),
        //       ],
        //     ),
        //   ),
        // );
        return [];
      }
    }
  }

  Future<List<ExtractedVideoInfo>> searchVideos(
    String query, {
    int limit = 10,
  }) async {
    try {
      final videos = <ExtractedVideoInfo>[];

      final results = await _ytExplode.search.search(
        query,
        filter: yt.TypeFilters.video,
      );

      // for (final item in results) {
      //   if (item is yt.SearchVideo) {
      //     print('Videohai video: ${item.title}');
      //   } else if (item is yt.SearchChannel) {
      //     print('Videohai Channel: ${item.name}');
      //   } else if (item is yt.SearchPlaylist) {
      //     print('Videohai Playlist: ${item.title}');
      //   } else {
      //     print('Videohai pata nahi ${item.thumbnails}');
      //   }
      // }

      for (final video in results) {
        // Don't include duplicates.
        if (videos.any((item) => item.id == video.id.value)) {
          continue;
        }

        // type: "video",
        //               channelId: video.channelId.value,
        //               viewCount: 10,
        //               isLive: video.isLive,
        //               id: video.id.value,
        //               url: 'https://www.youtube.com/watch?v=${video.id.value}',
        //               title: video.title,
        //               description: video.description,
        //               author: video.author,
        //               thumbnailUrl: video.thumbnails.highResUrl,
        //               durationSeconds: video.duration!.inSeconds,
        //               formats: const [],
        videos.add(
          ExtractedVideoInfo(
            id: video.id.value,
            url: 'https://www.youtube.com/watch?v=${video.id.value}',
            title: video.title,
            description: video.description,
            uploadDate: video.uploadDateRaw,
            author: video.author,
            thumbnailUrl: video.thumbnails.highResUrl.isNotEmpty
                ? video.thumbnails.highResUrl
                : video.thumbnails.standardResUrl,
            durationSeconds: video.duration?.inSeconds ?? 0,
            formats: const [],
          ),
        );

        if (videos.length >= limit) break;
      }

      return videos;
    } catch (e, stackTrace) {
      debugPrint('Video search failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return [];
    }
  }

  Future<yt.Channel> getChannel(channelId) async {
    final yt.Channel result = await _ytExplode.channels.get(channelId);
    return result;
  }

  Future getChannelInfo(channelId, _activeTab) async {
    final result = await _ytExplode.channels.getUploadsFromPage(
      channelId,
      videoType: _activeTab == 1 ? yt.VideoType.shorts : yt.VideoType.normal,
    );
    return result;
  }

  /// Validate if URL is a valid web media URL
  bool isValidUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
  }

  /// Clean & normalize URL
  String cleanUrl(String rawUrl) {
    return rawUrl.trim();
  }

  /// Extract video metadata and available formats directly on Android/client
  Future<ExtractedVideoInfo> extractInfo(String rawUrl) async {
    final url = cleanUrl(rawUrl);
    if (!isValidUrl(url)) {
      throw Exception(
        'Invalid URL format. Please provide a valid HTTP/HTTPS link.',
      );
    }

    // Try YouTubeExplode first (lightning fast Dart client-side extraction)
    try {
      final videoId = yt.VideoId(url);
      final results = await Future.wait([
        _ytExplode.videos.get(videoId),
        _ytExplode.videos.streamsClient.getManifest(videoId),
      ]);
      final video = results[0] as yt.Video;
      final manifest = results[1] as yt.StreamManifest;

      final List<ExtractedFormat> formats = [];

      // Muxed streams (both video & audio combined into single MP4)
      for (final s in manifest.muxed) {
        formats.add(
          ExtractedFormat(
            formatId: 'muxed_${s.tag}',
            qualityLabel: '${s.videoQuality.name} (Video + Audio)',
            height: s.videoResolution.height,
            fps: s.framerate.framesPerSecond.toInt(),
            sizeBytes: s.size.totalBytes,
            container: s.container.name,
            hasVideo: true,
            hasAudio: true,
            streamUrl: s.url.toString(),
            videoUrl: s.url.toString(),
          ),
        );
      }

      // Audio only streams
      final bestAudio = manifest.audioOnly.withHighestBitrate();

      formats.add(
        ExtractedFormat(
          formatId: 'audio_${bestAudio.tag}',
          qualityLabel:
              'Audio Only (${bestAudio.bitrate.kiloBitsPerSecond.round()} kbps)',
          sizeBytes: bestAudio.size.totalBytes,
          container: bestAudio.container.name,
          hasVideo: false,
          hasAudio: true,
          videoUrl: null,
          streamUrl: bestAudio.url.toString(),
        ),
      );

      // Sort formats: video+audio first, then descending height
      formats.sort((a, b) {
        if (a.hasVideo && a.hasAudio && !(b.hasVideo && b.hasAudio)) return -1;
        if (!(a.hasVideo && a.hasAudio) && (b.hasVideo && b.hasAudio)) return 1;
        if (a.hasVideo && !b.hasVideo) return -1;
        if (!a.hasVideo && b.hasVideo) return 1;
        return (b.height ?? 0).compareTo(a.height ?? 0);
      });

      return ExtractedVideoInfo(
        id: video.id.value,
        url: url,
        title: video.title,
        description: video.description,
        author: video.author,
        thumbnailUrl: video.thumbnails.highResUrl.isNotEmpty
            ? video.thumbnails.highResUrl
            : video.thumbnails.standardResUrl,
        durationSeconds: video.duration!.inSeconds,
        formats: formats,
      );
    } catch (ytError) {
      debugPrint(
        'YouTubeExplode extraction note: $ytError. Attempting ytdlp_flutter...',
      );

      // Secondary check using Ytdlp.getVideoInfo
      try {
        await _ensureYtdlpInit();
        final info = await ytdlp.Ytdlp.getVideoInfo(url);
        final raw = info.raw;
        final formats = <ExtractedFormat>[];

        if (raw != null && raw['formats'] is List) {
          for (final f in raw['formats']) {
            if (f is Map) {
              final vcodec = f['vcodec']?.toString() ?? 'none';
              final acodec = f['acodec']?.toString() ?? 'none';
              final hasV = vcodec != 'none';
              final hasA = acodec != 'none';
              final height = (f['height'] as num?)?.toInt();
              final note =
                  f['format_note']?.toString() ??
                  (height != null ? '${height}p' : 'Auto');

              // Filter out silent video-only streams without audio
              if (!hasA) continue;

              formats.add(
                ExtractedFormat(
                  formatId: (f['format_id'] ?? formats.length).toString(),
                  qualityLabel: hasV ? '$note (Video+Audio)' : 'Audio ($note)',
                  height: height,
                  fps: (f['fps'] as num?)?.toInt(),
                  sizeBytes: (f['filesize'] as num?)?.toInt(),
                  container: f['ext']?.toString() ?? 'mp4',
                  hasVideo: hasV,
                  hasAudio: hasA,
                  videoUrl: null,
                  streamUrl: f['url']?.toString() ?? '',
                ),
              );
            }
          }
        }

        return ExtractedVideoInfo(
          id: info.id.isNotEmpty
              ? info.id
              : DateTime.now().millisecondsSinceEpoch.toString(),
          url: url,
          title: info.title.isNotEmpty ? info.title : 'Extracted Video',
          description: raw?['description']?.toString(),
          author: info.uploader,
          thumbnailUrl: info.thumbnailUrl,
          durationSeconds: info.durationSeconds!.toInt(),
          formats: formats,
        );
      } catch (ytdlpErr) {
        debugPrint('ytdlp_flutter exception: $ytdlpErr');
      }
      throw Exception(
        'Could not extract media info. Please verify the link is valid and public.',
      );
    }
  }

  void dispose() {
    _ytExplode.close();
  }
}
