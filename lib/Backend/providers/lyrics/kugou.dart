// lib/Backend/providers/lyrics/kugou.dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mimic/Backend/songdata.dart';

import 'lrclib.dart'; // para reutilizar LyricsResult

class KugouLyricsResolver {
  KugouLyricsResolver({http.Client? httpClient})
    : _client = httpClient ?? http.Client();

  final http.Client _client;
  final Map<String, LyricsResult?> _cache = {};

  Future<LyricsResult?> getLyrics(SongInfo song) async {
    if (_cache.containsKey(song.id)) return _cache[song.id];

    try {
      final result = await _fetchLyrics(song);
      _cache[song.id] = result;
      return result;
    } catch (_) {
      _cache[song.id] = null;
      return null;
    }
  }

  Future<LyricsResult?> _fetchLyrics(SongInfo song) async {
    final artistName = song.artists.isNotEmpty ? song.artists.first.name : '';
    final keyword = artistName.isNotEmpty
        ? '$artistName - ${song.name}'
        : song.name;
    final durationMs = song.duration.inMilliseconds;

    // 1. Buscar candidatos de letra
    final searchUri = Uri.https('krcs.kugou.com', '/search', {
      'ver': '1',
      'man': 'no',
      'client': 'pc',
      'keyword': keyword,
      'duration': '$durationMs',
      'hash': '', // Kugou acepta hash vacío para búsqueda por keyword
    });

    final searchRes = await _client.get(searchUri);
    if (searchRes.statusCode != 200) return null;

    final searchJson = jsonDecode(searchRes.body) as Map<String, dynamic>;
    final candidates = searchJson['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;

    // Elegir el candidato con duración más parecida
    candidates.sort((a, b) {
      final da = a['duration'] as int?;
      final db = b['duration'] as int?;
      final diffA = da == null ? 1 << 30 : (da - durationMs).abs();
      final diffB = db == null ? 1 << 30 : (db - durationMs).abs();
      return diffA.compareTo(diffB);
    });

    final best = candidates.first as Map<String, dynamic>;
    final id = best['id']?.toString();
    final accesskey = best['accesskey']?.toString();
    if (id == null || accesskey == null) return null;

    // 2. Descargar la letra en formato LRC
    final downloadUri = Uri.https('lyrics.kugou.com', '/download', {
      'charset': 'utf8',
      'accesskey': accesskey,
      'id': id,
      'client': 'pc',
      'fmt': 'lrc',
      'ver': '1',
    });

    final downloadRes = await _client.get(downloadUri);
    if (downloadRes.statusCode != 200) return null;

    final downloadJson = jsonDecode(downloadRes.body) as Map<String, dynamic>;
    final content = downloadJson['content'] as String?;
    if (content == null) return null;

    // El contenido viene en Base64 → decodificar a texto LRC plano
    final lrcText = utf8.decode(base64Decode(content));

    return LyricsResult(
      plainLyrics: null,
      syncedLyrics: lrcText, // Kugou devuelve LRC con timestamps
      instrumental: false,
    );
  }

  void close() => _client.close();
}
