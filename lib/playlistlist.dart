import 'package:flutter/material.dart';
import 'package:mimic/appcolors.dart';
import 'package:mimic/track.dart';
import 'package:flutter/services.dart';

import 'Backend/playlisttransfer.dart';
import 'menu.dart';
import 'Backend/queuemanager.dart';
import 'Backend/songlisttoplay.dart';
import 'Backend/songdata.dart';
import 'Backend/playlistsmanager.dart';
import '3dotsmanager.dart';

import 'package:provider/provider.dart';

import 'Backend/metadatamanager.dart';
import 'playing_trackui.dart';

import 'dart:io';

import 'Backend/audiomanager.dart';
import 'player.dart';

import 'dart:math';

import 'Backend/createDownloadDir.dart';
import 'Backend/downloadManager.dart';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class Playlistlist extends StatefulWidget {
  const Playlistlist({super.key, required this.playlist, required this.name});
  final int playlist;
  final String name;

  @override
  State<Playlistlist> createState() => _PlaylistlistState();
}

enum PlaylistSort {
  dateAdded('Date added'),
  title('Title'),
  duration('Duration'),
  downloaded('Downloaded');

  const PlaylistSort(this.label);
  final String label;
}

class _PlaylistlistState extends State<Playlistlist> {
  List<SongInfo> songlist = [];
  SongDatabase? _songDb;
  bool get _isFavorites => widget.playlist == AppDatabase.favoritesId;

  late String _name = widget.name;
  String _cover = '';

  bool downloadingPlaylist = false;
  bool deletingPlaylist = false;
  bool allDownloaded = false;
  int downloadedCount = 0;
  int downloadTotal = 0;

  // ── Buscador ──
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadCover();
    SongContextManager.push(SongSource.playlist);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _songDb ??= context.read<SongDatabase>();
    if (_songDb != null) {
      _songDb!.removeListener(_onSongsChanged);
      _songDb!.addListener(_onSongsChanged);
    }
  }

  @override
  void dispose() {
    _songDb?.removeListener(_onSongsChanged);
    _searchController.dispose();
    SongContextManager.pop();
    super.dispose();
  }

  List<SongInfo> _source = []; // orden original de la DB
  PlaylistSort _sort = PlaylistSort.dateAdded;
  bool _ascending = true;

  Future<void> _exportPlaylist() async {
    if (_source.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('La playlist está vacía')));
      return;
    }

    // Favoritos se guarda de más nuevo a más viejo; en el archivo va al revés
    final tracks = _isFavorites ? _source.reversed.toList() : _source;

    final msg = await PlaylistTransfer.exportPlaylists([
      (title: _name, songs: tracks, favorites: _isFavorites),
    ], fileName: PlaylistTransfer.fileNameFor(_name));
    if (!mounted || msg == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _copyTrackNames() async {
    if (_source.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('La playlist está vacía')));
      return;
    }

    final text = _source
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value.name}')
        .join('\n');

    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_source.length} canciones copiadas')),
    );
  }

  /// Devuelve una copia ordenada. Dart's sort no es estable, así que uso
  /// el índice original como desempate para que los empates no se barajen.
  List<SongInfo> _sorted(List<SongInfo> src) {
    final entries = src.asMap().entries.toList();

    entries.sort((a, b) {
      int c;
      switch (_sort) {
        case PlaylistSort.dateAdded:
          c = a.key.compareTo(b.key);
          break;
        case PlaylistSort.title:
          c = a.value.name.toLowerCase().compareTo(b.value.name.toLowerCase());
          break;
        case PlaylistSort.duration:
          c = a.value.duration.compareTo(b.value.duration);
          break;
        case PlaylistSort.downloaded:
          // ascendente = descargadas primero
          final da = a.value.downloadPath != null ? 0 : 1;
          final db = b.value.downloadPath != null ? 0 : 1;
          c = da.compareTo(db);
          break;
      }
      if (!_ascending) c = -c;
      return c != 0 ? c : a.key.compareTo(b.key);
    });

    return entries.map((e) => e.value).toList();
  }

  List<SongInfo> _filter(List<SongInfo> src) {
    if (_searchQuery.isEmpty) return src;
    final q = _searchQuery.toLowerCase().trim();
    if (q.isEmpty) return src;

    return src.where((s) {
      final artistNames = s.artists.map((a) => a.name).join(' ');
      final haystack = '${s.name} $artistNames'.toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  void _applySort() => setState(() => songlist = _sorted(_filter(_source)));

  void _onSearchChanged(String v) {
    _searchQuery = v.trim();
    _applySort();
  }

  void _clearSearch() {
    _searchController.clear();
    _searchQuery = '';
    _applySort();
  }

  void _selectSort(PlaylistSort sort) {
    _sort = sort;
    _ascending = true; // cada criterio arranca en su orden natural
    _applySort();
  }

  void _toggleDirection() {
    _ascending = !_ascending;
    _applySort();
  }

  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            for (final option in PlaylistSort.values)
              ListTile(
                title: Text(
                  option.label,
                  style: TextStyle(
                    color: option == _sort ? AppColors.accent : AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: option == _sort
                    ? Icon(Icons.check, color: AppColors.accent)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _selectSort(option);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String get _totalDuration {
    final total = songlist.fold<Duration>(
      Duration.zero,
      (a, s) => a + s.duration,
    );
    final h = total.inHours;
    final m = total.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${total.inMinutes}:$s';
  }

  // ───────────────────────── Carga ─────────────────────────

  Future<void> _load() async {
    final s = await context.read<SongDatabase>().getTracks(widget.playlist);
    SongContextManager.currentPlaylistId = widget.playlist;
    if (!mounted) return;
    setState(() {
      _source = s;
      songlist = _sorted(_filter(s));
    });
    refreshDownloadedState();
  }

  void _onSongsChanged() => _load();

  Future<void> _loadCover() async {
    final c = await context.read<AppDatabase>().getPlaylistCover(
      widget.playlist,
    );
    if (!mounted) return;
    setState(() => _cover = c);
  }

  // ───────────────────────── Edición ─────────────────────────

  /// Copia la imagen a una carpeta permanente y devuelve la ruta nueva.
  Future<String> _saveCoverFile(String tempPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final coversDir = Directory(p.join(dir.path, 'playlist_covers'));
    if (!await coversDir.exists()) await coversDir.create(recursive: true);

    // Nombre único para que Flutter no sirva la imagen vieja desde caché
    final ext = p.extension(tempPath).isEmpty ? '.jpg' : p.extension(tempPath);
    final dest = p.join(
      coversDir.path,
      '${widget.playlist}_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    await File(tempPath).copy(dest);
    return dest;
  }

  Future<void> _editPlaylist() async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) =>
          _EditPlaylistDialog(initialName: _name, currentCover: _cover),
    );
    if (result == null || !mounted) return;

    final appDb = context.read<AppDatabase>();

    // Nombre
    if (result.name.isNotEmpty && result.name != _name) {
      await appDb.renamePlaylist(widget.playlist, result.name);
      if (!mounted) return;
      setState(() => _name = result.name);
    }

    // Portada
    final oldCover = _cover;
    String? newCover;
    if (result.newCoverPath != null) {
      newCover = await _saveCoverFile(result.newCoverPath!);
    } else if (result.removeCover) {
      newCover = '';
    }

    if (newCover != null) {
      await appDb.setPlaylistCover(widget.playlist, newCover);

      // Borra el archivo anterior para no acumular basura
      if (oldCover.isNotEmpty) {
        try {
          final f = File(oldCover);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _cover = newCover!);
    }
  }

  // ───────────────────────── Descargas ─────────────────────────

  String _pathFor(Directory dir, dynamic song) =>
      '${dir.path}/${song.source.label}_${song.id}.mp3';

  /// Revisa en disco si TODAS las canciones ya están descargadas.
  Future<void> refreshDownloadedState() async {
    if (_source.isEmpty) {
      if (mounted) setState(() => allDownloaded = false);
      return;
    }
    final dir = await getDownloadDirectory();
    var all = true;
    for (final song in _source) {
      final filePath = song.downloadPath ?? _pathFor(dir, song);
      if (!await File(filePath).exists()) {
        all = false;
        break;
      }
    }
    if (mounted) setState(() => allDownloaded = all);
  }

  Future<void> downloadPlaylist() async {
    if (downloadingPlaylist || deletingPlaylist || _source.isEmpty) return;

    final db = context.read<SongDatabase>(); // antes de los await
    // copia: _load() puede reemplazar _source mientras se descarga
    final songs = List<SongInfo>.from(_source);

    setState(() {
      downloadingPlaylist = true;
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
        setState(() => downloadingPlaylist = false);
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

  Future<void> confirmDeletePlaylistDownloads() async {
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
          'Delete ${_source.length} tracks from this playlist?',
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

    if (ok == true) await deletePlaylistDownloads();
  }

  Future<void> deletePlaylistDownloads() async {
    if (deletingPlaylist || downloadingPlaylist) return;
    setState(() => deletingPlaylist = true);

    final db = context.read<SongDatabase>(); // antes de los await
    final dir = await getDownloadDirectory();
    final songs = List<SongInfo>.from(_source);
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
    setState(() => deletingPlaylist = false);
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

  // ───────────────────────── UI ─────────────────────────

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Material(
        color: AppColors.background,
        child: ListTile(
          leading: Icon(icon, size: 37, color: AppColors.text),
          title: Text(
            label,
            style: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _showMenu() {
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
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListView(
                controller: scrollController,
                children: [
                  if (!_isFavorites)
                    _menuItem(
                      icon: Icons.edit_outlined,
                      label: "Edit",
                      onTap: () {
                        Navigator.of(context).pop(); // cierra el bottom sheet
                        _editPlaylist();
                      },
                    ),
                  _menuItem(
                    icon: Icons.queue_play_next,
                    label: "Add to Queue",
                    onTap: () {
                      print("KESO LOL");
                      QueueManager.instance.addAll(_source);
                      Navigator.of(context).pop();
                    },
                  ),

                  _menuItem(
                    icon: Icons.share,
                    label: "Share",
                    onTap: () {
                      Navigator.of(context).pop();
                      _copyTrackNames();
                    },
                  ),

                  _menuItem(
                    icon: Icons.file_upload_outlined,
                    label: "Export",
                    onTap: () {
                      Navigator.of(context).pop();
                      _exportPlaylist();
                    },
                  ),
                  if (!_isFavorites)
                    _menuItem(
                      icon: Icons.delete_outline,
                      label: "Delete",
                      onTap: () {
                        final appDb = context.read<AppDatabase>();

                        // Borra el archivo de portada para no dejarlo huérfano
                        if (_cover.isNotEmpty) {
                          try {
                            File(_cover).deleteSync();
                          } catch (_) {}
                        }

                        Navigator.of(context).pop();
                        Navigator.of(context).pop();
                        appDb.deletePlaylist(widget.playlist);
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        children: [
          Container(
            color: AppColors.background,
            child: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      //Buscador
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          style: TextStyle(
                            color: AppColors.text,
                            fontFamily: 'Adwaita',
                          ),
                          cursorColor: AppColors.accent,
                          decoration: InputDecoration(
                            hintText: 'Buscar en la playlist…',
                            hintStyle: TextStyle(
                              color: AppColors.text2,
                              fontFamily: 'Adwaita',
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: AppColors.text2,
                            ),
                            suffixIcon: _searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      color: AppColors.text2,
                                    ),
                                    onPressed: _clearSearch,
                                  ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide(color: AppColors.text2),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide(color: AppColors.accent),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 0,
                              horizontal: 16,
                            ),
                          ),
                        ),
                      ),

                      // Banner
                      if (_searchQuery.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: SizedBox(
                            width: double.infinity,
                            height: 360,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: _isFavorites
                                  ? Container(
                                      color: AppColors.bordier,
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.favorite,
                                        size: 330,
                                        color: AppColors.bordierlight,
                                      ),
                                    )
                                  : playlistBanner(_source, _cover),
                            ),
                          ),
                        ),

                      // Nombre
                      if (_searchQuery.isEmpty)
                        Align(
                          alignment: AlignmentGeometry.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              _name,
                              style: TextStyle(
                                fontSize: 30,
                                color: AppColors.text,
                                fontFamily: "Adwaita",
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),

                      // Canciones y duración
                      if (_searchQuery.isEmpty)
                        Align(
                          alignment: AlignmentGeometry.bottomLeft,
                          child: Text(
                            _searchQuery.isEmpty
                                ? "${songlist.length} Songs · $_totalDuration"
                                : "${songlist.length} of ${_source.length} · $_totalDuration",
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.text2,
                              fontFamily: "Adwaita",
                              fontWeight: FontWeight.w400,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),

                      // Botones
                      if (_searchQuery.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              // Play
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(60),
                                  ),
                                  color: AppColors.accent,
                                ),
                                child: IconButton(
                                  onPressed: () {
                                    if (songlist.isEmpty) return;

                                    mainMenuKey.currentState
                                        ?.updatepreviewplayer(songlist.first);
                                    Metadatamanager.instance.startRadioFrom(
                                      songlist.first,
                                    );
                                    QueueManager.instance
                                      ..clear()
                                      ..addAll(songlist.skip(1));
                                    AudioPlayerManager.instance.play(
                                      songlist.first,
                                    );
                                  },
                                  icon: Icon(Icons.play_arrow),
                                  iconSize: 45,
                                  color: AppColors.accentTeammate,
                                ),
                              ),

                              // Shuffle
                              if (_searchQuery.isEmpty)
                                IconButton(
                                  onPressed: () {
                                    if (songlist.isEmpty) return;
                                    final index = Random().nextInt(
                                      songlist.length,
                                    );
                                    mainMenuKey.currentState
                                        ?.updatepreviewplayer(songlist[index]);
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
                                      songlist[index],
                                    );
                                    QueueManager.instance
                                      ..clear()
                                      ..addAll(songlist.skip(1));
                                    AudioPlayerManager.instance.play(
                                      songlist[index],
                                    );
                                  },
                                  icon: Icon(
                                    Icons.shuffle,
                                    size: 37,
                                    color: AppColors.text,
                                  ),
                                ),

                              // 3 puntos
                              if (_searchQuery.isEmpty)
                                IconButton(
                                  onPressed: _showMenu,
                                  icon: Icon(
                                    Icons.more_horiz,
                                    size: 37,
                                    color: AppColors.text,
                                  ),
                                ),

                              Spacer(),

                              // Descargar
                              if (_searchQuery.isEmpty)
                                IconButton(
                                  onPressed:
                                      (downloadingPlaylist || deletingPlaylist)
                                      ? null
                                      : (allDownloaded
                                            ? confirmDeletePlaylistDownloads
                                            : downloadPlaylist),
                                  icon:
                                      (downloadingPlaylist || deletingPlaylist)
                                      ? SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: CircularProgressIndicator(
                                            value:
                                                (deletingPlaylist ||
                                                    downloadTotal == 0)
                                                ? null
                                                : downloadedCount /
                                                      downloadTotal,
                                            strokeWidth: 3,
                                            color: AppColors.accent,
                                          ),
                                        )
                                      : Icon(
                                          allDownloaded
                                              ? Icons.download_done
                                              : Icons
                                                    .download_for_offline_outlined,
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

                      // Orden
                      if (_searchQuery.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 30),
                          child: Row(
                            children: [
                              OutlinedButton(
                                onPressed: _showSortMenu,
                                child: Text(
                                  _sort.label,
                                  style: const TextStyle(
                                    color: AppColors.text,
                                    fontFamily: "Adwaita",
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _toggleDirection,
                                icon: Icon(
                                  _ascending
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  size: 30,
                                  color: AppColors.text,
                                ),
                              ),
                              Spacer(),
                            ],
                          ),
                        ),

                      // Canciones
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: songlist.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 40,
                                ),
                                child: Center(
                                  child: Text(
                                    _searchQuery.isEmpty
                                        ? 'La playlist está vacía'
                                        : 'Sin resultados para "$_searchQuery"',
                                    style: TextStyle(
                                      color: AppColors.text2,
                                      fontFamily: 'Adwaita',
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: songlist.length,
                                itemBuilder: (context, index) => Onesong(
                                  song: songlist[index],
                                  albumtracks: songlist,
                                ),
                              ),
                      ),
                      SizedBox(height: 80),
                    ],
                  ),
                ),
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
    );
  }
}

// ───────────────────────── Banner ─────────────────────────

Widget playlistBanner(List<SongInfo> songs, [String cover = '']) {
  // Portada custom: tiene prioridad sobre el mosaico
  if (cover.isNotEmpty && File(cover).existsSync()) {
    return SizedBox.expand(child: Image.file(File(cover), fit: BoxFit.cover));
  }

  final tracks = songs.take(4).toList();

  Widget empty() => Container(color: AppColors.bordier);

  Widget banner(SongInfo song) {
    // Archivo descargado, solo si realmente existe
    final path = song.downloadBannerPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => empty(),
      );
    }

    if (song.thumbnails.isEmpty) return empty();

    // 4ta miniatura si existe, si no la última disponible
    final thumb = song.thumbnails.length > 3
        ? song.thumbnails[3]
        : song.thumbnails.last;

    return Image.network(
      thumb.url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => empty(),
    );
  }

  Widget cell(int i) => i < tracks.length ? banner(tracks[i]) : empty();

  if (tracks.isEmpty) return empty();
  if (tracks.length == 1) return banner(tracks[0]);

  return Column(
    children: [
      Expanded(
        child: Row(
          children: [
            Expanded(child: cell(0)),
            Expanded(child: cell(1)),
          ],
        ),
      ),
      Expanded(
        child: Row(
          children: [
            Expanded(child: cell(2)),
            Expanded(child: cell(3)),
          ],
        ),
      ),
    ],
  );
}

// ───────────────────────── Diálogo de edición ─────────────────────────

class _EditResult {
  final String name;
  final String? newCoverPath; // ruta temporal elegida, null si no cambió
  final bool removeCover;
  _EditResult(this.name, this.newCoverPath, this.removeCover);
}

class _EditPlaylistDialog extends StatefulWidget {
  const _EditPlaylistDialog({
    required this.initialName,
    required this.currentCover,
  });
  final String initialName;
  final String currentCover;

  @override
  State<_EditPlaylistDialog> createState() => _EditPlaylistDialogState();
}

class _EditPlaylistDialogState extends State<_EditPlaylistDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  String? _pickedPath;
  bool _removeCover = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (x == null) return;
    setState(() {
      _pickedPath = x.path;
      _removeCover = false;
    });
  }

  void _save() => Navigator.pop(
    context,
    _EditResult(_controller.text.trim(), _pickedPath, _removeCover),
  );

  Widget _preview() {
    ImageProvider? img;
    if (_pickedPath != null) {
      img = FileImage(File(_pickedPath!));
    } else if (!_removeCover &&
        widget.currentCover.isNotEmpty &&
        File(widget.currentCover).existsSync()) {
      img = FileImage(File(widget.currentCover));
    }

    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: 140,
        height: 140,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.bordier,
          borderRadius: BorderRadius.circular(5),
          image: img == null
              ? null
              : DecorationImage(image: img, fit: BoxFit.cover),
        ),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.edit, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCover =
        _pickedPath != null ||
        (!_removeCover && widget.currentCover.isNotEmpty);

    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(
        'Editar playlist',
        style: TextStyle(
          color: AppColors.text,
          fontFamily: 'Adwaita',
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _preview(),
            if (hasCover)
              TextButton(
                onPressed: () => setState(() {
                  _pickedPath = null;
                  _removeCover = true;
                }),
                child: Text(
                  'Quitar portada',
                  style: TextStyle(color: AppColors.text2),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Nombre',
                hintStyle: TextStyle(color: AppColors.text2),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.text2),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accent),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: AppColors.text2)),
        ),
        TextButton(
          onPressed: _save,
          child: Text('Save', style: TextStyle(color: AppColors.accent)),
        ),
      ],
    );
  }
}
