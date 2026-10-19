import 'providers/privdersenums.dart';

extension SongInfoThumbs on SongInfo {
  bool get isLocal => id.startsWith('local_');

  String? thumbnailUrl([int preferredIndex = 3]) {
    if (thumbnails.isEmpty) return null;
    final i = preferredIndex.clamp(0, thumbnails.length - 1).toInt();
    return thumbnails[i].url;
  }
}

class SongInfo {
  final String id;
  final String name;
  final List<Artist> artists;
  final List<Thumbnail> thumbnails;

  final Duration duration;
  final DateTime? releaseDate;
  final int? bpm;
  final String? isrc;
  final String? genre;

  final dynamic streamingurl;
  final dynamic album;
  final dynamic shareurl;

  final metadataprovider source;
  final StreamingProvider streamingSource;

  String? downloadPath;
  String? downloadBannerPath;

  SongInfo({
    required this.id,
    required this.name,
    required this.artists,
    required this.thumbnails,
    required this.duration,
    required this.source,
    required this.streamingSource,
    this.releaseDate,
    this.bpm,
    this.isrc,
    this.genre,
    this.streamingurl,
    this.album,
    this.shareurl,
    this.downloadPath,
    this.downloadBannerPath,
  });
}

class Artist {
  final String name;
  final String id;
  final metadataprovider source;

  Artist({required this.name, required this.id, required this.source});
}

class Thumbnail {
  final String url;
  final int width;
  final int height;

  Thumbnail({required this.url, required this.width, required this.height});
}

class ArtistInfo {
  final String id;
  final String name;
  final String thumbnailUrl;
  final artistalbums;
  final toptracks;
  final String url;
  final metadataprovider source;
  String? downloadBannerPath;

  ArtistInfo({
    required this.id,
    required this.name,
    required this.thumbnailUrl,
    this.toptracks,
    this.artistalbums,
    required this.url,
    required this.source,
    this.downloadBannerPath,
  });
}

class SimplifiedArtist {
  final String id;
  final String name;
  final String thumbnailUrl;
  final String url;
  final metadataprovider source;
  String? downloadBannerPath;
  SimplifiedArtist({
    required this.id,
    required this.name,
    required this.thumbnailUrl,
    required this.url,
    required this.source,
    this.downloadBannerPath,
  });
}

class Albumc {
  final String id;
  final String name;
  final String bannerurl;
  final String year;
  final String recordType;
  final metadataprovider source;
  String? downloadBannerPath;

  Albumc({
    required this.id,
    required this.name,
    required this.bannerurl,
    required this.year,
    required this.recordType,
    required this.source,
    this.downloadBannerPath,
  });
}

class AlbumInfo {
  final SimplifiedArtist creator;
  final List<SongInfo> content;
  final String recordType;

  final Duration? duration;
  final DateTime? releaseDate;
  final int? bpm;
  final String? isrc;
  final String? genre;
  final metadataprovider source;
  String? downloadBannerPath;

  AlbumInfo({
    required this.creator,
    required this.content,
    required this.recordType,
    required this.source,
    this.duration,
    this.releaseDate,
    this.bpm,
    this.isrc,
    this.genre,
    this.downloadBannerPath,
  });
}
