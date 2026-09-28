import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:share_handler/share_handler.dart';

class ShareIntentService {
  static ShareIntentService? _instance;
  static ShareIntentService get instance =>
      _instance ??= ShareIntentService._();
  ShareIntentService._();

  StreamSubscription? _intentSubscription;
  final ValueNotifier<String?> sharedUrlNotifier = ValueNotifier<String?>(null);

  Future<void> init() async {
    final handler = ShareHandlerPlatform.instance;

    // Handle initial shared payload if app was opened from another app's share action
    try {
      final SharedMedia? media = await handler.getInitialSharedMedia();
      _handleSharedMedia(media);
    } catch (e) {
      debugPrint('ShareHandler initial media note: $e');
    }

    // Handle incoming shared media while app is running
    try {
      _intentSubscription = handler.sharedMediaStream.listen((SharedMedia media) {
        _handleSharedMedia(media);
      });
    } catch (e) {
      debugPrint('ShareHandler stream note: $e');
    }
  }

  void _handleSharedMedia(SharedMedia? media) {
    if (media == null) return;
    final text = media.content;
    if (text != null && text.trim().isNotEmpty) {
      // Find URLs in shared text
      final urlRegExp = RegExp(r'https?://[^\s]+');
      final match = urlRegExp.firstMatch(text);
      if (match != null) {
        sharedUrlNotifier.value = match.group(0);
      } else if (text.startsWith('http://') || text.startsWith('https://')) {
        sharedUrlNotifier.value = text.trim();
      }
    }
  }

  void clearSharedUrl() {
    sharedUrlNotifier.value = null;
  }

  void dispose() {
    _intentSubscription?.cancel();
  }
}
