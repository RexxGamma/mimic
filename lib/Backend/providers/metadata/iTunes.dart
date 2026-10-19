// lib/Backend/providers/metadata/itunes.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

class iTunesException implements Exception {
  final String message;
  iTunesException(this.message);
  @override
  String toString() => 'iTunesException: $message';
}

// ════════════════════════════════════════════════════════════════════
//  Cliente HTTP
// ════════════════════════════════════════════════════════════════════

class iTunesClient {
  iTunesClient({String country = 'US', http.Client? httpClient})
    : _country = country,
      _client = httpClient ?? http.Client();

  static const _baseUrl = 'https://itunes.apple.com';

  final String _country;
  final http.Client _client;

  // ─── Búsqueda ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> search(
    String term, {
    required String entity, // 'song', 'musicArtist', 'album'
    int limit = 25,
  }) async {
    final uri = Uri.parse('$_baseUrl/search').replace(
      queryParameters: {
        'term': term,
        'media': 'music',
        'entity': entity,
        'limit': '$limit',
        'country': _country,
      },
    );
    return _getList(uri);
  }

  // ─── Lookup por ID ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> lookup(
    String id, {
    String? entity,
    int? limit,
  }) async {
    final params = <String, String>{'id': id, 'country': _country};
    if (entity != null) params['entity'] = entity;
    if (limit != null) params['limit'] = '$limit';

    final uri = Uri.parse('$_baseUrl/lookup').replace(queryParameters: params);
    return _getList(uri);
  }

  // ─── HTTP ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _getList(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'application/json',
        },
      );
    } catch (e) {
      throw iTunesException('Error de red: $e');
    }

    if (response.statusCode != 200) {
      throw iTunesException('iTunes respondió ${response.statusCode} en $uri');
    }

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = body['results'] as List<dynamic>? ?? [];
      return results.cast<Map<String, dynamic>>();
    } catch (e) {
      throw iTunesException('No se pudo parsear la respuesta: $e');
    }
  }

  void close() => _client.close();
}
