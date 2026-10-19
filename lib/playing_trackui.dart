import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mimic/appcolors.dart';
import 'package:mimic/player.dart';

import "Backend/marqueeDecider.dart";
import 'Backend/metadatamanager.dart';
import 'Backend/audiomanager.dart';

class PlayingTrackui extends StatefulWidget {
  const PlayingTrackui({super.key});

  @override
  State<PlayingTrackui> createState() => _PlayingTrackuiState();
}

class _PlayingTrackuiState extends State<PlayingTrackui> {
  static const double _height = 52;
  static const double _bannerSize = 40;

  static const _titleStyle = TextStyle(
    color: AppColors.text,
    fontSize: 14,
    fontFamily: "Adwaita",
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
  );

  static const _artistStyle = TextStyle(
    color: AppColors.text2,
    fontSize: 12,
    fontFamily: "Adwaita",
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.none,
  );

  var oldCurrentSong = Metadatamanager.instance.currentSong!;

  @override
  void initState() {
    super.initState();
    Metadatamanager.instance.addListener(_onPlayerStateChanged);
  }

  @override
  void dispose() {
    Metadatamanager.instance.removeListener(_onPlayerStateChanged);
    super.dispose();
  }

  void _onPlayerStateChanged() {
    final currentSong = Metadatamanager.instance.currentSong;
    if (currentSong != null && currentSong.id != oldCurrentSong.id) {
      setState(() => oldCurrentSong = currentSong);
    }
  }

  Widget _placeholder() => Container(
    color: AppColors.background,
    child: const Icon(Icons.music_note, color: AppColors.text2, size: 20),
  );

  Widget _banner() {
    if (oldCurrentSong.downloadBannerPath != null) {
      return Image.file(
        File(oldCurrentSong.downloadBannerPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    final url = oldCurrentSong.thumbnails.isNotEmpty
        ? oldCurrentSong.thumbnails[3].url
        : '';
    if (url.isEmpty) return _placeholder();
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _controlButton({
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: icon,
      iconSize: 30,
      color: AppColors.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: AppColors.bordier,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.push(context, PlayerRoute()),
            child: SizedBox(
              height: _height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Row(
                      children: [
                        // Portada
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: _bannerSize,
                              height: _bannerSize,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: KeyedSubtree(
                                  key: ValueKey(oldCurrentSong.id),
                                  child: _banner(),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Título + artista
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: Column(
                                key: ValueKey(oldCurrentSong.id),
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AutoMarquee(
                                    text: oldCurrentSong.name,
                                    style: _titleStyle,
                                  ),
                                  AutoMarquee(
                                    text: oldCurrentSong.artists
                                        .map((a) => a.name)
                                        .join(', '),
                                    style: _artistStyle,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Controles
                        AnimatedBuilder(
                          animation: AudioPlayerManager.instance,
                          builder: (context, _) => _controlButton(
                            icon: AudioPlayerManager.instance
                                .consultPlayerState(),
                            onPressed:
                                AudioPlayerManager.instance.togglePlayPause,
                          ),
                        ),
                        _controlButton(
                          icon: const Icon(Icons.skip_next),
                          onPressed: AudioPlayerManager.instance.playnext,
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),

                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _MiniProgress(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniProgress extends StatefulWidget {
  final Duration? fallbackDuration;
  const _MiniProgress({this.fallbackDuration});

  @override
  State<_MiniProgress> createState() => _MiniProgressState();
}

class _MiniProgressState extends State<_MiniProgress> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = AudioPlayerManager.instance.player;

    final posMs = player.position.inMilliseconds;
    final totalMs =
        (player.duration ?? widget.fallbackDuration ?? Duration.zero)
            .inMilliseconds;
    final value = totalMs > 0
        ? (posMs / totalMs).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Container(
                width: constraints.maxWidth,
                height: 3,
                color: Colors.white.withOpacity(0.12),
              ),
              Container(
                width: constraints.maxWidth * value,
                height: 3,
                color: AppColors.accent,
              ),
            ],
          );
        },
      ),
    );
  }
}
