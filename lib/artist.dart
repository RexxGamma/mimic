import 'package:flutter/material.dart';
import 'package:mimic/albumview.dart';
import 'package:mimic/appcolors.dart';
import 'package:mimic/track.dart';

import 'dart:async';

import 'Backend/providers/privdersenums.dart';
import 'Backend/providers/providermanager.dart';
import 'playing_trackui.dart';
import 'Backend/songdata.dart';
import 'fullDiscographyView.dart';
import 'Backend/recordtypelabels.dart';
import 'miniArtistView.dart';
import '3dotsmanager.dart';
import 'Backend/metadatamanager.dart';
import 'Backend/audiomanager.dart';
import 'player.dart';

import 'dart:math';

import 'Backend/followedartistdb.dart';

import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'radiomenu.dart';
import 'songDiscography.dart';

import 'package:dio/dio.dart';

import 'Backend/createDownloadDir.dart';

/// Caché en memoria de artistas ya visitados. Dura mientras la app esté abierta.
class _ArtistCacheEntry {
  dynamic artist;
  List topTracks = [];
  List related = [];
  List<Albumc> albums = [];
  List<Albumc> epsAndSingles = [];

  bool complete = false; // true solo si las 4 peticiones salieron bien
  DateTime savedAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isFresh =>
      complete &&
      DateTime.now().difference(savedAt) < const Duration(minutes: 10);
}

class ArtistWidet extends StatefulWidget {
  const ArtistWidet({super.key, required this.id});
  final String id;

  @override
  State<ArtistWidet> createState() => _ArtistWidetState();
}

class _ArtistWidetState extends State<ArtistWidet> {
  var artist;
  List topTracks = [];
  List related = [];
  List<Albumc> albums = [];
  List<Albumc> epsAndSingles = [];

  static final Map<String, _ArtistCacheEntry> _cache = {};

  bool? followed;
  bool _failed = false;

  // ───────────────────────── Ciclo de vida ─────────────────────────

  @override
  void initState() {
    super.initState();
    SongContextManager.push(SongSource.exterior);
    Metadatamanager.instance.addListener(_onPlayerStateChanged);
    _loadAll();
  }

  @override
  void dispose() {
    SongContextManager.pop();
    Metadatamanager.instance.removeListener(_onPlayerStateChanged);
    super.dispose();
  }

  void _onPlayerStateChanged() {
    if (mounted) setState(() {});
  }

  // ───────────────────────── Carga ─────────────────────────

  /// Envuelve una petición para que un fallo devuelva null en vez de lanzar.
  Future<T?> _safe<T>(Future<T> request, String label) async {
    try {
      return await request;
    } catch (e) {
      debugPrint('Artista ${widget.id}: $label falló -> $e');
      return null;
    }
  }

  void _apply(_ArtistCacheEntry e) {
    setState(() {
      artist = e.artist;
      topTracks = e.topTracks;
      related = e.related;
      albums = e.albums;
      epsAndSingles = e.epsAndSingles;
    });
  }

  Future<void> _loadAll() async {
    final mp = context.read<MetadataProvider>();
    final key = '${mp.type.name}_${widget.id}';
    final cached = _cache[key];

    // 1. Visita repetida: se pinta al instante desde la caché
    if (cached != null && cached.artist != null) {
      _apply(cached);
      _refreshFollowed();
      if (cached.isFresh) return; // vigente: cero peticiones
    }

    // 2. Las 4 peticiones salen a la vez
    final artistReq = _safe(mp.getArtistById(widget.id), 'info');
    final topReq = _safe(
      mp.getArtistDiscographySongs(widget.id, maxItems: 5),
      'top tracks',
    );
    final collReq = _safe(
      mp.getArtistCollections(
        widget.id,
        albumsLimit: 10,
        epsLimit: 10,
        singlesLimit: 10,
      ),
      'discografía',
    );
    final relReq = _safe(mp.getRelatedArtists(widget.id), 'relacionados');

    final entry = cached ?? _ArtistCacheEntry();
    var allOk = true;

    // 3. El artista pinta apenas llega, sin esperar al resto
    final fetchedArtist = await artistReq;
    if (!mounted) return;
    if (fetchedArtist == null) {
      if (cached == null) setState(() => _failed = true);
      return;
    }
    entry.artist = fetchedArtist;
    setState(() => artist = fetchedArtist);
    _refreshFollowed(); // sin await: no bloquea nada

    // 4. Cada sección se pinta en el orden en que termine
    await Future.wait([
      topReq.then((v) {
        if (v == null) {
          allOk = false;
          return;
        }
        entry.topTracks = v.take(5).toList();
        if (mounted) setState(() => topTracks = entry.topTracks);
      }),
      collReq.then((v) {
        if (v == null) {
          allOk = false;
          return;
        }
        final List<Albumc> all = v;
        entry.albums = all.where((a) => a.recordType == 'album').toList();
        entry.epsAndSingles =
            (all
                    .where(
                      (a) => a.recordType == 'ep' || a.recordType == 'single',
                    )
                    .toList()
                  ..sort((a, b) {
                    final ya = int.tryParse(a.year) ?? 0;
                    final yb = int.tryParse(b.year) ?? 0;
                    return yb.compareTo(ya); // más reciente primero
                  }))
                .take(10)
                .toList();
        if (mounted) {
          setState(() {
            albums = entry.albums;
            epsAndSingles = entry.epsAndSingles;
          });
        }
      }),
      relReq.then((v) {
        if (v == null) {
          allOk = false;
          return;
        }
        entry.related = v;
        if (mounted) setState(() => related = entry.related);
      }),
    ]);

    // 5. Se guarda en caché; si algo falló, no cuenta como vigente
    //    y la próxima visita lo reintenta.
    entry.complete = allOk;
    entry.savedAt = DateTime.now();
    _cache[key] = entry;
    if (_cache.length > 30) _cache.remove(_cache.keys.first);
  }

  Future<void> _refreshFollowed() async {
    try {
      final artists = await context.read<ArtistDatabase>().getFollowedArtists();
      if (!mounted) return;
      setState(() => followed = artists.any((a) => a.id == artist.id));
    } catch (e) {
      debugPrint('Error leyendo seguidos: $e');
    }
  }

  // ───────────────────────── Acciones ─────────────────────────

  void _playFrom(dynamic song) {
    if (Metadatamanager.instance.currentSong == null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => Player()));
    }
    Metadatamanager.instance.startRadioFrom(song);
    AudioPlayerManager.instance.play(song);
  }

  void _play() {
    if (topTracks.isEmpty) return;
    _playFrom(topTracks.first);
  }

  void _shuffle() {
    if (topTracks.isEmpty) return;
    _playFrom(topTracks[Random().nextInt(topTracks.length)]);
  }

  Future<void> _follow() async {
    final artistDatabase = context.read<ArtistDatabase>();
    final a = artist;

    await artistDatabase.follow(
      SimplifiedArtist(
        id: a.id,
        name: a.name,
        thumbnailUrl: a.thumbnailUrl,
        url: a.url,
        source: a.source,
      ),
    );
    await _refreshFollowed();

    unawaited(_downloadArtistBanner(a)); // en segundo plano
  }

  Future<void> _downloadArtistBanner(dynamic a) async {
    try {
      if (a.thumbnailUrl.isEmpty) return;
      final directory = await getDownloadDirectory();
      final base = '${directory.path}/${a.source.label}_${a.id}_Artist';
      await Dio().download(a.thumbnailUrl, '${base}_banner.jpg');
    } catch (e) {
      debugPrint('Error descargando banner: $e');
    }
  }

  Future<void> _unfollow() async {
    await context.read<ArtistDatabase>().unfollow(artist);
    await _refreshFollowed();
  }

  // ───────────────────────── Widgets auxiliares ─────────────────────────

  static const _titleStyle = TextStyle(
    fontSize: 30,
    color: AppColors.text,
    fontFamily: "Adwaita",
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
  );

  Widget _sectionHeader(
    String title, {
    String? buttonLabel,
    VoidCallback? onPressed,
    double top = 20,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: top, left: 10, right: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _titleStyle,
            ),
          ),
          if (buttonLabel != null && onPressed != null)
            SizedBox(
              height: 30,
              child: OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(
                  buttonLabel,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 12,
                    fontFamily: "Adwaita",
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

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

  void _showMoreMenu() {
    final mp = context.read<MetadataProvider>();
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(120),
          topRight: Radius.circular(120),
        ),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.35,
          minChildSize: 0.2,
          maxChildSize: 0.35,
          builder: (_, scrollController) {
            return Container(
              height: 800,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListView(
                controller: scrollController,
                children: [
                  if (mp.type == metadataprovider.deezer)
                    _menuItem(
                      icon: Icons.radio,
                      label: "Start Radio",
                      onTap: () {
                        Navigator.pop(sheetContext); // cierra el sheet
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Radiomenu(artistdata: artist),
                          ),
                        );
                      },
                    ),
                  _menuItem(
                    icon: Icons.share,
                    label: "Share",
                    onTap: () {
                      Navigator.pop(sheetContext); // cierra el sheet
                      Clipboard.setData(ClipboardData(text: artist.name));
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

  Widget _placeholderImage() => Container(
    color: AppColors.bordier,
    alignment: Alignment.center,
    child: Icon(Icons.person, size: 140, color: AppColors.bordierlight),
  );

  Widget _followButton() {
    if (followed == null) return const SizedBox.shrink();

    if (followed == true) {
      return ElevatedButton(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.accent),
        ),
        onPressed: _unfollow,
        child: Text(
          "followed",
          style: TextStyle(
            color: AppColors.accentTeammate,
            fontFamily: "Adwaita",
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
          ),
        ),
      );
    }

    return OutlinedButton(
      onPressed: _follow,
      child: const Text(
        "follow",
        style: TextStyle(
          color: AppColors.text,
          fontFamily: "Adwaita",
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  Widget _seeMoreCard() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Fulldiscographyview(artistid: widget.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 10),
        child: Column(
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: AppColors.bordier,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(
                Icons.arrow_forward,
                size: 60,
                color: AppColors.bordierlight,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Full discography",
              style: TextStyle(
                fontSize: 15,
                color: AppColors.text,
                fontFamily: "Adwaita",
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        color: AppColors.background,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Couldn't load this artist",
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.text2,
                      fontFamily: "Adwaita",
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      setState(() => _failed = false);
                      _loadAll();
                    },
                    child: const Text(
                      "Retry",
                      style: TextStyle(color: AppColors.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (artist == null) {
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

    final String imageUrl = artist.thumbnailUrl ?? "";

    return Stack(
      children: [
        Container(
          color: AppColors.background,
          child: SingleChildScrollView(
            child: Column(
              children: [
                // ─── Image + name ───
                Stack(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 400,
                      child: imageUrl.isEmpty
                          ? _placeholderImage()
                          : Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholderImage(),
                            ),
                    ),

                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 350,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, AppColors.background],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 20,
                      child: Text(
                        artist.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 46,
                          height: 1.05,
                          color: AppColors.text,
                          fontFamily: "Adwaita",
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),

                // ─── Botones principales ───
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 5),
                  child: Row(
                    children: [
                      // Play
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(60)),
                          color: AppColors.accent,
                        ),
                        child: IconButton(
                          onPressed: _play,
                          icon: Icon(Icons.play_arrow),
                          iconSize: 45,
                          color: AppColors.accentTeammate,
                        ),
                      ),

                      // Shuffle
                      IconButton(
                        onPressed: _shuffle,
                        icon: Icon(
                          Icons.shuffle,
                          size: 37,
                          color: AppColors.text,
                        ),
                      ),

                      _followButton(),

                      IconButton(
                        onPressed: _showMoreMenu,
                        icon: Icon(
                          Icons.more_horiz,
                          size: 37,
                          color: AppColors.text,
                        ),
                      ),

                      // Follow / Followed
                    ],
                  ),
                ),

                // ─── Popular ───
                if (topTracks.isNotEmpty) ...[
                  _sectionHeader(
                    "Popular",
                    top: 10,
                    buttonLabel: "see all",
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SongDiscography(artistId: artist.id),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 10, right: 10),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: topTracks.length,
                      itemBuilder: (context, index) =>
                          Onesong(song: topTracks[index]),
                    ),
                  ),
                ],

                // ─── Álbumes ───
                if (albums.isNotEmpty) ...[
                  _sectionHeader("Albums"),
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: SizedBox(
                      height: 220,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: albums.length + 1, // +1 por la tarjeta final
                        itemBuilder: (context, index) {
                          if (index == albums.length) return _seeMoreCard();

                          final album = albums[index];
                          return AlbumView(
                            data: album,
                            label: recordTypeLabel(album.recordType),
                          );
                        },
                      ),
                    ),
                  ),
                ],

                // ─── Singles & EP's (ya vienen ordenados y limitados a 10) ───
                if (epsAndSingles.isNotEmpty) ...[
                  _sectionHeader("Singles & EP's", top: 30),
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: SizedBox(
                      height: 220,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: epsAndSingles.length + 1,
                        itemBuilder: (context, index) {
                          if (index == epsAndSingles.length)
                            return _seeMoreCard();

                          final album = epsAndSingles[index];
                          return AlbumView(
                            data: album,
                            label: recordTypeLabel(album.recordType),
                          );
                        },
                      ),
                    ),
                  ),
                ],

                // ─── Fans also like ───
                if (related.isNotEmpty) ...[
                  _sectionHeader("Fans also like", top: 10),
                  SizedBox(
                    height: 250,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: related.length,
                      itemBuilder: (context, index) {
                        return SizedBox(
                          width: 150,
                          child: Miniartistview(data: related[index]),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 110),
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
    );
  }
}
