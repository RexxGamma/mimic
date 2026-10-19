import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'providers/privdersenums.dart';
import 'songdata.dart';

/// Historial de reproducción. Singleton sin ChangeNotifier:
/// se puede llamar desde cualquier sitio sin BuildContext.
class HistoryDatabase {
  HistoryDatabase._();
  static final HistoryDatabase instance = HistoryDatabase._();

  Future<Database>? _opening;

  Future<Database> _conn() => _opening ??= _open();

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final db = sqlite3.open(p.join(dir.path, 'mi_app.db'));
    db.execute('''
      CREATE TABLE IF NOT EXISTS play_history (
        id TEXT NOT NULL,
        source TEXT NOT NULL,
        name TEXT NOT NULL,
        artists TEXT NOT NULL,
        thumbnails TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        streaming_source TEXT NOT NULL,
        played_at INTEGER NOT NULL,
        play_count INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (id, source)
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_played_at '
      'ON play_history(played_at DESC)',
    );
    return db;
  }

  // ── Enums ───────────────────────────────────────────────────
  static metadataprovider _meta(String? n) =>
      metadataprovider.values.firstWhere(
        (e) => e.name == n,
        orElse: () => metadataprovider.values.first,
      );

  static StreamingProvider _stream(String? n) =>
      StreamingProvider.values.firstWhere(
        (e) => e.name == n,
        orElse: () => StreamingProvider.values.first,
      );

  // ── Escritura ───────────────────────────────────────────────
  Future<void> record(SongInfo song) async {
    try {
      final db = await _conn();
      db.execute(
        '''
        INSERT INTO play_history
          (id, source, name, artists, thumbnails, duration_ms,
           streaming_source, played_at, play_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
        ON CONFLICT(id, source) DO UPDATE SET
          name = excluded.name,
          artists = excluded.artists,
          thumbnails = excluded.thumbnails,
          duration_ms = excluded.duration_ms,
          streaming_source = excluded.streaming_source,
          played_at = excluded.played_at,
          play_count = play_count + 1
        ''',
        [
          song.id,
          song.source.name,
          song.name,
          jsonEncode(
            song.artists
                .map(
                  (a) => {'id': a.id, 'name': a.name, 'source': a.source.name},
                )
                .toList(),
          ),
          jsonEncode(
            song.thumbnails
                .map((t) => {'url': t.url, 'w': t.width, 'h': t.height})
                .toList(),
          ),
          song.duration.inMilliseconds,
          song.streamingSource.name,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
    } catch (e) {
      debugPrint('HistoryDatabase.record error: $e');
    }
  }

  // ── Lectura ─────────────────────────────────────────────────
  Future<List<SongInfo>> getRecent({
    metadataprovider? source,
    int limit = 20,
  }) async {
    final db = await _conn();
    final rows = source == null
        ? db.select(
            'SELECT * FROM play_history ORDER BY played_at DESC LIMIT ?',
            [limit],
          )
        : db.select(
            'SELECT * FROM play_history WHERE source = ? '
            'ORDER BY played_at DESC LIMIT ?',
            [source.name, limit],
          );
    return rows.map(_songFromRow).toList();
  }

  /// Artistas principales (primer artista de cada canción) ordenados
  /// por número total de reproducciones.
  Future<List<Artist>> getTopArtists({
    metadataprovider? source,
    int limit = 5,
  }) async {
    final db = await _conn();
    final rows = source == null
        ? db.select('SELECT artists, play_count FROM play_history')
        : db.select(
            'SELECT artists, play_count FROM play_history WHERE source = ?',
            [source.name],
          );

    final counts = <String, int>{};
    final byKey = <String, Artist>{};
    for (final r in rows) {
      final list = jsonDecode(r['artists'] as String) as List;
      if (list.isEmpty) continue;
      final a = list.first as Map<String, dynamic>;
      final id = (a['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final key = '${a['source']}:$id';
      counts[key] = (counts[key] ?? 0) + (r['play_count'] as int);
      byKey[key] ??= Artist(
        id: id,
        name: (a['name'] ?? '').toString(),
        source: _meta(a['source']?.toString()),
      );
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return keys.take(limit).map((k) => byKey[k]!).toList();
  }

  SongInfo _songFromRow(Row r) {
    final artists = (jsonDecode(r['artists'] as String) as List)
        .map(
          (a) => Artist(
            id: (a['id'] ?? '').toString(),
            name: (a['name'] ?? '').toString(),
            source: _meta(a['source']?.toString()),
          ),
        )
        .toList();
    final thumbs = (jsonDecode(r['thumbnails'] as String) as List)
        .map(
          (t) => Thumbnail(
            url: (t['url'] ?? '').toString(),
            width: (t['w'] as num?)?.toInt() ?? 0,
            height: (t['h'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
    return SongInfo(
      id: r['id'] as String,
      name: r['name'] as String,
      artists: artists,
      thumbnails: thumbs,
      duration: Duration(milliseconds: r['duration_ms'] as int),
      source: _meta(r['source'] as String),
      streamingSource: _stream(r['streaming_source'] as String),
    );
  }
}
