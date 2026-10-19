// lib/Backend/Providers/deezer_provider.dart
import 'package:mimic/Backend/songdata.dart';
import 'deezercallback.dart' as cb;
import '../musicprovider.dart';

class DeezerProvider extends MusicProvider {
  const DeezerProvider();

  // ─── Canciones ───
  @override
  Future<SongInfo> searchSong(String query) => cb.deezer.search(query);

  @override
  Future<List<SongInfo>> searchSongs(String query, {int limit = 10}) =>
      cb.deezer.searchAll(query, limit: limit, fullArtists: true);

  @override
  Future<SongInfo> getSongById(String songId) => cb.getSongById(songId);

  @override
  Future<List<SongInfo>> getTrackRadio(SongInfo song, {int limit = 25}) =>
      cb.getTrackRadio(song, limit: limit);

  @override
  Future<List<SongInfo>> getAlbumRadio(String artistId, {int limit = 25}) =>
      cb.getAlbumRadio(artistId, limit: limit);

  // ─── Artistas ───
  @override
  Future<ArtistInfo> searchArtistWithDetails(String query) =>
      cb.searchArtistWithDetails(query);

  @override
  Future<ArtistInfo> getArtistById(String artistId) =>
      cb.deezerArtist.getById(artistId);

  @override
  Future<List<SongInfo>> getArtistTopTracks(String artistId,
          {int limit = 5}) =>
      cb.deezerArtist.topTracks(artistId, cb.deezer.fromJson, limit: limit);

  @override
  Future<List<ArtistInfo>> searchAllArtists(String query, {int limit = 10}) =>
      cb.searchAllArtists(query, limit: limit);

  @override
  Future<List<SimplifiedArtist>> searchArtists(String query,
          {int limit = 10}) =>
      cb.searchArtists(query, limit: limit);

  @override
  Future<SimplifiedArtist> searchArtist(String query) =>
      cb.searchArtist(query);

  @override
  Future<List<Albumc>> getArtistDiscography(
    String artistId, {
    int concurrency = 8,
    Duration minSpacing = const Duration(milliseconds: 60),
  }) =>
      cb.getArtistDiscography(
        artistId,
        concurrency: concurrency,
        minSpacing: minSpacing,
      );

  @override
  Future<List<Albumc>> getArtistCollections(
    String artistId, {
    int albumsLimit = 10,
    int epsLimit = 10,
    int singlesLimit = 10,
    int candidateBuffer = 60,
    int concurrency = 8,
    Duration minSpacing = const Duration(milliseconds: 60),
  }) =>
      cb.getArtistCollections(
        artistId,
        albumsLimit: albumsLimit,
        epsLimit: epsLimit,
        singlesLimit: singlesLimit,
        candidateBuffer: candidateBuffer,
        concurrency: concurrency,
        minSpacing: minSpacing,
      );

  @override
  Future<List<SimplifiedArtist>> getRelatedArtists(String artistId,
          {int limit = 10}) =>
      cb.getRelatedArtists(artistId, limit: limit);

  // ─── Álbumes ───
  @override
  Future<AlbumInfo> getAlbumById(String albumId) =>
      cb.getAlbumById(albumId);

  @override
  Future<Albumc?> getAlbumFromSong(SongInfo song) =>
      cb.getAlbumFromSong(song);

  @override
  Future<AlbumInfo?> getFullAlbumFromSong(SongInfo song) =>
      cb.getFullAlbumFromSong(song);

  @override
  Future<List<Albumc>> searchAlbums(String query, {int limit = 10}) =>
      cb.searchAlbums(query, limit: limit);

  @override
  Future<Albumc> searchAlbum(String query) => cb.searchAlbum(query);

  

  @override
Future<List<SongInfo>> getArtistDiscographySongs(
  String artistId, {
  int maxItems = 100,
}) async {
  // 1) Intento normal: /artist/{id}/top
  final top = await cb.deezerArtist.topTracksEnriched(
  artistId,
  cb.deezer,
  limit: maxItems.clamp(1, 100),
);
  if (top.isNotEmpty) return top;

  // 2) Fallback: buscar por nombre y filtrar por artistId.
  final artist = await cb.deezerArtist.getById(artistId);
  return cb.deezer.topTracksByArtistId(
    artistId,
    artist.name,
    limit: maxItems.clamp(1, 100),
  );
}
}