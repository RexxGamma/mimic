import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';

import 'Backend/playlistsmanager.dart';
import 'menu.dart';
import 'appcolors.dart';
import 'track.dart';
import 'Backend/providers/providermanager.dart';
import 'playing_trackui.dart';
import 'Backend/metadatamanager.dart';
import 'Backend/songlisttoplay.dart';

import 'dart:math';

import 'Backend/queuemanager.dart';
import 'Backend/audiomanager.dart';
import 'player.dart';
import 'Backend/providers/privdersenums.dart'; // metadataprovider

import 'dart:io';

import 'Backend/songdata.dart';
import 'Backend/createDownloadDir.dart';
import 'Backend/downloadManager.dart';

class Radiomenu extends StatefulWidget {
  const Radiomenu({super.key, required this.artistdata});
  final artistdata;

  @override
  State<Radiomenu> createState() => _RadiomenuState();
}

class _RadiomenuState extends State<Radiomenu> {
  static final Map<String, Color> _colorCache = {};

  Color _bg = AppColors.accent;

  var searchresult;

  bool _saved = false;

  String get _sourceName => (widget.artistdata.source as metadataprovider).name;
  Future searchradio(String id) async {
    final mp = context.read<MetadataProvider>();
    final result = await mp.getAlbumRadio(id);
    if (!mounted) return;
    refreshDownloadedState();
    setState(() => searchresult = result);
  }

  Future<void> _loadSaved() async {
    final saved = await context.read<AppDatabase>().isRadioSaved(
      widget.artistdata.id,
      _sourceName,
    );
    if (!mounted) return;
    setState(() => _saved = saved);
  }

  Future<void> _toggleSaved() async {
    final appDb = context.read<AppDatabase>();
    final id = widget.artistdata.id as String;

    if (_saved) {
      await appDb.removeRadio(id, _sourceName);
    } else {
      await appDb.saveRadio(
        artistId: id,
        source: _sourceName,
        name: widget.artistdata.name,
        thumbnail: widget.artistdata.thumbnailUrl ?? '',
      );
    }

    if (!mounted) return;
    setState(() => _saved = !_saved);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _saved
              ? 'Radio added to your library'
              : 'Radio removed from your library',
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _extractColor();
    searchradio(widget.artistdata.id);
    _loadSaved();
  }

  Future<void> _extractColor() async {
    final url = widget.artistdata.thumbnailUrl as String;

    final cached = _colorCache[url];
    if (cached != null) {
      _bg = cached;
      return;
    }

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(NetworkImage(url), width: 100),
        maximumColorCount: 16,
      );

      // Saturación promedio de la foto, ponderada por cuánto ocupa cada color
      double totalPop = 0;
      double weightedSat = 0;
      for (final p in palette.paletteColors) {
        final sat = HSLColor.fromColor(p.color).saturation;
        weightedSat += sat * p.population;
        totalPop += p.population;
      }
      final avgSat = totalPop == 0 ? 0.0 : weightedSat / totalPop;
      final isGrayscale = avgSat < 0.15;

      Color adjusted;

      if (isGrayscale) {
        // Foto en blanco y negro: fondo gris neutro, sin saturación forzada
        final base = palette.dominantColor?.color ?? Colors.grey;
        final lightness = HSLColor.fromColor(base).lightness
            .clamp(0.18, 0.32)
            .toDouble();
        adjusted = HSLColor.fromAHSL(1, 0, 0, lightness).toColor();
      } else {
        final base =
            palette.vibrantColor?.color ??
            palette.lightVibrantColor?.color ??
            palette.darkVibrantColor?.color ??
            palette.mutedColor?.color ??
            palette.dominantColor?.color;

        if (base == null) {
          debugPrint('Radiomenu: la paleta no devolvió colores para $url');
          return;
        }

        final hsl = HSLColor.fromColor(base);
        adjusted = hsl
            .withSaturation(hsl.saturation.clamp(0.45, 0.85).toDouble())
            .withLightness(hsl.lightness.clamp(0.28, 0.42).toDouble())
            .toColor();
      }

      _colorCache[url] = adjusted;
      if (mounted) setState(() => _bg = adjusted);
    } catch (e) {
      debugPrint('Radiomenu: error al sacar el color -> $e');
    }
  }

  Color _shade(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  bool downloadingRadio = false;
  bool deletingRadio = false;
  bool allDownloaded = false;
  int downloadedCount = 0;
  int downloadTotal = 0;

  List<SongInfo> get _songs => List<SongInfo>.from(searchresult ?? const []);

  String _pathFor(Directory dir, dynamic song) =>
      '${dir.path}/${song.source.label}_${song.id}.mp3';

  /// Revisa en disco si TODAS las canciones de la radio ya están descargadas.
  Future<void> refreshDownloadedState() async {
    final songs = _songs;
    if (songs.isEmpty) {
      if (mounted) setState(() => allDownloaded = false);
      return;
    }
    final dir = await getDownloadDirectory();
    var all = true;
    for (final song in songs) {
      final filePath = song.downloadPath ?? _pathFor(dir, song);
      if (!await File(filePath).exists()) {
        all = false;
        break;
      }
    }
    if (mounted) setState(() => allDownloaded = all);
  }

  Future<void> downloadRadio() async {
    final songs =
        _songs; // copia: searchresult puede cambiar mientras se descarga
    if (downloadingRadio || deletingRadio || songs.isEmpty) return;

    final db = context.read<SongDatabase>(); // antes de los await

    setState(() {
      downloadingRadio = true;
      downloadedCount = 0;
      downloadTotal = songs.length;
    });

    final directory = await getDownloadDirectory();
    int failed = 0;

    try {
      const concurrency = 2;
      var next = 0;

      Future<void> worker() async {
        while (true) {
          final i = next++;
          if (i >= songs.length) return;
          final song = songs[i];

          final path = _pathFor(directory, song);
          final file = File(path);

          if (await file.exists()) {
            if (mounted) setState(() => downloadedCount++);
            continue;
          }

          try {
            await downloadSongAudio(song, path);
            await db.setDownloads(song, path: path, bannerPath: null);
            if (mounted) setState(() => downloadedCount++);
          } catch (e) {
            failed++;
            debugPrint('Error descargando ${song.name}: $e');
            if (await file.exists()) await file.delete();
          }
        }
      }

      await Future.wait(List.generate(concurrency, (_) => worker()));
    } finally {
      refreshDownloadedState();
      if (mounted) {
        setState(() => downloadingRadio = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failed == 0
                  ? 'Descarga completada'
                  : 'Descarga terminada con $failed errores',
            ),
          ),
        );
      }
    }
  }

  Future<void> confirmDeleteRadioDownloads() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(
          'Eliminar descargas',
          style: TextStyle(
            color: AppColors.text,
            fontFamily: 'Adwaita',
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Delete ${_songs.length} tracks from this radio?',
          style: TextStyle(color: AppColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );

    if (ok == true) await deleteRadioDownloads();
  }

  Future<void> deleteRadioDownloads() async {
    if (deletingRadio || downloadingRadio) return;
    setState(() => deletingRadio = true);

    final db = context.read<SongDatabase>(); // antes de los await
    final dir = await getDownloadDirectory();
    final songs = _songs;
    int failed = 0;

    for (final song in songs) {
      try {
        final filePath = song.downloadPath ?? _pathFor(dir, song);
        final f = File(filePath);
        if (await f.exists()) await f.delete();

        final bp = song.downloadBannerPath;
        if (bp != null) {
          final bf = File(bp);
          if (await bf.exists()) await bf.delete();
        }

        await db.setDownloads(song, path: null, bannerPath: null);
      } catch (e) {
        failed++;
        debugPrint('Error eliminando ${song.name}: $e');
      }
    }

    if (!mounted) return;
    setState(() => deletingRadio = false);
    await refreshDownloadedState();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'Descargas eliminadas'
              : 'Eliminadas con $failed errores',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final size = c.maxWidth;
                          final photo = size * 0.72;
                          final photoCenter = Offset(
                            size - photo * 0.38,
                            size - photo * 0.38,
                          );

                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    _shade(_bg, 0.06),
                                    _shade(_bg, -0.08),
                                  ],
                                ),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // 1) Fondo: anillos gruesos
                                  CustomPaint(
                                    painter: _WavesPainter(
                                      center: photoCenter,
                                      startRadius: photo / 2,
                                      step: size * 0.16,
                                      strokeWidth: size * 0.07,
                                      color: AppColors.text,
                                    ),
                                  ),

                                  // 2) Foto del artista, encima de los anillos
                                  Positioned(
                                    right: -photo * 0.12,
                                    bottom: -photo * 0.12,
                                    child: ClipOval(
                                      child: Image.network(
                                        widget.artistdata.thumbnailUrl,
                                        width: photo,
                                        height: photo,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: photo,
                                          height: photo,
                                          color: Colors.black26,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // 3) Encabezado fijo
                                  Positioned(
                                    top: size * 0.08,
                                    left: size * 0.08,
                                    right: size * 0.08,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.radio,
                                              color: AppColors.text,
                                              size: size * 0.11,
                                            ),
                                            SizedBox(width: size * 0.03),

                                            Text(
                                              "RADIO",
                                              style: TextStyle(
                                                fontSize: size * 0.08,
                                                color: AppColors.text,
                                                fontFamily: "Adwaita",
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1.5,
                                                decoration: TextDecoration.none,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: size * 0.04),

                                        Text(
                                          widget.artistdata.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: size * 0.15,
                                            color: AppColors.text,
                                            fontFamily: "Adwaita",
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5,
                                            height: 1.1,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "${widget.artistdata.name} radio",
                      style: TextStyle(
                        fontSize: 30,
                        color: AppColors.text,
                        fontFamily: "Adwaita",
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.all(
                                Radius.circular(60),
                              ),
                              color: AppColors.accent,
                            ),
                            child: IconButton(
                              onPressed: () async {
                                if (searchresult.isEmpty) return;
                                final firstSong = searchresult.first;
                                mainMenuKey.currentState?.updatepreviewplayer(
                                  firstSong,
                                );
                                QueueManager.instance.clear();
                                QueueManager.instance.addAll(searchresult);

                                final hadSong =
                                    Metadatamanager.instance.currentSong !=
                                    null;

                                Metadatamanager.instance.startRadioFrom(
                                  firstSong,
                                );
                                await AudioPlayerManager.instance.play(
                                  firstSong,
                                );

                                if (!hadSong && context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => Player()),
                                  );
                                }
                              },
                              icon: Icon(Icons.play_arrow),
                              iconSize: 45,
                              color: AppColors.accentTeammate,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              final random = Random();
                              final index = random.nextInt(searchresult.length);
                              mainMenuKey.currentState?.updatepreviewplayer(
                                searchresult[index],
                              );
                              if (Metadatamanager.instance.currentSong ==
                                  null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => Player(),
                                  ),
                                );
                              }

                              Metadatamanager.instance.startRadioFrom(
                                searchresult[index],
                              );
                              AudioPlayerManager.instance.play(
                                searchresult[index],
                              );
                            },
                            icon: Icon(
                              Icons.shuffle,
                              size: 37,
                              color: AppColors.text,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(120),
                                    topRight: Radius.circular(120),
                                  ),
                                ),
                                builder: (BuildContext context) {
                                  return DraggableScrollableSheet(
                                    expand: false,
                                    initialChildSize: 0.6,
                                    minChildSize: 0.2,
                                    maxChildSize: 0.6,
                                    builder: (context, scrollController) {
                                      return Container(
                                        height: 800,
                                        decoration: BoxDecoration(
                                          color: AppColors.background,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: ListView(
                                          controller: scrollController,
                                          children: [
                                            GestureDetector(
                                              onTap: () {
                                                Navigator.of(context).pop(); // cierra el bottom sheet
                                                _toggleSaved();
                                              },
                                              child: Material(
                                                color: AppColors.background,
                                                child: ListTile(
                                                  leading: Icon(
                                                    _saved
                                                        ? Icons
                                                              .remove_circle_outline
                                                        : Icons
                                                              .add_circle_outline,
                                                    size: 37,
                                                    color: AppColors.text,
                                                  ),
                                                  title: Text(
                                                    _saved
                                                        ? "Remove from library"
                                                        : "Add to library",
                                                    style: TextStyle(
                                                      color: AppColors.text,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () {
                                                QueueManager.instance.addAll(
                                                  searchresult,
                                                );
                                                Navigator.of(context).pop();
                                              },
                                              child: Material(
                                                color: AppColors.background,
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons.queue_play_next,
                                                    size: 37,
                                                    color: AppColors.text,
                                                  ),
                                                  title: Text(
                                                    "Add to Queue",
                                                    style: TextStyle(
                                                      color: AppColors.text,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            GestureDetector(
                                              onTap: () {
                                                QueueManager.instance.addAll(
                                                  searchresult.content,
                                                );
                                                Navigator.of(context).pop();
                                              },
                                              child: Material(
                                                color: AppColors.background,
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons.share,
                                                    size: 37,
                                                    color: AppColors.text,
                                                  ),
                                                  title: Text(
                                                    "Share",
                                                    style: TextStyle(
                                                      color: AppColors.text,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                            icon: Icon(
                              Icons.more_horiz,
                              size: 37,
                              color: AppColors.text,
                            ),
                          ),
                          Spacer(),
                          IconButton(
                            onPressed:
                                (searchresult == null ||
                                    downloadingRadio ||
                                    deletingRadio)
                                ? null
                                : (allDownloaded
                                      ? confirmDeleteRadioDownloads
                                      : downloadRadio),
                            icon: (downloadingRadio || deletingRadio)
                                ? SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      value:
                                          (deletingRadio || downloadTotal == 0)
                                          ? null
                                          : downloadedCount / downloadTotal,
                                      strokeWidth: 3,
                                      color: AppColors.accent,
                                    ),
                                  )
                                : Icon(
                                    allDownloaded
                                        ? Icons.download_done
                                        : Icons.download_for_offline_outlined,
                                    size: 37,
                                    color: allDownloaded
                                        ? AppColors.accent
                                        : null,
                                  ),
                            color: AppColors.text,
                          ),
                        ],
                      ),
                    ),
                    if (searchresult != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: searchresult?.length ?? 0,
                          physics: const NeverScrollableScrollPhysics(),
                          itemBuilder: (context, index) {
                            final data = searchresult?[index];

                            return Onesong(
                              song: data,
                              albumtracks: searchresult,
                            );
                          },
                        ),
                      ),
                    SizedBox(height: 110),
                  ],
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  Spacer(),
                  if (Metadatamanager.instance.currentSong != null)
                    PlayingTrackui(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WavesPainter extends CustomPainter {
  _WavesPainter({
    required this.center,
    required this.startRadius,
    required this.step,
    required this.strokeWidth,
    required this.color,
  });

  final Offset center;
  final double startRadius;
  final double step;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 1; i <= 5; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        // Cada anillo es más tenue que el anterior
        ..color = color.withValues(alpha: 0.16 - (i * 0.025));
      canvas.drawCircle(center, startRadius + step * i - step * 0.5, paint);
    }
  }

  @override
  bool shouldRepaint(_WavesPainter old) =>
      old.center != center ||
      old.startRadius != startRadius ||
      old.step != step ||
      old.strokeWidth != strokeWidth ||
      old.color != color;
}
