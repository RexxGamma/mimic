// deezer.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class DeezerSearchException implements Exception {
  final String message;
  DeezerSearchException(this.message);
  @override
  String toString() => 'DeezerSearchException: $message';
}

class DeezerConfig {
  /// Peticiones concurrentes máximas.
  /// Deezer tolera ~50 req / 5s por IP. Con 8 vamos sobrados.
  final int concurrency;

  /// Batch endpoint no documentado. Default OFF — solo actívalo si
  /// confirmas que funciona en tu red. Si falla UNA vez, se desactiva
  /// para el resto de la sesión.
  final bool useBatchTrackEndpoint;

  final Duration batchTimeout;
  final Duration requestTimeout;
  final Duration connectionIdleTimeout;

  const DeezerConfig({
    this.concurrency = 8,
    this.useBatchTrackEndpoint = false,
    this.batchTimeout = const Duration(milliseconds: 800),
    this.requestTimeout = const Duration(seconds: 15),
    this.connectionIdleTimeout = const Duration(seconds: 30),
  });
}

// ── Semáforo FIFO ────────────────────────────────────────────────────
class _Semaphore {
  _Semaphore(this.max) : assert(max > 0);
  final int max;
  int _current = 0;
  final _queue = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() action) async {
    if (_current < max) {
      _current++;
    } else {
      final c = Completer<void>();
      _queue.add(c);
      await c.future;
    }
    try {
      return await action();
    } finally {
      if (_queue.isNotEmpty) {
        _queue.removeAt(0).complete();
      } else {
        _current--;
      }
    }
  }
}

// ════════════════════════════════════════════════════════════════════
//  Cliente HTTP compartido
// ════════════════════════════════════════════════════════════════════

class DeezerHttpClient {
  DeezerHttpClient({DeezerConfig? config})
    : _config = config ?? const DeezerConfig() {
    final httpClient = HttpClient()
      ..maxConnectionsPerHost = _config.concurrency
      ..idleTimeout = _config.connectionIdleTimeout;
    _client = IOClient(httpClient);
    _semaphore = _Semaphore(_config.concurrency);
  }

  final DeezerConfig _config;
  late final http.Client _client;
  late final _Semaphore _semaphore;

  final Map<String, Map<String, dynamic>> _trackCache = {};
  final Map<String, Future<Map<String, dynamic>>> _trackInFlight = {};

  final Map<String, Map<String, dynamic>> _albumCache = {};
  final Map<String, Future<Map<String, dynamic>?>> _albumInFlight = {};

  bool _batchEndpointBroken = false;

  // ── GET genérico ───────────────────────────────────────────────────
  // Sin rate limiter. Solo semáforo + backoff reactivo en 429/timeout.
  Future<Map<String, dynamic>> getJson(String url) {
    return _semaphore.run(() => _doGetJson(url));
  }

  Future<Map<String, dynamic>> _doGetJson(String url) async {
    var attempt = 0;
    while (true) {
      try {
        final response = await _client
            .get(Uri.parse(url))
            .timeout(_config.requestTimeout);

        if (response.statusCode == 429) {
          attempt++;
          if (attempt > 3) {
            throw DeezerSearchException('429 persistente en $url');
          }
          final ra = int.tryParse(response.headers['retry-after'] ?? '');
          final delay =
              Duration(seconds: ra ?? (1 << (attempt - 1))) +
              Duration(milliseconds: Random().nextInt(250));
          await Future.delayed(delay);
          continue;
        }

        if (response.statusCode != 200) {
          throw DeezerSearchException(
            'Deezer respondió con código ${response.statusCode}',
          );
        }

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json.containsKey('error')) {
          throw DeezerSearchException(
            'Deezer devolvió un error: ${json['error']}',
          );
        }
        return json;
      } on TimeoutException {
        attempt++;
        if (attempt > 2) {
          throw DeezerSearchException('Timeout al consultar $url');
        }
      } catch (e) {
        if (e is DeezerSearchException) rethrow;
        attempt++;
        if (attempt > 2) {
          throw DeezerSearchException('Error de red: $e');
        }
        await Future.delayed(Duration(milliseconds: 200 * attempt));
      }
    }
  }

  // ── Tracks (cache + coalescing) ────────────────────────────────────
  Future<Map<String, dynamic>> getTrack(String trackId) {
    final cached = _trackCache[trackId];
    if (cached != null) return Future.value(cached);
    final inFlight = _trackInFlight[trackId];
    if (inFlight != null) return inFlight;

    final future = _fetchTrack(trackId);
    _trackInFlight[trackId] = future;
    return future;
  }

  Future<Map<String, dynamic>> _fetchTrack(String trackId) async {
    try {
      final json = await getJson('https://api.deezer.com/track/$trackId');
      _trackCache[trackId] = json;
      return json;
    } finally {
      _trackInFlight.remove(trackId);
    }
  }

  // ── Batch opcional (con circuit breaker + timeout corto) ───────────
  Future<List<Map<String, dynamic>>?> getTracksBatch(List<String> ids) async {
    if (!_config.useBatchTrackEndpoint || _batchEndpointBroken || ids.isEmpty) {
      return null;
    }
    try {
      final url = 'https://api.deezer.com/track/${ids.join(',')}';
      final response = await _client
          .get(Uri.parse(url))
          .timeout(_config.batchTimeout);
      if (response.statusCode != 200) {
        _batchEndpointBroken = true;
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        _batchEndpointBroken = true;
        return null;
      }
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      _batchEndpointBroken = true;
      return null;
    }
  }

  // ── Álbumes (cache + coalescing) ───────────────────────────────────
  Future<Map<String, dynamic>?> getAlbum(String albumId) {
    final cached = _albumCache[albumId];
    if (cached != null) return Future.value(cached);
    final inFlight = _albumInFlight[albumId];
    if (inFlight != null) return inFlight;

    final future = _fetchAlbum(albumId);
    _albumInFlight[albumId] = future;
    return future;
  }

  Future<Map<String, dynamic>?> _fetchAlbum(String albumId) async {
    try {
      final json = await getJson('https://api.deezer.com/album/$albumId');
      _albumCache[albumId] = json;
      return json;
    } catch (_) {
      return null;
    } finally {
      _albumInFlight.remove(albumId);
    }
  }

  void close() => _client.close();
}

// ════════════════════════════════════════════════════════════════════
//  BÚSQUEDA DE CANCIONES
// ════════════════════════════════════════════════════════════════════

class DeezerSearch<T> {
  DeezerSearch({required this.fromJson, DeezerHttpClient? client})
    : _deezer = client ?? DeezerHttpClient();

  static const _baseUrl = 'https://api.deezer.com/search';

  final T Function(Map<String, dynamic> json) fromJson;
  final DeezerHttpClient _deezer;

  Future<T> search(
    String query, {
    bool fullArtists = true,
    bool withRecordType = true,
  }) async {
    final results = await searchAll(
      query,
      limit: 1,
      fullArtists: fullArtists,
      withRecordType: withRecordType,
    );
    if (results.isEmpty) {
      throw DeezerSearchException('No se encontraron resultados para "$query"');
    }
    return results.first;
  }

  Future<T> getById(String trackId, {bool withRecordType = true}) async {
    final json = await _deezer.getTrack(trackId);
    if (withRecordType) await _injectRecordType(json);
    return fromJson(json);
  }

  Future<List<T>> topTracksByArtistId(
    String artistId,
    String artistName, {
    int limit = 25,
  }) async {
    final fetchLimit = (limit * 5).clamp(limit, 100);
    final url = Uri.parse(_baseUrl)
        .replace(queryParameters: {'q': artistName, 'limit': '$fetchLimit'});

    final body = await _deezer.getJson(url.toString());
    final data = (body['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    final filtered = data.where((t) {
      final a = t['artist'] as Map<String, dynamic>?;
      return '${a?['id']}' == artistId;
    }).toList();

    filtered.sort((a, b) {
      final ra = (a['rank'] as int?) ?? 0;
      final rb = (b['rank'] as int?) ?? 0;
      return rb.compareTo(ra);
    });

    return parseBatch(filtered.take(limit).toList());
  }

  Future<List<T>> searchAll(
    String query, {
    int limit = 25,
    int index = 0,
    bool fullArtists = false,
    bool withRecordType = false,
  }) async {
    final url = Uri.parse(_baseUrl).replace(
      queryParameters: {'q': query, 'limit': '$limit', 'index': '$index'},
    );

    final body = await _deezer.getJson(url.toString());
    final data = body['data'] as List<dynamic>? ?? [];
    final rawItems = data.cast<Map<String, dynamic>>();

    if (!fullArtists && !withRecordType) {
      return rawItems.map(fromJson).toList();
    }

    if (fullArtists) {
      await enrichTracksInPlace(rawItems);
      return rawItems.map(fromJson).toList();
    }

    await _injectRecordTypeBatch(rawItems);
    return rawItems.map(fromJson).toList();
  }

  // ── Enriquecimiento masivo ─────────────────────────────────────────
  Future<void> enrichTracksInPlace(List<Map<String, dynamic>> tracks) async {
    if (tracks.isEmpty) return;

    // 1) Intentar batch (si está habilitado; circuit breaker lo apaga
    //    al primer fallo). Si falla, paralelo individual.
    final ids = tracks.map((t) => '${t['id']}').toList();
    final batch = await _deezer.getTracksBatch(ids);

    if (batch != null && batch.length == ids.length) {
      for (var i = 0; i < tracks.length; i++) {
        final fullJson = batch[i];
        for (final key in const [
          'contributors',
          'release_date',
          'bpm',
          'isrc',
          'gain',
          'available_countries',
        ]) {
          if (fullJson.containsKey(key)) tracks[i][key] = fullJson[key];
        }
      }
    } else {
      await Future.wait(
        tracks.map((item) async {
          try {
            final fullJson = await _deezer.getTrack('${item['id']}');
            for (final key in const [
              'contributors',
              'release_date',
              'bpm',
              'isrc',
              'gain',
              'available_countries',
            ]) {
              if (fullJson.containsKey(key)) item[key] = fullJson[key];
            }
          } catch (_) {}
        }),
      );
    }

    // 2) Album metadata: primero extraer IDs únicos y pedirlos todos
    //    en paralelo, luego inyectar (sin awaits en bucle).
    await _injectRecordTypeBatch(tracks);
  }

  Future<List<T>> parseBatch(List<Map<String, dynamic>> raw) async {
    await enrichTracksInPlace(raw);
    return raw.map(fromJson).toList();
  }

  // ── Metadata del álbum, batcheada por ID único ─────────────────────
  Future<String?> recordTypeOfAlbum(String albumId) async {
    final meta = await _deezer.getAlbum(albumId);
    return meta?['record_type'] as String?;
  }

  Future<void> _injectRecordTypeBatch(List<Map<String, dynamic>> tracks) async {
    if (tracks.isEmpty) return;

    final albumIds = <String>{};
    for (final t in tracks) {
      final album = t['album'] as Map<String, dynamic>?;
      final id = album?['id'];
      if (id != null) albumIds.add('$id');
    }
    if (albumIds.isEmpty) return;

    // Descarga todos los álbumes únicos en paralelo (coalescing interno
    // ya evita duplicados; aquí además deduplicamos por si acaso).
    final metas = await Future.wait(albumIds.map((id) => _deezer.getAlbum(id)));
    final metaById = <String, Map<String, dynamic>>{
      for (var i = 0; i < albumIds.length; i++)
        if (metas[i] != null) albumIds.elementAt(i): metas[i]!,
    };

    // Inyección sincrónica (sin awaits)
    for (final t in tracks) {
      final album = t['album'] as Map<String, dynamic>?;
      final id = album?['id'];
      if (id == null) continue;
      final meta = metaById['$id'];
      if (meta == null) continue;
      final rt = meta['record_type'] as String?;
      if (rt != null) album!['record_type'] = rt;
      final genres = meta['genres'];
      if (genres != null) album!['genres'] = genres;
    }
  }

  Future<void> _injectRecordType(Map<String, dynamic> trackJson) async {
    await _injectRecordTypeBatch([trackJson]);
  }

  // No cerrar el cliente compartido desde aquí.
  void close() {}
}

// ════════════════════════════════════════════════════════════════════
//  BÚSQUEDA DE ARTISTAS
// ════════════════════════════════════════════════════════════════════

class DeezerArtistSearch<T> {
  DeezerArtistSearch({required this.fromJson, DeezerHttpClient? client})
    : _deezer = client ?? DeezerHttpClient();

  static const _baseUrl = 'https://api.deezer.com/search/artist';

  final T Function(Map<String, dynamic> json) fromJson;
  final DeezerHttpClient _deezer;

  Future<T> search(String query) async {
    final results = await searchAll(query, limit: 1);
    if (results.isEmpty) {
      throw DeezerSearchException('No se encontraron artistas para "$query"');
    }
    return results.first;
  }

  Future<T> getById(String artistId) async {
    final json = await _deezer.getJson(
      'https://api.deezer.com/artist/$artistId',
    );
    return fromJson(json);
  }

  Future<List<T>> searchAll(
    String query, {
    int limit = 10,
    int index = 0,
    bool withRecordType = true,
  }) async {
    final url = Uri.parse(_baseUrl).replace(
      queryParameters: {'q': query, 'limit': '$limit', 'index': '$index'},
    );
    final body = await _deezer.getJson(url.toString());
    final data = (body['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return data.map(fromJson).toList();
  }

  Future<List<S>> topTracks<S>(
    String artistId,
    S Function(Map<String, dynamic> json) fromJson, {
    int limit = 10,
  }) async {
    final url = Uri.parse('https://api.deezer.com/artist/$artistId/top')
        .replace(queryParameters: {'limit': '$limit'});
    final body = await _deezer.getJson(url.toString());
    final data = (body['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return data.map(fromJson).toList();
  }

  Future<List<S>> topTracksEnriched<S>(
    String artistId,
    DeezerSearch<S> enricher, {
    int limit = 10,
  }) async {
    final url = Uri.parse('https://api.deezer.com/artist/$artistId/top')
        .replace(queryParameters: {'limit': '$limit'});
    final body = await _deezer.getJson(url.toString());
    final data = (body['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return enricher.parseBatch(data);
  }

  Future<List<S>> radioForArtist<S>(
    String artistId,
    S Function(Map<String, dynamic> json) fromJson, {
    int limit = 25,
  }) async {
    final url = Uri.parse('https://api.deezer.com/artist/$artistId/radio')
        .replace(queryParameters: {'limit': '$limit'});
    final body = await _deezer.getJson(url.toString());
    final data = (body['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return data.map(fromJson).toList();
  }

  Future<List<S>> radioEnriched<S>(
    String artistId,
    DeezerSearch<S> enricher, {
    int limit = 25,
  }) async {
    final url = Uri.parse('https://api.deezer.com/artist/$artistId/radio')
        .replace(queryParameters: {'limit': '$limit'});
    final body = await _deezer.getJson(url.toString());
    final data = (body['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return enricher.parseBatch(data);
  }

  Future<List<S>> relatedArtists<S>(
    String artistId,
    S Function(Map<String, dynamic> json) fromJson, {
    int limit = 10,
  }) async {
    final url = Uri.parse('https://api.deezer.com/artist/$artistId/related')
        .replace(queryParameters: {'limit': '$limit'});
    final body = await _deezer.getJson(url.toString());
    final data = (body['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return data.map(fromJson).toList();
  }

  // ── Lanzamientos (paginación paralela) ─────────────────────────────
  Future<List<Map<String, dynamic>>> _allReleases(
    String artistId, {
    int maxPages = 10,
  }) async {
    const limit = 100;
    final firstUrl =
        'https://api.deezer.com/artist/$artistId/albums?limit=$limit';
    final first = await _deezer.getJson(firstUrl);
    final all = <Map<String, dynamic>>[];
    all.addAll(
      (first['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
    );
    final total = first['total'] as int? ?? all.length;
    final totalPages = ((total + limit - 1) ~/ limit).clamp(1, maxPages);

    if (totalPages > 1) {
      final futures = <Future<Map<String, dynamic>?>>[
        for (var i = 1; i < totalPages; i++)
          _tryGetOne(
            'https://api.deezer.com/artist/$artistId/albums'
            '?limit=$limit&index=${i * limit}',
          ),
      ];
      final results = await Future.wait(futures);
      for (final r in results) {
        if (r == null) continue;
        all.addAll(
          (r['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
        );
      }
    }

    final seen = <String>{};
    return [
      for (final it in all)
        if (seen.add('${it['id']}')) it,
    ];
  }

  Future<Map<String, dynamic>?> _tryGetOne(String url) async {
    try {
      return await _deezer.getJson(url);
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeSingleOrEp(Map<String, dynamic> it) {
    final rt = it['record_type'] as String?;
    if (rt == 'single' || rt == 'ep') return true;
    if (rt == 'album') {
      final n = it['nb_tracks'] as int? ?? 999;
      if (n <= 6) return true;
    }
    return false;
  }

  int _byDateDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
    final da = a['release_date'] as String? ?? '';
    final db = b['release_date'] as String? ?? '';
    if (da.isEmpty && db.isEmpty) return 0;
    if (da.isEmpty) return 1;
    if (db.isEmpty) return -1;
    return db.compareTo(da);
  }

  Future<List<String>> albumsOnly(String artistId, {int limit = 10}) async {
    final items = await _allReleases(artistId);
    final albums =
        items
            .where(
              (it) =>
                  it['record_type'] == 'album' &&
                  ((it['nb_tracks'] as int? ?? 999) > 6),
            )
            .toList()
          ..sort(_byDateDesc);
    return albums.take(limit).map((a) => '${a['id']}').toList();
  }

  Future<List<String>> epsAndSinglesOnly(
    String artistId, {
    int limit = 10,
  }) async {
    final items = await _allReleases(artistId);
    final eps = items.where(_looksLikeSingleOrEp).toList()..sort(_byDateDesc);
    return eps.take(limit).map((a) => '${a['id']}').toList();
  }

  Future<List<String>> allReleaseIds(
    String artistId, {
    int maxItems = 60,
    int maxPages = 10,
  }) async {
    const limit = 100;
    final firstUrl =
        'https://api.deezer.com/artist/$artistId/albums?limit=$limit';
    final first = await _deezer.getJson(firstUrl);
    final all = <Map<String, dynamic>>[];
    all.addAll(
      (first['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
    );
    final total = first['total'] as int? ?? all.length;
    final totalPages = ((total + limit - 1) ~/ limit).clamp(1, maxPages);

    if (totalPages > 1) {
      final futures = <Future<Map<String, dynamic>?>>[
        for (var i = 1; i < totalPages; i++)
          _tryGetOne(
            'https://api.deezer.com/artist/$artistId/albums'
            '?limit=$limit&index=${i * limit}',
          ),
      ];
      final results = await Future.wait(futures);
      for (final r in results) {
        if (r == null) continue;
        all.addAll(
          (r['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
        );
      }
    }

    final ids = <String>[];
    final seen = <String>{};
    for (final it in all) {
      final id = '${it['id']}';
      if (seen.add(id)) {
        ids.add(id);
        if (ids.length >= maxItems) break;
      }
    }
    return ids;
  }

  Future<List<String>> albums(
    String artistId, {
    int albumsLimit = 10,
    int epsAndSinglesLimit = 10,
  }) async {
    final items = await _allReleases(artistId);
    final albums =
        items
            .where(
              (it) =>
                  it['record_type'] == 'album' &&
                  ((it['nb_tracks'] as int? ?? 999) > 6),
            )
            .toList()
          ..sort(_byDateDesc);
    final eps = items.where(_looksLikeSingleOrEp).toList()..sort(_byDateDesc);
    return [
      ...albums.take(albumsLimit).map((a) => '${a['id']}'),
      ...eps.take(epsAndSinglesLimit).map((a) => '${a['id']}'),
    ];
  }

  void close() {}
}

// ════════════════════════════════════════════════════════════════════
//  BÚSQUEDA DE ÁLBUMES
// ════════════════════════════════════════════════════════════════════

class DeezerAlbumSearch<T> {
  DeezerAlbumSearch({required this.fromJson, DeezerHttpClient? client})
    : _deezer = client ?? DeezerHttpClient();

  static const _baseUrl = 'https://api.deezer.com/search/album';

  final T Function(Map<String, dynamic> json) fromJson;
  final DeezerHttpClient _deezer;

  Future<T> search(String query) async {
    final results = await searchAll(query, limit: 1);
    if (results.isEmpty) {
      throw DeezerSearchException('No se encontraron álbumes para "$query"');
    }
    return results.first;
  }

  Future<List<T>> searchAll(
    String query, {
    int limit = 10,
    int index = 0,
  }) async {
    final url = Uri.parse(_baseUrl).replace(
      queryParameters: {'q': query, 'limit': '$limit', 'index': '$index'},
    );
    final body = await _deezer.getJson(url.toString());
    final data = (body['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return data.map(fromJson).toList();
  }

  Future<T> previewById(String albumId) async {
    final json = await _deezer.getJson('https://api.deezer.com/album/$albumId');
    return fromJson(json);
  }

  Future<S> getById<S>(
    String albumId,
    S Function(Map<String, dynamic> json) fromJson, {
    Future<void> Function(List<Map<String, dynamic>>)? enrichTracks,
  }) async {
    final results = await Future.wait<dynamic>([
      _deezer.getJson('https://api.deezer.com/album/$albumId'),
      _fetchAllTracks(albumId),
    ]);
    final json = results[0] as Map<String, dynamic>;
    final allTracks = results[1] as List<Map<String, dynamic>>;

    final albumMeta = {
      'cover_small': json['cover_small'],
      'cover_medium': json['cover_medium'],
      'cover_big': json['cover_big'],
      'cover_xl': json['cover_xl'],
      'release_date': json['release_date'],
      'record_type': json['record_type'],
      'genres': json['genres'],
    };
    for (final track in allTracks) {
      track['album'] = albumMeta;
    }

    if (enrichTracks != null) {
      await enrichTracks(allTracks);
    }

    json['tracks'] = {'data': allTracks};
    return fromJson(json);
  }

  Future<List<Map<String, dynamic>>> _fetchAllTracks(String albumId) async {
    const limit = 100;
    final firstUrl =
        'https://api.deezer.com/album/$albumId/tracks?limit=$limit';
    final first = await _deezer.getJson(firstUrl);
    final tracks = <Map<String, dynamic>>[];
    tracks.addAll(
      (first['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
    );
    final total = first['total'] as int? ?? tracks.length;

    if (total > limit) {
      final totalPages = (total + limit - 1) ~/ limit;
      final futures = <Future<Map<String, dynamic>>>[
        for (var i = 1; i < totalPages; i++)
          _deezer.getJson(
            'https://api.deezer.com/album/$albumId/tracks'
            '?limit=$limit&index=${i * limit}',
          ),
      ];
      final results = await Future.wait(futures);
      for (final r in results) {
        tracks.addAll(
          (r['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
        );
      }
    }
    return tracks;
  }

  void close() {}
}
