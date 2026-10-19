// soundcloud.dart
//
// Resuelve audio de SoundCloud con la MISMA interfaz que youtube.dart, para
// que StreamingManager pueda llamar a soundcloudApi.resolveStreamUrl(song)
// exactamente igual que hace con youtubeApi.
//
// SoundCloud no tiene alta pública de API key desde hace años. La técnica
// que usa toda la comunidad no oficial es extraer un client_id embebido en
// el propio bundle JS de soundcloud.com. Es no oficial y se puede romper si
// SoundCloud cambia su frontend.
//
// SOBRE "progressive" vs "hls":
//   - progressive -> un único archivo .mp3 por HTTP GET. Reproducible en
//                    cualquier target, se puede descargar y hacer seek.
//   - hls         -> playlist .m3u8 (AAC, mejor bitrate). just_audio no la
//                    reproduce de forma confiable en todos los targets, y no
//                    se puede descargar como un archivo normal.
//
// Flujo:
//   SongInfo -> búsqueda (varias queries de respaldo) -> filtro por niveles
//   (estricto, luego relajado) -> ranking -> pedir URL firmada de cada
//   transcoding hasta que uno funcione.
//
// QUÉ SE CORRIGIÓ respecto a la versión anterior (causas de los null):
//   1. client_id cacheado para siempre: si caducaba, todo fallaba hasta
//      reiniciar la app. Ahora se detecta 401/403 y se renueva solo.
//   2. Varias llamadas simultáneas (preload) pedían el client_id en
//      paralelo y se pisaban. Ahora comparten un solo Future.
//   3. Sin User-Agent ni timeout: soundcloud.com a veces responde distinto
//      (o cuelga) al UA por defecto de Dart.
//   4. El filtro duro era demasiado agresivo y solo miraba 8 resultados.
//      Ahora hay nivel estricto + relajado, 20 candidatos y queries de
//      respaldo (sin "feat.", sin sufijo "Remastered", solo título).
//   5. _normalizeTitle usaba \w (solo ASCII): "Beyoncé", "Canción", títulos
//      en japonés/cirílico quedaban mutilados o vacíos. Ahora es unicode.
//   6. Bug: uploader vacío -> `a.contains('')` era true y daba bonus falso.
//   7. Se probaba UN solo transcoding. Ahora se prueban todos en orden, se
//      ignoran los `snipped` (previews) y los HLS en opus (ilegibles para
//      just_audio) quedan al final.
//   8. _preferHls estaba en true aunque el comentario decía false.
//      Ahora es por defecto false (progressive primero).
//   9. Se descartaban policy=BLOCK / streamable=false solo de casualidad.
//  10. Resoluciones duplicadas (preload + play del mismo tema) ahora se
//      unifican, y preload ya no dispara todo de golpe (evita 429).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mimic/Backend/songdata.dart';

import '../privdersenums.dart';

class SoundcloudException implements Exception {
  final String message;
  SoundcloudException(this.message);

  @override
  String toString() => 'SoundcloudException: $message';
}

class _CachedUrl {
  final String url;
  final DateTime fetchedAt;
  _CachedUrl(this.url, this.fetchedAt);

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) > SoundcloudResolver.streamUrlTtl;
}

class _Scored {
  final Map<String, dynamic> track;
  final int score;
  final int extras;
  _Scored(this.track, this.score, this.extras);
}

class _QueryPlan {
  final String query;

  /// Las queries de respaldo (más sueltas) exigen que el artista aparezca
  /// en el título o en el uploader, para no devolver otra canción con el
  /// mismo nombre.
  final bool requireArtist;
  _QueryPlan(this.query, {this.requireArtist = false});
}

class SoundcloudResolver {
  SoundcloudResolver({http.Client? httpClient})
    : _client = httpClient ?? http.Client();

  final http.Client _client;

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const _headers = {
    'User-Agent': _userAgent,
    'Accept-Language': 'en-US,en;q=0.9',
  };
  static const _requestTimeout = Duration(seconds: 12);

  /// Cuánto se reutiliza una URL ya resuelta. Las URLs firmadas caducan;
  /// 1 hora es un margen conservador. Si el player falla con una URL
  /// cacheada, llamá a [invalidate] y volvé a resolver.
  static const streamUrlTtl = Duration(hours: 1);

  /// `false` (por defecto): progressive/MP3 primero, funciona en todos los
  /// targets y se puede descargar. `true`: HLS-AAC primero (mejor calidad,
  /// pero solo si el backend de audio lo soporta).
  static const bool _preferHls = false;

  String? _clientId;
  Future<String>? _clientIdFuture;
  final Map<String, _CachedUrl> _urlCache = {};
  final Map<String, Future<String?>> _inflight = {};

  // ---------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------

  Future<http.Response> _get(Uri uri) =>
      _client.get(uri, headers: _headers).timeout(_requestTimeout);

  /// GET a api-v2 agregando el client_id. Si responde 401/403 (client_id
  /// vencido) lo renueva y reintenta; si responde 429/5xx o falla la red,
  /// reintenta una vez tras una pausa corta.
  Future<http.Response?> _apiGet(Uri base, Map<String, String> params) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final id = await _getClientId();
      try {
        final res = await _get(
          base.replace(
            queryParameters: {
              ...base.queryParameters,
              ...params,
              'client_id': id,
            },
          ),
        );

        final code = res.statusCode;
        if (attempt == 0) {
          if (code == 401 || code == 403) {
            debugPrint('SoundcloudResolver: $code -> renovando client_id');
            await _refreshClientId(id);
            continue;
          }
          if (code == 429 || code >= 500) {
            await Future.delayed(const Duration(milliseconds: 700));
            continue;
          }
        }
        return res;
      } catch (e) {
        debugPrint('SoundcloudResolver: error de red en ${base.path}: $e');
        if (attempt == 1) return null;
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // client_id
  // ---------------------------------------------------------------------

  Future<String> _getClientId() {
    final cached = _clientId;
    if (cached != null) return Future.value(cached);

    // Todas las llamadas simultáneas comparten el mismo Future.
    return _clientIdFuture ??= _fetchClientId()
        .then((id) {
          _clientId = id;
          return id;
        })
        .whenComplete(() {
          _clientIdFuture = null;
        });
  }

  /// Invalida el client_id [stale] solo si nadie lo renovó ya.
  Future<String> _refreshClientId(String stale) {
    if (_clientId != null && _clientId != stale) {
      return Future.value(_clientId!);
    }
    _clientId = null;
    return _getClientId();
  }

  Future<String> _fetchClientId() async {
    final homeRes = await _get(Uri.parse('https://soundcloud.com'));
    if (homeRes.statusCode != 200) {
      throw SoundcloudException(
        'No se pudo cargar soundcloud.com (${homeRes.statusCode})',
      );
    }

    final scriptUrls = RegExp(r'<script[^>]+src="([^"]+)"')
        .allMatches(homeRes.body)
        .map((m) => m.group(1)!)
        .where((url) => url.contains('sndcdn.com'))
        .toSet()
        .toList();

    debugPrint(
      'SoundcloudResolver: ${scriptUrls.length} scripts sndcdn.com encontrados',
    );

    final idRegex = RegExp(
      r'client_id\s*[:=]\s*["\x27]([a-zA-Z0-9]{20,40})["\x27]',
    );

    // De más nuevo a más viejo: el client_id suele estar en los últimos.
    for (final scriptUrl in scriptUrls.reversed) {
      try {
        final scriptRes = await _get(Uri.parse(scriptUrl));
        if (scriptRes.statusCode != 200) continue;
        final match = idRegex.firstMatch(scriptRes.body);
        if (match != null) {
          debugPrint('SoundcloudResolver: client_id obtenido');
          return match.group(1)!;
        }
      } catch (e) {
        debugPrint('SoundcloudResolver: error pidiendo script: $e');
      }
    }

    throw SoundcloudException(
      'No se pudo extraer un client_id de SoundCloud — es posible que hayan '
      'cambiado la estructura de su frontend.',
    );
  }

  // ---------------------------------------------------------------------
  // Normalización y heurísticas de título
  // ---------------------------------------------------------------------

  static const _titleNoise = {
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
    'remaster',
    'remastered',
  };

  /// Minúsculas, sin cláusulas "(feat. X)" / "- ft. X", sin puntuación
  /// (conservando letras/números de cualquier idioma), espacios colapsados.
  String _normalizeTitle(String s) {
    var out = s
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .toLowerCase();
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
    out = out.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  /// Título apto para buscar: sin "(feat. X)" y sin sufijos tipo
  /// "- 2011 Remaster" que casi nunca están en el título de SoundCloud.
  String _searchTitle(String name) {
    var out = name;
    out = out.replaceAll(
      RegExp(
        r'\s*[\(\[]\s*(?:feat|ft|featuring)\.?\s+[^)\]]*[\)\]]',
        caseSensitive: false,
      ),
      '',
    );
    out = out.replaceAll(
      RegExp(r'\s*[-–]\s*(?:feat|ft|featuring)\.?\s+.*$', caseSensitive: false),
      '',
    );
    out = out.replaceAll(
      RegExp(
        r'\s*[-–]\s*(?:\d{4}\s*)?(?:remaster(?:ed)?|single version|mono|stereo|deluxe|bonus).*$',
        caseSensitive: false,
      ),
      '',
    );
    return out.trim();
  }

  /// Cuántos tokens del título candidato NO provienen ni del nombre
  /// buscado, ni de los artistas, ni del whitelist de ruido, ni son solo
  /// números (años). Un original da 0–1; un remix típicamente 2 o más.
  int _extraTokenCount(String candidateTitle, SongInfo song) {
    final onlyDigits = RegExp(r'^\d+$');
    Set<String> significant(String s) =>
        _normalizeTitle(s)
            .split(' ')
            .where((t) => t.length > 2 && !onlyDigits.hasMatch(t))
            .toSet();

    final allowed = <String>{
      ...significant(song.name),
      ...song.artists.expand((a) => significant(a.name)),
      ..._titleNoise,
    };

    return significant(candidateTitle).difference(allowed).length;
  }

  /// Patrones de versión NO original. Se evalúan contra el título CRUDO.
  static final List<RegExp> _editPatterns = [
    RegExp(
      r'\b(?:remix|rmx|bootleg|refix|reflip|flip|mashup|rework|redo|vip)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:extended|radio|club|instrumental|dub)\s+(?:mix|edit|version)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:instrumental|karaoke|acapella|a\s?cappella)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:sped\s?up|speed\s?up|slowed|nightcore|chopped|screwed|pitched|reverb)\b',
      caseSensitive: false,
    ),
    RegExp(r'\b8d\s*audio\b', caseSensitive: false),
    RegExp(r'\bbass\s*boosted\b', caseSensitive: false),
    RegExp(r'\b(?:tiktok|tik\s?tok)\b', caseSensitive: false),
    RegExp(r'\bcover\b', caseSensitive: false),
    RegExp(r'\blive\s+(?:at|from|version)\b', caseSensitive: false),
    RegExp(r'\(\s*live\s*\)', caseSensitive: false),
    RegExp(r'\bdemo\b', caseSensitive: false),
    RegExp(r'\bedit\b', caseSensitive: false),
  ];

  static final RegExp _remasterPattern = RegExp(
    r'\bremaster(?:ed)?\b',
    caseSensitive: false,
  );

  /// Es edit/remix SOLO si el patrón aparece en el candidato y NO en el
  /// nombre de la canción pedida. Así, si pedís "X (Live)" o "X - Remix",
  /// los candidatos con esa palabra no se descartan.
  bool _looksLikeEdit(String candidateTitle, SongInfo song) {
    for (final p in _editPatterns) {
      if (p.hasMatch(candidateTitle) && !p.hasMatch(song.name)) return true;
    }
    return false;
  }

  String _uploaderOf(Map<String, dynamic> track) => _normalizeTitle(
    (track['user'] as Map<String, dynamic>?)?['username'] as String? ?? '',
  );

  bool _artistMatches(Map<String, dynamic> track, SongInfo song) {
    final title = _normalizeTitle(track['title'] as String? ?? '');
    final uploader = _uploaderOf(track);
    for (final a in song.artists) {
      final name = _normalizeTitle(a.name);
      if (name.isEmpty) continue;
      if (title.contains(name)) return true;
      if (uploader.isNotEmpty &&
          (uploader.contains(name) || name.contains(uploader))) {
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------
  // Filtros y ranking
  // ---------------------------------------------------------------------

  /// Sirve para streaming completo: no es preview (SNIP), no está
  /// bloqueado por región (BLOCK) y es streameable.
  bool _isPlayable(Map<String, dynamic> t) {
    final policy = (t['policy'] as String? ?? '').toUpperCase();
    if (policy == 'SNIP' || policy == 'BLOCK') return false;
    if (t['streamable'] == false) return false;
    return true;
  }

  /// Deezer a veces entrega la duración del PREVIEW (30 s) en vez de la del
  /// tema. Si es ≤ 35 s la tratamos como desconocida.
  bool _hasReliableDuration(SongInfo song) =>
      song.duration.inMilliseconds > 35000;

  bool _durationOk(Map<String, dynamic> t, SongInfo song, bool relaxed) {
    final d = t['duration'];
    if (d is! int) return true; // sin dato: no descartamos
    if (d < 60000) return false; // cualquier cosa < 60s es un preview
    if (!_hasReliableDuration(song)) {
      // Duración objetivo desconocida: solo descartamos mixes/sets largos.
      return d <= (relaxed ? 20 : 12) * 60000;
    }
    final target = song.duration.inMilliseconds;
    final ratio = d / target;
    final lo = relaxed ? 0.6 : 0.75;
    final hi = relaxed ? 1.8 : 1.35;
    return ratio >= lo && ratio <= hi;
  }

  /// Puntaje: **menor es mejor**.
  int _score(Map<String, dynamic> track, SongInfo song) {
    final rawTitle = track['title'] as String? ?? '';
    final title = _normalizeTitle(rawTitle);
    final songTitle = _normalizeTitle(song.name);

    // 1. Cobertura de tokens del título (0..2000).
    var titlePenalty = 0;
    final wanted = songTitle.split(' ').where((t) => t.length > 1).toSet();
    if (wanted.isNotEmpty) {
      final have = title.split(' ').where((t) => t.length > 1).toSet();
      final coverage = wanted.intersection(have).length / wanted.length;
      titlePenalty = ((1.0 - coverage) * 2000).round();
    }

    // 2. Cercanía de duración (0..2000).
    final durationMs = track['duration'];
    final durationPenalty = !_hasReliableDuration(song)
        ? 0
        : durationMs is! int
        ? 2000
        : ((durationMs - song.duration.inMilliseconds).abs() ~/ 200).clamp(
            0,
            2000,
          );

    var score = titlePenalty + durationPenalty;

    // 3. Bonus por artista.
    final artistNames = song.artists
        .map((a) => _normalizeTitle(a.name))
        .where((s) => s.isNotEmpty)
        .toList();
    if (artistNames.isNotEmpty) {
      if (artistNames.any(title.contains)) score -= 700;
      final uploader = _uploaderOf(track);
      if (uploader.isNotEmpty &&
          artistNames.any(
            (a) => uploader.contains(a) || a.contains(uploader),
          )) {
        score -= 500;
      }
    }

    // 3b. Ninguna señal del artista (ni en título ni en uploader): puede
    // ser otra canción con el mismo nombre.
    if (artistNames.isNotEmpty && !_artistMatches(track, song)) score += 1200;

    // 4. Título idéntico.
    if (title == songTitle) score -= 1500;

    // 5. Remaster: mismo audio en esencia, solo una leve penalización.
    if (_remasterPattern.hasMatch(rawTitle) &&
        !_remasterPattern.hasMatch(song.name)) {
      score += 300;
    }

    return score;
  }

  List<Map<String, dynamic>> _filterAndRank(
    List<Map<String, dynamic>> raw,
    SongInfo song, {
    required bool relaxed,
    required bool requireArtist,
  }) {
    final maxExtras = relaxed ? 4 : 2; // exclusivo
    final scored = <_Scored>[];

    final tier = relaxed ? 'relajado' : 'estricto';
    debugPrint(
      'SoundcloudResolver: nivel $tier, buscando "${song.name}" '
      '(${song.duration.inMilliseconds} ms) de ${song.artists.map((a) => a.name).join(", ")}',
    );

    for (final t in raw) {
      final title = t['title'] as String? ?? '';
      final tag =
          '"$title" by ${(t['user'] as Map?)?['username']} '
          '(${t['duration']} ms, policy=${t['policy']}, streamable=${t['streamable']})';

      if (!_isPlayable(t)) {
        debugPrint('  ✗ no reproducible (SNIP/BLOCK/streamable): $tag');
        continue;
      }
      if (!_durationOk(t, song, relaxed)) {
        debugPrint('  ✗ duración fuera de rango: $tag');
        continue;
      }
      if (_looksLikeEdit(title, song)) {
        debugPrint('  ✗ parece edit/remix: $tag');
        continue;
      }
      if (requireArtist && !_artistMatches(t, song)) {
        debugPrint('  ✗ artista no coincide: $tag');
        continue;
      }

      final extras = _extraTokenCount(title, song);
      if (extras >= maxExtras) {
        debugPrint('  ✗ $extras tokens extra: $tag');
        continue;
      }

      scored.add(_Scored(t, _score(t, song), extras));
    }

    scored.sort((a, b) => a.score.compareTo(b.score));

    for (final s in scored.take(5)) {
      debugPrint(
        'SoundcloudResolver: [score ${s.score}] extras=${s.extras} '
        '"${s.track['title']}" by ${(s.track['user'] as Map?)?['username']} '
        '(${s.track['duration']} ms, policy=${s.track['policy']}) '
        '${relaxed ? "[relajado]" : "[estricto]"}',
      );
    }

    return scored.map((s) => s.track).toList();
  }

  Future<List<Map<String, dynamic>>> _searchTracks(
    String query,
    int limit,
  ) async {
    final res = await _apiGet(
      Uri.parse('https://api-v2.soundcloud.com/search/tracks'),
      {'q': query, 'limit': '$limit'},
    );

    if (res == null) return [];
    if (res.statusCode != 200) {
      debugPrint('SoundcloudResolver: búsqueda "$query" -> ${res.statusCode}');
      return [];
    }

    try {
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) return [];
      final collection = body['collection'];
      if (collection is! List) return [];
      final tracks = collection.whereType<Map<String, dynamic>>().toList();
      debugPrint('SoundcloudResolver: ${tracks.length} tracks para "$query"');
      return tracks;
    } catch (e) {
      debugPrint('SoundcloudResolver: JSON inválido en búsqueda: $e');
      return [];
    }
  }

  /// Busca con varias queries (de más a menos específica) y filtra por
  /// niveles: primero estricto, luego relajado. Devuelve candidatos
  /// ordenados; vacío si ninguno es confiable (mejor nada que un remix).
  Future<List<Map<String, dynamic>>> _rankedTracks(SongInfo song) async {
    final artistName = song.artists.isNotEmpty ? song.artists.first.name : '';
    final cleanName = _searchTitle(song.name);
    final hasArtist = artistName.trim().isNotEmpty;

    final plans = <_QueryPlan>[];
    final seen = <String>{};
    void add(String q, {bool requireArtist = false}) {
      final key = q.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) return;
      plans.add(_QueryPlan(q.trim(), requireArtist: requireArtist));
    }

    add(hasArtist ? '$cleanName $artistName' : cleanName);
    if (hasArtist) add('${song.name} $artistName');
    if (hasArtist) add(cleanName, requireArtist: true);

    for (final plan in plans) {
      final raw = await _searchTracks(plan.query, 20);
      if (raw.isEmpty) continue;

      for (final relaxed in const [false, true]) {
        final ranked = _filterAndRank(
          raw,
          song,
          relaxed: relaxed,
          // En nivel relajado siempre exigimos artista (si lo conocemos).
          requireArtist: hasArtist && (plan.requireArtist || relaxed),
        );
        if (ranked.isNotEmpty) return ranked;
      }
    }

    debugPrint(
      'SoundcloudResolver: ningún candidato confiable para "${song.name}"',
    );
    return [];
  }

  // ---------------------------------------------------------------------
  // Transcodings -> URL final
  // ---------------------------------------------------------------------

  /// Devuelve TODOS los transcodings utilizables, en el orden en que hay
  /// que probarlos. Se ignoran los `snipped` (previews) y el HLS cifrado;
  /// el HLS en opus queda al final porque just_audio casi nunca lo toca.
  List<Map<String, dynamic>> _orderedTranscodings(
    List<Map<String, dynamic>> all,
  ) {
    String protocolOf(Map<String, dynamic> t) =>
        (t['format']?['protocol'] as String?) ?? '';
    String presetOf(Map<String, dynamic> t) =>
        ((t['preset'] as String?) ?? '').toLowerCase();
    String mimeOf(Map<String, dynamic> t) =>
        ((t['format']?['mime_type'] as String?) ?? '').toLowerCase();

    bool isOpus(Map<String, dynamic> t) =>
        presetOf(t).contains('opus') ||
        mimeOf(t).contains('opus') ||
        mimeOf(t).contains('ogg');

    int bitrate(Map<String, dynamic> t) {
      final m = RegExp(r'(\d{2,3})').firstMatch(presetOf(t));
      return m != null ? int.tryParse(m.group(1)!) ?? 0 : 0;
    }

    int byBitrateDesc(Map<String, dynamic> a, Map<String, dynamic> b) =>
        bitrate(b).compareTo(bitrate(a));

    final usable = all
        .where(
          (t) =>
              t['snipped'] != true &&
              t['url'] is String &&
              !protocolOf(t).contains('encrypted'),
        )
        .toList();

    final progressive =
        usable.where((t) => protocolOf(t) == 'progressive').toList()
          ..sort((a, b) {
            // audio/mpeg primero, luego mayor bitrate.
            final am = mimeOf(a).contains('mpeg') ? 0 : 1;
            final bm = mimeOf(b).contains('mpeg') ? 0 : 1;
            return am != bm ? am.compareTo(bm) : byBitrateDesc(a, b);
          });

    final hls =
        usable.where((t) => protocolOf(t) == 'hls' && !isOpus(t)).toList()
          ..sort(byBitrateDesc);

    final hlsOpus = usable
        .where((t) => protocolOf(t) == 'hls' && isOpus(t))
        .toList();

    return _preferHls
        ? [...hls, ...progressive, ...hlsOpus]
        : [...progressive, ...hls, ...hlsOpus];
  }

  List<Map<String, dynamic>> _transcodingsOf(Map<String, dynamic> track) {
    final media = track['media'];
    if (media is! Map<String, dynamic>) return [];
    final list = media['transcodings'];
    if (list is! List) return [];
    return list.whereType<Map<String, dynamic>>().toList();
  }

  Future<String?> _resolveMediaUrl(Map<String, dynamic> track) async {
    var full = track;
    var transcodings = _transcodingsOf(full);

    // A veces el resultado de búsqueda viene "sin hidratar" (sin media).
    if (transcodings.isEmpty && track['id'] != null) {
      final res = await _apiGet(
        Uri.parse('https://api-v2.soundcloud.com/tracks/${track['id']}'),
        {},
      );
      if (res != null && res.statusCode == 200) {
        try {
          final body = jsonDecode(res.body);
          if (body is Map<String, dynamic>) {
            full = body;
            transcodings = _transcodingsOf(full);
          }
        } catch (_) {}
      }
    }

    debugPrint(
      'SoundcloudResolver: "${full['title']}" tiene ${transcodings.length} transcodings',
    );
    for (final t in transcodings) {
      debugPrint(
        '  · protocol=${t['format']?['protocol']} preset=${t['preset']} '
        'mime=${t['format']?['mime_type']} snipped=${t['snipped']}',
      );
    }
    if (transcodings.isEmpty) return null;

    // api-v2 exige este token junto al client_id para muchos tracks.
    final trackAuth = full['track_authorization'] as String?;

    for (final tc in _orderedTranscodings(transcodings)) {
      final res = await _apiGet(Uri.parse(tc['url'] as String), {
        if (trackAuth != null) 'track_authorization': trackAuth,
      });

      if (res == null || res.statusCode != 200) {
        debugPrint(
          'SoundcloudResolver: transcoding ${tc['preset']} -> '
          '${res?.statusCode}, probando el siguiente',
        );
        continue;
      }

      try {
        final body = jsonDecode(res.body);
        final finalUrl = body is Map<String, dynamic> ? body['url'] : null;
        if (finalUrl is String && finalUrl.isNotEmpty) {
          debugPrint(
            'SoundcloudResolver: OK ${tc['format']?['protocol']} ${tc['preset']} '
            '-> $finalUrl',
          );
          return finalUrl;
        }
      } catch (e) {
        debugPrint('SoundcloudResolver: respuesta de media inválida: $e');
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------
  // API pública (misma interfaz que antes)
  // ---------------------------------------------------------------------

  /// URL de streaming lista para reproducir. Prueba los mejores
  /// candidatos (hasta 5) y todos sus transcodings antes de rendirse.
  /// Resoluciones simultáneas de la misma canción comparten el trabajo.
  Future<String?> resolveStreamUrl(SongInfo song) {
    final cached = _urlCache[song.id];
    if (cached != null && !cached.isExpired) return Future.value(cached.url);

    return _inflight.putIfAbsent(
      song.id,
      () => _resolveUncached(song).whenComplete(() {
        _inflight.remove(song.id);
      }),
    );
  }

  Future<String?> _resolveUncached(SongInfo song) async {
    final ranked = await _rankedTracks(song);
    if (ranked.isEmpty) return null;

    for (final track in ranked.take(5)) {
      final url = await _resolveMediaUrl(track);
      if (url != null) {
        _urlCache[song.id] = _CachedUrl(url, DateTime.now());
        return url;
      }
    }
    return null;
  }

  /// Descarta la URL cacheada de una canción. Llamalo si el player falla
  /// al abrir una URL ya resuelta (probablemente caducó) y reintentá.
  void invalidate(String songId) => _urlCache.remove(songId);

  /// Precarga en background. Fire-and-forget, de a 2 por vez para no
  /// disparar 429. Reutiliza el cache, así que luego es un hit instantáneo.
  void preload(Iterable<SongInfo> songs) {
    final list = songs.toList();
    unawaited(() async {
      for (var i = 0; i < list.length; i += 2) {
        final batch = list.skip(i).take(2);
        await Future.wait(
          batch.map((s) async {
            try {
              await resolveStreamUrl(s);
            } catch (e) {
              debugPrint('SoundcloudResolver: preload falló: $e');
            }
          }),
        );
      }
    }());
  }

  /// Copia de tu SongInfo con `streamingurl` ya lleno (null si falla).
  Future<SongInfo> withStreamingUrl(SongInfo song) async {
    String? url;
    try {
      url = await resolveStreamUrl(song);
    } catch (e) {
      debugPrint('SoundcloudResolver: no se pudo resolver "${song.name}": $e');
    }
    return SongInfo(
      id: song.id,
      name: song.name,
      artists: song.artists,
      thumbnails: song.thumbnails,
      duration: song.duration,
      album: song.album,
      streamingurl: url,
      source: song.source,
      streamingSource: StreamingProvider.soundcloud,
    );
  }

  /// Resuelve varias canciones con límite de concurrencia.
  Future<List<SongInfo>> resolveAll(
    List<SongInfo> songs, {
    int concurrency = 3,
  }) async {
    final results = <SongInfo>[];

    for (var i = 0; i < songs.length; i += concurrency) {
      final batch = songs.skip(i).take(concurrency);
      final resolved = await Future.wait(batch.map(withStreamingUrl));
      results.addAll(resolved);
    }

    return results;
  }

  void close() => _client.close();
}

final soundcloudApi = SoundcloudResolver();
