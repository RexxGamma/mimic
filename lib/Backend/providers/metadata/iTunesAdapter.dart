// lib/Backend/Providers/itunes_provider.dart
import 'package:mimic/Backend/songdata.dart';

import 'iTunes.dart';
import '../musicprovider.dart';
import '../privdersenums.dart';
import '../streaming/streamingmanager.dart';
import '../../songlisttoplay.dart';

class iTunesProvider extends MusicProvider {
  iTunesProvider({String country = 'US', iTunesClient? client})
    : _client = client ?? iTunesClient(country: country);

  final iTunesClient _client;

  // ─────────────────────────────────────────────────────────────
  //  STREAM
  // ─────────────────────────────────────────────────────────────

  @override
  Future<String?> resolveStreamUrl(SongInfo song) async {
    // iTunes solo devuelve preview de 30s vía previewUrl.
    try {
      final results = await _client.lookup(song.id);
      if (results.isEmpty) return null;
      // El primer resultado del lookup sin entity es el propio track.
      return results.first['previewUrl'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  CANCIONES
  // ─────────────────────────────────────────────────────────────

  @override
  Future<SongInfo> searchSong(String query) async {
    final results = await _client.search(query, entity: 'song', limit: 1);
    if (results.isEmpty) throw iTunesException('Sin resultados para "$query"');
    return _songFromJson(results.first);
  }

  @override
  Future<List<SongInfo>> searchSongs(String query, {int limit = 10}) async {
    final results = await _client.search(query, entity: 'song', limit: limit);
    return results.map(_songFromJson).toList();
  }

  @override
  Future<SongInfo> getSongById(String songId) async {
    final results = await _client.lookup(songId);
    if (results.isEmpty) throw iTunesException('Track $songId no encontrado');
    return _songFromJson(results.first);
  }

  @override
  Future<List<SongInfo>> getTrackRadio(SongInfo song, {int limit = 25}) async {
    if (song.artists.isEmpty) return const [];
    final artistName = song.artists.first.name;
    return searchSongs(artistName, limit: limit);
  }

  @override
  Future<List<SongInfo>> getAlbumRadio(
    String artistId, {
    int limit = 25,
  }) async {
    final results = await _client.lookup(
      artistId,
      entity: 'song',
      limit: limit,
    );
    // Filtra el "artist" que iTunes mete como primer resultado.
    final tracks = results.where((r) => r['wrapperType'] == 'track');
    return tracks.map(_songFromJson).toList();
  }

  // ─────────────────────────────────────────────────────────────
  //  ARTISTAS
  // ─────────────────────────────────────────────────────────────

  @override
  Future<ArtistInfo> searchArtistWithDetails(String query) async {
    final artists = await _client.search(
      query,
      entity: 'musicArtist',
      limit: 1,
    );
    if (artists.isEmpty) throw iTunesException('Sin artista para "$query"');

    var artist = _artistFromJson(artists.first);
    artist = await _withArtistArtwork(artist);

    final top = await getArtistTopTracks(artist.id, limit: 5);
    final albums = await getArtistDiscography(artist.id);
    return ArtistInfo(
      source: metadataprovider.itunes,
      id: artist.id,
      name: artist.name,
      thumbnailUrl: artist.thumbnailUrl,
      url: artist.url,
      toptracks: top,
      artistalbums: albums,
    );
  }

  @override
  Future<ArtistInfo> getArtistById(String artistId) async {
    // ignore: avoid_print
    print('>>> getArtistById llamado con: "$artistId"');
    final results = await _client.lookup(artistId, entity: 'musicArtist');
    // ignore: avoid_print
    print('>>> getArtistById results: ${results.length}');
    if (results.isNotEmpty) {
      // ignore: avoid_print
      print('>>> primer resultado: ${results.first}');
    }
    if (results.isEmpty) {
      throw iTunesException('Artista $artistId no encontrado');
    }
    var artist = _artistFromJson(results.first);
    artist = await _withArtistArtwork(artist);
    return artist;
  }

  /// iTunes no devuelve `artworkUrl100` en los resultados de
  /// `musicArtist`. Este helper pide 1 álbum del artista y usa su
  /// artwork como thumbnail.
  Future<ArtistInfo> _withArtistArtwork(ArtistInfo basic) async {
    if (basic.thumbnailUrl.isNotEmpty) return basic;
    try {
      final albums = await _client.lookup(basic.id, entity: 'album', limit: 1);
      if (albums.isEmpty) return basic;
      final art = albums.first['artworkUrl100'] as String? ?? '';
      if (art.isEmpty) return basic;
      return ArtistInfo(
        source: basic.source,
        id: basic.id,
        name: basic.name,
        thumbnailUrl: _upsizeArt(art, 600),
        url: basic.url,
      );
    } catch (_) {
      return basic;
    }
  }

  @override
  Future<List<SongInfo>> getArtistTopTracks(
    String artistId, {
    int limit = 5,
  }) async {
    final results = await _client.lookup(
      artistId,
      entity: 'song',
      limit: limit,
    );
    // El primer resultado es el artista (wrapperType='artist').
    final tracks = results.where((r) => r['wrapperType'] == 'track').toList();
    return tracks.map(_songFromJson).toList();
  }

  @override
  Future<List<ArtistInfo>> searchAllArtists(
    String query, {
    int limit = 10,
  }) async {
    final results = await _client.search(
      query,
      entity: 'musicArtist',
      limit: limit,
    );
    return results.map(_artistFromJson).toList();
  }

  @override
  Future<List<SimplifiedArtist>> searchArtists(
    String query, {
    int limit = 10,
  }) async {
    final results = await _client.search(
      query,
      entity: 'musicArtist',
      limit: limit,
    );
    return results.map(_simplifiedArtistFromJson).toList();
  }

  @override
  Future<SimplifiedArtist> searchArtist(String query) async {
    final results = await _client.search(
      query,
      entity: 'musicArtist',
      limit: 1,
    );
    if (results.isEmpty) throw iTunesException('Sin artista para "$query"');
    return _simplifiedArtistFromJson(results.first);
  }

  @override
  Future<List<Albumc>> getArtistDiscography(
    String artistId, {
    int concurrency = 8,
    Duration minSpacing = const Duration(milliseconds: 60),
  }) async {
    final results = await _client.lookup(artistId, entity: 'album', limit: 200);
    // El primer resultado es el artista (wrapperType='artist').
    final albums = results
        .where((r) => r['wrapperType'] == 'collection')
        .toList();
    return albums.map(_albumcFromJson).toList();
  }

  @override
  Future<List<Albumc>> getArtistCollections(
    String artistId, {
    int albumsLimit = 10,
    int epsLimit = 10,
    int singlesLimit = 10,
    int candidateBuffer = 60,
    int concurrency = 8,
    Duration minSpacing = const Duration(milliseconds: 60),
  }) async {
    final all = await getArtistDiscography(artistId);
    final albums = <Albumc>[];
    final epsAndSingles = <Albumc>[];
    for (final a in all) {
      if (a.recordType == 'album') {
        albums.add(a);
      } else {
        epsAndSingles.add(a);
      }
    }
    return [
      ...albums.take(albumsLimit),
      ...epsAndSingles.take(epsLimit + singlesLimit),
    ];
  }

  @override
  Future<List<SimplifiedArtist>> getRelatedArtists(
    String artistId, {
    int limit = 10,
  }) async {
    try {
      final self = await getArtistById(artistId);
      final results = await _client.search(
        self.name,
        entity: 'musicArtist',
        limit: limit + 1,
      );
      return results
          .where((r) => '${r['artistId']}' != artistId)
          .take(limit)
          .map(_simplifiedArtistFromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<SongInfo>> getArtistDiscographySongs(
    String artistId, {
    int maxItems = 500,
  }) async {
    final uri = Uri.parse('https://itunes.apple.com/lookup').replace(
      queryParameters: {
        'id': artistId,
        'entity': 'song',
        'limit': '200',
        'country': 'US',
      },
    );
    // ignore: avoid_print
    print('═══════════════════════════════════════════');
    // ignore: avoid_print
    print('>>> discographySongs URL: $uri');

    final raw = await _client.lookup(artistId, entity: 'song', limit: 200);
    // ignore: avoid_print
    print('>>> resultCount: ${raw.length}');
    for (var i = 0; i < raw.length && i < 5; i++) {
      // ignore: avoid_print
      print(
        '>>> [$i] wrapperType=${raw[i]['wrapperType']} '
        'trackId=${raw[i]['trackId']} '
        'collectionId=${raw[i]['collectionId']} '
        'trackName=${raw[i]['trackName']} '
        'artistId=${raw[i]['artistId']}',
      );
    }
    // ignore: avoid_print
    print('═══════════════════════════════════════════');

    final tracks = raw.where((r) => r['trackId'] != null).toList();
    // ignore: avoid_print
    print('>>> tracks después del filtro: ${tracks.length}');
    return tracks.map(_songFromJson).toList();
  }

  // ─────────────────────────────────────────────────────────────
  //  ÁLBUMES
  // ─────────────────────────────────────────────────────────────

  @override
  Future<AlbumInfo> getAlbumById(String albumId) async {
    final results = await _client.lookup(albumId, entity: 'song', limit: 200);
    if (results.isEmpty) throw iTunesException('Álbum $albumId no encontrado');

    final tracks = results.where((r) => r['wrapperType'] == 'track').toList();
    final collection = results.firstWhere(
      (r) => r['wrapperType'] == 'collection',
      orElse: () => results.first,
    );

    return _albumInfoFromJson(collection, tracks);
  }

  @override
  Future<Albumc?> getAlbumFromSong(SongInfo song) async {
    try {
      final results = await _client.lookup(song.id);
      if (results.isEmpty) return null;
      final r = results.first;
      final collectionId = r['collectionId'];
      if (collectionId == null) return null;
      final albumResults = await _client.lookup(
        '$collectionId',
        entity: 'album',
      );
      if (albumResults.isEmpty) return null;
      // Filtra por si el primero es el artista.
      final album = albumResults.firstWhere(
        (x) => x['wrapperType'] == 'collection',
        orElse: () => albumResults.first,
      );
      return _albumcFromJson(album);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AlbumInfo?> getFullAlbumFromSong(SongInfo song) async {
    final preview = await getAlbumFromSong(song);
    if (preview == null) return null;
    return getAlbumById(preview.id);
  }

  @override
  Future<List<Albumc>> searchAlbums(String query, {int limit = 50}) async {
    // ignore: avoid_print
    print('>>> searchAlbums query="$query" limit=$limit');
    final results = await _client.search(query, entity: 'album', limit: limit);
    // ignore: avoid_print
    print('>>> searchAlbums devolvió ${results.length}');
    for (var i = 0; i < results.length && i < 3; i++) {
      // ignore: avoid_print
      print(
        '>>> [$i] collectionId=${results[i]['collectionId']} '
        'collectionName=${results[i]['collectionName']} '
        'trackCount=${results[i]['trackCount']}',
      );
    }
    return results.map(_albumcFromJson).toList();
  }

  @override
  Future<Albumc> searchAlbum(String query) async {
    final results = await _client.search(query, entity: 'album', limit: 1);
    if (results.isEmpty) throw iTunesException('Sin álbum para "$query"');
    return _albumcFromJson(results.first);
  }

  // ─────────────────────────────────────────────────────────────
  //  MAPPERS
  // ─────────────────────────────────────────────────────────────

  DateTime? _parseReleaseDate(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  int? _parseBpm(dynamic raw) {
    if (raw is! num) return null;
    final v = raw.round();
    return v <= 0 ? null : v;
  }

  String _upsizeArt(String url, int size) {
    if (url.isEmpty) return '';
    return url.replaceAll('100x100', '${size}x$size');
  }

  SongInfo _songFromJson(Map<String, dynamic> json) {
    final art = json['artworkUrl100'] as String? ?? '';
    final trackId = '${json['trackId']}';
    final artistId = '${json['artistId']}';
    final artistName = json['artistName'] as String? ?? 'Unknown';
    final albumName = json['collectionName'] as String? ?? '';
    final collectionId = '${json['collectionId']}';

    final album = <String, dynamic>{
      'id': collectionId,
      'title': albumName,
      'cover_small': _upsizeArt(art, 56),
      'cover_medium': _upsizeArt(art, 250),
      'cover_big': _upsizeArt(art, 500),
      'cover_xl': _upsizeArt(art, 1000),
      'record_type': 'album',
    };

    final song = SongInfo(
      id: trackId,
      album: album,
      name: json['trackName'] as String? ?? '',
      duration: Duration(milliseconds: (json['trackTimeMillis'] as int?) ?? 0),
      shareurl: json['trackViewUrl'] as String? ?? '',
      artists: [
        Artist(source: metadataprovider.itunes, name: artistName, id: artistId),
      ],
      source: metadataprovider.itunes,
      streamingSource: StreamingManager.instance.provider,
      releaseDate: _parseReleaseDate(json['releaseDate']),
      bpm: _parseBpm(json['bpm']),
      isrc: json['isrc'] as String?,
      genre: json['primaryGenreName'] as String?,
      thumbnails: [
        Thumbnail(url: _upsizeArt(art, 56), width: 56, height: 56),
        Thumbnail(url: _upsizeArt(art, 250), width: 250, height: 250),
        Thumbnail(url: _upsizeArt(art, 500), width: 500, height: 500),
        Thumbnail(url: _upsizeArt(art, 1000), width: 1000, height: 1000),
      ],
    );

    return SongDatabase.instance?.resolveDownloaded(song) ?? song;
  }

  SimplifiedArtist _simplifiedArtistFromJson(Map<String, dynamic> json) {
    // iTunes NO devuelve artworkUrl100 en resultados de musicArtist.
    // Para listas, dejamos thumbnailUrl vacío. Si lo quieres, hay que
    // hacer un lookup por cada uno → caro.
    return SimplifiedArtist(
      source: metadataprovider.itunes,
      id: '${json['artistId']}',
      name: json['artistName'] as String? ?? '',
      thumbnailUrl: '',
      url: json['artistViewUrl'] as String? ?? '',
    );
  }

  ArtistInfo _artistFromJson(Map<String, dynamic> json) {
    return ArtistInfo(
      source: metadataprovider.itunes,
      id: '${json['artistId']}',
      name: json['artistName'] as String? ?? '',
      thumbnailUrl: '',
      url: json['artistViewUrl'] as String? ?? '',
    );
  }

  Albumc _albumcFromJson(Map<String, dynamic> json) {
    final art = json['artworkUrl100'] as String? ?? '';
    final releaseDate = json['releaseDate'] as String?;
    final trackCount = json['trackCount'] as int? ?? 99;

    final String recordType;
    if (trackCount <= 3) {
      recordType = 'single';
    } else if (trackCount <= 6) {
      recordType = 'ep';
    } else {
      recordType = 'album';
    }

    return Albumc(
      source: metadataprovider.itunes,
      id: '${json['collectionId']}',
      name: json['collectionName'] as String? ?? '',
      bannerurl: _upsizeArt(art, 500),
      year: releaseDate != null && releaseDate.length >= 4
          ? releaseDate.substring(0, 4)
          : '',
      recordType: recordType,
    );
  }

  AlbumInfo _albumInfoFromJson(
    Map<String, dynamic> collection,
    List<Map<String, dynamic>> tracks,
  ) {
    final artistId = '${collection['artistId']}';
    final artistName = collection['artistName'] as String? ?? '';
    final releaseDate = collection['releaseDate'] as String?;

    return AlbumInfo(
      source: metadataprovider.itunes,
      creator: SimplifiedArtist(
        source: metadataprovider.itunes,
        id: artistId,
        name: artistName,
        thumbnailUrl: '',
        url: collection['artistViewUrl'] as String? ?? '',
      ),
      content: tracks.map(_songFromJson).toList(),
      recordType: 'album',
      duration: Duration(
        milliseconds: (collection['trackTimeMillis'] as int?) ?? 0,
      ),
      releaseDate: _parseReleaseDate(releaseDate),
      genre: collection['primaryGenreName'] as String?,
      bpm: null,
      isrc: null,
    );
  }
}
