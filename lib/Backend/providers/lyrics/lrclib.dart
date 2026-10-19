// lrclib.dart
//
// Busca lyrics (planas y sincronizadas) en LRCLIB a partir de un SongInfo.
// Gratis, sin API key — pero LRCLIB pide identificar tu app con un header
// User-Agent (nombre, versión, link al proyecto o email). Cámbialo por el
// tuyo real antes de usar esto en producción.
//
// Flujo:
//   SongInfo (de Deezer)
//        ↓ 1. intento exacto: /api/get (track + artist + duración)
//        ↓ 2. si no hay match exacto: /api/search (difuso) + se elige
//             el resultado con duración más parecida
//   LyricsResult (plainLyrics / syncedLyrics / instrumental)

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mimic/Backend/songdata.dart';

class LrcLibException implements Exception {
  final String message;
  LrcLibException(this.message);

  @override
  String toString() => 'LrcLibException: $message';
}

class LyricsResult {
  final String? plainLyrics;
  final String? syncedLyrics; // formato LRC: "[00:17.12] línea..."
  final bool instrumental;

  LyricsResult({
    required this.plainLyrics,
    required this.syncedLyrics,
    required this.instrumental,
  });

  /// true si hay algo que mostrar (la canción no es instrumental y trae
  /// al menos un tipo de letra).
  bool get hasLyrics =>
      !instrumental && (plainLyrics != null || syncedLyrics != null);

  factory LyricsResult.fromJson(Map<String, dynamic> json) => LyricsResult(
    plainLyrics: json['plainLyrics'] as String?,
    syncedLyrics: json['syncedLyrics'] as String?,
    instrumental: json['instrumental'] as bool? ?? false,
  );
}

class LrcLibResolver {
  LrcLibResolver({http.Client? httpClient})
    : _client = httpClient ?? http.Client();

  final http.Client _client;
  static const _baseUrl = 'https://lrclib.net/api';

  // LRCLIB pide identificar el cliente. Cambia esto por el nombre real de
  // tu app y un link a tu repo/página.
  static const _userAgent =
      'somerandommusicapp/1.0 (https://github.com/tu-usuario/tu-repo)';

  final Map<String, LyricsResult?> _cache = {};

  String? _albumTitle(SongInfo song) {
    final album = song.album;
    if (album is Map) return album['title'] as String?;
    if (album is String) return album;
    return null;
  }

  /// Busca las lyrics de una canción. Devuelve `null` si no se encontró
  /// nada (no lanza excepción en ese caso — solo si falla la red).
  Future<LyricsResult?> getLyrics(SongInfo song) async {
    if (_cache.containsKey(song.id)) return _cache[song.id];

    final artistName = song.artists.isNotEmpty ? song.artists.first.name : '';
    final albumName = _albumTitle(song);
    final durationSeconds = song.duration.inSeconds;

    // 1. Intento exacto.
    try {
      final exact = await _getExact(
        trackName: song.name,
        artistName: artistName,
        albumName: albumName,
        durationSeconds: durationSeconds,
      );
      final result = LyricsResult.fromJson(exact);
      _cache[song.id] = result;
      return result;
    } catch (_) {
      // Sin match exacto — se sigue con búsqueda difusa.
    }

    // 2. Fallback: búsqueda difusa, eligiendo el resultado con duración
    // más parecida a la de Deezer.
    List<Map<String, dynamic>> candidates;
    try {
      candidates = await _search(trackName: song.name, artistName: artistName);
    } catch (_) {
      candidates = [];
    }

    if (candidates.isEmpty) {
      _cache[song.id] = null;
      return null;
    }

    candidates.sort((a, b) {
      final da = a['duration'] as int?;
      final db = b['duration'] as int?;
      final diffA = da == null ? 1 << 30 : (da - durationSeconds).abs();
      final diffB = db == null ? 1 << 30 : (db - durationSeconds).abs();
      return diffA.compareTo(diffB);
    });

    final result = LyricsResult.fromJson(candidates.first);
    _cache[song.id] = result;
    return result;
  }

  Future<Map<String, dynamic>> _getExact({
    required String trackName,
    required String artistName,
    String? albumName,
    required int durationSeconds,
  }) async {
    final url = Uri.parse('$_baseUrl/get').replace(
      queryParameters: {
        'track_name': trackName,
        'artist_name': artistName,
        if (albumName != null && albumName.isNotEmpty)
          'album_name': albumName,
        'duration': '$durationSeconds',
      },
    );

    final http.Response res;
    try {
      res = await _client.get(url, headers: {'User-Agent': _userAgent});
    } catch (e) {
      throw LrcLibException('Error de red al consultar LRCLIB: $e');
    }

    if (res.statusCode == 404) {
      throw LrcLibException('No hay match exacto en LRCLIB');
    }
    if (res.statusCode != 200) {
      throw LrcLibException('LRCLIB respondió ${res.statusCode}');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> _search({
    required String trackName,
    required String artistName,
  }) async {
    final url = Uri.parse('$_baseUrl/search').replace(
      queryParameters: {
        'track_name': trackName,
        if (artistName.isNotEmpty) 'artist_name': artistName,
      },
    );

    final http.Response res;
    try {
      res = await _client.get(url, headers: {'User-Agent': _userAgent});
    } catch (e) {
      throw LrcLibException('Error de red al consultar LRCLIB: $e');
    }

    if (res.statusCode != 200) {
      throw LrcLibException('LRCLIB respondió ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  void close() => _client.close();
}

final lrcLibApi = LrcLibResolver();