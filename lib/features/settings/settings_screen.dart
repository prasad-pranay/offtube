import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/database/database_service.dart';
import '../../services/storage/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onThemeChanged;

  const SettingsScreen({
    super.key,
    required this.onThemeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoplayNext = true;
  bool _rememberPosition = true;
  String _defaultQuality = '1080p';
  bool _wifiOnly = false;
  String _themeMode = 'dark';
  int _storageUsedBytes = 0;
  int _videoCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = DatabaseService.instance;
    final videos = db.getAllVideos();
    final used = await StorageService.instance.getTotalStorageUsedBytes();

    setState(() {
      _autoplayNext = db.getSetting('autoplay_next', true);
      _rememberPosition = db.getSetting('remember_position', true);
      _defaultQuality = db.getSetting('default_quality', '1080p');
      _wifiOnly = db.getSetting('wifi_only', false);
      _themeMode = db.getSetting('theme_mode', 'dark');
      _storageUsedBytes = used;
      _videoCount = videos.length;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  void _confirmClearStorage() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all downloads?'),
        content: const Text(
          'This will permanently delete all downloaded videos, audio files, and thumbnails from your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService.instance.clearAllStorage();
              await DatabaseService.instance.clearAllVideos();
              await _loadSettings();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All downloads cleared.')),
                );
              }
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        children: [
          // Storage Management Section
          _buildSectionHeader('Storage & Data', theme),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Used Storage', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            '$_videoCount offline videos',
                            style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                          ),
                        ],
                      ),
                      Text(
                        _formatBytes(_storageUsedBytes),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _confirmClearStorage,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent, width: 0.8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                      label: const Text('Clear All Downloads'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Playback Settings
          _buildSectionHeader('Playback', theme),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Autoplay Next Video'),
                  subtitle: const Text('Automatically play subsequent videos in library'),
                  activeThumbColor: AppTheme.accentColor,
                  value: _autoplayNext,
                  onChanged: (val) {
                    setState(() => _autoplayNext = val);
                    DatabaseService.instance.setSetting('autoplay_next', val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Remember Playback Position'),
                  subtitle: const Text('Resume watched videos from where you left off'),
                  activeThumbColor: AppTheme.accentColor,
                  value: _rememberPosition,
                  onChanged: (val) {
                    setState(() => _rememberPosition = val);
                    DatabaseService.instance.setSetting('remember_position', val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Downloads Settings
          _buildSectionHeader('Downloads', theme),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Default Quality'),
                  subtitle: Text(_defaultQuality),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Default Quality', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            ...['Best Available', '1080p', '720p', '480p', 'Audio Only'].map((q) {
                              return ListTile(
                                title: Text(q),
                                trailing: _defaultQuality == q
                                    ? const Icon(Icons.check_rounded, color: AppTheme.accentColor)
                                    : null,
                                onTap: () {
                                  setState(() => _defaultQuality = q);
                                  DatabaseService.instance.setSetting('default_quality', q);
                                  Navigator.pop(ctx);
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Wi-Fi Only Downloads'),
                  subtitle: const Text('Avoid downloading videos over cellular mobile data'),
                  activeThumbColor: AppTheme.accentColor,
                  value: _wifiOnly,
                  onChanged: (val) {
                    setState(() => _wifiOnly = val);
                    DatabaseService.instance.setSetting('wifi_only', val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Appearance Settings
          _buildSectionHeader('Appearance', theme),
          Card(
            child: ListTile(
              title: const Text('Theme'),
              subtitle: Text(_themeMode.toUpperCase()),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        ...['dark', 'light', 'system'].map((m) {
                          return ListTile(
                            title: Text(m.toUpperCase()),
                            trailing: _themeMode == m
                                ? const Icon(Icons.check_rounded, color: AppTheme.accentColor)
                                : null,
                            onTap: () {
                              setState(() => _themeMode = m);
                              DatabaseService.instance.setSetting('theme_mode', m);
                              widget.onThemeChanged();
                              Navigator.pop(ctx);
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // About Section
          _buildSectionHeader('About', theme),
          Card(
            child: Column(
              children: [
                const ListTile(
                  title: Text('OfflineTube'),
                  subtitle: Text('Version 1.0.0 • Pure offline playback & downloader'),
                  leading: Icon(Icons.offline_bolt_rounded, color: AppTheme.accentColor),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Open Source Licenses'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showLicensePage(context: context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: theme.textTheme.bodySmall?.color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
