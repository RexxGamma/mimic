import 'package:flutter/material.dart';
import 'package:mimic/Backend/songlisttoplay.dart';
import 'package:provider/provider.dart';

import 'Backend/providers/privdersenums.dart';
import 'appcolors.dart';
import 'Backend/queuemanager.dart';
import 'Backend/providers/providermanager.dart';
import 'artist.dart';
import 'albumsonglist.dart';
import 'miniPlaylistView.dart';
import 'Backend/playlistsmanager.dart';
import '3dotsmanager.dart';

import 'dart:async';

import 'package:flutter/services.dart';

import 'Backend/createDownloadDir.dart';

import 'package:dio/dio.dart';

import 'dart:io';

import 'Backend/downloadManager.dart';
import 'detailspopup.dart';

class MenuOptions {
  final bool showDownload;
  final bool showAddToPlaylist;
  final bool showShare;
  final bool showViewArtist;
  final bool showViewAlbum;
  final bool showDetails;
  final bool showAddToQueue;
  final bool showStartRadio;
  final bool showDeleteFromPlaylist;
  final bool showQueueOrder;
  final bool showPlayNext;

  const MenuOptions({
    this.showDownload = true,
    this.showAddToPlaylist = true,
    this.showShare = true,
    this.showViewArtist = true,
    this.showViewAlbum = true,
    this.showDetails = true,
    this.showAddToQueue = true,
    this.showStartRadio = true,
    this.showDeleteFromPlaylist = false,
    this.showQueueOrder = false,
    this.showPlayNext = true,
  });
}

MenuOptions optionsForSource(SongSource source) {
  switch (source) {
    case SongSource.album:
      return const MenuOptions(showViewAlbum: false);
    case SongSource.exterior:
      return const MenuOptions();
    case SongSource.player:
      return const MenuOptions(showAddToQueue: false, showPlayNext: false);
    case SongSource.playlist:
      return const MenuOptions(showDeleteFromPlaylist: true);
    case SongSource.queue:
      return const MenuOptions(showQueueOrder: true, showPlayNext: false);
  }
}

class Threedotssongs extends StatefulWidget {
  const Threedotssongs({
    super.key,
    required this.icom,
    required this.data,
    this.index,
  });

  final Widget icom;
  final dynamic data;
  final int? index;

  @override
  State<Threedotssongs> createState() => _ThreedotssongsState();
}

class _ThreedotssongsState extends State<Threedotssongs> {
  MenuOptions get options => optionsForSource(SongContextManager.current);

  Future<void> _openAlbum(BuildContext sheetContext) async {
    final mp = context.read<MetadataProvider>();
    Navigator.of(sheetContext).pop();
    final album = await mp.getAlbumFromSong(widget.data);
    if (!mounted || album == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            Albumsonglist(albid: album.id, albumdata: album, type: ""),
      ),
    );
  }

  Future<String?> _downloadBanner(Dio dio, dynamic song, String base) async {
    try {
      if (song.thumbnails.isEmpty) return null;
      final p = '${base}_banner.jpg';
      await dio.download(song.thumbnails.last.url, p);
      return p;
    } catch (e) {
      debugPrint('Error descargando banner: $e');
      return null;
    }
  }

  Future<void> _startRadio(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    final mp = context.read<MetadataProvider>();
    final radio = await mp.getTrackRadio(widget.data);
    if (!mounted) return;
    QueueManager.instance.clear();
    for (final t in radio) {
      QueueManager.instance.add(t);
    }
  }

  void _startDownload(BuildContext sheetContext) {
    // 1) Capturar TODO lo que necesita la descarga ANTES de cerrar
    final songDatabase = context.read<SongDatabase>();
    final song = widget.data;

    // 2) Cerrar la hoja ya
    Navigator.of(sheetContext).pop();

    // 3) Lanzar la descarga SIN await: sigue aunque el widget se destruya
    unawaited(_downloadSong(song, songDatabase));
  }

  // 4) Función que NO depende del widget/context
  Future<void> _downloadSong(song, SongDatabase db) async {
    final dio = Dio();
    try {
      final directory = await getDownloadDirectory();
      final base = '${directory.path}/${song.source.label}_${song.id}';
      final path = '$base.mp3';

      final bannerFuture = _downloadBanner(dio, song, base);
      await downloadSongAudio(song, path);

      final file = File(path);
      if (!await file.exists() || await file.length() == 0) {
        throw Exception('El archivo descargado no existe o está vacío');
      }

      final bannerPath = await bannerFuture;

      await db.setDownloads(song, path: path, bannerPath: bannerPath);
      debugPrint('Descarga terminada: $path | banner: $bannerPath');
    } catch (e, s) {
      debugPrint('Error descargando: $e');
      debugPrint('Stacktrace: $s');
    }
  }

  @override
  Widget build(BuildContext context) {
    final opt = options;

    // ── Métricas adaptativas ────────────────────────────────────────────
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    // Referencia: 390dp (iPhone 14 / Pixel estándar).
    final scale = (width / 390).clamp(0.85, 1.35);

    final cardHeight = (100 * scale).clamp(76.0, 130.0);
    final cardIconSize = (34 * scale).clamp(24.0, 44.0);
    final cardLabelSize = (13 * scale).clamp(11.0, 16.0);
    final gap = (10 * scale).clamp(6.0, 16.0);

    // Radio superior del bottom sheet — fijo, como en las apps de referencia.
    final sheetRadius = (width * 0.06).clamp(18.0, 28.0);

    // Diálogo de playlists.
    final dialogWidth = (width * 0.85).clamp(260.0, 520.0);
    final dialogHeight = (height * 0.45).clamp(240.0, 520.0);

    // Iconos de los ListTile.
    final tileIconSize = (36 * scale).clamp(26.0, 46.0);
    final tileOverlayIconSize = (20 * scale).clamp(14.0, 26.0);

    Future<void> deleteDownloads() async {
      final db = context.read<SongDatabase>();
      int failed = 0;

      try {
        // Delete song
        final p = widget.data.downloadPath;

        if (p != null && p.isNotEmpty) {
          final f = File(p);

          if (await f.exists()) {
            try {
              await f.delete();
            } catch (e) {
              failed++;
              debugPrint('Song deletion failed: $e');
            }
          }
        }

        // Delete banner
        final bp = widget.data.downloadBannerPath;

        if (bp != null && bp.isNotEmpty) {
          final bf = File(bp);

          if (await bf.exists()) {
            try {
              await bf.delete();
            } catch (e) {
              failed++;
              debugPrint('Banner deletion failed: $e');
            }
          }
        }

        // Clear download paths in database
        await db.removeDownload(widget.data);

        if (!mounted) return;

        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failed == 0
                  ? 'Track Deleted'
                  : 'Track deleted with $failed errors',
            ),
          ),
        );
      } catch (e, stackTrace) {
        debugPrint('deleteDownloads failed: $e');
        debugPrintStack(stackTrace: stackTrace);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete downloads')),
        );
      }
    }

    Future<void> confirmDeleteDownloads() async {
      final danger =
          Colors.red.shade400; // o AppColors.accent si prefieres marca

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

            // ── Header ─────────────────────────────────────────────────
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
                    Icons.download_done_rounded,
                    color: danger,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Delete download',
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
                  'You can download it again later',
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

            // ── Contenido: mini-card con la pista ──────────────────────
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
                    Icons.audio_file_rounded,
                    size: 18,
                    color: AppColors.text2,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Remove the offline copy for this track',
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

      if (ok == true) await deleteDownloads();
    }

    return IconButton(
      onPressed: () {
        if (SongContextManager.current == SongSource.queue) return;

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (sheetContext) {
            return DraggableScrollableSheet(
              // ── Tamaños relativos a la pantalla (0.0 – 1.0) ──
              initialChildSize: 0.55, // tamaño al abrir
              minChildSize: 0.30, // mínimo al arrastrar hacia abajo
              maxChildSize: 0.95, // máximo al expandir hacia arriba
              expand: false, // respeta initialChildSize
              snap: true, // se "pega" a tamaños intermedios
              snapSizes: const [0.55, 0.95],
              builder: (context, scrollController) {
                // Tarjetas superiores (visibles según las opciones).
                final actionCards = <Widget>[
                  if (widget.data.downloadPath == null)
                    _ActionCard(
                      icon: Icons.download_for_offline_outlined,
                      label: 'download',
                      height: cardHeight,
                      iconSize: cardIconSize,
                      labelSize: cardLabelSize,
                      onTap: () => _startDownload(sheetContext),
                    ),

                  if (widget.data.downloadPath != null &&
                      widget.data.source == metadataprovider.deezer)
                    _ActionCard(
                      icon: Icons.check_circle_outlined,
                      label: 'remove download',
                      height: cardHeight,
                      iconSize: cardIconSize,
                      labelSize: cardLabelSize,
                      onTap: () async {
                        confirmDeleteDownloads();
                      },
                    ),

                  if (opt.showAddToPlaylist)
                    _ActionCard(
                      icon: Icons.playlist_add,
                      label: 'Add to playlist',
                      height: cardHeight,
                      iconSize: cardIconSize,
                      labelSize: cardLabelSize,
                      onTap: () async {
                        final playlists = await context
                            .read<AppDatabase>()
                            .getPlaylists();
                        if (!context.mounted) return;
                        if (playlists == null) return;
                        showDialog<String>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            backgroundColor: AppColors.background,
                            title: const Text(
                              'Select Playlist',
                              style: TextStyle(
                                fontSize: 23,
                                color: AppColors.text,
                                fontFamily: 'Adwaita',
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            content: SizedBox(
                              width: dialogWidth,
                              height: dialogHeight,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final crossAxisCount =
                                      (constraints.maxWidth / 160)
                                          .floor()
                                          .clamp(2, 4);
                                  return GridView.builder(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          mainAxisExtent: 220,
                                          crossAxisSpacing: 10,
                                          mainAxisSpacing: 10,
                                        ),
                                    itemCount: playlists.length,
                                    itemBuilder: (context, index) {
                                      return Miniplaylistview(
                                        data: playlists[index],
                                        songdata: widget.data,
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  if (opt.showShare)
                    _ActionCard(
                      icon: Icons.reply,
                      label: 'share',
                      height: cardHeight,
                      iconSize: cardIconSize,
                      labelSize: cardLabelSize,
                      flipIcon: true,
                      onTap: () {
                        if (widget.data == null) return;
                        Clipboard.setData(
                          ClipboardData(text: widget.data.shareurl),
                        );
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                ];

                return ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(sheetRadius),
                  ),
                  child: Container(
                    color: AppColors.background,
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        Padding(
                          padding: EdgeInsets.all(gap),
                          child: Row(
                            children: [
                              for (int i = 0; i < actionCards.length; i++) ...[
                                if (i > 0) SizedBox(width: gap),
                                Expanded(child: actionCards[i]),
                              ],
                            ],
                          ),
                        ),

                        Divider(color: AppColors.bordier),

                        if (opt.showPlayNext)
                          GestureDetector(
                            onTap: () {
                              QueueManager.instance.add(widget.data);
                              QueueManager.instance.moveToFront(widget.data);
                              Navigator.of(sheetContext).pop();
                            },
                            child: Material(
                              color: AppColors.background,
                              child: ListTile(
                                leading: Stack(
                                  children: [
                                    Icon(
                                      Icons.menu,
                                      size: tileIconSize,
                                      color: AppColors.text,
                                    ),
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: AppColors.background,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.play_arrow,
                                          size: tileOverlayIconSize,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  'Play Next',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (opt.showViewArtist)
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ArtistWidet(
                                    id: widget.data.artists[0].id,
                                  ),
                                ),
                              );
                            },
                            child: Material(
                              color: AppColors.background,
                              child: ListTile(
                                leading: Stack(
                                  children: [
                                    Icon(
                                      Icons.person,
                                      size: tileIconSize,
                                      color: AppColors.text,
                                    ),
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: AppColors.background,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.music_note,
                                          size: tileOverlayIconSize,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  'View Artist',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  widget.data.artists.first.name,
                                  style: TextStyle(color: AppColors.text2),
                                ),
                              ),
                            ),
                          ),

                        if (opt.showViewAlbum &&
                            widget.data.album?['title'] != null)
                          GestureDetector(
                            onTap: () => _openAlbum(sheetContext),
                            child: Material(
                              color: AppColors.background,
                              child: ListTile(
                                leading: Icon(
                                  Icons.album,
                                  size: tileIconSize,
                                  color: AppColors.text,
                                ),
                                title: Text(
                                  'View Album',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  widget.data.album['title'] ?? 'Unknown Album',
                                  style: TextStyle(color: AppColors.text2),
                                ),
                              ),
                            ),
                          ),

                        if (opt.showDetails)
                          GestureDetector(
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              showDetailsPopup(context, widget.data);
                            },
                            child: Material(
                              color: AppColors.background,
                              child: ListTile(
                                leading: Icon(
                                  Icons.info_outline,
                                  size: tileIconSize,
                                  color: AppColors.text,
                                ),
                                title: Text(
                                  'Details',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (opt.showAddToQueue)
                          GestureDetector(
                            onTap: () {
                              QueueManager.instance.add(widget.data);
                              Navigator.of(sheetContext).pop();
                            },
                            child: Material(
                              color: AppColors.background,
                              child: ListTile(
                                leading: Icon(
                                  Icons.queue_play_next,
                                  size: tileIconSize,
                                  color: AppColors.text,
                                ),
                                title: Text(
                                  'Add to Queue',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (opt.showStartRadio &&
                            widget.data.source != metadataprovider.local)
                          GestureDetector(
                            onTap: () => _startRadio(sheetContext),
                            child: Material(
                              color: AppColors.background,
                              child: ListTile(
                                leading: Icon(
                                  Icons.radio,
                                  size: tileIconSize,
                                  color: AppColors.text,
                                ),
                                title: Text(
                                  'Start Radio',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (opt.showDeleteFromPlaylist)
                          GestureDetector(
                            onTap: () {
                              context.read<SongDatabase>().deleteTracks(
                                widget.data.id,
                                SongContextManager.currentPlaylistId,
                              );
                              Navigator.of(sheetContext).pop();
                            },
                            child: Material(
                              color: AppColors.background,
                              child: ListTile(
                                leading: Icon(
                                  Icons.delete_outline,
                                  size: tileIconSize,
                                  color: AppColors.text,
                                ),
                                title: Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
      icon: opt.showQueueOrder
          ? ReorderableDragStartListener(
              index: widget.index ?? 0,
              child: Icon(Icons.drag_handle, color: AppColors.text, size: 35),
            )
          : widget.icom,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 25, minHeight: 25),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.height,
    required this.iconSize,
    required this.labelSize,
    required this.onTap,
    this.flipIcon = false,
  });

  final IconData icon;
  final String label;
  final double height;
  final double iconSize;
  final double labelSize;
  final VoidCallback onTap;
  final bool flipIcon;

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Icon(icon, color: AppColors.text2, size: iconSize);
    if (flipIcon) {
      iconWidget = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0),
        child: iconWidget,
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.bordier,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.text2, fontSize: labelSize),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
