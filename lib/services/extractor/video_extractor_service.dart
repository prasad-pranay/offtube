import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:ytdlp_flutter/ytdlp_flutter.dart' as ytdlp;
import 'extracted_video_info.dart';

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
      final video = await _ytExplode.videos.get(videoId);
      final manifest = await _ytExplode.videos.streamsClient.getManifest(
        videoId,
      );

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
        durationSeconds: video.duration?.inSeconds ?? 0,
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
          durationSeconds: info.durationSeconds?.toInt() ?? 0,
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
