import 'dart:io';

import 'Backend/localmusic.dart';

import 'package:flutter/material.dart';
import 'package:mimic/appcolors.dart';

import 'Backend/settings.dart';
import 'Backend/searchHistory.dart';
import 'Backend/createDownloadDir.dart';
import 'Backend/metadatamanager.dart';
import 'Backend/providers/privdersenums.dart';
import 'playing_trackui.dart';

class SettingsMenu extends StatefulWidget {
  const SettingsMenu({super.key});

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  final _s = AppSettings.instance;
  int? _downloadsBytes;

  @override
  void initState() {
    super.initState();
    _s.addListener(_refresh);
    Metadatamanager.instance.addListener(_refresh);
    _loadDownloadsSize();
  }

  @override
  void dispose() {
    _s.removeListener(_refresh);
    Metadatamanager.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDownloadsSize() async {
    var total = 0;
    try {
      final dir = await getDownloadDirectory();
      if (await dir.exists()) {
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Settings: error calculando descargas -> $e');
    }
    if (!mounted) return;
    setState(() => _downloadsBytes = total);
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    final kb = b / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  Future<void> _confirmClearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(
          'Clear search history',
          style: TextStyle(
            color: AppColors.text,
            fontFamily: 'Adwaita',
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Remove all your recent searches?',
          style: TextStyle(color: AppColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await SearchHistory.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Search history cleared')));
  }

  String _providerLabel(metadataprovider p) {
    switch (p) {
      case metadataprovider.deezer:
        return 'Deezer';
      case metadataprovider.soundcloud:
        return 'SoundCloud';
      case metadataprovider.itunes:
        return 'iTunes';
      case metadataprovider.musicbrainz:
        return 'MusicBrainz';
      case metadataprovider.local:
        return "";
    }
  }

  void _showProviderPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            for (final p in metadataprovider.selectable)
              ListTile(
                title: Text(
                  _providerLabel(p),
                  style: TextStyle(
                    color: p == _s.defaultMetadataProvider
                        ? AppColors.accent
                        : AppColors.text,
                    fontFamily: 'Adwaita',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: p == _s.defaultMetadataProvider
                    ? Icon(Icons.check, color: AppColors.accent)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _s.setDefaultMetadataProvider(p);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          letterSpacing: 1.2,
          color: AppColors.accent,
          fontFamily: "Adwaita",
          fontWeight: FontWeight.w800,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 30, color: AppColors.text),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.text,
          fontFamily: 'Adwaita',
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(color: AppColors.text2)),
      trailing: trailing,
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _tile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accentTeammate
              : AppColors.text2,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.bordier,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }

  Widget _swatch(AppPalette p) {
    final selected = p.id == _s.palette.id;
    final t = p.theme;

    return SizedBox(
      width: 64,
      child: GestureDetector(
        onTap: () => _s.setPalette(p),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.bordier,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.text : t.bordierlight,
                  width: selected ? 3 : 2,
                ),
              ),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: p.adaptive ? null : t.accent,
                  gradient: p.adaptive
                      ? const SweepGradient(
                          colors: [
                            Color(0xFFFF5C8A),
                            Color(0xFFFFB74D),
                            Color(0xFF81C784),
                            Color(0xFF4FC3F7),
                            Color(0xFFBA68C8),
                            Color(0xFFFF5C8A),
                          ],
                        )
                      : null,
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? Icon(
                        Icons.check,
                        size: 20,
                        color: p.adaptive ? Colors.black : t.onAccent,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppColors.text : AppColors.text2,
                fontFamily: 'Adwaita',
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 110),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
                    child: Row(
                      children: [
                        if (Navigator.canPop(context))
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(
                              Icons.arrow_back,
                              size: 30,
                              color: AppColors.text,
                            ),
                          )
                        else
                          const SizedBox(width: 8),
                        const Text(
                          "Settings",
                          style: TextStyle(
                            fontSize: 30,
                            color: AppColors.text,
                            fontFamily: "Adwaita",
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ─── Apariencia ───
                  _section('Appearance'),
                  _tile(
                    icon: Icons.palette_outlined,
                    title: 'Color palette',
                    subtitle:
                        'Material colors. Tints backgrounds and highlights',
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        for (final p in AppSettings.palettes) _swatch(p),
                      ],
                    ),
                  ),

                  // ─── Fondo del reproductor (NUEVO) ───
                  _section('Player background'),
                  _switchTile(
                    icon: Icons.blur_on,
                    title: 'Blurred artwork background',
                    subtitle:
                        'Fill the player with a blurred copy of the artwork',
                    value: _s.playerBlurBackground,
                    onChanged: _s.setPlayerBlurBackground,
                  ),
                  _switchTile(
                    icon: Icons.fullscreen,
                    title: 'Large artwork banner',
                    subtitle:
                        'Show the artwork full-width behind the track info',
                    value: _s.playerLargeBannerBackground,
                    onChanged: _s.setPlayerLargeBannerBackground,
                  ),

                  // ─── Fuentes de música ───
                  _section('Music sources'),
                  _tile(
                    icon: Icons.travel_explore,
                    title: 'Default metadata source',
                    subtitle:
                        '${_providerLabel(_s.defaultMetadataProvider)}. Used every time the app starts',
                    trailing: Icon(Icons.chevron_right, color: AppColors.text2),
                    onTap: _showProviderPicker,
                  ),

                  _section('Local music'),
                  ListenableBuilder(
                    listenable: LocalMusicManager.instance,
                    builder: (context, _) {
                      final lm = LocalMusicManager.instance;
                      return Column(
                        children: [
                          _tile(
                            icon: Icons.phone_android_rounded,
                            title: lm.enabled
                                ? 'Rescan device'
                                : 'Scan device for music',
                            subtitle: lm.scanning
                                ? 'Scanning...'
                                : lm.error ??
                                      (lm.enabled
                                          ? '${lm.songs.length} songs found. Shown in your Library'
                                          : 'Add the audio files stored on this phone to your Library'),
                            trailing: lm.scanning
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.accent,
                                    ),
                                  )
                                : null,
                            onTap: lm.scanning ? null : lm.scan,
                          ),
                          if (lm.enabled)
                            _tile(
                              icon: Icons.visibility_off_outlined,
                              title: 'Hide local music',
                              subtitle: 'Removes the section from your Library',
                              onTap: lm.disable,
                            ),
                        ],
                      );
                    },
                  ),

                  // ─── Búsqueda ───
                  _section('Search'),
                  _switchTile(
                    icon: Icons.history,
                    title: 'Save search history',
                    subtitle: 'Remember what you search for',
                    value: _s.saveSearchHistory,
                    onChanged: _s.setSaveSearchHistory,
                  ),
                  _tile(
                    icon: Icons.delete_outline,
                    title: 'Clear search history',
                    onTap: _confirmClearHistory,
                  ),

                  // ─── Reproductor ───
                  _section('Player'),
                  _switchTile(
                    icon: Icons.lyrics_outlined,
                    title: 'Show lyrics',
                    subtitle: 'Turn off to save data',
                    value: _s.showLyrics,
                    onChanged: _s.setShowLyrics,
                  ),
                  _tile(
                    icon: Icons.swap_horiz,
                    title: 'Crossfade',
                    subtitle: _s.crossfadeSeconds == 0
                        ? 'Off'
                        : 'Songs fade out and in over ${_s.crossfadeSeconds} s',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: AppColors.bordier,
                        thumbColor: AppColors.accent,
                        overlayColor: AppColors.accent.withValues(alpha: 0.12),
                        valueIndicatorColor: AppColors.accent,
                        valueIndicatorTextStyle: TextStyle(
                          color: AppColors.accentTeammate,
                          fontWeight: FontWeight.w700,
                        ),
                        activeTickMarkColor: Colors.transparent,
                        inactiveTickMarkColor: Colors.transparent,
                      ),
                      child: Slider(
                        value: _s.crossfadeSeconds.toDouble(),
                        min: 0,
                        max: 12,
                        divisions: 12,
                        label: _s.crossfadeSeconds == 0
                            ? 'Off'
                            : '${_s.crossfadeSeconds} s',
                        onChanged: (v) => _s.setCrossfadeSeconds(v.round()),
                      ),
                    ),
                  ),

                  // ─── Descargas ───
                  _section('Downloads'),
                  _tile(
                    icon: Icons.storage_outlined,
                    title: 'Storage used',
                    subtitle: _downloadsBytes == null
                        ? 'Calculating...'
                        : _fmtBytes(_downloadsBytes!),
                    trailing: IconButton(
                      icon: Icon(Icons.refresh, color: AppColors.text2),
                      onPressed: () {
                        setState(() => _downloadsBytes = null);
                        _loadDownloadsSize();
                      },
                    ),
                  ),
                  _tile(
                    icon: Icons.download_for_offline_outlined,
                    title: 'Simultaneous downloads',
                    subtitle: 'Songs downloaded at the same time',
                    trailing: SizedBox(
                      width: 130,
                      height: 40,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          backgroundColor: AppColors.bordier,
                          foregroundColor: AppColors.accent,
                          selectedForegroundColor: AppColors.accentTeammate,
                          selectedBackgroundColor: AppColors.accent,
                          overlayColor: AppColors.surface,
                        ),
                        segments: const [
                          ButtonSegment(value: 1, label: Text('1')),
                          ButtonSegment(value: 2, label: Text('2')),
                          ButtonSegment(value: 3, label: Text('3')),
                        ],
                        selected: {_s.downloadConcurrency},
                        onSelectionChanged: (v) =>
                            _s.setDownloadConcurrency(v.first),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (Metadatamanager.instance.currentSong != null)
              Align(alignment: Alignment.bottomCenter, child: PlayingTrackui()),
          ],
        ),
      ),
    );
  }
}
