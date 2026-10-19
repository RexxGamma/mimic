// youtube.dart
//
// Resolver de YouTube vía NewPipeExtractor (MethodChannel).
//
// v5: logs con timestamps para diagnosticar latencia.

import 'dart:async';
import 'dart:io' show HttpClient, HttpHeaders;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mimic/Backend/songdata.dart';

import '../privdersenums.dart';

// ─────────────────────────────────────────────────────────────────────
// Bridge (MethodChannel)
// ─────────────────────────────────────────────────────────────────────

class _YtSearchResult {
  final String url;
  final String title;
  final String uploader;
  final Duration duration;

  _YtSearchResult({
    required this.url,
    required this.title,
    required this.uploader,
    required this.duration,
  });

  factory _YtSearchResult.fromMap(Map<dynamic, dynamic> m) {
    final seconds = (m['durationSeconds'] as num?)?.toInt() ?? 0;
    return _YtSearchResult(
      url: m['url'] as String,
      title: m['title'] as String? ?? '',
      uploader: m['uploader'] as String? ?? '',
      duration: Duration(seconds: seconds),
    );
  }

  @override
  String toString() => '"$title" — $uploader (${duration.inSeconds}s) [$url]';
}

class _YtAudioStream {
  final String url;
  final String mimeType;
  final int bitrate;
  final Map<String, String> headers;

  _YtAudioStream({
    required this.url,
    required this.mimeType,
    required this.bitrate,
    required this.headers,
  });

  factory _YtAudioStream.fromMap(Map<dynamic, dynamic> m) {
    final rawHeaders = m['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (k != null && v != null) headers[k.toString()] = v.toString();
      });
    }
    return _YtAudioStream(
      url: m['url'] as String,
      mimeType: m['mimeType'] as String? ?? '',
      bitrate: (m['bitrate'] as num?)?.toInt() ?? 0,
      headers: headers,
    );
  }

  @override
  String toString() => '$mimeType @ ${bitrate}bps [$url]';
}

class _YoutubeBridge {
  static const _channel = MethodChannel(
    'com.example.somerandommusicapp/youtube',
  );

  Future<List<_YtSearchResult>> search(String query, {int limit = 10}) async {
    final res = await _channel.invokeMethod<List<dynamic>>('search', {
      'query': query,
      'limit': limit,
    });
    if (res == null) return [];
    return res
        .cast<Map<dynamic, dynamic>>()
        .map(_YtSearchResult.fromMap)
        .toList();
  }

  Future<List<_YtAudioStream>> getAudioStreams(String videoUrl) async {
    final res = await _channel.invokeMethod<List<dynamic>>('getAudioStreams', {
      'videoUrl': videoUrl,
    });
    if (res == null) return [];
    return res
        .cast<Map<dynamic, dynamic>>()
        .map(_YtAudioStream.fromMap)
        .toList();
  }
}

final _bridge = _YoutubeBridge();

// Helper de timestamp para diagnóstico.
int _ts() => DateTime.now().millisecondsSinceEpoch;

// ─────────────────────────────────────────────────────────────────────
// Helpers de scoring
// ─────────────────────────────────────────────────────────────────────

String _deLeet(String s) {
  return s
      .replaceAll(r'$', 's')
      .replaceAll('@', 'a')
      .replaceAll('0', 'o')
      .replaceAll('1', 'i')
      .replaceAll('3', 'e')
      .replaceAll('4', 'a')
      .replaceAll('5', 's')
      .replaceAll('7', 't');
}

String _normalizeTitle(String s) {
  var out = _deLeet(s.toLowerCase());
  out = out.replaceAll(
    RegExp(
      r'\s*[\(\[]\s*(?:feat|ft|featuring)\.?\s+[^)\]]*[\)\]]',
      caseSensitive: false,
    ),
    ' ',
  );
  out = out.replaceAll(
    RegExp(r'\s*[-–]\s*(?:feat|ft|featuring)\.?\s+.*$', caseSensitive: false),
    ' ',
  );
  out = out.replaceAll(RegExp(r'[^\w\s]'), ' ');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  return out;
}

String _normalizeKeepFeat(String s) {
  var out = _deLeet(s.toLowerCase());
  out = out.replaceAll(RegExp(r'[^\w\s]'), ' ');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  return out;
}

const Set<String> _titleNoise = {
  'official',
  'audio',
  'music',
  'video',
  'lyric',
  'lyrics',
  'visualizer',
  'original',
  'hq',
  'hd',
  'track',
  'song',
  'album',
  'single',
  'ep',
  'version',
  'mix',
  'main',
  'feat',
  'ft',
  'featuring',
  'with',
  'prod',
  'by',
  'the',
  'and',
};

const List<String> _remixKeywords = [
  'remix',
  'rmx',
  'bootleg',
  'refix',
  'reflip',
  'flip',
  'mashup',
  'rework',
  'vip',
  'edit',
  'redo',
  'sped up',
  'slowed',
  'nightcore',
];

Set<String> _remixKeywordsIn(String s) {
  final lower = s.toLowerCase();
  return _remixKeywords
      .where((k) => RegExp(r'\b' + RegExp.escape(k) + r'\b').hasMatch(lower))
      .toSet();
}

/// Patrones que SIEMPRE rechazan, sin importar qué sea el target.
/// target NO contiene un marcador de live. Igual que los remixes.
final List<RegExp> _livePatterns = [
  RegExp(r'[\(\[]\s*live\b[^\)\]]*[\)\]]', caseSensitive: false),
  RegExp(
    r'\blive\s+(?:at|from|version|performance|recording|session)\b',
    caseSensitive: false,
  ),
  RegExp(
    r'\blive\s*(?:video|audio|concert|set|show|stream)\b',
    caseSensitive: false,
  ),
  RegExp(
    r'\b(?:performing|performed|performance)\s+live\b',
    caseSensitive: false,
  ),
  RegExp(r'\b(?:en\s+vivo|ao\s+vivo|directo)\b', caseSensitive: false),
  RegExp(
    r'\b(?:lollapalooza|coachella|glastonbury|tomorrowland|ultra|edc|bonnaroo|primavera|rock\s+in\s+rio|sziget|exit\s+festival|electric\s+daisy)\b',
    caseSensitive: false,
  ),
];

/// Patrones que SIEMPRE rechazan, sin importar el target. Un cover o
/// un instrumental nunca es la canción pedida.
final List<RegExp> _alwaysRejectPatterns = [
  RegExp(
    r'\b(?:instrumental|karaoke|acapella|a\s?cappella)\b',
    caseSensitive: false,
  ),
  RegExp(r'\bcover\b', caseSensitive: false),
  RegExp(r'\bdemo\b', caseSensitive: false),
];

bool _looksLiveOrCover(String title, SongInfo song) {
  // Cover / instrumental / karaoke → rechazo siempre.
  if (_alwaysRejectPatterns.any((p) => p.hasMatch(title))) return true;

  // Live → rechazo solo si el target NO es live.
  final targetIsLive = _livePatterns.any((p) => p.hasMatch(song.name));
  if (!targetIsLive && _livePatterns.any((p) => p.hasMatch(title))) {
    return true;
  }
  return false;
}

final List<RegExp> _editPatterns = [
  RegExp(
    r'\b(?:remix|rmx|bootleg|refix|reflip|flip|mashup|rework|redo|vip)\b',
    caseSensitive: false,
  ),
  RegExp(
    r'\b(?:extended|radio|club|dub)\s+(?:mix|edit|version)\b',
    caseSensitive: false,
  ),
  RegExp(r'\bremaster(?:ed)?\b', caseSensitive: false),
  RegExp(
    r'\b(?:sped\s?up|speed\s?up|slowed|nightcore|chopped|screwed|pitched|reverb)\b',
    caseSensitive: false,
  ),
  RegExp(r'\b8d\s*audio\b', caseSensitive: false),
  RegExp(r'\bbass\s*boosted\b', caseSensitive: false),
  RegExp(r'\b(?:tiktok|tik\s?tok)\b', caseSensitive: false),
  RegExp(r'\bedit\b', caseSensitive: false),
];

bool _looksLikeEdit(String title) =>
    _editPatterns.any((p) => p.hasMatch(title));

Set<String> _sigTokens(String s) {
  var raw = _deLeet(s.toLowerCase());
  raw = raw.replaceAll(RegExp(r'\b(?:feat|ft|featuring)\.?\s*'), ' ');
  raw = raw.replaceAll(RegExp(r'[^\w\s]'), ' ');
  return raw.split(' ').where((t) => t.length > 2).toSet();
}

int _extraTokenCount(String candidateTitle, SongInfo song) {
  final parts = candidateTitle.split(RegExp(r'\s[-–]\s'));
  final titlePart = parts.length > 1
      ? parts.sublist(1).join(' - ')
      : candidateTitle;

  final titleTokens = _sigTokens(titlePart);

  final allowed = <String>{
    ..._sigTokens(song.name),
    ...song.artists.expand((a) => _sigTokens(a.name)),
    ..._titleNoise,
  };
  return titleTokens.difference(allowed).length;
}

bool _hasUnexpectedFeature(String candidateTitle, SongInfo song) {
  final match = RegExp(
    r'\b(?:feat|ft|featuring)\.?\s+([\w\s]+?)(?:\s*[\)\]\-–]|$)',
    caseSensitive: false,
  ).firstMatch(candidateTitle);
  if (match == null) return false;

  final featured = _normalizeTitle(match.group(1) ?? '');
  if (featured.isEmpty) return false;

  final targetNorm = _normalizeKeepFeat(song.name);
  final featuredTokens = featured
      .split(' ')
      .where((t) => t.length > 2)
      .toList();
  if (featuredTokens.isNotEmpty &&
      featuredTokens.every((t) => targetNorm.contains(t))) {
    return false;
  }

  for (final a in song.artists) {
    final an = _normalizeTitle(a.name);
    if (an.isEmpty) continue;
    if (featured.contains(an) || an.contains(featured)) return false;
  }
  return true;
}

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), '');

bool _namesMatch(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  if (a.contains(b) || b.contains(a)) return true;
  final sa = _squash(a);
  final sb = _squash(b);
  return sa.contains(sb) || sb.contains(sa);
}

bool _uploaderMatchesArtist(_YtSearchResult r, SongInfo song) {
  if (song.artists.isEmpty) return true;
  final uploader = _normalizeTitle(r.uploader);
  for (final a in song.artists) {
    final an = _normalizeTitle(a.name);
    if (an.isEmpty) continue;
    if (_namesMatch(uploader, an)) return true;
  }
  return false;
}

bool _titleMentionsArtist(_YtSearchResult r, SongInfo song) {
  if (song.artists.isEmpty) return true;
  final title = _normalizeTitle(r.title);
  for (final a in song.artists) {
    final an = _normalizeTitle(a.name);
    if (an.isEmpty) continue;
    if (_namesMatch(title, an)) return true;
  }
  return false;
}

int _score(_YtSearchResult r, SongInfo song) {
  final title = _normalizeTitle(r.title);
  final target = _normalizeTitle(song.name);
  final uploader = _normalizeTitle(r.uploader);
  final artists = song.artists.map((a) => _normalizeTitle(a.name)).toList();

  var titlePenalty = 0;
  final wanted = target.split(' ').where((t) => t.length > 1).toSet();
  if (wanted.isNotEmpty) {
    final have = title.split(' ').where((t) => t.length > 1).toSet();
    final matched = wanted.intersection(have).length;
    final coverage = matched / wanted.length;
    titlePenalty = ((1.0 - coverage) * 12000).round();
  }

  final diffMs = (r.duration - song.duration).abs().inMilliseconds;
  final durationPenalty = (diffMs ~/ 100).clamp(0, 4000);

  var score = titlePenalty + durationPenalty;

  if (RegExp(r'\blyric', caseSensitive: false).hasMatch(r.title)) {
    score -= 1000;
  }

  if (artists.any(title.contains)) score -= 500;
  if (artists.any((a) => _namesMatch(uploader, a))) {
    score -= 1500;
  }
  if (title == target) score -= 2000;

  if (_looksLikeEdit(r.title) && _remixKeywordsIn(song.name).isEmpty) {
    score += 5000;
  }

  if (song.artists.isNotEmpty) {
    final matched = artists.any(
      (a) => uploader.contains(a) || a.contains(uploader),
    );
    if (!matched) score += 3000;
  }

  return score;
}

// ─────────────────────────────────────────────────────────────────────
// Tiers
// ─────────────────────────────────────────────────────────────────────

enum _YtTier { official, clean, uncertain, rejected }

const Map<_YtTier, int> _tierRank = {
  _YtTier.official: 0,
  _YtTier.clean: 1,
  _YtTier.uncertain: 2,
  _YtTier.rejected: 99,
};

_YtTier _tier(_YtSearchResult r, SongInfo song) {
  if (_looksLiveOrCover(r.title, song)) return _YtTier.rejected;

  final targetRemixes = _remixKeywordsIn(song.name);
  if (targetRemixes.isEmpty) {
    if (_looksLikeEdit(r.title)) return _YtTier.rejected;
  } else {
    final candidateRemixes = _remixKeywordsIn(r.title);
    if (candidateRemixes.intersection(targetRemixes).isEmpty) {
      return _YtTier.rejected;
    }
  }

  if (r.duration.inSeconds < 30) return _YtTier.rejected;
  final targetMs = song.duration.inMilliseconds;
  if (targetMs > 0) {
    final ratio = r.duration.inMilliseconds / targetMs;
    if (ratio < 0.70 || ratio > 1.40) return _YtTier.rejected;
  }

  final title = _normalizeTitle(r.title);
  final targetTokens = _normalizeTitle(song.name)
      .split(' ')
      .where((t) => t.length > 2)
      .toSet();
  if (targetTokens.isNotEmpty) {
    final matched = targetTokens.where(title.contains).length;
    if (matched / targetTokens.length < 0.5) return _YtTier.rejected;
  }

  final uploaderIsArtist = _uploaderMatchesArtist(r, song);
  final titleHasArtist = _titleMentionsArtist(r, song);
  if (!uploaderIsArtist && !titleHasArtist) {
    return _YtTier.rejected;
  }

  if (_hasUnexpectedFeature(r.title, song)) return _YtTier.uncertain;
  if (_extraTokenCount(r.title, song) >= 3) return _YtTier.uncertain;

  if (uploaderIsArtist) return _YtTier.official;
  return _YtTier.clean;
}

String _warningFor(_YtSearchResult r, SongInfo song, _YtTier tier) {
  switch (tier) {
    case _YtTier.clean:
      final isLyric = r.title.toLowerCase().contains('lyric');
      return isLyric
          ? 'Video con letras (audio probablemente original)'
          : 'Reupload por "${r.uploader}" — no es el canal oficial';
    case _YtTier.uncertain:
      if (_hasUnexpectedFeature(r.title, song)) {
        return 'Versión con artista invitado no listado: ${r.title}';
      }
      if (_extraTokenCount(r.title, song) >= 3) {
        return 'Título con términos extra: ${r.title}';
      }
      return 'Coincidencia débil: ${r.title}';
    case _YtTier.official:
    case _YtTier.rejected:
      return '';
  }
}

// ─────────────────────────────────────────────────────────────────────
// Tipos auxiliares
// ─────────────────────────────────────────────────────────────────────

class ResolvedStream {
  final String url;
  final Map<String, String> headers;
  final bool isLikelyOriginal;
  final String? warning;

  ResolvedStream({
    required this.url,
    this.headers = const {},
    required this.isLikelyOriginal,
    this.warning,
  });
}

class _ScoredCandidate {
  final _YtSearchResult result;
  final _YtTier tier;
  final int score;
  _ScoredCandidate(this.result, this.tier, this.score);
}

class _CandidateAndStream {
  final _ScoredCandidate candidate;
  final _YtAudioStream stream;
  _CandidateAndStream(this.candidate, this.stream);
}

class _SearchCacheEntry {
  final List<_YtSearchResult> results;
  final DateTime at;
  _SearchCacheEntry(this.results, this.at);
  bool get isFresh =>
      DateTime.now().difference(at) < const Duration(minutes: 30);
}

class _CachedResolved {
  final ResolvedStream stream;
  final DateTime fetchedAt;
  _CachedResolved(this.stream, this.fetchedAt);

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) > YoutubeResolver.streamUrlTtl;
}

// ─────────────────────────────────────────────────────────────────────
// Resolver
// ─────────────────────────────────────────────────────────────────────

class YoutubeResolver {
  static const streamUrlTtl = Duration(hours: 4);
  // Primer intento: rápido si BotGuard ya está warm.
  static const _searchTimeoutFast = Duration(seconds: 6);
  // Retry: cubre BotGuard corriendo por primera vez (~10-15s).
  static const _searchTimeoutSlow = Duration(seconds: 20);
  static const _extractTimeout = Duration(seconds: 10);
  static const _probeTimeout = Duration(seconds: 3);
  static const _extractWindow = 2;
  static const _searchLimit = 10;
  static const _searchCacheMax = 64;

  static const bool probeBeforeReturn = false;

  final Map<String, _CachedResolved> _cache = {};
  final Map<String, Future<ResolvedStream?>> _inflight = {};
  final Map<String, _SearchCacheEntry> _searchCache = {};

  Future<ResolvedStream?> resolveStreamInfo(
    SongInfo song, {
    bool forceRefresh = false,
  }) {
    if (forceRefresh) {
      _cache.remove(song.id);
      _inflight.remove(song.id);
    }

    final inFlight = _inflight[song.id];
    if (inFlight != null) return inFlight;

    final cached = _cache[song.id];
    if (cached != null && !cached.isExpired) {
      return Future.value(cached.stream);
    }

    final future = _resolveImpl(song);
    _inflight[song.id] = future;
    future.whenComplete(() => _inflight.remove(song.id));
    return future;
  }

  Future<String?> resolveStreamUrl(
    SongInfo song, {
    bool forceRefresh = false,
  }) async {
    final info = await resolveStreamInfo(song, forceRefresh: forceRefresh);
    return info?.url;
  }

  Future<SongInfo> withStreamingUrl(SongInfo song) async {
    final url = await resolveStreamUrl(song);
    return SongInfo(
      id: song.id,
      name: song.name,
      artists: song.artists,
      thumbnails: song.thumbnails,
      duration: song.duration,
      album: song.album,
      streamingurl: url,
      source: song.source,
      streamingSource: StreamingProvider.youtube,
    );
  }

  Future<List<SongInfo>> resolveAll(
    List<SongInfo> songs, {
    int concurrency = 6,
  }) async {
    final out = <SongInfo>[];
    for (var i = 0; i < songs.length; i += concurrency) {
      final batch = songs.skip(i).take(concurrency);
      final resolved = await Future.wait(batch.map(withStreamingUrl));
      out.addAll(resolved);
    }
    return out;
  }

  void preload(Iterable<SongInfo> songs) {
    for (final s in songs) {
      // ignore: discarded_futures
      resolveStreamInfo(s);
    }
  }

  void close() {
    _cache.clear();
    _inflight.clear();
    _searchCache.clear();
  }

  // ── Implementación ────────────────────────────────────────────────

  List<String> _buildQueries(SongInfo song) {
    final artistName = song.artists.isNotEmpty ? song.artists.first.name : '';
    // Una sola query: la segunda añadía ~400 ms y casi nunca cambiaba
    // el resultado.
    if (artistName.isNotEmpty) return ['$artistName ${song.name}'];
    return ['${song.name} official audio'];
  }

  Future<ResolvedStream?> _resolveImpl(SongInfo song) async {
    final t0 = _ts();
    final queries = _buildQueries(song);
    if (queries.isEmpty) return null;

    var primaryResults = await _searchOne(queries.first);
    debugPrint(
      'YT: [${_ts() - t0}ms] search primaria "${queries.first}" '
      '(${primaryResults.length} resultados)',
    );

    // Fallback: si la primaria devolvió vacío, probar variantes.
    if (primaryResults.isEmpty) {
      final fallbacks = <String>[
        song.name, // sin artista
        '${song.name} official audio', // variante oficial
        if (song.artists.isNotEmpty)
          '${song.name} ${song.artists.first.name} audio', // invertido
      ].where((q) => q.trim().isNotEmpty && q != queries.first).toList();

      for (final fb in fallbacks) {
        debugPrint('YT: [${_ts() - t0}ms] fallback "$fb"');
        primaryResults = await _searchOne(fb);
        if (primaryResults.isNotEmpty) {
          debugPrint(
            'YT: [${_ts() - t0}ms] fallback "${fb}" OK '
            '(${primaryResults.length} resultados)',
          );
          break;
        }
      }
    }

    if (primaryResults.isEmpty) {
      debugPrint('YT: [${_ts() - t0}ms] sin resultados (con fallback)');
      return null;
    }

    final primaryScored = _scorePool(primaryResults, song);
    Future<_CandidateAndStream?>? primaryExtraction;
    if (primaryScored.isNotEmpty) {
      primaryExtraction = _extractFirstWorking(primaryScored);
    }

    final otherQueries = queries.skip(1);
    final otherResultsFuture = otherQueries.isEmpty
        ? Future.value(<_YtSearchResult>[])
        : Future.wait(otherQueries.map(_searchOne))
              .then((batches) => batches.expand((b) => b).toList());

    if (primaryExtraction != null) {
      final primaryPicked = await primaryExtraction;
      debugPrint('YT: [${_ts() - t0}ms] extracción primaria');

      if (primaryPicked != null &&
          primaryPicked.candidate.tier == _YtTier.official) {
        debugPrint(
          'YT: [${_ts() - t0}ms] FAST PATH [official] — '
          '"${primaryPicked.candidate.result.title}"',
        );
        return _finish(song, primaryPicked);
      }

      final otherResults = await otherResultsFuture;
      debugPrint('YT: [${_ts() - t0}ms] queries secundarias');

      final merged = <_YtSearchResult>[...primaryResults, ...otherResults];
      final seen = <String>{};
      final deduped = <_YtSearchResult>[];
      for (final r in merged) {
        if (seen.add(r.url)) deduped.add(r);
      }

      final scored = _scorePool(deduped, song);
      if (scored.isEmpty) {
        if (primaryPicked != null) {
          return _finish(song, primaryPicked);
        }
        debugPrint('YT: [${_ts() - t0}ms] sin candidatos');
        return null;
      }

      if (primaryPicked != null &&
          scored.first.result.url == primaryPicked.candidate.result.url) {
        debugPrint('YT: [${_ts() - t0}ms] reusando primaria');
        return _finish(song, primaryPicked);
      }

      final better = await _extractFirstWorking(scored);
      final picked = better ?? primaryPicked;
      if (picked == null) {
        debugPrint('YT: [${_ts() - t0}ms] todos fallaron');
        return null;
      }
      debugPrint('YT: [${_ts() - t0}ms] extracción mejorada');
      return _finish(song, picked);
    }

    final otherResults = await otherResultsFuture;
    final scored = _scorePool(otherResults, song);
    if (scored.isEmpty) {
      debugPrint('YT: [${_ts() - t0}ms] sin resultados');
      return null;
    }
    final picked = await _extractFirstWorking(scored);
    if (picked == null) return null;
    debugPrint('YT: [${_ts() - t0}ms] extracción fallback');
    return _finish(song, picked);
  }

  List<_ScoredCandidate> _scorePool(List<_YtSearchResult> pool, SongInfo song) {
    final scored = <_ScoredCandidate>[];
    final rejected = <String>[];

    for (final r in pool) {
      final t = _tier(r, song);
      if (t == _YtTier.rejected) {
        rejected.add('"${r.title}" — ${r.uploader} (${r.duration.inSeconds}s)');
        continue;
      }
      scored.add(_ScoredCandidate(r, t, _score(r, song)));
    }

    if (scored.isEmpty && rejected.isNotEmpty) {
      debugPrint('YT: pool vacío — rechazados:');
      for (final r in rejected.take(5)) {
        debugPrint('YT:   $r');
      }
    }

    scored.sort((a, b) {
      final ta = _tierRank[a.tier]!;
      final tb = _tierRank[b.tier]!;
      if (ta != tb) return ta.compareTo(tb);
      return a.score.compareTo(b.score);
    });
    return scored;
  }

  ResolvedStream _finish(SongInfo song, _CandidateAndStream picked) {
    final isOriginal = picked.candidate.tier == _YtTier.official;
    final warning = isOriginal
        ? null
        : _warningFor(picked.candidate.result, song, picked.candidate.tier);

    debugPrint(
      'YoutubeResolver: elegido [${picked.candidate.tier.name}] '
      '"${picked.candidate.result.title}" '
      '(headers=${picked.stream.headers.keys.join(",")})',
    );

    final resolved = ResolvedStream(
      url: picked.stream.url,
      headers: picked.stream.headers,
      isLikelyOriginal: isOriginal,
      warning: warning,
    );
    _cache[song.id] = _CachedResolved(resolved, DateTime.now());
    return resolved;
  }

  bool _ytWarmedUp = false;

  Future<List<_YtSearchResult>> _searchOne(String q) async {
    final cached = _searchCache[q];
    if (cached != null && cached.isFresh) return cached.results;

    // Intento 1: timeout agresivo.
    try {
      final results = await _bridge
          .search(q, limit: _searchLimit)
          .timeout(_searchTimeoutFast);
      _ytWarmedUp = true;
      _searchCache[q] = _SearchCacheEntry(results, DateTime.now());
      _pruneSearchCache();
      return results;
    } on TimeoutException {
      debugPrint(
        'YoutubeResolver: timeout rápido "${q}" — reintentando con 20s',
      );
    } catch (e) {
      debugPrint('YoutubeResolver: error búsqueda "$q": $e');
      return const [];
    }

    // Intento 2: timeout largo (cubre BotGuard frío).
    try {
      final results = await _bridge
          .search(q, limit: _searchLimit)
          .timeout(_searchTimeoutSlow);
      _ytWarmedUp = true;
      _searchCache[q] = _SearchCacheEntry(results, DateTime.now());
      _pruneSearchCache();
      return results;
    } on TimeoutException {
      debugPrint('YoutubeResolver: timeout 20s agotado "${q}"');
      return const [];
    } catch (e) {
      debugPrint('YoutubeResolver: error búsqueda (retry) "$q": $e');
      return const [];
    }
  }

  void _pruneSearchCache() {
    if (_searchCache.length <= _searchCacheMax) return;
    final entries = _searchCache.entries.toList()
      ..sort((a, b) => a.value.at.compareTo(b.value.at));
    final excess = _searchCache.length - _searchCacheMax ~/ 2;
    for (var i = 0; i < excess; i++) {
      _searchCache.remove(entries[i].key);
    }
  }

  Future<_CandidateAndStream?> _extractFirstWorking(
    List<_ScoredCandidate> candidates,
  ) async {
    for (var i = 0; i < candidates.length; i += _extractWindow) {
      final batch = candidates.skip(i).take(_extractWindow).toList();
      final results = await Future.wait(
        batch.map((c) async {
          final stream = await _pickAudioStream(c.result.url);
          return stream == null ? null : _CandidateAndStream(c, stream);
        }),
      );
      for (final r in results) {
        if (r != null) return r;
      }
    }
    return null;
  }

  Future<_YtAudioStream?> _pickAudioStream(String videoUrl) async {
    List<_YtAudioStream> streams;
    try {
      streams = await _bridge
          .getAudioStreams(videoUrl)
          .timeout(_extractTimeout);
    } on TimeoutException {
      debugPrint('YoutubeResolver: timeout extrayendo $videoUrl');
      return null;
    } on PlatformException catch (e) {
      debugPrint(
        'YoutubeResolver: PlatformException $videoUrl: '
        '${e.code} — ${e.message}',
      );
      return null;
    } catch (e) {
      debugPrint('YoutubeResolver: error inesperado extrayendo $videoUrl: $e');
      return null;
    }

    if (streams.isEmpty) return null;

    final m4a = streams
        .where((s) => s.mimeType.contains('mp4') || s.mimeType.contains('m4a'))
        .toList();
    final pool = m4a.isNotEmpty ? m4a : streams;
    pool.sort((a, b) => b.bitrate.compareTo(a.bitrate));

    for (final s in pool) {
      if (!_looksPlayableUrl(s.url)) continue;
      if (probeBeforeReturn) {
        final ok = await _probeUrl(s.url, s.headers);
        if (!ok) {
          debugPrint('YoutubeResolver: probe 403 en ${s.url} — probando otro');
          continue;
        }
      }
      return s;
    }
    return null;
  }

  static bool _looksPlayableUrl(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) return false;
      if (uri.scheme == 'https') return true;
      if (uri.scheme == 'http' && uri.host == '127.0.0.1') return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _probeUrl(String url, Map<String, String> headers) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _probeTimeout;
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final resp = await req.close().timeout(_probeTimeout);
      final code = resp.statusCode;
      await resp.drain<void>();
      return code == 200 || code == 206;
    } catch (e) {
      debugPrint('YoutubeResolver: probe fallo en $url: $e');
      return false;
    } finally {
      client?.close(force: true);
    }
  }
}

final youtubeApi = YoutubeResolver();
