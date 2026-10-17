import 'package:flutter/material.dart';
import 'package:offlinetube/features/downloader/add_video_modal.dart';

void openAddVideoModalBasic(BuildContext context, {String? initialUrl}) async {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => AddVideoModal(initialUrl: initialUrl),
  );
}
