// lib/Backend/Providers/musicbrainz_provider.dart
import 'package:mimic/Backend/songdata.dart';

import 'musicbrainz.dart';
import '../musicprovider.dart';
import '../privdersenums.dart';
import '../streaming/streamingmanager.dart';
import '../../songlisttoplay.dart';

class MusicBrainzProvider extends MusicProvider {
  MusicBrainzProvider({
    String userAgent = 'Mimic/1.0 ( https://github.com/usuario/mimic )',
    MusicBrainzClient? client,
  }) : _client = client ?? MusicBrainzClient(userAgent: userAgent);

  final MusicBrainzClient _client;

  @override
  Future<String?> resolveStreamUrl(SongInfo song) async => null;

  // ─────────────────────────────────────────────────────────────
  //  CANCIONES
  // ─────────────────────────────────────────────────────────────

  @override
  Future<SongInfo> searchSong(String query) async {
    final results = await _client.searchRecordings(query, limit: 1);
    if (results.isEmpty) {
      throw MusicBrainzException('Sin resultados para "$query"');
    }
    return _songFromJson(results.first);
  }

  @override
  Future<List<SongInfo>> searchSongs(String query, {int limit = 10}) async {
    final results = await _client.searchRecordings(query, limit: limit);
    return results.map(_songFromJson).toList();
  }

  @override
  Future<SongInfo> getSongById(String songId) async {
    final json = await _client.getRecording(songId);
    return _songFromJson(json);
  }

  @override
  Future<List<SongInfo>> getTrackRadio(SongInfo song, {int limit = 25}) async {
    if (song.artists.isEmpty) return const [];
    final results = await _client.searchRecordings(
      song.artists.first.name,
      limit: limit,
    );
    return results.map(_songFromJson).toList();
  }

  @override
  Future<List<SongInfo>> getAlbumRadio(
    String artistId, {
    int limit = 25,
  }) async {
    final results = await _client.browseRecordingsByArtist(
      artistId,
      limit: limit,
    );
    return results.map(_songFromJson).toList();
  }

  // ─────────────────────────────────────────────────────────────
  //  ARTISTAS
  // ─────────────────────────────────────────────────────────────

  @override
  Future<ArtistInfo> searchArtistWithDetails(String query) async {
    final artist = await searchArtist(query);
    final top = await getArtistTopTracks(artist.id, limit: 5);
    final albums = await getArtistDiscography(artist.id);
    return ArtistInfo(
      source: metadataprovider.musicbrainz,
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
    final json = await _client.getArtist(artistId);
    return _artistFromJson(json);
  }

  @override
  Future<List<SongInfo>> getArtistTopTracks(
    String artistId, {
    int limit = 5,
  }) async {
    final results = await _client.searchRecordingsByArtist(
      artistId,
      limit: limit,
    );
    return results.map(_songFromJson).toList();
  }

  @override
  Future<List<ArtistInfo>> searchAllArtists(
    String query, {
    int limit = 10,
  }) async {
    final results = await _client.searchArtists(query, limit: limit);
    return results.map(_artistFromJson).toList();
  }

  @override
  Future<List<SimplifiedArtist>> searchArtists(
    String query, {
    int limit = 10,
  }) async {
    final results = await _client.searchArtists(query, limit: limit);
    return results.map(_simplifiedArtistFromJson).toList();
  }

  @override
  Future<SimplifiedArtist> searchArtist(String query) async {
    final results = await _client.searchArtists(query, limit: 1);
    if (results.isEmpty) {
      throw MusicBrainzException('Sin artistas para "$query"');
    }
    return _simplifiedArtistFromJson(results.first);
  }

  @override
  Future<List<Albumc>> getArtistDiscography(
    String artistId, {
    int concurrency = 8,
    Duration minSpacing = const Duration(milliseconds: 60),
  }) async {
    final results = await _client.browseReleaseGroupsByArtist(artistId);
    return results.map(_albumcFromJson).toList();
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
    final eps = <Albumc>[];
    final singles = <Albumc>[];
    for (final a in all) {
      switch (a.recordType) {
        case 'single':
          singles.add(a);
        case 'ep':
          eps.add(a);
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

  @override
  Future<List<SimplifiedArtist>> getRelatedArtists(
    String artistId, {
    int limit = 10,
  }) async {
    return const [];
  }

  @override
  Future<List<SongInfo>> getArtistDiscographySongs(
    String artistId, {
    int maxItems = 500,
  }) async {
    final results = await _client.searchRecordingsByArtist(
      artistId,
      limit: maxItems.clamp(1, 100),
    );
    return results.map(_songFromJson).toList();
  }

  // ─────────────────────────────────────────────────────────────
  //  ÁLBUMES
  // ─────────────────────────────────────────────────────────────

  @override
  Future<AlbumInfo> getAlbumById(String albumId) async {
    final rg = await _client.getReleaseGroup(albumId);
    final releases = (rg['releases'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    if (releases.isEmpty) {
      throw MusicBrainzException('Release-group $albumId sin releases');
    }
    final releaseId = releases.first['id'] as String;
    final release = await _client.getRelease(releaseId);

    release['_releaseGroupTitle'] = rg['title'];
    release['_releaseGroupFirstDate'] = rg['first-release-date'];
    release['_releaseGroupPrimaryType'] = rg['primary-type'];
    release['_releaseGroupSecondaryTypes'] = rg['secondary-types'];
    release['_releaseGroupId'] = rg['id'];

    return _albumInfoFromJson(release);
  }

  @override
  Future<Albumc?> getAlbumFromSong(SongInfo song) async {
    try {
      final json = await _client.getRecording(song.id);
      final releases = (json['releases'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      if (releases.isEmpty) return null;

      Map<String, dynamic>? chosen;
      for (final rel in releases) {
        final rg = rel['release-group'];
        if (rg is Map) {
          final primary = rg['primary-type'] as String?;
          if (primary == 'Album' || primary == 'EP') {
            chosen = rel;
            break;
          }
        }
      }
      chosen ??= releases.first;

      final rg = chosen['release-group'] as Map<String, dynamic>?;
      if (rg == null) return null;

      final artistCredit = chosen['artist-credit'] ?? json['artist-credit'];
      final rgWithCredit = Map<String, dynamic>.from(rg);
      rgWithCredit['_artistCredit'] = artistCredit;

      return _albumcFromJson(rgWithCredit);
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
    final results = await _client.searchReleaseGroups(query, limit: limit);
    return results.map(_albumcFromJson).toList();
  }

  @override
  Future<Albumc> searchAlbum(String query) async {
    final results = await _client.searchReleaseGroups(query, limit: 1);
    if (results.isEmpty) {
      throw MusicBrainzException('Sin álbumes para "$query"');
    }
    return _albumcFromJson(results.first);
  }

  // ─────────────────────────────────────────────────────────────
  //  MAPPERS
  // ─────────────────────────────────────────────────────────────

  DateTime? _parseReleaseDate(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    final parts = raw.split('-');
    if (parts.isEmpty) return null;
    final y = int.tryParse(parts[0]);
    if (y == null) return null;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
    final d = parts.length > 2 ? int.tryParse(parts[2]) ?? 1 : 1;
    return DateTime(y, m, d);
  }

  String _artistCreditToString(dynamic credit) {
    if (credit is! List) return 'Unknown';
    final sb = StringBuffer();
    for (final c in credit) {
      if (c is Map && c['name'] is String) {
        sb.write(c['name']);
        if (c['joinphrase'] is String) sb.write(c['joinphrase']);
      }
    }
    final s = sb.toString().trim();
    return s.isEmpty ? 'Unknown' : s;
  }

  String? _firstArtistId(dynamic credit) {
    if (credit is! List || credit.isEmpty) return null;
    final first = credit.first;
    if (first is Map) {
      final artist = first['artist'];
      if (artist is Map && artist['id'] is String) return artist['id'];
    }
    return null;
  }

  String _recordTypeFromReleaseGroup(Map<String, dynamic> json) {
    final primary = json['primary-type'] as String?;
    final secondary = (json['secondary-types'] as List<dynamic>? ?? [])
        .cast<String>();

    if (primary == 'Single') return 'single';
    if (primary == 'EP') return 'ep';
    if (primary == 'Album') {
      if (secondary.contains('Compilation')) return 'compile';
      return 'album';
    }
    return 'album';
  }

  SongInfo _songFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final title = json['title'] as String? ?? '';
    final lengthMs = json['length'] as int? ?? 0;

    final credit = json['artist-credit'];
    final artistName = _artistCreditToString(credit);
    final artistId = _firstArtistId(credit) ?? '';

    // Campos inyectados por _albumInfoFromJson.
    String albumTitle = json['_albumTitle'] as String? ?? '';
    String albumId = json['_albumId'] as String? ?? '';
    String rgId = json['_albumCoverRgId'] as String? ?? '';
    String? releaseDate;

    // Fallback: resolver desde releases[] si no hay nada inyectado.
    if (albumId.isEmpty || rgId.isEmpty) {
      final releases = (json['releases'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      if (releases.isNotEmpty) {
        final rel = releases.first;
        albumTitle = albumTitle.isEmpty
            ? (rel['title'] as String? ?? '')
            : albumTitle;
        albumId = albumId.isEmpty ? (rel['id'] as String? ?? '') : albumId;
        releaseDate = rel['date'] as String?;
        final rg = rel['release-group'];
        if (rg is Map && rg['id'] is String && rgId.isEmpty) {
          rgId = rg['id'] as String;
        }
      }
    }

    final coverSmall = rgId.isEmpty ? '' : coverArtUrl(rgId, size: 250);
    final coverMedium = rgId.isEmpty ? '' : coverArtUrl(rgId, size: 250);
    final coverBig = rgId.isEmpty ? '' : coverArtUrl(rgId, size: 500);
    final coverXl = rgId.isEmpty ? '' : coverArtUrl(rgId, size: 1200);

    final album = <String, dynamic>{
      'id': albumId,
      'title': albumTitle,
      'cover_small': coverSmall,
      'cover_medium': coverMedium,
      'cover_big': coverBig,
      'cover_xl': coverXl,
      'record_type': 'album',
    };

    final song = SongInfo(
      id: id,
      album: album,
      name: title,
      duration: Duration(milliseconds: lengthMs),
      shareurl: 'https://musicbrainz.org/recording/$id',
      artists: [
        Artist(
          source: metadataprovider.musicbrainz,
          name: artistName,
          id: artistId,
        ),
      ],
      source: metadataprovider.musicbrainz,
      streamingSource: StreamingManager.instance.provider,
      releaseDate: _parseReleaseDate(releaseDate),
      bpm: null,
      isrc: (json['isrcs'] as List<dynamic>?)?.firstOrNull as String?,
      genre: null,
      thumbnails: [
        Thumbnail(url: coverSmall, width: 56, height: 56),
        Thumbnail(url: coverMedium, width: 250, height: 250),
        Thumbnail(url: coverBig, width: 500, height: 500),
        Thumbnail(url: coverXl, width: 1000, height: 1000),
      ],
    );

    return SongDatabase.instance?.resolveDownloaded(song) ?? song;
  }

  SimplifiedArtist _simplifiedArtistFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    return SimplifiedArtist(
      source: metadataprovider.musicbrainz,
      id: id,
      name: json['name'] as String? ?? '',
      thumbnailUrl: '',
      url: 'https://musicbrainz.org/artist/$id',
    );
  }

  ArtistInfo _artistFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    return ArtistInfo(
      source: metadataprovider.musicbrainz,
      id: id,
      name: json['name'] as String? ?? '',
      thumbnailUrl: '',
      url: 'https://musicbrainz.org/artist/$id',
    );
  }

  Albumc _albumcFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final title = json['title'] as String? ?? '';
    final firstDate =
        json['first-release-date'] as String? ?? json['date'] as String?;
    final recordType = _recordTypeFromReleaseGroup(json);

    return Albumc(
      source: metadataprovider.musicbrainz,
      id: id,
      name: title,
      bannerurl: id.isEmpty ? '' : coverArtUrl(id, size: 1200),
      year: firstDate != null && firstDate.length >= 4
          ? firstDate.substring(0, 4)
          : '',
      recordType: recordType,
    );
  }

  AlbumInfo _albumInfoFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final title =
        json['_releaseGroupTitle'] as String? ?? json['title'] as String? ?? '';
    final firstDate =
        json['_releaseGroupFirstDate'] as String? ?? json['date'] as String?;
    final primaryType = json['_releaseGroupPrimaryType'] as String? ?? 'Album';

    final rgId =
        json['_releaseGroupId'] as String? ??
        (json['release-group'] as Map<String, dynamic>?)?['id'] as String? ??
        id;

    final credit = json['artist-credit'];
    final artistName = _artistCreditToString(credit);
    final artistId = _firstArtistId(credit) ?? '';

    final media = (json['media'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final recordings = <Map<String, dynamic>>[];
    for (final m in media) {
      final tracks = (m['tracks'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      for (final t in tracks) {
        final rec = t['recording'];
        if (rec is Map<String, dynamic>) {
          final lengthMs = rec['length'] as int? ?? t['length'] as int? ?? 0;
          rec['length'] = lengthMs;
          rec['artist-credit'] = credit;

          // Inyectar campos del álbum padre.
          rec['_albumCoverRgId'] = rgId;
          rec['_albumTitle'] = title;
          rec['_albumId'] = id;

          recordings.add(rec);
        }
      }
    }

    final recordType = (primaryType == 'Single')
        ? 'single'
        : (primaryType == 'EP' ? 'ep' : 'album');

    return AlbumInfo(
      source: metadataprovider.musicbrainz,
      creator: SimplifiedArtist(
        source: metadataprovider.musicbrainz,
        id: artistId,
        name: artistName,
        thumbnailUrl: '',
        url: 'https://musicbrainz.org/artist/$artistId',
      ),
      content: recordings.map(_songFromJson).toList(),
      recordType: recordType,
      duration: Duration.zero,
      releaseDate: _parseReleaseDate(firstDate),
      genre: null,
      bpm: null,
      isrc: null,
    );
  }
}
