import 'deezer.dart';

import 'package:mimic/Backend/songdata.dart';

import 'dart:math';

import '../privdersenums.dart';
import '../streaming/streamingmanager.dart';
import '../../songlisttoplay.dart';

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

DateTime? _parseReleaseDate(dynamic raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

int? _parseBpm(dynamic raw) {
  if (raw is! num) return null;
  final v = raw.round();
  return v <= 0 ? null : v;
}

String? _genresToString(dynamic raw) {
  if (raw == null) return null;

  // Deezer envuelve la lista en {data: [...]}, pero algunos
  // endpoints ya devuelven la lista pelada. Aceptamos los dos.
  final List<dynamic> list;
  if (raw is List) {
    list = raw;
  } else if (raw is Map && raw['data'] is List) {
    list = raw['data'] as List<dynamic>;
  } else {
    return null;
  }

  final names = list
      .whereType<Map<String, dynamic>>()
      .map((g) => g['name'] as String? ?? '')
      .where((n) => n.isNotEmpty)
      .toList();
  return names.isEmpty ? null : names.join(', ');
}

// ─────────────────────────────────────────────────────────────────────
// Canciones
// ─────────────────────────────────────────────────────────────────────

final deezer = DeezerSearch<SongInfo>(fromJson: _songFromDeezerTrack);

SongInfo _songFromDeezerTrack(Map<String, dynamic> json) {
  final album = json['album'] as Map<String, dynamic>? ?? {};
  final primaryArtist = json['artist'] as Map<String, dynamic>? ?? {};

  final List<Artist> artistsList = [];
  if (json['contributors'] is List) {
    for (final item in json['contributors'] as List<dynamic>) {
      if (item is Map<String, dynamic> && item['name'] != null) {
        artistsList.add(
          Artist(
            source: metadataprovider.deezer,
            name: item['name'] as String? ?? '',
            id: '${item['id']}',
          ),
        );
      }
    }
  }
  if (artistsList.isEmpty && primaryArtist.isNotEmpty) {
    artistsList.add(
      Artist(
        source: metadataprovider.deezer,
        name: primaryArtist['name'] as String? ?? 'Unknown Artist',
        id: '${primaryArtist['id'] ?? ''}',
      ),
    );
  }

  final song = SongInfo(
    id: '${json['id']}',
    album: album,
    name: json['title'] as String? ?? '',
    duration: Duration(seconds: json['duration'] as int? ?? 0),
    shareurl: _resolveShareUrl(json),
    artists: artistsList,
    source: metadataprovider.deezer,
    streamingSource: StreamingManager.instance.provider,
    releaseDate:
        _parseReleaseDate(json['release_date']) ??
        _parseReleaseDate(album['release_date']),
    bpm: _parseBpm(json['bpm']),
    isrc: json['isrc'] as String?,
    genre: _genresToString(album['genres']),
    thumbnails: [
      Thumbnail(
        url: album['cover_small'] as String? ?? '',
        width: 56,
        height: 56,
      ),
      Thumbnail(
        url: album['cover_medium'] as String? ?? '',
        width: 250,
        height: 250,
      ),
      Thumbnail(
        url: album['cover_big'] as String? ?? '',
        width: 500,
        height: 500,
      ),
      Thumbnail(
        url: album['cover_xl'] as String? ?? '',
        width: 1000,
        height: 1000,
      ),
    ],
  );

  // 🔁 Proveedor → DB → track descargado o track original
  return SongDatabase.instance?.resolveDownloaded(song) ?? song;
}

String _resolveShareUrl(Map<String, dynamic> json) {
  final share = json['share'] as String?;
  if (share != null && share.isNotEmpty) return share;
  final link = json['link'] as String?;
  if (link != null && link.isNotEmpty) return link;
  final id = json['id'];
  if (id != null) return 'https://www.deezer.com/track/$id';
  return '';
}

Future<SongInfo> getSongById(String songId) => deezer.getById(songId);

// ─────────────────────────────────────────────────────────────────────
// Artists
// ─────────────────────────────────────────────────────────────────────

final deezerArtist = DeezerArtistSearch<ArtistInfo>(
  fromJson: (json) => ArtistInfo(
    source: metadataprovider.deezer,
    id: '${json['id']}',
    name: json['name'] as String? ?? '',
    thumbnailUrl:
        (json['picture_xl'] ??
                json['picture_big'] ??
                json['picture_medium'] ??
                '')
            as String,
    url: json['link'] as String? ?? '',
  ),
);

final deezerArtistSimple = DeezerArtistSearch<SimplifiedArtist>(
  fromJson: (json) => SimplifiedArtist(
    source: metadataprovider.deezer,
    id: '${json['id']}',
    name: json['name'] as String? ?? '',
    thumbnailUrl:
        (json['picture_xl'] ??
                json['picture_big'] ??
                json['picture_medium'] ??
                '')
            as String,
    url: json['link'] as String? ?? '',
  ),
);

Future<ArtistInfo> searchArtistWithDetails(String query) async {
  final artist = await deezerArtist.search(query);
  final tracks = await deezerArtist.topTracksEnriched(artist.id, deezer);
  final albumIds = await deezerArtist.albums(artist.id);
  return ArtistInfo(
    source: metadataprovider.deezer,
    id: artist.id,
    name: artist.name,
    thumbnailUrl: artist.thumbnailUrl,
    url: artist.url,
    toptracks: tracks,
    artistalbums: albumIds,
  );
}

Future<List<ArtistInfo>> searchAllArtists(String query, {int limit = 10}) =>
    deezerArtist.searchAll(query, limit: limit);

Future<List<SimplifiedArtist>> searchArtists(String query, {int limit = 10}) =>
    deezerArtistSimple.searchAll(query, limit: limit);

Future<SimplifiedArtist> searchArtist(String query) =>
    deezerArtistSimple.search(query);

Future<List<SimplifiedArtist>> getRelatedArtists(
  String artistId, {
  int limit = 10,
}) => deezerArtist.relatedArtists(artistId, (json) {
  return SimplifiedArtist(
    source: metadataprovider.deezer,
    id: '${json['id']}',
    name: json['name'] as String? ?? '',
    thumbnailUrl:
        (json['picture_xl'] ??
                json['picture_big'] ??
                json['picture_medium'] ??
                '')
            as String,
    url: json['link'] as String? ?? '',
  );
}, limit: limit);

// ─────────────────────────────────────────────────────────────────────
// Álbumes
// ─────────────────────────────────────────────────────────────────────

final deezerAlbum = DeezerAlbumSearch<Albumc>(
  fromJson: (json) {
    final releaseDate = json['release_date'] as String?;
    return Albumc(
      source: metadataprovider.deezer,
      id: '${json['id']}',
      name: json['title'] as String? ?? '',
      bannerurl:
          (json['cover_xl'] ?? json['cover_big'] ?? json['cover_medium'] ?? '')
              as String,
      year: releaseDate != null ? releaseDate.split('-')[0] : '',
      recordType: json['record_type'] as String? ?? 'album',
    );
  },
);

Future<AlbumInfo> getAlbumById(String albumId) {
  return deezerAlbum.getById(albumId, (json) {
    final artist = json['artist'] as Map<String, dynamic>? ?? {};
    final tracksJson = (json['tracks']?['data'] as List<dynamic>?) ?? const [];

    return AlbumInfo(
      source: metadataprovider.deezer,
      creator: SimplifiedArtist(
        source: metadataprovider.deezer,
        id: '${artist['id'] ?? ''}',
        name: artist['name'] as String? ?? '',
        thumbnailUrl:
            (artist['picture_xl'] ??
                    artist['picture_big'] ??
                    artist['picture_medium'] ??
                    '')
                as String,
        url:
            artist['link'] as String? ??
            'https://www.deezer.com/artist/${artist['id']}',
      ),
      content: tracksJson
          .cast<Map<String, dynamic>>()
          .map(deezer.fromJson)
          .toList(),
      recordType: json['record_type'] as String? ?? '',

      // ── Los 5 campos de detalle ─────────────────────────────
      duration: Duration(seconds: json['duration'] as int? ?? 0),
      releaseDate: _parseReleaseDate(json['release_date']),
      genre: _genresToString(json['genres']),
      // BPM e ISRC no existen a nivel de álbum en Deezer — son por track.
      bpm: null,
      isrc: null,
    );
  }, enrichTracks: deezer.enrichTracksInPlace);
}

Future<List<Albumc>> searchAlbums(String query, {int limit = 10}) =>
    deezerAlbum.searchAll(query, limit: limit);

Future<Albumc> searchAlbum(String query) => deezerAlbum.search(query);

Future<List<Albumc>> getArtistDiscography(
  String artistId, {
  int concurrency = 8,
  Duration minSpacing = const Duration(milliseconds: 60),
}) async {
  final albumIds = await deezerArtist.albums(
    artistId,
    albumsLimit: 1000,
    epsAndSinglesLimit: 1000,
  );
  if (albumIds.isEmpty) return const [];

  final results = List<Albumc?>.filled(albumIds.length, null);
  var nextIndex = 0;

  Future<void> worker() async {
    while (true) {
      final i = nextIndex++;
      if (i >= albumIds.length) return;
      if (minSpacing > Duration.zero) await Future.delayed(minSpacing);
      try {
        results[i] = await _fetchWithRetry(albumIds[i]);
      } catch (_) {}
    }
  }

  await Future.wait(List.generate(concurrency, (_) => worker()));
  return results.whereType<Albumc>().toList(growable: false);
}

Future<Albumc> _fetchWithRetry(
  String id, {
  int maxRetries = 4,
  Duration base = const Duration(milliseconds: 250),
}) async {
  var attempt = 0;
  while (true) {
    try {
      return await deezerAlbum.previewById(id);
    } catch (e) {
      if (attempt >= maxRetries) rethrow;
      final backoff = base * (1 << attempt);
      final jitter = Duration(milliseconds: Random().nextInt(150));
      await Future.delayed(backoff + jitter);
      attempt++;
    }
  }
}

String? _albumIdFromSong(SongInfo song) {
  final album = song.album;
  if (album is Map && album['id'] != null) return '${album['id']}';
  return null;
}

Future<Albumc?> getAlbumFromSong(SongInfo song) async {
  final albumId = _albumIdFromSong(song);
  if (albumId == null) return null;
  return deezerAlbum.previewById(albumId);
}

Future<AlbumInfo?> getFullAlbumFromSong(SongInfo song) async {
  final albumId = _albumIdFromSong(song);
  if (albumId == null) return null;
  return getAlbumById(albumId);
}

// ─────────────────────────────────────────────────────────────────────
// Radio
// ─────────────────────────────────────────────────────────────────────

Future<List<SongInfo>> getTrackRadio(SongInfo song, {int limit = 25}) {
  final artistId = song.artists.isNotEmpty ? song.artists.first.id : '';
  return deezerArtist.radioEnriched(artistId, deezer, limit: limit);
}

Future<List<SongInfo>> getAlbumRadio(String artistId, {int limit = 25}) =>
    deezerArtist.radioEnriched(artistId, deezer, limit: limit);

// ─────────────────────────────────────────────────────────────────────
// Pantalla de artista (colecciones: albums / EPs / singles)
// ─────────────────────────────────────────────────────────────────────

Future<List<Albumc>> getArtistCollections(
  String artistId, {
  int albumsLimit = 10,
  int epsLimit = 10,
  int singlesLimit = 10,
  int candidateBuffer = 60,
  int concurrency = 8,
  Duration minSpacing = const Duration(milliseconds: 60),
}) async {
  final ids = await deezerArtist.allReleaseIds(artistId);
  if (ids.isEmpty) return const [];

  final fetched = List<Albumc?>.filled(ids.length, null);
  var nextIndex = 0;

  Future<void> worker() async {
    while (true) {
      final i = nextIndex++;
      if (i >= ids.length) return;
      if (minSpacing > Duration.zero) await Future.delayed(minSpacing);
      try {
        fetched[i] = await _fetchWithRetry(ids[i]);
      } catch (_) {}
    }
  }

  await Future.wait(List.generate(concurrency, (_) => worker()));
  final all = fetched.whereType<Albumc>().toList();

  int byYearDesc(Albumc a, Albumc b) {
    final ya = int.tryParse(a.year) ?? 0;
    final yb = int.tryParse(b.year) ?? 0;
    return yb.compareTo(ya);
  }

  all.sort(byYearDesc);

  final albums = <Albumc>[];
  final eps = <Albumc>[];
  final singles = <Albumc>[];
  for (final a in all) {
    switch (a.recordType) {
      case 'ep':
        eps.add(a);
        break;
      case 'single':
        singles.add(a);
        break;
      case 'compile':
        break;
      default:
        albums.add(a);
    }
  }

  return [
    ...albums.take(albumsLimit),
    ...eps.take(epsLimit),
    ...singles.take(singlesLimit),
  ];
}
