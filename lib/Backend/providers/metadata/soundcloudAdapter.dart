// lib/Backend/Providers/soundcloud_provider.dart
import 'package:mimic/Backend/songdata.dart';

import 'soundcloud.dart';
import '../musicprovider.dart';
import '../privdersenums.dart';
import '../streaming/streamingmanager.dart';
import '../../songlisttoplay.dart';

/// Proveedor SoundCloud que implementa [MusicProvider].
class SoundCloudProvider extends MusicProvider {
  SoundCloudProvider({String? clientId, SoundCloudClient? client})
    : _client = client ?? SoundCloudClient(clientId: clientId);

  final SoundCloudClient _client;

  // ─── Búsqueda (instancias lazy) ───

  late final SoundCloudSearch<SongInfo> _songSearch = SoundCloudSearch(
    client: _client,
    fromJson: _songFromJson,
  );

  late final SoundCloudArtistSearch<ArtistInfo> _artistSearch =
      SoundCloudArtistSearch(client: _client, fromJson: _artistInfoFromJson);

  late final SoundCloudArtistSearch<SimplifiedArtist> _artistSimple =
      SoundCloudArtistSearch(
        client: _client,
        fromJson: _simplifiedArtistFromJson,
      );

  late final SoundCloudAlbumSearch<Albumc> _albumSearch = SoundCloudAlbumSearch(
    client: _client,
    fromJson: _albumcFromJson,
  );

  // ─────────────────────────────────────────────────────────────
  //  STREAM
  // ─────────────────────────────────────────────────────────────

  @override
  Future<String?> resolveStreamUrl(SongInfo song) =>
      _songSearch.resolveStreamUrl(song.id);

  // ─────────────────────────────────────────────────────────────
  //  CANCIONES
  // ─────────────────────────────────────────────────────────────

  @override
  Future<SongInfo> searchSong(String query) => _songSearch.search(query);

  @override
  Future<List<SongInfo>> searchSongs(String query, {int limit = 10}) =>
      _songSearch.searchAll(query, limit: limit);

  @override
  Future<SongInfo> getSongById(String songId) => _songSearch.getById(songId);

  @override
  Future<List<SongInfo>> getTrackRadio(SongInfo song, {int limit = 25}) =>
      Future.error(UnsupportedError('SoundCloud no expone radio por track'));

  @override
  Future<List<SongInfo>> getAlbumRadio(String artistId, {int limit = 25}) =>
      Future.error(UnsupportedError('SoundCloud no expone radio por artista'));

  // ─────────────────────────────────────────────────────────────
  //  ARTISTAS
  // ─────────────────────────────────────────────────────────────

  @override
  Future<ArtistInfo> searchArtistWithDetails(String query) async {
    final artist = await _artistSearch.search(query);
    final tracks = await _artistSearch.topTracks(
      artist.id,
      _songFromJson,
      limit: 5,
    );
    final albums = await _artistSearch.playlists(
      artist.id,
      _albumcFromJson,
      limit: 20,
    );
    return ArtistInfo(
      source: metadataprovider.soundcloud,
      id: artist.id,
      name: artist.name,
      thumbnailUrl: artist.thumbnailUrl,
      url: artist.url,
      toptracks: tracks,
      artistalbums: albums,
    );
  }

  @override
  Future<ArtistInfo> getArtistById(String artistId) =>
      _artistSearch.getById(artistId);

  @override
  Future<List<SongInfo>> getArtistTopTracks(String artistId, {int limit = 5}) =>
      _artistSearch.topTracks(artistId, _songFromJson, limit: limit);

  @override
  Future<List<ArtistInfo>> searchAllArtists(String query, {int limit = 10}) =>
      _artistSearch.searchAll(query, limit: limit);

  @override
  Future<List<SimplifiedArtist>> searchArtists(
    String query, {
    int limit = 10,
  }) => _artistSimple.searchAll(query, limit: limit);

  @override
  Future<SimplifiedArtist> searchArtist(String query) =>
      _artistSimple.search(query);

  @override
  Future<List<Albumc>> getArtistDiscography(
    String artistId, {
    int concurrency = 8,
    Duration minSpacing = const Duration(milliseconds: 60),
  }) async {
    return _artistSearch.playlists(artistId, _albumcFromJson, limit: 100);
  }

  @override
  Future<List<SongInfo>> getArtistDiscographySongs(
    String artistId, {
    int maxItems = 500,
  }) => _artistSearch.allTracks(artistId, _songFromJson, maxItems: maxItems);

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
    final playlists = await _artistSearch.playlists(
      artistId,
      _albumcFromJson,
      limit: albumsLimit + epsLimit + singlesLimit,
    );

    final albums = <Albumc>[];
    final singles = <Albumc>[];
    for (final p in playlists) {
      if (p.recordType == 'album') {
        albums.add(p);
      } else {
        singles.add(p);
      }
    }

    return [
      ...albums.take(albumsLimit),
      ...singles.take(epsLimit + singlesLimit),
    ];
  }

  @override
  Future<List<SimplifiedArtist>> getRelatedArtists(
    String artistId, {
    int limit = 10,
  }) => _artistSimple.relatedArtists(
    artistId,
    _simplifiedArtistFromJson,
    limit: limit,
  );

  // ─────────────────────────────────────────────────────────────
  //  ÁLBUMES (playlists is_album)
  // ─────────────────────────────────────────────────────────────

  @override
  Future<AlbumInfo> getAlbumById(String albumId) =>
      _albumSearch.getWithTracks(albumId, _albumInfoFromJson);

  @override
  Future<Albumc?> getAlbumFromSong(SongInfo song) async {
    try {
      final track = await _songSearch.rawById(song.id);
      final user = track['user'] as Map<String, dynamic>?;
      final userId = user?['id'];
      if (userId == null) return null;

      final playlists = await _artistSearch.playlists(
        '$userId',
        _albumcFromJson,
        limit: 20,
      );
      if (playlists.isEmpty) return null;
      return playlists.first;
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
  Future<List<Albumc>> searchAlbums(String query, {int limit = 10}) =>
      _albumSearch.searchAll(query, limit: limit);

  @override
  Future<Albumc> searchAlbum(String query) => _albumSearch.search(query);

  // ─────────────────────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────────────────────

  DateTime? _parseReleaseDate(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// SoundCloud guarda art en distintos tamaños cambiando el sufijo.
  String _upgradeArt(String url, int target) {
    if (url.isEmpty) return '';
    final match = RegExp(r'-(large|t\d+x\d+|small|mini|original)\.(jpg|png)$')
        .firstMatch(url);
    if (match == null) return url;

    final String size;
    if (target >= 500) {
      size = 't500x500';
    } else if (target >= 300) {
      size = 't300x300';
    } else if (target >= 200) {
      size = 't200x200';
    } else {
      size = 'small';
    }
    return url.replaceFirst(match.group(0)!, '-$size.${match.group(2)}');
  }

  // ─────────────────────────────────────────────────────────────
  //  MAPPERS JSON → modelos
  // ─────────────────────────────────────────────────────────────

  // lib/Backend/Providers/soundcloud_provider.dart

  // …

  SongInfo _songFromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final artwork =
        (json['artwork_url'] as String?) ??
        (user['avatar_url'] as String?) ??
        '';

    final trackUrn =
        json['urn'] as String? ?? 'soundcloud:tracks:${json['id']}';

    final album = <String, dynamic>{
      'id': trackUrn,
      'title': json['title'] ?? '',
      'cover_xl': _upgradeArt(artwork, 1000),
      'cover_big': _upgradeArt(artwork, 500),
      'cover_medium': _upgradeArt(artwork, 250),
      'cover_small': _upgradeArt(artwork, 56),
      'record_type': (json['is_album'] == true) ? 'album' : 'playlist',
    };

    final song = SongInfo(
      id: '${json['id']}',
      album: album,
      name: json['title'] as String? ?? '',
      duration: Duration(milliseconds: (json['duration'] as int?) ?? 0),
      shareurl: json['permalink_url'] as String? ?? '',
      artists: [
        Artist(
          source: metadataprovider.soundcloud,
          name: user['username'] as String? ?? 'Unknown',
          id: '${user['id']}',
        ),
      ],
      streamingSource: StreamingManager.instance.provider,
      source: metadataprovider.soundcloud,
      releaseDate: _parseReleaseDate(json['release_date']),
      bpm: (json['bpm'] as num?)?.round(),
      isrc: json['isrc'] as String?,
      genre: json['genre'] as String?,
      thumbnails: [
        Thumbnail(url: _upgradeArt(artwork, 56), width: 56, height: 56),
        Thumbnail(url: _upgradeArt(artwork, 250), width: 250, height: 250),
        Thumbnail(url: _upgradeArt(artwork, 500), width: 500, height: 500),
        Thumbnail(url: _upgradeArt(artwork, 1000), width: 1000, height: 1000),
      ],
    );

    // 🔁 Proveedor → DB → track descargado o track original
    return SongDatabase.instance?.resolveDownloaded(song) ?? song;
  }

  AlbumInfo _albumInfoFromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final tracksRaw =
        (json['tracks'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
        const [];

    return AlbumInfo(
      source: metadataprovider.soundcloud,
      creator: SimplifiedArtist(
        source: metadataprovider.soundcloud,
        id: '${user['id'] ?? ''}',
        name: user['username'] as String? ?? '',
        thumbnailUrl: _upgradeArt(user['avatar_url'] as String? ?? '', 500),
        url: user['permalink_url'] as String? ?? '',
      ),
      content: tracksRaw.map(_songFromJson).toList(),
      recordType: (json['is_album'] == true) ? 'album' : 'playlist',
      duration: Duration(milliseconds: (json['duration'] as int?) ?? 0),
      releaseDate: _parseReleaseDate(json['release_date']),
      genre: json['genre'] as String?,
      bpm: null,
      isrc: null,
    );
  }

  SimplifiedArtist _simplifiedArtistFromJson(Map<String, dynamic> json) {
    final avatar = json['avatar_url'] as String? ?? '';
    return SimplifiedArtist(
      source: metadataprovider.soundcloud,
      id: '${json['id']}',
      name: json['username'] as String? ?? '',
      thumbnailUrl: _upgradeArt(avatar, 500),
      url: json['permalink_url'] as String? ?? '',
    );
  }

  ArtistInfo _artistInfoFromJson(Map<String, dynamic> json) {
    final avatar = json['avatar_url'] as String? ?? '';
    return ArtistInfo(
      source: metadataprovider.soundcloud,
      id: '${json['id']}',
      name: json['username'] as String? ?? '',
      thumbnailUrl: _upgradeArt(avatar, 500),
      url: json['permalink_url'] as String? ?? '',
    );
  }

  Albumc _albumcFromJson(Map<String, dynamic> json) {
    final artwork =
        (json['artwork_url'] as String?) ??
        ((json['user'] as Map<String, dynamic>?)?['avatar_url'] as String?) ??
        '';
    final releaseDate = json['release_date'] as String?;
    return Albumc(
      source: metadataprovider.soundcloud,
      id: '${json['id']}',
      name: json['title'] as String? ?? '',
      bannerurl: _upgradeArt(artwork, 500),
      year: releaseDate != null && releaseDate.length >= 4
          ? releaseDate.substring(0, 4)
          : '',
      recordType: (json['is_album'] == true) ? 'album' : 'playlist',
    );
  }
}
