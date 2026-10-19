// lyrics_aggregator.dart
import 'dart:async';

import 'package:mimic/Backend/songdata.dart';

import 'lrclib.dart';
import 'kugou.dart';

class LyricsAggregator {
  LyricsAggregator({LrcLibResolver? lrcLib, KugouLyricsResolver? kugou})
    : _lrcLib = lrcLib ?? lrcLibApi,
      _kugou = kugou ?? KugouLyricsResolver();

  final LrcLibResolver _lrcLib;
  final KugouLyricsResolver _kugou;
  final Map<String, LyricsResult?> _cache = {};

  /// Busca en ambos proveedores simultáneamente.
  /// - Si alguno devuelve letras sincronizadas, se usa inmediatamente.
  /// - Si ambos devuelven letras planas, se usa la primera que llegó.
  /// - Si uno devuelve null, se espera al otro.
  Future<LyricsResult?> getLyrics(SongInfo song) async {
    if (_cache.containsKey(song.id)) return _cache[song.id];

    final completer = Completer<LyricsResult?>();
    LyricsResult? firstPlainResult;
    bool lrcLibDone = false;
    bool kugouDone = false;

    void maybeComplete() {
      if (lrcLibDone && kugouDone && !completer.isCompleted) {
        completer.complete(firstPlainResult);
      }
    }

    void handleResult(LyricsResult? result) {
      if (result == null || !result.hasLyrics) return;

      if (result.syncedLyrics != null) {
        // Sincronizadas: máxima prioridad, completar ya
        if (!completer.isCompleted) completer.complete(result);
      } else if (result.plainLyrics != null) {
        // Planas: guardar como fallback
        firstPlainResult ??= result;
        maybeComplete();
      }
    }

    // Lanzar ambos en paralelo
    _lrcLib
        .getLyrics(song)
        .then((res) {
          lrcLibDone = true;
          handleResult(res);
          maybeComplete();
        })
        .catchError((_) {
          lrcLibDone = true;
          maybeComplete();
        });

    _kugou
        .getLyrics(song)
        .then((res) {
          kugouDone = true;
          handleResult(res);
          maybeComplete();
        })
        .catchError((_) {
          kugouDone = true;
          maybeComplete();
        });

    final best = await completer.future;
    _cache[song.id] = best;
    return best;
  }

  void close() {
    _lrcLib.close();
    _kugou.close();
  }
}
