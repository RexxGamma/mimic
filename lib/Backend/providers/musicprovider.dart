// lib/Backend/Providers/musicprovider.dart
import 'package:mimic/Backend/songdata.dart';

abstract class MusicProvider {
  const MusicProvider();

  // ─── Stream ───

  // ─── Canciones ───
  Future<SongInfo> searchSong(String query) =>
      throw UnsupportedError('searchSong no soportado');

  Future<List<SongInfo>> searchSongs(String query, {int limit = 50}) =>
      throw UnsupportedError('searchSongs no soportado');

  Future<SongInfo> getSongById(String songId) =>
      throw UnsupportedError('getSongById no soportado');

  Future<List<SongInfo>> getTrackRadio(SongInfo song, {int limit = 30}) =>
      throw UnsupportedError('getTrackRadio no soportado');

  Future<List<SongInfo>> getAlbumRadio(String artistId, {int limit = 25}) =>
      throw UnsupportedError('getAlbumRadio no soportado');

  // ─── Artistas ───
  Future<ArtistInfo> searchArtistWithDetails(String query) =>
      throw UnsupportedError('searchArtistWithDetails no soportado');

  /// Artista por id. Sólo info básica + thumbnail + url.
  Future<ArtistInfo> getArtistById(String artistId) =>
      throw UnsupportedError('getArtistById no soportado');

  /// Top tracks de un artista.
  Future<List<SongInfo>> getArtistTopTracks(String artistId, {int limit = 5}) =>
      throw UnsupportedError('getArtistTopTracks no soportado');

  Future<List<ArtistInfo>> searchAllArtists(String query, {int limit = 10}) =>
      throw UnsupportedError('searchAllArtists no soportado');

  Future<List<SimplifiedArtist>> searchArtists(
    String query, {
    int limit = 10,
  }) => throw UnsupportedError('searchArtists no soportado');

  Future<SimplifiedArtist> searchArtist(String query) =>
      throw UnsupportedError('searchArtist no soportado');

  Future<List<Albumc>> getArtistDiscography(
    String artistId, {
    int concurrency = 8,
    Duration minSpacing = const Duration(milliseconds: 60),
  }) => throw UnsupportedError('getArtistDiscography no soportado');

  Future<List<Albumc>> getArtistCollections(
    String artistId, {
    int albumsLimit = 10,
    int epsLimit = 10,
    int singlesLimit = 10,
    int candidateBuffer = 60,
    int concurrency = 8,
    Duration minSpacing = const Duration(milliseconds: 60),
  }) => throw UnsupportedError('getArtistCollections no soportado');

  Future<List<SimplifiedArtist>> getRelatedArtists(
    String artistId, {
    int limit = 10,
  }) => throw UnsupportedError('getRelatedArtists no soportado');

  // ─── Álbumes ───
  Future<AlbumInfo> getAlbumById(String albumId) =>
      throw UnsupportedError('getAlbumById no soportado');

  Future<Albumc?> getAlbumFromSong(SongInfo song) =>
      throw UnsupportedError('getAlbumFromSong no soportado');

  Future<AlbumInfo?> getFullAlbumFromSong(SongInfo song) =>
      throw UnsupportedError('getFullAlbumFromSong no soportado');

  Future<List<Albumc>> searchAlbums(String query, {int limit = 10}) =>
      throw UnsupportedError('searchAlbums no soportado');

  Future<Albumc> searchAlbum(String query) =>
      throw UnsupportedError('searchAlbum no soportado');

  Future<List<SongInfo>> getArtistDiscographySongs(
    String artistId, {
    int maxItems = 500,
  }) => throw UnsupportedError('getArtistDiscographySongs no soportado');
}
