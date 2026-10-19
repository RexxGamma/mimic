// synced_lyrics.dart
//
// Parsea el formato LRC que devuelve LRCLIB (lyrics.syncedLyrics) y provee
// un widget que resalta la línea actual según la posición de reproducción.

import 'package:flutter/material.dart';

class LyricLine {
  final Duration time;
  final String text;
  LyricLine(this.time, this.text);
}

/// Convierte un string LRC crudo (ej. "[00:17.12] Letra de la línea") en
/// una lista ordenada de [LyricLine]. Soporta líneas con más de un
/// timestamp (ej. coros repetidos: "[00:12.00][00:45.00]Chorus").
List<LyricLine> parseSyncedLyrics(String lrc) {
  final lines = <LyricLine>[];
  final tagRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

  for (final rawLine in lrc.split('\n')) {
    final tags = tagRegex.allMatches(rawLine).toList();
    if (tags.isEmpty) continue;

    final text = rawLine.substring(tags.last.end).trim();

    for (final tag in tags) {
      final minutes = int.parse(tag.group(1)!);
      final seconds = int.parse(tag.group(2)!);
      final fraction = tag.group(3)!;
      // El LRC puede traer centésimas (2 dígitos) o milésimas (3 dígitos).
      final milliseconds = fraction.length == 2
          ? int.parse(fraction) * 10
          : int.parse(fraction);

      lines.add(
        LyricLine(
          Duration(minutes: minutes, seconds: seconds, milliseconds: milliseconds),
          text,
        ),
      );
    }
  }

  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

/// Widget que muestra las lyrics sincronizadas, resaltando la línea actual
/// y haciendo scroll automático a medida que avanza [positionStream].
///
/// Uso:
/// ```dart
/// SyncedLyricsView(
///   lines: parseSyncedLyrics(lyrics.syncedLyrics!),
///   positionStream: AudioPlayerManager.instance.player.positionStream,
///   onSeek: (time) => AudioPlayerManager.instance.player.seek(time),
/// )
/// ```
class SyncedLyricsView extends StatefulWidget {
  final List<LyricLine> lines;
  final Stream<Duration> positionStream;

  /// Opcional: si el usuario toca una línea, permite hacer seek ahí.
  final void Function(Duration time)? onSeek;

  final TextStyle? activeStyle;
  final TextStyle? inactiveStyle;

  const SyncedLyricsView({
    super.key,
    required this.lines,
    required this.positionStream,
    this.onSeek,
    this.activeStyle,
    this.inactiveStyle,
  });

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _activeIndex = -1;
  late List<GlobalKey> _keys;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.lines.length, (_) => GlobalKey());
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lines != widget.lines) {
      _keys = List.generate(widget.lines.length, (_) => GlobalKey());
      _activeIndex = -1;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int _indexForPosition(Duration position) {
    var result = -1;
    for (var i = 0; i < widget.lines.length; i++) {
      if (widget.lines[i].time <= position) {
        result = i;
      } else {
        break;
      }
    }
    return result;
  }

  void _scrollToActive() {
    if (_activeIndex < 0 || _activeIndex >= _keys.length) return;
    if (!_scrollController.hasClients) return;

    final ctx = _keys[_activeIndex].currentContext;
    final renderObject = ctx?.findRenderObject();
    if (renderObject == null) return;

    // Se usa el ensureVisible de ESTE ScrollPosition (no el estático
    // Scrollable.ensureVisible), para que solo se mueva este ListView y
    // no burbujee hacia el SingleChildScrollView que envuelve toda la
    // pantalla del Player.
    _scrollController.position.ensureVisible(
      renderObject,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeStyle = widget.activeStyle ??
        const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontFamily: "Adwaita",
        );
    final inactiveStyle = widget.inactiveStyle ??
        TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          fontFamily: "Adwaita",
          color: activeStyle.color?.withValues(alpha: 0.5),
        );

    return StreamBuilder<Duration>(
      stream: widget.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final newIndex = _indexForPosition(position);

        if (newIndex != _activeIndex) {
          _activeIndex = newIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
        }

        return ListView.builder(
          controller: _scrollController,
          itemCount: widget.lines.length,
          itemBuilder: (context, index) {
            final line = widget.lines[index];
            final isActive = index == _activeIndex;

            return GestureDetector(
              key: _keys[index],
              onTap: widget.onSeek == null ? null : () => widget.onSeek!(line.time),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: isActive ? activeStyle : inactiveStyle,
                  child: Text(line.text.isEmpty ? '♪' : line.text),
                ),
              ),
            );
          },
        );
      },
    );
  }
}