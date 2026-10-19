// lib/Backend/providers/providermanager.dart
import 'package:flutter/foundation.dart';
import 'package:mimic/Backend/songdata.dart';

import 'metadata/MusicBrainzAdapter.dart';
import 'musicprovider.dart';
import 'metadata/deezerAdapter.dart';
import 'metadata/soundcloudAdapter.dart';
import 'metadata/iTunesAdapter.dart';
import '../settings.dart';

import 'package:flutter/material.dart';

import 'privdersenums.dart';

class MetadataProvider extends ChangeNotifier {
  /// Proveedor actual, público y reasignable.
  MusicProvider inner;
  metadataprovider type;

  MetadataProvider({MusicProvider? provider, metadataprovider? type})
    : type = type ?? AppSettings.instance.defaultMetadataProvider,
      inner =
          provider ??
          _create(type ?? AppSettings.instance.defaultMetadataProvider);

  static MusicProvider _create(metadataprovider t) => switch (t) {
    metadataprovider.deezer => const DeezerProvider(),
    metadataprovider.soundcloud => SoundCloudProvider(),
    metadataprovider.itunes => iTunesProvider(),
    metadataprovider.musicbrainz => MusicBrainzProvider(),
    // Las canciones locales no tienen proveedor propio: si algo lo pide
    // (por ejemplo al abrir un artista), usamos el que eligió el usuario.
    metadataprovider.local => _create(
      AppSettings.instance.defaultMetadataProvider,
    ),
  };
  Future<void> switchTo(metadataprovider newType) async {
    if (newType == type) return;
    inner = _create(newType);
    type = newType;
    notifyListeners();
  }

  // ─── Canciones ───
  Future<SongInfo> searchSong(String q) => inner.searchSong(q);
  Future<List<SongInfo>> searchSongs(String q, {int limit = 10}) =>
      inner.searchSongs(q, limit: limit);
  Future<List<SongInfo>> searchAll(String q, {int limit = 10}) =>
      inner.searchSongs(q, limit: limit);
  Future<SongInfo> getSongById(String id) => inner.getSongById(id);
  Future<List<SongInfo>> getTrackRadio(SongInfo s, {int limit = 25}) =>
      inner.getTrackRadio(s, limit: limit);
  Future<List<SongInfo>> getAlbumRadio(String artistId, {int limit = 25}) =>
      inner.getAlbumRadio(artistId, limit: limit);

  Future<List<SongInfo>> getArtistDiscographySongs(
    String artistId, {
    int maxItems = 500,
  }) => inner.getArtistDiscographySongs(artistId, maxItems: maxItems);

  // ─── Artistas ───
  Future<ArtistInfo> searchArtistWithDetails(String q) =>
      inner.searchArtistWithDetails(q);
  Future<ArtistInfo> getArtistById(String artistId) =>
      inner.getArtistById(artistId);
  Future<List<SongInfo>> getArtistTopTracks(String artistId, {int limit = 5}) =>
      inner.getArtistTopTracks(artistId, limit: limit);
  Future<List<ArtistInfo>> searchAllArtists(String q, {int limit = 10}) =>
      inner.searchAllArtists(q, limit: limit);
  Future<List<SimplifiedArtist>> searchArtists(String q, {int limit = 10}) =>
      inner.searchArtists(q, limit: limit);
  Future<SimplifiedArtist> searchArtist(String q) => inner.searchArtist(q);

  Future<List<Albumc>> getArtistDiscography(
    String artistId, {
    int concurrency = 8,
    Duration minSpacing = const Duration(milliseconds: 60),
  }) => inner.getArtistDiscography(
    artistId,
    concurrency: concurrency,
    minSpacing: minSpacing,
  );

  Future<List<Albumc>> getArtistCollections(
    String artistId, {
    int albumsLimit = 10,
    int epsLimit = 10,
    int singlesLimit = 10,
    int candidateBuffer = 60,
    int concurrency = 8,
    Duration minSpacing = const Duration(milliseconds: 60),
  }) => inner.getArtistCollections(
    artistId,
    albumsLimit: albumsLimit,
    epsLimit: epsLimit,
    singlesLimit: singlesLimit,
    candidateBuffer: candidateBuffer,
    concurrency: concurrency,
    minSpacing: minSpacing,
  );

  Future<List<SimplifiedArtist>> getRelatedArtists(
    String artistId, {
    int limit = 10,
  }) => inner.getRelatedArtists(artistId, limit: limit);

  // ─── Álbumes ───
  Future<AlbumInfo> getAlbumById(String albumId) => inner.getAlbumById(albumId);
  Future<Albumc?> getAlbumFromSong(SongInfo s) => inner.getAlbumFromSong(s);
  Future<AlbumInfo?> getFullAlbumFromSong(SongInfo s) =>
      inner.getFullAlbumFromSong(s);
  Future<List<Albumc>> searchAlbums(String q, {int limit = 50}) =>
      inner.searchAlbums(q, limit: limit);
  Future<Albumc> searchAlbum(String q) => inner.searchAlbum(q);
}
