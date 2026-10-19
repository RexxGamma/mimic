import 'package:flutter/material.dart';
import 'package:mimic/3dotssongs.dart';
import 'package:mimic/appcolors.dart';
import 'package:marquee/marquee.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;

import "Backend/settings.dart";
import "Backend/marqueeDecider.dart";
import 'artistlinks.dart';
import 'Backend/adaptivepalette.dart';

import 'package:mimic/Backend/audiomanager.dart';

import 'Backend/providers/lyrics/lyricsorquestator.dart';
import 'slidertheme.dart';
import 'queue.dart';
import 'Backend/metadatamanager.dart';
import 'Backend/providers/lyrics/syncedlyrics.dart';

import 'package:palette_generator/palette_generator.dart';

import 'Backend/palettegenerator.dart';
import '3dotsmanager.dart';

import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:provider/provider.dart';

import 'Backend/songlisttoplay.dart';
import 'Backend/settings.dart';

enum _PlayerMode { loading, buffering, playing, paused, completed }

class PlayerRoute extends PageRouteBuilder {
  factory PlayerRoute() => PlayerRoute._();

  PlayerRoute._()
    : super(
        opaque: false,
        barrierColor: null,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => const Player(),
      );

  @override
  Widget buildTransitions(_, animation, __, child) {
    return SlideTransition(
      position: Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    );
  }
}

class Player extends StatefulWidget {
  const Player({super.key});

  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> with TickerProviderStateMixin {
  var oldCurrentSong = Metadatamanager.instance.currentSong!;

  final _lyricsAggregator = LyricsAggregator();

  late final AnimationController _drag;
  final ScrollController _scroll = ScrollController();
  double _startY = 0;
  double _lastY = 0;
  bool _dragging = false;

  // ── Fullscreen lyrics ──────────────────────────────────
  bool _fullscreenLyrics = false;

  final player = AudioPlayerManager.instance.player;
  List<LyricLine>? syncedLines;
  String? plainLyricsFallback;
  bool lyricsLoading = true;
  bool lyricsReady = false; // true = ya terminamos de cargar (con o sin letras)
  Color dominantColor = Colors.white24;

  @override
  void initState() {
    super.initState();

    _drag = AnimationController.unbounded(vsync: this);

    _loadLyrics();
    _generatepalette();
    Metadatamanager.instance.addListener(_onPlayerStateChanged);
    SongContextManager.push(SongSource.player);
    context.read<SongDatabase>().loadFavorites();
  }

  @override
  void dispose() {
    Metadatamanager.instance.removeListener(_onPlayerStateChanged);
    _drag.dispose();
    _scroll.dispose();
    SongContextManager.pop();
    super.dispose();
  }

  void _onPlayerStateChanged() {
    final s = Metadatamanager.instance.currentSong;
    if (s?.id != oldCurrentSong.id) {
      setState(() => oldCurrentSong = s!);
      _loadLyrics();
      _generatepalette();
    }
  }

  Widget banner() {
    if (oldCurrentSong.downloadBannerPath != null) {
      return Image.file(
        File(oldCurrentSong.downloadBannerPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    final url = oldCurrentSong.thumbnails.isNotEmpty
        ? oldCurrentSong.thumbnails[3].url
        : '';
    if (url.isEmpty) {
      return Container(
        color: AppColors.background,
        child: const Icon(Icons.music_note, size: 100, color: AppColors.text2),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.background,
        child: const Icon(Icons.music_note, size: 100, color: AppColors.text2),
      ),
    );
  }

  // ── Fondo blur ─────────────────────────────────────────
  Widget _blurBackgroundLayer() {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Transform.scale(scale: 1.25, child: banner()),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background,
                  Colors.transparent,
                  Colors.transparent,
                  AppColors.background,
                ],
                stops: const [0.0, 0.2, 0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerSection() {
    if (AppSettings.instance.playerLargeBannerBackground) {
      final screenW = MediaQuery.of(context).size.width;
      final sectionHeight = 60 + (screenW - 40) + 80;
      return SizedBox(
        width: double.infinity,
        height: sectionHeight,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (Rect bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0.0, 0.24, 0.90, 1.0],
          ).createShader(bounds),
          child: banner(),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 60, bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: AspectRatio(aspectRatio: 1 / 1, child: banner()),
      ),
    );
  }

  bool get _atTop => !_scroll.hasClients || _scroll.position.pixels <= 0;

  void _onDown(PointerDownEvent e) {
    if (_drag.isAnimating) _drag.stop();
    _lastY = e.position.dy;
    _dragging = false;
  }

  void _onMove(PointerMoveEvent e) {
    final y = e.position.dy;
    if (!_dragging && _atTop && y > _lastY + 1) {
      _dragging = true;
      _startY = y;
      _drag.value = 0;
    }
    if (_dragging) {
      _drag.value = (y - _startY).clamp(0.0, double.infinity);
    }
    _lastY = y;
  }

  void _release() {
    if (!_dragging) return;
    _dragging = false;
    final h = MediaQuery.of(context).size.height;

    if (_drag.value > 120) {
      _drag
          .animateTo(
            h,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted) Navigator.of(context).pop();
          });
    } else {
      _drag.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _nowPlayingHeader() {
    const titleStyle = TextStyle(
      fontSize: 20,
      color: AppColors.text,
      fontFamily: "Adwaita",
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.none,
    );
    const subStyle = TextStyle(
      fontSize: 17,
      color: AppColors.text2,
      fontFamily: "Adwaita",
      decoration: TextDecoration.none,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: StreamBuilder<PlayerState>(
        stream: player.playerStateStream,
        initialData: player.playerState,
        builder: (context, snap) {
          final mode = _modeFor(snap.data!);
          return Column(
            children: [
              _fadingText(_titleFor(mode), titleStyle),
              _subtitle(mode, subStyle),
            ],
          );
        },
      ),
    );
  }

  _PlayerMode _modeFor(PlayerState s) {
    switch (s.processingState) {
      case ProcessingState.loading:
        return _PlayerMode.loading;
      case ProcessingState.buffering:
        return _PlayerMode.buffering;
      case ProcessingState.completed:
        return _PlayerMode.completed;
      case ProcessingState.idle:
        return s.playing ? _PlayerMode.loading : _PlayerMode.paused;
      case ProcessingState.ready:
        return s.playing ? _PlayerMode.playing : _PlayerMode.paused;
    }
  }

  String _titleFor(_PlayerMode mode) {
    switch (mode) {
      case _PlayerMode.loading:
        return 'Loading...';
      case _PlayerMode.buffering:
        return 'Buffering...';
      case _PlayerMode.paused:
        return 'Paused';
      case _PlayerMode.completed:
        return 'Finished';
      case _PlayerMode.playing:
        if (AudioPlayerManager.instance.repeatTrack) return 'On repeat';
        if (AudioPlayerManager.instance.shuffle) return 'Shuffling';
        return 'Now playing';
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _fadingText(String text, TextStyle style) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Text(
        text,
        key: ValueKey(text),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }

  Widget _subtitle(_PlayerMode mode, TextStyle style) {
    switch (mode) {
      case _PlayerMode.loading:
        return _fadingText('Getting your track ready', style);
      case _PlayerMode.buffering:
        return _fadingText('Waiting for more data', style);
      case _PlayerMode.completed:
        return _fadingText('Reached the end of the track', style);
      case _PlayerMode.paused:
      case _PlayerMode.playing:
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, ps) {
            final pos = ps.data ?? player.position;
            final total = player.duration;
            final playing = mode == _PlayerMode.playing;

            String text;
            if (total == null) {
              text = playing ? _fmt(pos) : 'At ${_fmt(pos)}';
            } else if (playing) {
              final left = total - pos;
              text = '${_fmt(left.isNegative ? Duration.zero : left)} left';
            } else {
              text = 'At ${_fmt(pos)} of ${_fmt(total)}';
            }
            return Text(text, maxLines: 1, style: style);
          },
        );
    }
  }

  Future<void> _generatepalette() async {
    final provider = AdaptiveTheme.bannerProvider(oldCurrentSong);
    if (provider == null) return; // sin portada: se queda el color por defecto
    try {
      final p = await PaletteGenerator.fromImageProvider(provider);
      if (mounted) {
        setState(() => dominantColor = p.dominantColor?.color ?? Colors.grey);
      }
    } catch (e) {
      debugPrint('Player: error generando paleta -> $e');
    }
  }

  Future<void> _loadLyrics() async {
    final song = oldCurrentSong;

    setState(() {
      lyricsLoading = true;
      lyricsReady = false;
      syncedLines = null;
      plainLyricsFallback = null;
    });

    try {
      final l = await _lyricsAggregator.getLyrics(song);
      // Evita que la respuesta de una canción anterior
      // sobrescriba las letras de la canción actual.
      if (!mounted || oldCurrentSong.id != song.id) return;
      setState(() {
        lyricsLoading = false;
        lyricsReady = true;
        if (l?.syncedLyrics != null) {
          syncedLines = parseSyncedLyrics(l!.syncedLyrics!);
        } else if (l?.plainLyrics != null) {
          plainLyricsFallback = l!.plainLyrics;
        }
      });
    } catch (e) {
      debugPrint('Player: error cargando letras -> $e');
      if (!mounted || oldCurrentSong.id != song.id) return;
      setState(() {
        lyricsLoading = false;
        lyricsReady = true;
      });
    }
  }

  // ── Contenido de letras (reutilizado en normal + fullscreen) ──
  Widget _buildLyricsContent({
    required bool fullscreen,
    required Color light,
    required Color dark,
  }) {
    final activeSize = fullscreen ? 30.0 : 23.0;
    final inactiveSize = fullscreen ? 25.0 : 20.0;
    final plainSize = fullscreen ? 24.0 : 20.0;
    final emptySize = fullscreen ? 20.0 : 18.0;

    if (lyricsLoading) {
      return Center(child: CircularProgressIndicator(color: light));
    }

    if (syncedLines != null) {
      return SyncedLyricsView(
        lines: syncedLines!,
        positionStream: player.positionStream,
        onSeek: (t) => player.seek(t),
        activeStyle: TextStyle(
          fontSize: activeSize,
          color: light,
          fontWeight: FontWeight.w700,
          fontFamily: "Adwaita",
          decoration: TextDecoration.none,
        ),
        inactiveStyle: TextStyle(
          fontSize: inactiveSize,
          color: dark,
          fontWeight: FontWeight.w600,
          fontFamily: "Adwaita",
          decoration: TextDecoration.none,
        ),
      );
    }

    if (plainLyricsFallback != null) {
      return SingleChildScrollView(
        child: Text(
          plainLyricsFallback!,
          style: TextStyle(
            fontSize: plainSize,
            color: light,
            fontFamily: "Adwaita",
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ),
      );
    }

    return Center(
      child: Text(
        "No lyrics available",
        style: TextStyle(
          fontSize: emptySize,
          color: light,
          fontFamily: "Adwaita",
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  // ── Vista fullscreen de letras ─────────────────────────
  Widget _buildFullscreenLyricsView(Color light, Color dark) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _fullscreenLyrics = false);
      },
      child: Material(
        // Mismo color que el contenedor de letras del reproductor.
        color: dominantColor,
        child: SafeArea(
          child: Stack(
            children: [
              // Letras ocupando toda la pantalla.
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 80, 24, 40),
                  child: _buildLyricsContent(
                    fullscreen: true,
                    light: light,
                    dark: dark,
                  ),
                ),
              ),

              // Botón de salida en el borde superior-izquierdo.
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  onPressed: () => setState(() => _fullscreenLyrics = false),
                  icon: Icon(Icons.keyboard_arrow_down, size: 36, color: light),
                  tooltip: 'Exit fullscreen',
                ),
              ),

              // Título + artista (contexto de la canción actual).
              Positioned(
                top: 16,
                left: 56,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      oldCurrentSong.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        color: light,
                        fontFamily: "Adwaita",
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    Text(
                      oldCurrentSong.artists.map((a) => a.name).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: dark,
                        fontFamily: "Adwaita",
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final light = ColorContraste.claro(dominantColor);
    final dark = ColorContraste.oscuro(dominantColor);

    // ── Modo pantalla completa de letras ─────────────────
    if (_fullscreenLyrics) {
      return _buildFullscreenLyricsView(light, dark);
    }

    final textW = calculateSpan(
      oldCurrentSong.name,
      const TextStyle(
        fontSize: 18,
        fontFamily: "Adwaita",
        decoration: TextDecoration.none,
      ),
    );
    final subW = calculateSpan(
      oldCurrentSong.artists.map((a) => a.name).join(', '),
      const TextStyle(
        fontSize: 18,
        fontFamily: "Adwaita",
        decoration: TextDecoration.none,
      ),
    );

    final content = AspectRatio(
      aspectRatio: 1 / 1,
      child: Container(
        color: AppColors.background,
        child: SafeArea(
          child: SingleChildScrollView(
            controller: _scroll,
            physics: const ClampingScrollPhysics(),
            child: Column(
              children: [
                Stack(
                  children: [
                    if (AppSettings.instance.playerBlurBackground)
                      _blurBackgroundLayer(),
                    Column(
                      children: [
                        _nowPlayingHeader(),
                        _buildBannerSection(),

                        // ── Nombre + Favorito ────────────────
                        Padding(
                          padding: const EdgeInsets.only(left: 20, right: 20),
                          child: Row(
                            children: [
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, c) {
                                    if (textW > c.maxWidth) {
                                      return SizedBox(
                                        height: 30,
                                        child: Marquee(
                                          text: oldCurrentSong.name,
                                          style: TextStyle(
                                            color: AppColors.text,
                                            fontSize: 20,
                                            fontFamily: "Adwaita",
                                            decoration: TextDecoration.none,
                                          ),
                                          blankSpace: 50,
                                          velocity: 35,
                                          pauseAfterRound: const Duration(
                                            seconds: 2,
                                          ),
                                        ),
                                      );
                                    }
                                    return Text(
                                      oldCurrentSong.name,
                                      style: TextStyle(
                                        fontSize: 20,
                                        color: AppColors.text,
                                        fontFamily: "Adwaita",
                                        decoration: TextDecoration.none,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  final isFav = context
                                      .select<SongDatabase, bool>(
                                        (db) => db.isFavoriteSync(
                                          oldCurrentSong.id,
                                        ),
                                      );
                                  return Align(
                                    alignment: AlignmentGeometry.topRight,
                                    child: IconButton(
                                      onPressed: () => context
                                          .read<SongDatabase>()
                                          .toggleFavorite(oldCurrentSong),
                                      icon: Icon(
                                        isFav
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        size: 30,
                                        color: isFav
                                            ? AppColors.accent
                                            : AppColors.text,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        // ── Artista ─────────────────────────
                        Padding(
                          padding: const EdgeInsets.only(left: 10, right: 20),
                          child: LayoutBuilder(
                            builder: (context, c) {
                              final txt = oldCurrentSong.artists
                                  .map((a) => a.name)
                                  .join(', ');
                              final marquee = subW > c.maxWidth;
                              return TextButton(
                                onPressed: () => showModalBottomSheet(
                                  context: context,
                                  builder: (_) =>
                                      Artistlinks(data: oldCurrentSong),
                                ),
                                child: marquee
                                    ? SizedBox(
                                        height: 25,
                                        child: Marquee(
                                          text: txt,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: AppColors.text2,
                                            fontFamily: "Adwaita",
                                            fontWeight: FontWeight.w700,
                                            decoration: TextDecoration.none,
                                          ),
                                          blankSpace: 50,
                                          velocity: 30,
                                        ),
                                      )
                                    : Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          txt,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: AppColors.text2,
                                            fontFamily: "Adwaita",
                                            fontWeight: FontWeight.w700,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ),
                              );
                            },
                          ),
                        ),

                        // ── Slider ──────────────────────────
                        StreamBuilder<Duration?>(
                          stream: player.durationStream,
                          builder: (context, ds) {
                            final d = ds.data;
                            if (d == null || d.inMilliseconds <= 0) {
                              return const SizedBox();
                            }
                            return StreamBuilder<Duration>(
                              stream: player.positionStream,
                              builder: (context, ps) {
                                final pos = ps.data ?? Duration.zero;
                                final v = pos.inMilliseconds
                                    .clamp(0, d.inMilliseconds)
                                    .toDouble();
                                return Material(
                                  color: Colors.transparent,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 6,
                                      inactiveTrackColor:
                                          AppColors.bordierlight,
                                      activeTrackColor: AppColors.accent,
                                      thumbColor: AppColors.accent,
                                      thumbShape: const RoundedRectThumbShape(
                                        width: 12,

                                        height: 16,
                                        pressedHeight: 18,
                                        radius: 60,
                                      ),
                                      trackShape:
                                          const GappedRectSliderTrackShape(
                                            thumbWidth: 16,
                                            // Usa la altura de presionado para que el hueco siempre
                                            // acomode al thumb aunque crezca al tocarlo.
                                            thumbHeight: 16,
                                            gapHorizontalPadding: 3,
                                            gapVerticalPadding: 3,
                                            trackCornerRadius: 3,
                                          ),
                                      overlayColor: AppColors.bordierlight,
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 1,
                                          ),
                                    ),
                                    child: SizedBox(
                                      width: 370,
                                      child: Slider(
                                        value: v,
                                        max: d.inMilliseconds.toDouble(),
                                        onChanged: (x) => player.seek(
                                          Duration(milliseconds: x.toInt()),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),

                // ── Botones de reproducción ────────────────
                Padding(
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: 10,
                    top: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _roundBtn(
                        AppColors.accentTeammate,
                        AppColors.accent,
                        Icons.skip_previous,
                        48,
                        () => AudioPlayerManager.instance.playprevious(),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent,
                        ),
                        child: AnimatedBuilder(
                          animation: AudioPlayerManager.instance,
                          builder: (_, __) => IconButton(
                            onPressed: () =>
                                AudioPlayerManager.instance.togglePlayPause(),
                            icon: AudioPlayerManager.instance
                                .consultPlayerState(),
                            iconSize: 80,
                            color: AppColors.accentTeammate,
                          ),
                        ),
                      ),
                      _roundBtn(
                        AppColors.accentTeammate,
                        AppColors.accent,
                        Icons.skip_next,
                        48,
                        () => AudioPlayerManager.instance.playnext(),
                      ),
                    ],
                  ),
                ),

                // ── Utilidades ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(
                    top: 8,
                    bottom: 8,
                    left: 10,
                    right: 10,
                  ),
                  child: Align(
                    alignment: AlignmentGeometry.bottomCenter,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () =>
                              Navigator.of(context).push(QueueRoute()),
                          icon: Icon(
                            Icons.queue_music,
                            size: 37,
                            color: AppColors.text,
                          ),
                        ),
                        const Spacer(),
                        Threedotssongs(
                          icom: Icon(
                            Icons.info_outline,
                            size: 37,
                            color: AppColors.text,
                          ),
                          data: oldCurrentSong,
                        ),
                        IconButton(
                          onPressed: () => setState(() {
                            AudioPlayerManager.instance.shuffle =
                                !AudioPlayerManager.instance.shuffle;
                          }),
                          icon: Icon(
                            Icons.shuffle,
                            size: 37,
                            color: AudioPlayerManager.instance.shuffle
                                ? AppColors.accent
                                : AppColors.text,
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() {
                            AudioPlayerManager.instance.repeatTrack =
                                !AudioPlayerManager.instance.repeatTrack;
                          }),
                          icon: Icon(
                            Icons.repeat,
                            size: 37,
                            color: AudioPlayerManager.instance.repeatTrack
                                ? AppColors.accent
                                : AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Bloque de letras ────────────────────────
                if (lyricsLoading ||
                    syncedLines != null ||
                    plainLyricsFallback != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: 30,
                      left: 20,
                      right: 20,
                    ),
                    child: Container(
                      width: double.infinity,
                      height: 470,
                      decoration: BoxDecoration(
                        color: dominantColor,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 15,
                                right: 5,
                                top: 45,
                                bottom: 30,
                              ),
                              child: _buildLyricsContent(
                                fullscreen: false,
                                light: light,
                                dark: dark,
                              ),
                            ),
                          ),

                          Positioned(
                            top: 6,
                            right: 6,
                            child: IconButton(
                              onPressed: () =>
                                  setState(() => _fullscreenLyrics = true),
                              icon: Icon(
                                Icons.fullscreen,
                                size: 26,
                                color: light,
                              ),
                              tooltip: 'Fullscreen lyrics',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: _drag,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, _drag.value),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular((_drag.value / 20).clamp(0.0, 24.0)),
            ),
            child: child,
          ),
        ),
        child: content,
      ),
    );
  }

  Widget _roundBtn(
    Color bg,
    Color fg,
    IconData icon,
    double size,
    VoidCallback onTap,
  ) {
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon),
        iconSize: size,
        color: fg,
      ),
    );
  }
}
