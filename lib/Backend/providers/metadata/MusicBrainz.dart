// lib/Backend/providers/metadata/musicbrainz.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

class MusicBrainzException implements Exception {
  final String message;
  MusicBrainzException(this.message);
  @override
  String toString() => 'MusicBrainzException: $message';
}

class MusicBrainzClient {
  MusicBrainzClient({required this.userAgent, http.Client? httpClient})
    : _client = httpClient ?? http.Client();

  static const _baseUrl = 'https://musicbrainz.org/ws/2';
  static const _minInterval = Duration(milliseconds: 1100);

  final String userAgent;
  final http.Client _client;

  DateTime? _lastRequestAt;

  Future<void> _waitForSlot() async {
    if (_lastRequestAt != null) {
      final elapsed = DateTime.now().difference(_lastRequestAt!);
      if (elapsed < _minInterval) {
        await Future.delayed(_minInterval - elapsed);
      }
    }
    _lastRequestAt = DateTime.now();
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    await _waitForSlot();
    final uri = Uri.parse('$_baseUrl$path')
        .replace(queryParameters: {...?query, 'fmt': 'json'});

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
      );
    } catch (e) {
      throw MusicBrainzException('Error de red: $e');
    }

    if (response.statusCode == 503) {
      await Future.delayed(const Duration(seconds: 2));
      return _get(path, query: query);
    }

    if (response.statusCode != 200) {
      throw MusicBrainzException(
        'MusicBrainz respondió ${response.statusCode} en $uri',
      );
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw MusicBrainzException('No se pudo parsear la respuesta: $e');
    }
  }

  Future<List<Map<String, dynamic>>> searchArtists(
    String query, {
    int limit = 10,
  }) async {
    final body = await _get(
      '/artist',
      query: {'query': query, 'limit': '$limit'},
    );
    return (body['artists'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> searchRecordings(
    String query, {
    int limit = 10,
  }) async {
    final body = await _get(
      '/recording',
      query: {'query': query, 'limit': '$limit'},
    );
    return (body['recordings'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> searchReleaseGroups(
    String query, {
    int limit = 10,
  }) async {
    final body = await _get(
      '/release-group',
      query: {'query': query, 'limit': '$limit'},
    );
    return (body['release-groups'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getArtist(String mbid) =>
      _get('/artist/$mbid', query: {'inc': 'release-groups'});

  Future<Map<String, dynamic>> getReleaseGroup(String mbid) =>
      _get('/release-group/$mbid', query: {'inc': 'releases artist-credits'});

  Future<Map<String, dynamic>> getRelease(String mbid) => _get(
    '/release/$mbid',
    query: {'inc': 'recordings artist-credits release-groups'},
  );

  Future<Map<String, dynamic>> getRecording(String mbid) => _get(
    '/recording/$mbid',
    query: {'inc': 'artist-credits releases release-groups'},
  );

  Future<List<Map<String, dynamic>>> browseReleaseGroupsByArtist(
    String mbid, {
    int limit = 100,
  }) async {
    final body = await _get(
      '/release-group',
      query: {'artist': mbid, 'limit': '$limit', 'type': 'album|single|ep'},
    );
    return (body['release-groups'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> browseRecordingsByArtist(
    String mbid, {
    int limit = 100,
  }) async {
    final body = await _get(
      '/recording',
      query: {'artist': mbid, 'limit': '$limit'},
    );
    return (body['recordings'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  /// Grabaciones del artista ordenadas por relevancia del índice Lucene.
  Future<List<Map<String, dynamic>>> searchRecordingsByArtist(
    String artistMbid, {
    int limit = 25,
  }) async {
    final body = await _get(
      '/recording',
      query: {'query': 'arid:$artistMbid', 'limit': '$limit'},
    );
    return (body['recordings'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
  }

  void close() => _client.close();
}

/// URL directa a la portada. `size` puede ser 250, 500 o 1200.
String coverArtUrl(String releaseGroupMbid, {int size = 500}) =>
    'https://coverartarchive.org/release-group/$releaseGroupMbid/front-$size';
