// lib/Backend/providers/metadata/soundcloud.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

class SoundCloudException implements Exception {
  final String message;
  SoundCloudException(this.message);
  @override
  String toString() => 'SoundCloudException: $message';
}

/// Extrae el id numérico de un URN `soundcloud:xxx:123` o lo deja igual
/// si ya es un número puro.
String _numericId(String urnOrId) {
  if (!urnOrId.contains(':')) return urnOrId;
  return urnOrId.split(':').last;
}

// ════════════════════════════════════════════════════════════════════
//  Cliente HTTP
// ════════════════════════════════════════════════════════════════════

class SoundCloudClient {
  SoundCloudClient({String? clientId, http.Client? httpClient})
    : _clientId = clientId,
      _client = httpClient ?? http.Client();

  static const _baseUrl = 'https://api-v2.soundcloud.com';

  String? _clientId;
  final http.Client _client;

  Future<String> get clientId async => _clientId ??= await _scrapeClientId();
  set clientId(String value) => _clientId = value;

  // ─── Scraping de client_id ────────────────────────────────────────

  Future<String> _scrapeClientId() async {
    final http.Response home;
    try {
      home = await _client.get(
        Uri.parse('https://soundcloud.com'),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'text/html,application/xhtml+xml',
        },
      );
    } catch (e) {
      throw SoundCloudException('Error de red scrapeando client_id: $e');
    }

    if (home.statusCode != 200) {
      throw SoundCloudException(
        'soundcloud.com respondió ${home.statusCode} al scrapear client_id',
      );
    }

    final scriptUrls = RegExp(
      r'src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"',
    ).allMatches(home.body).map((m) => m.group(1)!).toList();

    for (final url in scriptUrls.reversed) {
      try {
        final js = await _client.get(Uri.parse(url));
        final match = RegExp(r'client_id:"([a-zA-Z0-9]{32})"')
            .firstMatch(js.body);
        if (match != null) return match.group(1)!;
      } catch (_) {
        continue;
      }
    }

    return 'iFagfuAuwkp6GbI6M6rA7UMw4LOdqC95';
  }

  // ─── Helpers internos ─────────────────────────────────────────────

  Uri _buildUri(
    String path, {
    Map<String, String>? query,
    required String cid,
  }) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$cleanPath')
        .replace(queryParameters: {...?query, 'client_id': cid});
  }

  Future<Map<String, dynamic>> _getOne(String url) async {
    const headers = {
      'Accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    };

    http.Response response;
    try {
      response = await _client.get(Uri.parse(url), headers: headers);
    } catch (e) {
      throw SoundCloudException('Error de red: $e');
    }

    if (response.statusCode == 401) {
      _clientId = null;
      final newCid = await clientId;
      final newUrl = url.replaceFirst(
        RegExp(r'client_id=[^&]+'),
        'client_id=$newCid',
      );
      try {
        response = await _client.get(Uri.parse(newUrl), headers: headers);
      } catch (e) {
        throw SoundCloudException('Error de red tras refresh: $e');
      }
    }

    if (response.statusCode != 200) {
      // ignore: avoid_print
      print('SC ${response.statusCode} -> $url');
      throw SoundCloudException(
        'SoundCloud respondió ${response.statusCode} en $url',
      );
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw SoundCloudException('No se pudo parsear la respuesta: $e');
    }
  }

  // ─── API pública ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final cid = await clientId;
    return _getOne(_buildUri(path, query: query, cid: cid).toString());
  }

  /// Para URLs absolutas (por ejemplo, la URL firmada del transcoding).
  Future<Map<String, dynamic>> getAbsolute(String fullUrl) => _getOne(fullUrl);

  Future<List<Map<String, dynamic>>> getPaged(
    String path, {
    required Map<String, String> query,
    int maxItems = 50,
    int maxPages = 10,
  }) async {
    final cid = await clientId;
    String? next = _buildUri(path, query: query, cid: cid).toString();

    final all = <Map<String, dynamic>>[];
    var page = 0;

    while (next != null && page < maxPages && all.length < maxItems) {
      page++;
      final body = await _getOne(next);
      final collection = (body['collection'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      if (collection.isEmpty) break;

      for (final item in collection) {
        all.add(item);
        if (all.length >= maxItems) break;
      }

      final nextHref = body['next_href'] as String?;
      if (nextHref == null || nextHref.isEmpty) break;

      next = nextHref.contains('client_id')
          ? nextHref
          : '$nextHref${nextHref.contains('?') ? '&' : '?'}client_id=$cid';
    }
    return all;
  }

  Future<List<Map<String, dynamic>>> scrapePlaylistTracks(
    String permalinkUrl,
  ) async {
    const headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/122.0.0.0 Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };

    // ignore: avoid_print
    print('SCRAPE -> $permalinkUrl');

    final http.Response response;
    try {
      response = await _client.get(Uri.parse(permalinkUrl), headers: headers);
    } catch (e) {
      throw SoundCloudException('Error de red scrapeando playlist: $e');
    }

    // ignore: avoid_print
    print('SCRAPE status=${response.statusCode} len=${response.body.length}');

    if (response.statusCode != 200) {
      throw SoundCloudException(
        'soundcloud.com respondió ${response.statusCode} para $permalinkUrl',
      );
    }

    // Comprobación 1: ¿existe el patrón en el HTML?
    final hasPattern = response.body.contains('__sc_hydration');
    // ignore: avoid_print
    print('SCRAPE __sc_hydration present=$hasPattern');

    final match = RegExp(
      r'window\.__sc_hydration\s*=\s*(\[.*?\]);',
      dotAll: true,
    ).firstMatch(response.body);

    // ignore: avoid_print
    print('SCRAPE regex match=${match != null}');

    if (match == null) {
      throw SoundCloudException(
        'No se encontró __sc_hydration en $permalinkUrl',
      );
    }

    final List<dynamic> hydration;
    try {
      hydration = jsonDecode(match.group(1)!) as List<dynamic>;
    } catch (e) {
      throw SoundCloudException('No se pudo parsear __sc_hydration: $e');
    }

    // ignore: avoid_print
    print('SCRAPE hydration entries=${hydration.length}');

    // Comprobación 2: ¿qué hydratables hay?
    for (final item in hydration) {
      if (item is Map) {
        // ignore: avoid_print
        print('SCRAPE hydratable=${item['hydratable']}');
      }
    }

    for (final item in hydration) {
      if (item is Map && item['hydratable'] == 'playlist') {
        final data = item['data'];
        if (data is Map) {
          final tracks = data['tracks'];
          if (tracks is List) {
            // ignore: avoid_print
            print('SCRAPE tracks en hydration=${tracks.length}');
            return tracks.cast<Map<String, dynamic>>();
          }
        }
      }
    }

    throw SoundCloudException(
      'No se encontró playlist en hydration data de $permalinkUrl',
    );
  }

  /// Trae TODOS los tracks de una playlist paginando
  /// `/playlists/{numericId}/tracks`. Devuelve la lista cruda.
  Future<List<Map<String, dynamic>>> getAllPlaylistTracks(
    String playlistIdOrUrn, {
    int maxItems = 500,
  }) async {
    final numeric = _numericId(playlistIdOrUrn);
    final cid = await clientId;

    final all = <Map<String, dynamic>>[];
    String? next = _buildUri(
      '/playlists/$numeric/tracks',
      query: {'limit': '200'},
      cid: cid,
    ).toString();

    var page = 0;
    while (next != null && page < 10 && all.length < maxItems) {
      page++;
      final body = await _getOne(next);
      final coll = (body['collection'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      if (coll.isEmpty) break;
      for (final t in coll) {
        all.add(t);
        if (all.length >= maxItems) break;
      }

      final nextHref = body['next_href'] as String?;
      if (nextHref == null || nextHref.isEmpty) break;
      next = nextHref.contains('client_id')
          ? nextHref
          : '$nextHref${nextHref.contains('?') ? '&' : '?'}client_id=$cid';
    }
    return all;
  }

  void close() => _client.close();
}

// ════════════════════════════════════════════════════════════════════
//  Búsqueda de tracks
// ════════════════════════════════════════════════════════════════════

class SoundCloudSearch<T> {
  SoundCloudSearch({required this.fromJson, required this.client});

  final T Function(Map<String, dynamic> json) fromJson;
  final SoundCloudClient client;

  Future<T> search(String query, {int limit = 1}) async {
    final results = await searchAll(query, limit: limit);
    if (results.isEmpty) {
      throw SoundCloudException('No hay resultados para "$query"');
    }
    return results.first;
  }

  Future<List<T>> searchAll(
    String query, {
    int limit = 10,
    int maxItems = 50,
  }) async {
    final items = await client.getPaged(
      '/search/tracks',
      query: {'q': query, 'limit': '$limit'},
      maxItems: maxItems,
    );
    return items.map(fromJson).toList();
  }

  /// Todas las canciones del artista: tracks subidos directamente + los
  /// que están dentro de sus playlists/álbumes. Deduplicadas por id y
  /// hidratadas si les falta `media` (necesario para poder reproducirlas).
  Future<List<S>> allTracks<S>(
    String userIdOrUrn,
    S Function(Map<String, dynamic>) fromJson, {
    int maxItems = 500,
    int hydrateConcurrency = 8,
  }) async {
    final numeric = _numericId(userIdOrUrn);

    // 1) Tracks subidos directamente por el user.
    final uploaded = await client.getPaged(
      '/users/$numeric/tracks',
      query: {'limit': '200'},
      maxItems: maxItems,
    );

    // 2) Tracks dentro de sus playlists/álbumes.
    final playlists = await client.getPaged(
      '/users/$numeric/playlists',
      query: {'limit': '100'},
      maxItems: 100,
    );

    final fromPlaylists = <Map<String, dynamic>>[];
    for (final pl in playlists) {
      final inlineTracks =
          (pl['tracks'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      fromPlaylists.addAll(inlineTracks);

      // Si la playlist tiene más tracks que los inline, pedirla completa.
      final declared = pl['track_count'] as int? ?? 0;
      if (declared > inlineTracks.length) {
        try {
          final full = await client.getJson(
            '/playlists/${pl['id']}',
            query: {'representation': 'full'},
          );
          final fullTracks =
              (full['tracks'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          fromPlaylists.addAll(fullTracks);
        } catch (_) {
          // seguimos con lo que ya tenemos
        }
      }
    }

    // 3) Dedup por id. Preferimos el que tenga `media` (completo).
    final byId = <String, Map<String, dynamic>>{};
    for (final t in [...uploaded, ...fromPlaylists]) {
      final id = t['id'];
      if (id == null) continue;
      final key = '$id';
      final existing = byId[key];
      if (existing != null && existing['media'] != null) continue;
      byId[key] = t;
    }

    final all = byId.values.toList();

    // 4) Hidratar los que no tengan `media`.
    final hydrated = await _hydrateAll(all, concurrency: hydrateConcurrency);

    return hydrated.map(fromJson).toList();
  }

  /// Hidrata en paralelo los tracks que no traen `media`. Los que ya
  /// están completos se devuelven tal cual.
  Future<List<Map<String, dynamic>>> _hydrateAll(
    List<Map<String, dynamic>> tracks, {
    int concurrency = 8,
  }) async {
    final result = List<Map<String, dynamic>>.filled(tracks.length, const {});
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= tracks.length) return;
        final t = tracks[i];

        if (t['media'] != null) {
          result[i] = t;
          continue;
        }
        final id = t['id'];
        if (id == null) {
          result[i] = t;
          continue;
        }
        try {
          result[i] = await client.getJson('/tracks/$id');
        } catch (_) {
          result[i] = t;
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return result;
  }

  Future<Map<String, dynamic>> rawById(String trackIdOrUrn) async {
    final numeric = _numericId(trackIdOrUrn);
    return client.getJson(
      '/tracks/$numeric',
      query: {'representation': 'full'},
    );
  }

  Future<T> getById(String trackIdOrUrn) async {
    final json = await rawById(trackIdOrUrn);
    return fromJson(json);
  }

  Future<String?> resolveStreamUrl(String trackIdOrUrn) async {
    final track = await rawById(trackIdOrUrn);
    final media = track['media'] as Map<String, dynamic>?;
    final transcodings =
        (media?['transcodings'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        const [];

    if (transcodings.isEmpty) return null;

    // Preferir progressive MP3 (compatible con todo). Si solo hay HLS,
    // usar el primero — ExoPlayer lo reproduce nativo en Android.
    Map<String, dynamic>? chosen;
    for (final t in transcodings) {
      final format = t['format'] as Map<String, dynamic>? ?? {};
      if (format['protocol'] == 'progressive') {
        chosen = t;
        if (format['mime_type'] == 'audio/mpeg') break;
      }
    }
    chosen ??= transcodings.first;

    final url = chosen['url'] as String?;
    if (url == null) return null;

    final resolved = await client.getAbsolute(url);
    final finalUrl = resolved['url'] as String?;
    if (finalUrl == null) return null;

    // Log para confirmar qué protocolo se eligió
    // ignore: avoid_print
    print(
      'SC stream: track=$trackIdOrUrn '
      'protocol=${chosen['format']?['protocol']} '
      'preset=${chosen['preset']}',
    );

    return finalUrl;
  }
}

// ════════════════════════════════════════════════════════════════════
//  Búsqueda de artistas (users)
// ════════════════════════════════════════════════════════════════════

class SoundCloudArtistSearch<T> {
  SoundCloudArtistSearch({required this.fromJson, required this.client});

  final T Function(Map<String, dynamic> json) fromJson;
  final SoundCloudClient client;

  Future<T> search(String query) async {
    final all = await searchAll(query, limit: 1);
    if (all.isEmpty) {
      throw SoundCloudException('No hay artistas para "$query"');
    }
    return all.first;
  }

  Future<List<T>> searchAll(String query, {int limit = 10}) async {
    final items = await client.getPaged(
      '/search/users',
      query: {'q': query, 'limit': '$limit'},
      maxItems: limit,
    );
    return items.map(fromJson).toList();
  }

  Future<List<S>> allTracks<S>(
    String userIdOrUrn,
    S Function(Map<String, dynamic>) fromJson, {
    int maxItems = 500,
    int hydrateConcurrency = 8,
  }) async {
    final numeric = _numericId(userIdOrUrn);

    // 1) Tracks subidos directamente por el user.
    final uploaded = await client.getPaged(
      '/users/$numeric/tracks',
      query: {'limit': '200'},
      maxItems: maxItems,
    );

    // 2) Tracks dentro de sus playlists/álbumes.
    final playlists = await client.getPaged(
      '/users/$numeric/playlists',
      query: {'limit': '100'},
      maxItems: 100,
    );

    final fromPlaylists = <Map<String, dynamic>>[];
    for (final pl in playlists) {
      final inlineTracks =
          (pl['tracks'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      fromPlaylists.addAll(inlineTracks);

      final declared = pl['track_count'] as int? ?? 0;
      if (declared > inlineTracks.length) {
        try {
          final full = await client.getJson(
            '/playlists/${pl['id']}',
            query: {'representation': 'full'},
          );
          final fullTracks =
              (full['tracks'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          fromPlaylists.addAll(fullTracks);
        } catch (_) {}
      }
    }

    // 3) Dedup por id, prefiriendo los que tengan media.
    final byId = <String, Map<String, dynamic>>{};
    for (final t in [...uploaded, ...fromPlaylists]) {
      final id = t['id'];
      if (id == null) continue;
      final key = '$id';
      final existing = byId[key];
      if (existing != null && existing['media'] != null) continue;
      byId[key] = t;
    }

    final all = byId.values.toList();

    // 4) Hidratar los que no tengan media.
    final result = List<Map<String, dynamic>>.filled(all.length, const {});
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= all.length) return;
        final t = all[i];

        if (t['media'] != null) {
          result[i] = t;
          continue;
        }
        final id = t['id'];
        if (id == null) {
          result[i] = t;
          continue;
        }
        try {
          result[i] = await client.getJson('/tracks/$id');
        } catch (_) {
          result[i] = t;
        }
      }
    }

    await Future.wait(List.generate(hydrateConcurrency, (_) => worker()));
    return result.map(fromJson).toList();
  }

  Future<T> getById(String userIdOrUrn) async {
    final numeric = _numericId(userIdOrUrn);
    final json = await client.getJson('/users/$numeric');
    return fromJson(json);
  }

  Future<List<S>> topTracks<S>(
    String userIdOrUrn,
    S Function(Map<String, dynamic>) fromJson, {
    int limit = 10,
  }) async {
    final numeric = _numericId(userIdOrUrn);
    final items = await client.getPaged(
      '/users/$numeric/tracks',
      query: {'limit': '$limit'},
      maxItems: limit,
    );
    items.sort((a, b) {
      final pa = (a['playback_count'] as int?) ?? 0;
      final pb = (b['playback_count'] as int?) ?? 0;
      return pb.compareTo(pa);
    });
    return items.map(fromJson).toList();
  }

  Future<List<S>> playlists<S>(
    String userIdOrUrn,
    S Function(Map<String, dynamic>) fromJson, {
    int limit = 50,
  }) async {
    final numeric = _numericId(userIdOrUrn);
    final items = await client.getPaged(
      '/users/$numeric/playlists',
      query: {'limit': '$limit'},
      maxItems: limit,
    );
    return items.map(fromJson).toList();
  }

  Future<List<S>> relatedArtists<S>(
    String userIdOrUrn,
    S Function(Map<String, dynamic>) fromJson, {
    int limit = 10,
  }) async {
    try {
      final numeric = _numericId(userIdOrUrn);
      final self = await client.getJson('/users/$numeric');
      final name = self['username'] as String? ?? '';
      if (name.isEmpty) return const [];
      final items = await client.getPaged(
        '/search/users',
        query: {'q': name, 'limit': '${limit + 1}'},
        maxItems: limit + 1,
      );
      return items
          .where((u) => '${u['id']}' != numeric)
          .take(limit)
          .map(fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

// ════════════════════════════════════════════════════════════════════
//  Búsqueda de álbumes (playlists)
// ════════════════════════════════════════════════════════════════════

class SoundCloudAlbumSearch<T> {
  SoundCloudAlbumSearch({required this.fromJson, required this.client});

  final T Function(Map<String, dynamic> json) fromJson;
  final SoundCloudClient client;

  Future<T> search(String query) async {
    final all = await searchAll(query, limit: 1);
    if (all.isEmpty) {
      throw SoundCloudException('No hay álbumes para "$query"');
    }
    return all.first;
  }

  Future<List<T>> searchAll(String query, {int limit = 10}) async {
    final items = await client.getPaged(
      '/search/albums',
      query: {'q': query, 'limit': '$limit'},
      maxItems: limit,
    );
    return items.map(fromJson).toList();
  }

  Future<Map<String, dynamic>> rawById(String playlistIdOrUrn) async {
    final numeric = _numericId(playlistIdOrUrn);
    return client.getJson('/playlists/$numeric');
  }

  Future<T> getById(String playlistIdOrUrn) async {
    final json = await rawById(playlistIdOrUrn);
    return fromJson(json);
  }

  /// Playlist + todos sus tracks.
  ///
  /// SoundCloud incluye los tracks completos en el response de la playlist
  /// cuando se pide con `representation=full`. El endpoint
  /// `/playlists/{id}/tracks` fue deprecado y devuelve 404.
  Future<S> getWithTracks<S>(
    String playlistIdOrUrn,
    S Function(Map<String, dynamic> json) fromJson,
  ) async {
    final numeric = _numericId(playlistIdOrUrn);
    final json = await client.getJson(
      '/playlists/$numeric',
      query: {'representation': 'full'},
    );

    final rawTracks =
        (json['tracks'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    final withoutMedia = rawTracks.where((t) => t['media'] == null).length;
    // ignore: avoid_print
    print('SC tracks=${rawTracks.length} sinMedia=$withoutMedia');

    // Hidratar en paralelo los que no tengan media.
    final hydrated = await Future.wait(
      rawTracks.map((t) async {
        if (t['media'] != null) return t;
        final id = t['id'];
        if (id == null) return t;
        try {
          final full = await client.getJson('/tracks/$id');
          return full;
        } catch (e) {
          // ignore: avoid_print
          print('SC hydrate track $id falló: $e');
          return t;
        }
      }),
    );

    json['tracks'] = hydrated;
    return fromJson(json);
  }
}

