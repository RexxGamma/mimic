import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mimic/3dotssongs.dart';
import 'package:mimic/Backend/queuemanager.dart';
import 'package:mimic/Backend/songdata.dart';
import 'package:mimic/appcolors.dart';
import 'package:mimic/player.dart';

import 'Backend/historydb.dart';
import 'menu.dart';

import 'Backend/metadatamanager.dart';
import 'Backend/audiomanager.dart';
import '3dotsmanager.dart';

import 'package:lottie/lottie.dart';

import 'Backend/songlisttoplay.dart';

import 'package:provider/provider.dart';

var menu = MainMenuState;

class Onesong extends StatefulWidget {
  final SongInfo song;
  final bool? thredots;
  final int? index;
  final bool? hideplayingnow;

  final dynamic albumtracks;

  const Onesong({
    super.key,
    required this.song,
    this.thredots,
    this.index,
    this.albumtracks,
    this.hideplayingnow,
  });

  @override
  State<Onesong> createState() => _OnesongState();
}

class _OnesongState extends State<Onesong> {
  static const double _size = 48;

  static const _titleStyle = TextStyle(
    color: AppColors.text,
    fontSize: 13,
    fontFamily: "Adwaita",
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
  );

  static const _artistStyle = TextStyle(
    color: AppColors.text2,
    fontSize: 11,
    fontFamily: "Adwaita",
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.none,
  );

  static const _metaStyle = TextStyle(
    color: AppColors.text2,
    fontSize: 8,
    fontFamily: "Adwaita",
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.none,
  );

  @override
  void initState() {
    super.initState();
    Metadatamanager.instance.addListener(_updateBanner);
  }

  @override
  void dispose() {
    Metadatamanager.instance.removeListener(_updateBanner);
    super.dispose();
  }

  bool isCurrentSong(SongInfo song) {
    return widget.song.id == Metadatamanager.instance.currentSong?.id &&
        widget.song.source == Metadatamanager.instance.currentSong?.source;
  }

  void _updateBanner() {
    debugPrint("Queso Lol ekisde");
    if (mounted) setState(() {});
  }

  void _onSongTap() {
    if (widget.thredots != null) {
      return;
    }

    if (SongContextManager.current == SongSource.album ||
        SongContextManager.current == SongSource.playlist) {
      QueueManager.instance.clear();
      QueueManager.instance.addAll(widget.albumtracks);
    } else {}

    if (Metadatamanager.instance.currentSong == null) {
      Navigator.push(context, PlayerRoute());
    }

    mainMenuKey.currentState?.updatepreviewplayer(widget.song);

    Metadatamanager.instance.startRadioFrom(widget.song);

    AudioPlayerManager.instance.play(widget.song);
    HistoryDatabase.instance.record(widget.song);
  }

  Widget banner() {
    if (SongContextManager.current == SongSource.album &&
        widget.index != null) {
      return Align(
        alignment: Alignment.center,
        child: Text(
          "${widget.index}",
          style: const TextStyle(fontSize: 20.0, color: AppColors.text),
        ),
      );
    }

    if (widget.song.downloadBannerPath != null) {
      return Container(
        color: AppColors.bordier,
        child: Image.file(
          File(widget.song.downloadBannerPath!),
          cacheWidth: 100,
          gaplessPlayback: true,
          fit: BoxFit.cover,
          width: _size,
          height: _size,
        ),
      );
    }

    final url = widget.song.thumbnails.isNotEmpty
        ? widget.song.thumbnails.last.url
        : '';
    if (url.isEmpty) {
      return Container(
        color: AppColors.background,
        child: const Icon(Icons.music_note, size: 100, color: AppColors.text2),
      );
    }

    return Container(
      color: AppColors.bordier,
      child: Image.network(
        url,
        cacheWidth: 100,
        gaplessPlayback: true,
        fit: BoxFit.cover,
        width: _size,
        height: _size,
        errorBuilder: (_, __, ___) => Container(
          color: AppColors.background,
          child: const Icon(
            Icons.music_note,
            size: 100,
            color: AppColors.text2,
          ),
        ),
      ),
    );
  }

  Widget animBanner() {
    if (widget.hideplayingnow == true) {
      return banner();
    }
    if (widget.index != null) {
      return Lottie.asset('resources/wave.json', fit: BoxFit.contain);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        banner(),
        const ColoredBox(color: Color(0xB3000000)), //70%
        Lottie.asset('resources/wave.json', fit: BoxFit.contain),
      ],
    );
  }

  Widget _dot() => const Text(" • ", style: _metaStyle);

  @override
  Widget build(BuildContext context) {
    final current = isCurrentSong(widget.song);

    final isFav = context.select<SongDatabase, bool>(
      (db) => db.isFavoriteSync(widget.song.id),
    );

    return RepaintBoundary(
      child: Material(
        color: AppColors.background,
        child: InkWell(
          onTap: _onSongTap,
          splashColor: Colors.white.withOpacity(0.08),
          highlightColor: Colors.white.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    width: _size,
                    height: _size,
                    child: current ? animBanner() : banner(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.song.name,
                        style: _titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.song.artists.map((a) => a.name).join(', '),
                        style: _artistStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          if (widget.song.isLocal)
                            Text(
                              'Device',
                              style: _metaStyle.copyWith(
                                color: Color(0xFF4DB6AC),
                              ),
                            )
                          else ...[
                            Text(
                              widget.song.source.label,
                              style: _metaStyle.copyWith(
                                color: widget.song.source.color,
                              ),
                            ),
                            _dot(),
                            Text(
                              widget.song.streamingSource.label,
                              style: _metaStyle.copyWith(
                                color: widget.song.streamingSource.color,
                              ),
                            ),
                          ],
                          if (widget.song.downloadPath != null &&
                              !widget.song.isLocal) ...[
                            _dot(),
                            const Icon(
                              Icons.check_circle,
                              size: 8,
                              color: AppColors.text2,
                            ),
                          ],
                          if (isFav) ...[
                            _dot(),
                            const Icon(
                              Icons.favorite,
                              size: 9,
                              color: AppColors.text2,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (!(widget.thredots ?? false))
                  SizedBox(
                    width: 20,
                    child: Threedotssongs(
                      icom: const Icon(
                        Icons.more_vert,
                        color: AppColors.text2,
                        size: 22,
                      ),
                      data: widget.song,
                      index: widget.index,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
