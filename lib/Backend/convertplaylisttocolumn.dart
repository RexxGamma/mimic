import 'dart:convert';
import 'songdata.dart';
import 'providers/privdersenums.dart';

// ═══════════════════════════════════════════════════════════════
// SongInfo → Map (para INSERT)
// ═══════════════════════════════════════════════════════════════
extension SongInfoMapper on SongInfo {
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'artists': jsonEncode(artists.map((a) => a.toMap()).toList()),
        'thumbnails': jsonEncode(thumbnails.map((t) => t.toMap()).toList()),
        'duration_ms': duration.inMilliseconds,
        'release_date': releaseDate?.millisecondsSinceEpoch,
        'bpm': bpm,
        'isrc': isrc,
        'genre': genre,
        'streaming_url': streamingurl?.toString(),
        'album': album == null ? null : jsonEncode(album),
        'share_url': shareurl?.toString(),
        'source': source.name,
        'streaming_source': streamingSource.name,
        'downloadpath' : downloadPath,
        'downloadbannerpath': downloadBannerPath
      };
}

extension ArtistMapper on Artist {
  Map<String, dynamic> toMap() => {
    'name': name,
    'id': id,
    'source': source.name,
  };

  static Artist fromMap(Map<String, dynamic> m) =>
      Artist(
        name: m['name'] as String,
        id: m['id'] as String,
        source: metadataprovider.values.byName(m['source'] as String),
      );
}
extension ThumbnailMapper on Thumbnail {
  Map<String, dynamic> toMap() =>
      {'url': url, 'width': width, 'height': height};
  static Thumbnail fromMap(Map<String, dynamic> m) => Thumbnail(
        url: m['url'] as String,
        width: (m['width'] as num).toInt(),
        height: (m['height'] as num).toInt(),
      );
}

// ═══════════════════════════════════════════════════════════════
// Row(sqlite3) → SongInfo
// ═══════════════════════════════════════════════════════════════
class SongInfoFromMap {
  
  static metadataprovider _parseMetadata(String? name) {
  if (name == null) {
    throw StateError('songs.source es NULL — dato corrupto');
  }
  return metadataprovider.values.firstWhere(
    (e) => e.name == name,
    orElse: () => throw StateError(
      'songs.source = "$name" no es un metadataprovider válido. '
      'Valores: ${metadataprovider.values.map((e) => e.name).join(", ")}',
    ),
  );
}

static StreamingProvider _parseStreaming(String? name) {
  if (name == null) {
    throw StateError('songs.streaming_source es NULL — dato corrupto');
  }
  return StreamingProvider.values.firstWhere(
    (e) => e.name == name,
    orElse: () => throw StateError(
      'songs.streaming_source = "$name" no es un StreamingProvider válido. '
      'Valores: ${StreamingProvider.values.map((e) => e.name).join(", ")}',
    ),
  );
}

  static SongInfo fromMap(Map<String, dynamic> row) {
    final artistsJson = row['artists'] as String?;
    final thumbsJson = row['thumbnails'] as String?;
    final albumRaw = row['album'];

    return SongInfo(
      id: row['id'] as String,
      name: row['name'] as String,
      artists: artistsJson == null || artistsJson.isEmpty
          ? []
          : (jsonDecode(artistsJson) as List)
              .map((e) => ArtistMapper.fromMap(
                    Map<String, dynamic>.from(e),
                  ))
              .toList(),
      thumbnails: thumbsJson == null || thumbsJson.isEmpty
          ? []
          : (jsonDecode(thumbsJson) as List)
              .map((e) => ThumbnailMapper.fromMap(
                    Map<String, dynamic>.from(e),
                  ))
              .toList(),
      duration: Duration(milliseconds: (row['duration_ms'] as int?) ?? 0),
      releaseDate: row['release_date'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['release_date'] as int),
      bpm: row['bpm'] as int?,
      isrc: row['isrc'] as String?,
      genre: row['genre'] as String?,
      streamingurl: row['streaming_url'],
      album: albumRaw == null ? null : jsonDecode(albumRaw as String),
      shareurl: row['share_url'],
      source: _parseMetadata(row['source'] as String?),
      streamingSource: _parseStreaming(row['streaming_source'] as String?),
      downloadPath: row['downloadpath'] as String?,
      downloadBannerPath: row['downloadbannerpath'] as String?,
    );
  }
}