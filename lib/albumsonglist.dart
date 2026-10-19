import 'package:flutter/material.dart';
import 'package:mimic/Backend/providers/providermanager.dart';

import 'Backend/providers/privdersenums.dart';

import 'package:flutter/services.dart';

import 'appcolors.dart';
import 'track.dart';
import 'playing_trackui.dart';
import '3dotsmanager.dart';
import 'Backend/metadatamanager.dart';
import 'Backend/queuemanager.dart';
import 'Backend/audiomanager.dart';
import 'player.dart';
import 'artist.dart';
import 'menu.dart';

import 'package:provider/provider.dart';

import 'Backend/albumsSaved.dart';
import 'Backend/createDownloadDir.dart';

import 'package:dio/dio.dart';

import 'Backend/songlisttoplay.dart';
import 'Backend/downloadManager.dart';

import 'dart:io';

class Albumsonglist extends StatefulWidget {
  const Albumsonglist({
    super.key,
    required this.albid,
    required this.albumdata,
    required this.type,
  });
  final albid;
  final albumdata;
  final type;

  @override
  State<Albumsonglist> createState() => _AlbumsonglistState();
}

class _AlbumsonglistState extends State<Albumsonglist> {
  var searchresult;

  var db;
  var followed;

  @override
  void dispose() {
    super.dispose();
    SongContextManager.pop();
    Metadatamanager.instance.removeListener(_onPlayerStateChanged);
  }

  void s() async {
    db = context.read<AlbumDatabase>();
    var dobleese = await db.isSaved(widget.albumdata);
    followed = dobleese;
    print("ALBUM SAVED: $followed");
    sets();
  }

  @override
  void initState() {
    super.initState();
    searchtracks();
    s();
    SongContextManager.push(SongSource.album);
    Metadatamanager.instance.addListener(_onPlayerStateChanged);
  }

  void sets() {
    setState(() {});
  }

  void _onPlayerStateChanged() {
    sets();
  }

  String get _albumKey {
    final metadataprovider src = widget.albumdata.source;
    return SongDatabase.albumKey(src.name, widget.albumdata.id);
  }

  void searchtracks() async {
    final songDb = context.read<SongDatabase>();
    final albumDb = context.read<AlbumDatabase>();
    final mp = context.read<MetadataProvider>();

    // 1. Si el álbum está guardado, los tracks salen de la DB
    //    (no depende del proveedor activo).
    final saved = await songDb.getAlbum(_albumKey);
    if (!mounted) return;
    if (saved != null) {
      setState(() => searchresult = saved);
      refreshDownloadedState();
      return;
    }

    // 2. Si no, del proveedor actual, como antes.
    final tracks = await mp.getAlbumById(widget.albid);
    if (!mounted) return;
    setState(() => searchresult = tracks);
    refreshDownloadedState();

    // 3. Álbum guardado antes de esta función: rellenar los tracks ahora.
    if (await albumDb.isSaved(widget.albumdata)) {
      try {
        await songDb.saveAlbum(_albumKey, tracks);
      } catch (_) {}
    }
  }

  bool downloadingAlbum = false;
  int downloadedCount = 0;
  int downloadTotal = 0;

  bool allDownloaded = false;
  bool deletingAlbum = false;

  String _pathFor(Directory dir, dynamic song) =>
      '${dir.path}/${song.source.label}_${song.id}.mp3';

  /// Verifica en disco (no en memoria) si TODAS las canciones están descargadas.
  Future<void> refreshDownloadedState() async {
    final songs = searchresult?.content;
    if (songs == null || songs.isEmpty) {
      if (mounted) setState(() => allDownloaded = false);
      return;
    }

    final dir = await getDownloadDirectory();
    var all = true;
    for (final song in songs) {
      final p = song.downloadPath ?? _pathFor(dir, song);
      if (!await File(p).exists()) {
        all = false;
        break;
      }
    }
    if (mounted) setState(() => allDownloaded = all);
  }

  Future<void> confirmDeleteAlbumDownloads() async {
    final count = searchresult.content.length;

    final danger = Colors.red.shade400;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 16,
          shadowColor: Colors.black.withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withOpacity(0.06), width: 1),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),

          // ── Header: icon badge + título + subtítulo ────────────────
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      danger.withOpacity(0.22),
                      danger.withOpacity(0.06),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: danger.withOpacity(0.30)),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: danger,
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Delete downloads',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  color: AppColors.text,
                  fontFamily: 'Adwaita',
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.2,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This action cannot be undone',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.text.withOpacity(0.55),
                  fontFamily: 'Adwaita',
                  fontWeight: FontWeight.w400,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),

          // ── Contenido: mini-card con el conteo ─────────────────────
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bordier.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: danger.withOpacity(0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.music_note_rounded,
                  size: 18,
                  color: AppColors.text2,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '$count ${count == 1 ? "track" : "tracks"} from this album',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.text,
                      fontFamily: 'Adwaita',
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Acciones ───────────────────────────────────────────────
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.text.withOpacity(0.70),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Adwaita',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Adwaita',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (ok == true) await deleteAlbumDownloads();
  }

  Future<void> deleteAlbumDownloads() async {
    if (deletingAlbum || downloadingAlbum) return;
    setState(() => deletingAlbum = true);

    final db = context.read<SongDatabase>(); // antes de los await
    final dir = await getDownloadDirectory();
    final songs = searchresult.content;
    int failed = 0;

    for (final song in songs) {
      try {
        final p = song.downloadPath ?? _pathFor(dir, song);
        final f = File(p);
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
    setState(() => deletingAlbum = false);
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

  Future<void> downloadAlbum() async {
    if (downloadingAlbum || searchresult.content.isEmpty) return;

    setState(() {
      downloadingAlbum = true;
      downloadedCount = 0;
      downloadTotal = searchresult.content.length;
    });

    final db = context.read<SongDatabase>(); // antes de los await
    final directory = await getDownloadDirectory();
    final songs = searchresult.content;
    int failed = 0;

    try {
      // Cada descarga ya abre 4 conexiones: 2 canciones a la vez bastan.
      const concurrency = 2;
      var next = 0;

      Future<void> worker() async {
        while (true) {
          final i = next++;
          if (i >= songs.length) return;
          final song = songs[i];

          final path = '${directory.path}/${song.source.label}_${song.id}.mp3';
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
        setState(() => downloadingAlbum = false);
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

  String convertLongTime(String duracion) {
    final partes = duracion.split(':');
    return '${partes[1]}:${partes[2].substring(0, 2)}';
  }

  @override
  Widget build(BuildContext context) {
    Image banner() {
      if (widget.albumdata.downloadBannerPath != null) {
        return Image.file(
          File(widget.albumdata.downloadBannerPath!),
          fit: BoxFit.cover,
        );
      } else {
        return Image.network(
          widget.albumdata?.bannerurl ?? "",
          fit: BoxFit.cover,
        );
      }
    }

    if (Metadatamanager.instance.currentSong != null) {
      sets();
    }

    if (searchresult == null) {
      return Container(
        color: AppColors.background,
        child: Center(
          child: CircularProgressIndicator(
            backgroundColor: AppColors.bordier,
            color: AppColors.accent,
          ),
        ),
      );
    }

    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    //Album banner
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Container(
                        width: 350,
                        height: 350,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: banner(),
                      ),
                    ),

                    //Album Name
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              widget.albumdata.name,
                              style: TextStyle(
                                fontSize: 30,
                                color: AppColors.text,
                                fontFamily: "Adwaita",
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    //Songs number and Album duration
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          "${searchresult.content.length} Songs • ${convertLongTime(searchresult.duration.toString())}",
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.text2,
                            fontFamily: "Adwaita",
                            fontWeight: FontWeight.w400,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                    //Important buttons
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          //play
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.all(
                                Radius.circular(60),
                              ),
                              color: AppColors.accent,
                            ),
                            child: IconButton(
                              onPressed: () async {
                                if (searchresult.content.isEmpty) return;
                                final firstSong = searchresult.content.first;
                                mainMenuKey.currentState?.updatepreviewplayer(
                                  firstSong,
                                );
                                if (SongContextManager.current ==
                                        SongSource.album ||
                                    SongContextManager.current ==
                                        SongSource.playlist) {
                                  QueueManager.instance.clear();
                                  QueueManager.instance.addAll(
                                    searchresult.content,
                                  );
                                }

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

                          //favorite
                          if (followed != null && followed == false)
                            IconButton(
                              onPressed: () async {
                                final dio = Dio();
                                final directory = await getDownloadDirectory();
                                final base =
                                    '${directory.path}/${widget.albumdata.source.label}_${widget.albumdata.id}_Album';

                                debugPrint("PATH $base");

                                String? bannerPath;
                                try {
                                  debugPrint(
                                    "Comenzando a descargar el banner",
                                  );
                                  if (widget.albumdata.bannerurl.isNotEmpty) {
                                    bannerPath = '${base}_banner.jpg';
                                    debugPrint("BANNER PATH: $bannerPath");
                                    await dio.download(
                                      widget.albumdata.bannerurl,
                                      bannerPath,
                                    );
                                    debugPrint("DOWNLOADED BANNER");
                                  }
                                } catch (e) {
                                  debugPrint('Error descargando banner: $e');
                                  bannerPath = null;
                                }

                                debugPrint(
                                  'Descarga terminada: $base | banner: $bannerPath',
                                );

                                final albumDb = context.read<AlbumDatabase>();
                                final songDb = context.read<SongDatabase>();
                                albumDb.save(widget.albumdata);
                                try {
                                  await songDb.saveAlbum(
                                    _albumKey,
                                    searchresult,
                                  );
                                } catch (e) {
                                  debugPrint(
                                    'No se pudieron guardar los tracks del álbum: $e',
                                  );
                                }
                                s();
                              },
                              icon: Icon(
                                Icons.favorite_border,
                                size: 37,
                                color: AppColors.text,
                              ),
                            ),

                          if (followed != null && followed)
                            IconButton(
                              onPressed: () async {
                                final albumDb = context.read<AlbumDatabase>();
                                final songDb = context.read<SongDatabase>();
                                albumDb.unfollow(widget.albumdata);
                                await songDb.deleteAlbum(_albumKey);
                                s();
                              },
                              icon: Icon(
                                Icons.favorite,
                                size: 37,
                                color: AppColors.accent,
                              ),
                            ),

                          //3 dots button
                          //IconButton(onPressed: () {}, icon: Icon(Icons.more_horiz, size: 37, color: AppColors.text,)),
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
                                    initialChildSize: 0.4,
                                    minChildSize: 0.2,
                                    maxChildSize: 0.4,
                                    builder: (context, ScrollController) {
                                      return Container(
                                        height: 800,
                                        decoration: BoxDecoration(
                                          color: AppColors.background,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),

                                        child: ListView(
                                          controller: ScrollController,
                                          children: [
                                            //See Artist
                                            GestureDetector(
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => ArtistWidet(
                                                      id: searchresult
                                                          .creator
                                                          .id,
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Material(
                                                color: AppColors.background,
                                                child: ListTile(
                                                  //Icon
                                                  leading: Stack(
                                                    children: [
                                                      Icon(
                                                        Icons.person,
                                                        size: 35,
                                                        color: AppColors.text,
                                                      ),
                                                      Positioned(
                                                        right: -2,
                                                        bottom: -2,
                                                        child: Container(
                                                          decoration:
                                                              BoxDecoration(
                                                                color: AppColors
                                                                    .background,
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                          child: Icon(
                                                            Icons.music_note,
                                                            size: 20,
                                                            color:
                                                                AppColors.text,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),

                                                  //Text
                                                  title: Text(
                                                    "View Artist",
                                                    style: TextStyle(
                                                      color: AppColors.text,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),

                                                  //Artist
                                                  subtitle: Text(
                                                    searchresult.creator.name,
                                                    style: TextStyle(
                                                      color: AppColors.text2,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            //Queue
                                            GestureDetector(
                                              onTap: () {
                                                print("KESO LOL");
                                                QueueManager.instance.addAll(
                                                  searchresult.content,
                                                );
                                                Navigator.of(context).pop();
                                              },
                                              child: Material(
                                                color: AppColors.background,
                                                child: ListTile(
                                                  //Icon
                                                  leading: Icon(
                                                    Icons.queue_play_next,
                                                    size: 37,
                                                    color: AppColors.text,
                                                  ),

                                                  //Text
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

                                            //Share
                                            GestureDetector(
                                              onTap: () {
                                                Navigator.pop(context);
                                                Clipboard.setData(
                                                  ClipboardData(
                                                    text: widget.albumdata.name,
                                                  ),
                                                );
                                              },
                                              child: Material(
                                                color: AppColors.background,
                                                child: ListTile(
                                                  //Icon
                                                  leading: Icon(
                                                    Icons.share,
                                                    size: 37,
                                                    color: AppColors.text,
                                                  ),

                                                  //Text
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

                          //download
                          IconButton(
                            onPressed: (downloadingAlbum || deletingAlbum)
                                ? null
                                : (allDownloaded
                                      ? confirmDeleteAlbumDownloads
                                      : downloadAlbum),
                            icon: (downloadingAlbum || deletingAlbum)
                                ? SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      value:
                                          (deletingAlbum || downloadTotal == 0)
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

                    //Album Songs
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: searchresult.content.length,
                        itemBuilder: (context, index) {
                          final data = searchresult.content[index];

                          return Onesong(
                            song: data,
                            albumtracks: searchresult.content,
                            index: index + 1,
                          );
                        },
                      ),
                    ),
                    SizedBox(height: 110),
                  ],
                ),
              ),
            ),

            if (Metadatamanager.instance.currentSong != null)
              Positioned(left: 0, right: 0, bottom: 0, child: PlayingTrackui()),
          ],
        ),
      ),
    );
  }
}
