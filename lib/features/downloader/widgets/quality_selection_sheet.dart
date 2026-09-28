import 'package:flutter/material.dart';
import 'package:offlinetube/core/theme/app_theme.dart';
import 'package:offlinetube/services/extractor/extracted_video_info.dart';
import 'package:offlinetube/services/download/download_manager.dart';

class QualitySelectionSheet extends StatefulWidget {
  final ExtractedVideoInfo info;

  const QualitySelectionSheet({
    super.key,
    required this.info,
  });

  @override
  State<QualitySelectionSheet> createState() => _QualitySelectionSheetState();
}

class _QualitySelectionSheetState extends State<QualitySelectionSheet> {
  ExtractedFormat? _selectedFormat;

  @override
  void initState() {
    super.initState();
    if (widget.info.formats.isNotEmpty) {
      _selectedFormat = widget.info.formats.first;
    }
  }

  void _startDownload() {
    if (_selectedFormat == null) return;

    DownloadManager.instance.enqueueDownload(
      videoId: widget.info.id,
      title: widget.info.title,
      author: widget.info.author,
      description: widget.info.description,
      thumbnailUrl: widget.info.thumbnailUrl,
      durationSeconds: widget.info.durationSeconds,
      qualityLabel: _selectedFormat!.qualityLabel,
      streamUrl: _selectedFormat!.streamUrl,
      formatId: _selectedFormat!.formatId,
      container: _selectedFormat!.container,
      totalBytes: _selectedFormat!.sizeBytes ?? 0,
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading "${widget.info.title}"'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Video preview card
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.info.thumbnailUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    widget.info.thumbnailUrl!,
                    width: 100,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 100,
                      height: 64,
                      color: theme.colorScheme.surface,
                      child: const Icon(Icons.video_library_rounded, color: AppTheme.accentColor),
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.info.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.info.author ?? 'Unknown author'} • ${widget.info.formattedDuration}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Select Quality',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          // Formats list
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.info.formats.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final format = widget.info.formats[index];
                final isSelected = _selectedFormat == format;

                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedFormat = format;
                    });
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accentColor.withAlpha(25)
                          : theme.cardTheme.color,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.accentColor
                            : theme.colorScheme.outline.withAlpha(40),
                        width: isSelected ? 1.5 : 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          format.hasVideo
                              ? Icons.hd_outlined
                              : Icons.audiotrack_rounded,
                          color: isSelected ? AppTheme.accentColor : theme.textTheme.bodySmall?.color,
                          size: 22,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                format.qualityLabel,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${format.container.toUpperCase()}${format.fps != null ? ' • ${format.fps} fps' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textTheme.bodySmall?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (format.formattedSize.isNotEmpty)
                          Text(
                            format.formattedSize,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? AppTheme.accentColor : theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        const SizedBox(width: 8),
                        Icon(
                          isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                          color: isSelected ? AppTheme.accentColor : theme.textTheme.bodySmall?.color,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          // Download button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _selectedFormat != null ? _startDownload : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.download_rounded),
              label: const Text(
                'Download Video',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
