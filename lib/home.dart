import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mimic/playing_trackui.dart';
import 'package:provider/provider.dart';

import 'menu.dart';
import 'player.dart';
import 'Backend/metadatamanager.dart';
import 'Backend/audiomanager.dart';
import 'appcolors.dart';
import 'track.dart';
import 'playlistview.dart';
import 'miniArtistView.dart';
import 'libraryabumView.dart';
import 'Backend/songdata.dart';
import 'Backend/historydb.dart';
import 'Backend/playlistsmanager.dart';
import 'Backend/followedartistdb.dart';
import 'Backend/albumsSaved.dart';
import 'Backend/providers/providermanager.dart';
import 'Backend/providers/privdersenums.dart';
import '3dotsmanager.dart';
import 'Backend/queuemanager.dart';

const _netTimeout = Duration(seconds: 12);
const _cacheTtl = Duration(minutes: 10);
const _songsPerPage = 4;

// ─────────────────────────────────────────────────────────────
// Modelos internos
// ─────────────────────────────────────────────────────────────

class _LikeSection {
  final String artistName;
  final List<SimplifiedArtist> artists;
  _LikeSection(this.artistName, this.artists);
}

class _DailyMix {
  final String title;
  final String subtitle;
  final List<SongInfo> songs;
  _DailyMix(this.title, this.subtitle, this.songs);
}

class _DailyCache {
  final metadataprovider type;
  final String day;
  final List<_DailyMix> mixes;
  _DailyCache(this.type, this.day, this.mixes);
}

_DailyCache? _dailyCache;

String _today() {
  final n = DateTime.now();
  return '${n.year}${n.month.toString().padLeft(2, '0')}'
      '${n.day.toString().padLeft(2, '0')}';
}

class _Sec<T> {
  T value;
  bool loading = true;
  _Sec(this.value);
}

class _ArtistSection {
  final String artistName;
  final List<SongInfo> songs;

  _ArtistSection(this.artistName, this.songs);
}

typedef _ArtistRef = ({String id, String name});

class _Taste {
  /// Frecuentes primero, luego seguidos (mezclados).
  final List<_ArtistRef> artists;

  /// Solo los seguidos del proveedor activo.
  final List<_ArtistRef> followed;
  const _Taste(this.artists, this.followed);
}

class _HomeCache {
  final metadataprovider type;
  final DateTime at = DateTime.now();
  final List<SongInfo> recommended;
  final List<Albumc> recAlbums;
  final List<_ArtistSection> artistSections;
  final List<Albumc> releases;
  final List<_LikeSection> moreLike;
  _HomeCache(
    this.type,
    this.recommended,
    this.recAlbums,
    this.artistSections,
    this.releases,
    this.moreLike,
  );
}

/// Ejecuta las peticiones en tandas para no lanzar 30 a la vez.
Future<List<List<T>>> _inBatches<T>(
  List<Future<List<T>> Function()> jobs, {
  int size = 4,
}) async {
  final out = <List<T>>[];
  for (var i = 0; i < jobs.length; i += size) {
    final res = await Future.wait(
      jobs
          .skip(i)
          .take(size)
          .map((j) => j().timeout(_netTimeout).catchError((_) => <T>[])),
    );
    out.addAll(res);
  }
  return out;
}

_HomeCache? _homeCache;

// ─────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────

class HomeMenu extends StatefulWidget {
  const HomeMenu({super.key});

  @override
  State<HomeMenu> createState() => _HomeMenuState();
}

class _HomeMenuState extends State<HomeMenu> {
  metadataprovider? _type;
  int _gen = 0;
  final moreLike = _Sec<List<_LikeSection>>([]);
  final recents = _Sec<List<SongInfo>>([]);
  final recommended = _Sec<List<SongInfo>>([]);
  final recAlbums = _Sec<List<Albumc>>([]);
  final releases = _Sec<List<Albumc>>([]);
  final artistSections = _Sec<List<_ArtistSection>>([]);

  final dailyMixes = _Sec<List<_DailyMix>>([]);

  List<Map<String, dynamic>> libPlaylists = [];
  List<Albumc> libAlbums = [];
  List<SimplifiedArtist> libArtists = [];
  bool libLoading = true;

  bool _live(int gen) => mounted && gen == _gen;

  // ─── Carga ──────────────────────────────────────────────────

  Future<void> _loadDaily(
    int gen,
    MetadataProvider mp,
    metadataprovider type,
    Future<_Taste> tasteF,
  ) async {
    debugPrint('DAILY: called');
    final day = _today();
    final c = _dailyCache;
    if (c != null && c.type == type && c.day == day) {
      if (!_live(gen)) return;
      setState(
        () => dailyMixes
          ..value = c.mixes
          ..loading = false,
      );
      return;
    }

    if (_live(gen)) {
      setState(
        () => dailyMixes
          ..value = []
          ..loading = true,
      );
    }

    final sw = Stopwatch()..start();
    final out = <_DailyMix>[];
    var expected = 0;
    try {
      final taste = await tasteF;
      debugPrint(
        'Daily: taste listo (${sw.elapsedMilliseconds}ms), '
        '${taste.artists.length} artistas',
      );
      final dayInt = int.parse(day);

      final pool = [...taste.artists]..sort((a, b) => a.id.compareTo(b.id));
      pool.shuffle(Random(dayInt ^ type.index));
      final seeds = pool.take(4).toList();
      expected = seeds.length;

      // De 2 en 2, mostrando cada tanda en cuanto está lista.
      for (var i = 0; i < seeds.length; i += 2) {
        final batch = seeds.skip(i).take(2).toList();
        final res = await Future.wait([
          for (var k = 0; k < batch.length; k++)
            _buildMix(i + k, batch[k], mp, dayInt + i + k),
        ]);
        out.addAll(res.whereType<_DailyMix>());
        debugPrint(
          'Daily: tanda ${i ~/ 2 + 1} lista '
          '(${sw.elapsedMilliseconds}ms), ${out.length} mixes',
        );
        if (!_live(gen)) return;
        setState(
          () => dailyMixes
            ..value = List.of(out)
            ..loading = i + 2 < seeds.length,
        );
      }
    } catch (e) {
      debugPrint('Home daily error: $e');
    }
    if (!_live(gen)) return;
    if (out.isNotEmpty && out.length == expected) {
      _dailyCache = _DailyCache(type, day, List.of(out));
    }
    setState(
      () => dailyMixes
        ..value = List.of(out)
        ..loading = false,
    );
  }

  Future<_DailyMix?> _buildMix(
    int n,
    _ArtistRef seed,
    MetadataProvider mp,
    int rndSeed,
  ) async {
    Future<List<T>> safe<T>(Future<List<T>> f) =>
        f.timeout(const Duration(seconds: 8)).catchError((_) => <T>[]);

    Future<_DailyMix?> run() async {
      final results = await Future.wait([
        safe<SongInfo>(mp.getArtistTopTracks(seed.id, limit: 10)),
        safe<SimplifiedArtist>(mp.getRelatedArtists(seed.id, limit: 2)),
      ]);
      final top = results[0] as List<SongInfo>;
      final related = results[1] as List<SimplifiedArtist>;

      final extra = await Future.wait(
        related.map(
          (r) => safe<SongInfo>(mp.getArtistTopTracks(r.id, limit: 5)),
        ),
      );

      final seen = <String>{};
      final songs = [
        ...top,
        ...extra.expand((l) => l),
      ].where((s) => seen.add(s.id)).toList()..shuffle(Random(rndSeed));
      if (songs.length < 5) return null;

      final names = [seed.name, ...related.map((r) => r.name)];
      return _DailyMix(
        'Daily Mix ${n + 1}',
        '${names.join(', ')} y más',
        songs.take(25).toList(),
      );
    }

    try {
      // Tope duro por mix: si se cuelga, se descarta.
      return await run().timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Daily: mix ${n + 1} descartada: $e');
      return null;
    }
  }

  Future<void> _loadAll({bool force = false}) async {
    if (!mounted) return;
    final gen = ++_gen;
    debugPrint('LOADALL: start gen=$gen');

    final mp = context.read<MetadataProvider>();
    final type = mp.type;
    final appDb = context.read<AppDatabase>();
    final artistDb = context.read<ArtistDatabase>();
    final albumDb = context.read<AlbumDatabase>();

    final cache = _homeCache;
    final cacheOk =
        !force &&
        cache != null &&
        cache.type == type &&
        DateTime.now().difference(cache.at) < _cacheTtl;

    setState(() {
      if (cacheOk) {
        recommended
          ..value = cache.recommended
          ..loading = false;
        recAlbums
          ..value = cache.recAlbums
          ..loading = false;
        artistSections
          ..value = cache.artistSections
          ..loading = false;
        releases
          ..value = cache.releases
          ..loading = false;
        moreLike
          ..value = cache.moreLike
          ..loading = false;
      } else if (!force) {
        recommended
          ..value = []
          ..loading = true;
        recAlbums
          ..value = []
          ..loading = true;
        artistSections
          ..value = []
          ..loading = true;
        releases
          ..value = []
          ..loading = true;
        moreLike
          ..value = []
          ..loading = true;
      }
    });

    // Fuera del if: lo usan Daily y el resto.
    final taste = _loadTaste(type, artistDb);

    final futures = <Future<void>>[
      _loadRecents(gen, type),
      _loadLibrary(gen, appDb, artistDb, albumDb),
      _loadDaily(gen, mp, type, taste),
    ];

    if (!cacheOk) {
      futures.addAll([
        _loadRecommended(gen, mp, type, taste),
        _loadRecAlbums(gen, mp, taste),
        _loadArtistSections(gen, mp, taste),
        _loadReleases(gen, mp, taste),
        _loadMoreLike(gen, mp, taste),
      ]);
    }

    await Future.wait(futures);

    if (!cacheOk &&
        _live(gen) &&
        (recommended.value.isNotEmpty || releases.value.isNotEmpty)) {
      _homeCache = _HomeCache(
        type,
        recommended.value,
        recAlbums.value,
        artistSections.value,
        releases.value,
        moreLike.value,
      );
    }
  }

  Future<void> _loadRecents(int gen, metadataprovider type) async {
    var out = <SongInfo>[];
    try {
      out = await HistoryDatabase.instance.getRecent(source: type, limit: 12);
    } catch (e) {
      debugPrint('Home recents error: $e');
    }
    if (!_live(gen)) return;
    setState(
      () => recents
        ..value = out
        ..loading = false,
    );
  }

  Future<void> _loadMoreLike(
    int gen,
    MetadataProvider mp,
    Future<_Taste> tasteF,
  ) async {
    var out = <_LikeSection>[];
    try {
      final taste = await tasteF;
      // "More from" ya usa los 2 primeros; si no sobran, se permite repetir.
      var pool = taste.artists.skip(2).toList();
      if (pool.isEmpty) pool = [...taste.artists];
      pool.shuffle(Random());
      final count = 1 + Random().nextInt(2); // 1 o 2

      final secs = await Future.wait(
        pool.take(count).map((a) async {
          try {
            final rel = await mp
                .getRelatedArtists(a.id, limit: 12)
                .timeout(_netTimeout);
            return _LikeSection(
              a.name,
              rel.where((r) => r.id != a.id).toList(),
            );
          } catch (_) {
            return _LikeSection(a.name, const []);
          }
        }),
      );
      out = secs.where((s) => s.artists.isNotEmpty).toList();
    } catch (e) {
      debugPrint('Home more like error: $e');
    }
    if (!_live(gen)) return;
    setState(
      () => moreLike
        ..value = out
        ..loading = false,
    );
  }

  Future<void> _loadLibrary(
    int gen,
    AppDatabase appDb,
    ArtistDatabase artistDb,
    AlbumDatabase albumDb,
  ) async {
    try {
      final p = await appDb.getPlaylists();
      final al = await albumDb.getSavedAlbums();
      final ar = await artistDb.getFollowedArtists();
      if (!_live(gen)) return;
      setState(() {
        libPlaylists = p;
        libAlbums = al;
        libArtists = ar;
        libLoading = false;
      });
    } catch (e) {
      debugPrint('Home library error: $e');
      if (_live(gen)) setState(() => libLoading = false);
    }
  }

  Future<_Taste> _loadTaste(
    metadataprovider type,
    ArtistDatabase artistDb,
  ) async {
    try {
      final top = await HistoryDatabase.instance.getTopArtists(
        source: type,
        limit: 5,
      );
      final followed =
          (await artistDb.getFollowedArtists())
              .where((a) => a.source == type)
              .toList()
            ..shuffle(Random());

      final seen = <String>{};
      final out = <_ArtistRef>[];
      for (final a in top) {
        if (seen.add(a.id)) out.add((id: a.id, name: a.name));
      }
      for (final a in followed) {
        if (seen.add(a.id)) out.add((id: a.id, name: a.name));
      }
      return _Taste(
        out,
        followed.map((a) => (id: a.id, name: a.name)).toList(),
      );
    } catch (e) {
      debugPrint('Home taste error: $e');
      return const _Taste([], []);
    }
  }

  Future<void> _loadRecAlbums(
    int gen,
    MetadataProvider mp,
    Future<_Taste> tasteF,
  ) async {
    var out = <Albumc>[];
    try {
      final taste = await tasteF;
      final base =
          (taste.followed.isNotEmpty ? taste.followed : taste.artists).toList()
            ..shuffle(Random());
      final known = taste.artists.map((a) => a.id).toSet();

      // Artistas relacionados a todos los seguidos
      final relLists = await _inBatches<SimplifiedArtist>(
        base
            .map(
              (a) =>
                  () => mp.getRelatedArtists(a.id, limit: 4),
            )
            .toList(),
      );
      final seenArtists = <String>{};
      final related =
          relLists
              .expand((l) => l)
              .where((r) => !known.contains(r.id) && seenArtists.add(r.id))
              .toList()
            ..shuffle(Random());

      // Y sus álbumes
      final albumLists = await _inBatches<Albumc>(
        related
            .take(8)
            .map(
              (r) =>
                  () => mp.getArtistCollections(
                    r.id,
                    albumsLimit: 2,
                    epsLimit: 1,
                    singlesLimit: 1,
                    candidateBuffer: 20,
                    concurrency: 4,
                  ),
            )
            .toList(),
      );

      final seen = <String>{};
      out = albumLists.expand((l) => l).where((a) => seen.add(a.id)).toList()
        ..shuffle(Random());
      out = out.take(15).toList();
    } catch (e) {
      debugPrint('Home rec albums error: $e');
    }
    if (!_live(gen)) return;
    setState(
      () => recAlbums
        ..value = out
        ..loading = false,
    );
  }

  Future<void> _loadRecommended(
    int gen,
    MetadataProvider mp,
    metadataprovider type,
    Future<_Taste> tasteF,
  ) async {
    var out = <SongInfo>[];
    try {
      final taste = await tasteF;
      final seeds = await HistoryDatabase.instance.getRecent(
        source: type,
        limit: 2,
      );
      final seedIds = seeds.map((s) => s.id).toSet();

      final radioLists = await Future.wait(
        seeds.map(
          (s) => mp
              .getTrackRadio(s, limit: 10)
              .timeout(_netTimeout)
              .catchError((_) => <SongInfo>[]),
        ),
      );

      // Todos los seguidos; si no hay, los más escuchados.
      final refs =
          (taste.followed.isNotEmpty
                  ? taste.followed
                  : taste.artists.take(3).toList())
              .toList()
            ..shuffle(Random());

      final artistLists = await _inBatches<SongInfo>(
        refs
            .map(
              (a) =>
                  () => mp.getArtistTopTracks(a.id, limit: 5),
            )
            .toList(),
      );

      out = _interleave([...radioLists, ...artistLists])
        ..removeWhere((s) => seedIds.contains(s.id));
    } catch (e) {
      debugPrint('Home recommended error: $e');
    }
    if (!_live(gen)) return;
    setState(
      () => recommended
        ..value = out.take(24).toList()
        ..loading = false,
    );
  }

  Future<void> _loadArtistSections(
    int gen,
    MetadataProvider mp,
    Future<_Taste> tasteF,
  ) async {
    var out = <_ArtistSection>[];
    try {
      final taste = await tasteF;
      final secs = await Future.wait(
        taste.artists.take(2).map((a) async {
          try {
            final songs = await mp
                .getArtistTopTracks(a.id, limit: 8)
                .timeout(_netTimeout);
            return _ArtistSection(a.name, songs);
          } catch (_) {
            return _ArtistSection(a.name, const []);
          }
        }),
      );
      out = secs.where((s) => s.songs.isNotEmpty).toList();
    } catch (e) {
      debugPrint('Home artist sections error: $e');
    }
    if (!_live(gen)) return;
    setState(
      () => artistSections
        ..value = out
        ..loading = false,
    );
  }

  Future<void> _loadReleases(
    int gen,
    MetadataProvider mp,
    Future<_Taste> tasteF,
  ) async {
    var out = <Albumc>[];
    try {
      final taste = await tasteF;
      final lists = await Future.wait(
        taste.artists
            .take(5)
            .map(
              (a) => mp
                  .getArtistCollections(
                    a.id,
                    albumsLimit: 3,
                    epsLimit: 2,
                    singlesLimit: 3,
                    candidateBuffer: 20,
                    concurrency: 4,
                  )
                  .timeout(_netTimeout)
                  .catchError((_) => <Albumc>[]),
            ),
      );
      final seen = <String>{};
      out = lists.expand((l) => l).where((a) => seen.add(a.id)).toList()
        ..sort((a, b) => _year(b).compareTo(_year(a)));
      out = out.take(15).toList();
    } catch (e) {
      debugPrint('Home releases error: $e');
    }
    if (!_live(gen)) return;
    setState(
      () => releases
        ..value = out
        ..loading = false,
    );
  }

  static int _year(Albumc a) =>
      int.tryParse(a.year.length >= 4 ? a.year.substring(0, 4) : a.year) ?? 0;

  static List<SongInfo> _interleave(List<List<SongInfo>> lists) {
    final out = <SongInfo>[];
    final seen = <String>{};
    final n = lists.fold<int>(0, (m, l) => max(m, l.length));
    for (var i = 0; i < n; i++) {
      for (final l in lists) {
        if (i < l.length && seen.add(l[i].id)) out.add(l[i]);
      }
    }
    return out;
  }

  // ─── UI ─────────────────────────────────────────────────────

  static const _titleStyle = TextStyle(
    fontSize: 22,
    color: AppColors.text,
    fontFamily: "Adwaita",
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
  );

  Widget _title(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(t, style: _titleStyle),
  );

  Widget _loadingBox(double h) => SizedBox(
    height: h,
    child: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.accent,
        ),
      ),
    ),
  );

  List<Widget> _songSection(String tag, String title, _Sec<List<SongInfo>> s) {
    if (!s.loading && s.value.isEmpty) return const [];
    return [
      _title(title),
      if (s.loading && s.value.isEmpty)
        _loadingBox(240)
      else
        _SongCarousel(tag: tag, songs: s.value),
    ];
  }

  List<Widget> _cardsSection(String title, bool loading, List<Widget> tiles) {
    if (!loading && tiles.isEmpty) return const [];
    return [
      _title(title),
      if (loading && tiles.isEmpty)
        _loadingBox(266)
      else
        SizedBox(
          height: 266,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(width: 160, child: tiles[i]),
          ),
        ),
    ];
  }

  List<Widget> _libraryTiles() {
    final out = <Widget>[];
    final n = max(
      libPlaylists.length,
      max(libAlbums.length, libArtists.length),
    );
    for (var i = 0; i < n && out.length < 12; i++) {
      if (i < libPlaylists.length) {
        out.add(
          Playlistview(
            key: ValueKey('home_playlist_${libPlaylists[i]["id"]}'),
            data: libPlaylists[i],
          ),
        );
      }
      if (i < libAlbums.length) {
        out.add(AlbumView(data: libAlbums[i], label: ""));
      }
      if (i < libArtists.length) {
        out.add(Miniartistview(data: libArtists[i]));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final mp = context.watch<MetadataProvider>();
    if (_type != mp.type) {
      _type = mp.type;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
    }

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.bordier,
      onRefresh: () => _loadAll(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24, top: kToolbarHeight + 8),
        children: [
          if (dailyMixes.loading || dailyMixes.value.isNotEmpty) ...[
            _title('Daily mixes'),
            if (dailyMixes.loading && dailyMixes.value.isEmpty)
              _loadingBox(200)
            else
              _DailyCarousel(mixes: dailyMixes.value),
          ],
          ..._songSection('recents', 'Recently played', recents),
          ..._songSection('recommended', 'Recommended', recommended),
          ..._cardsSection(
            'Recommended albums',
            recAlbums.loading,
            recAlbums.value
                .map<Widget>((a) => AlbumView(data: a, label: ""))
                .toList(),
          ),
          ..._cardsSection(
            'New releases',
            releases.loading,
            releases.value
                .map<Widget>((a) => AlbumView(data: a, label: ""))
                .toList(),
          ),

          for (final sec in artistSections.value) ...[
            _title('More from ${sec.artistName}'),
            _SongCardRow(tag: 'artist_${sec.artistName}', songs: sec.songs),
          ],

          ..._cardsSection('From your library', libLoading, _libraryTiles()),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Carrusel estilo "columnas de 4 canciones" reutilizando Onesong
// ─────────────────────────────────────────────────────────────

class _SongCarousel extends StatefulWidget {
  final String tag;
  final List<SongInfo> songs;
  const _SongCarousel({required this.tag, required this.songs});

  @override
  State<_SongCarousel> createState() => _SongCarouselState();
}

class _SongCarouselState extends State<_SongCarousel> {
  late final PageController _ctrl = PageController(viewportFraction: 0.9);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = (widget.songs.length / _songsPerPage).ceil();
    return SizedBox(
      height: 240,
      child: PageView.builder(
        controller: _ctrl,
        padEnds: false,
        itemCount: pages,
        itemBuilder: (_, i) {
          final chunk = widget.songs
              .skip(i * _songsPerPage)
              .take(_songsPerPage)
              .toList();
          return Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                for (final s in chunk)
                  Onesong(
                    key: ValueKey('${widget.tag}_${s.source.name}_${s.id}'),
                    song: s,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Carrusel de tarjetas cuadradas (estilo YT Music)
// ─────────────────────────────────────────────────────────────

class _SongCardRow extends StatelessWidget {
  final String tag;
  final List<SongInfo> songs;
  const _SongCardRow({required this.tag, required this.songs});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 224,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: songs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _SongCard(
          key: ValueKey('${tag}_${songs[i].source.name}_${songs[i].id}'),
          song: songs[i],
        ),
      ),
    );
  }
}

class _SongCard extends StatelessWidget {
  static const double _size = 150;
  final SongInfo song;
  const _SongCard({super.key, required this.song});

  void _play(BuildContext context) {
    if (Metadatamanager.instance.currentSong == null) {
      Navigator.push(context, PlayerRoute());
    }
    mainMenuKey.currentState?.updatepreviewplayer(song);
    Metadatamanager.instance.startRadioFrom(song);
    AudioPlayerManager.instance.play(song);
    HistoryDatabase.instance.record(song);
  }

  Widget _placeholder() => Container(
    color: AppColors.bordier,
    alignment: Alignment.center,
    child: const Icon(Icons.music_note, size: 60, color: AppColors.text2),
  );

  @override
  Widget build(BuildContext context) {
    final url = song.thumbnails.isNotEmpty ? song.thumbnails.last.url : '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _play(context),
      child: SizedBox(
        width: _size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: _size,
                height: _size,
                child: url.isEmpty
                    ? _placeholder()
                    : Image.network(
                        url,
                        cacheWidth: 300,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              song.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 14,
                fontFamily: "Adwaita",
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
            Text(
              song.artists.map((a) => a.name).join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.text2,
                fontSize: 12,
                fontFamily: "Adwaita",
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Daily mixes: carrusel + página de detalle
// ─────────────────────────────────────────────────────────────

class _DailyCarousel extends StatelessWidget {
  final List<_DailyMix> mixes;
  const _DailyCarousel({required this.mixes});

  static const double _extent = 300;

  Widget _cover(_DailyMix mix) {
    final urls = <String>[];
    for (final s in mix.songs) {
      if (s.thumbnails.isEmpty) continue;
      final u = s.thumbnails.last.url;
      if (u.isNotEmpty && !urls.contains(u)) urls.add(u);
      if (urls.length == 4) break;
    }

    Widget img(String u) => Image.network(
      u,
      cacheWidth: 300,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => Container(color: AppColors.bordier),
    );

    if (urls.isEmpty) {
      return Container(
        color: AppColors.bordier,
        child: const Icon(Icons.music_note, size: 60, color: AppColors.text2),
      );
    }
    if (urls.length < 4) return img(urls.first);

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: img(urls[0])),
              Expanded(child: img(urls[1])),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: img(urls[2])),
              Expanded(child: img(urls[3])),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: CarouselView(
        itemExtent: _extent,
        shrinkExtent: 200,
        itemSnapping: true,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        backgroundColor: AppColors.bordier,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: (i) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => _DailyMixPage(mix: mixes[i]))),
        children: [
          for (final mix in mixes)
            ClipRect(
              child: OverflowBox(
                minWidth: _extent,
                maxWidth: _extent,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _cover(mix),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xCC000000)],
                          stops: [0.4, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            mix.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontFamily: "Adwaita",
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          Text(
                            mix.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontFamily: "Adwaita",
                              fontWeight: FontWeight.w500,
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
        ],
      ),
    );
  }
}

class _DailyMixPage extends StatelessWidget {
  final _DailyMix mix;
  const _DailyMixPage({required this.mix});

  void _playFirst(BuildContext context) async {
    final firstSong = mix.songs.first;
    mainMenuKey.currentState?.updatepreviewplayer(firstSong);
    QueueManager.instance.clear();
    QueueManager.instance.addAll(mix.songs);

    final hadSong = Metadatamanager.instance.currentSong != null;

    Metadatamanager.instance.startRadioFrom(firstSong);
    await AudioPlayerManager.instance.play(firstSong);

    if (!hadSong && context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => Player()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        iconTheme: const IconThemeData(color: AppColors.text),
        title: Text(mix.title, style: TextStyle(color: AppColors.accent)),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                mix.subtitle,
                style: const TextStyle(
                  color: AppColors.text2,
                  fontSize: 14,
                  fontFamily: "Adwaita",
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.background,
                  ),
                  onPressed: () => _playFirst(context),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ),
              const SizedBox(height: 8),
              for (final s in mix.songs)
                Onesong(
                  key: ValueKey('mix_${mix.title}_${s.source.name}_${s.id}'),
                  song: s,
                  albumtracks: mix.songs,
                ),

              SizedBox(height: 110),
            ],
          ),
          if (Metadatamanager.instance.currentSong != null)
            Positioned(left: 0, right: 0, bottom: 0, child: PlayingTrackui()),
        ],
      ),
    );
  }
}
