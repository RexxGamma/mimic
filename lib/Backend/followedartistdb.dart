import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'providers/privdersenums.dart'; // metadataprovider
import 'songdata.dart'; // SimplifiedArtist

class ArtistDatabase extends ChangeNotifier {
  Database? _db;
  List<SimplifiedArtist> followedartists = [];

  List<SimplifiedArtist> get artistsfollowed => followedartists;

  Future<Database> _getConnection() async {
    if (_db != null) return _db!;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'mi_app.db');

    final db = sqlite3.open(dbPath);
    _createdb(db);

    _db = db;
    return db;
  }

  // ── Conversión fila -> SimplifiedArtist ─────────────────────
  static metadataprovider _parseSource(String name) {
    // 'legacy' (filas migradas de la tabla vieja) no es un enum válido
    for (final e in metadataprovider.values) {
      if (e.name == name) return e;
    }
    return metadataprovider.values.first;
  }

  static SimplifiedArtist _fromRow(Row row) => SimplifiedArtist(
        id: row['id'] as String,
        name: row['name'] as String,
        thumbnailUrl: row['bannerpath'] as String,
        url: (row['url'] as String?) ?? '',
        source: _parseSource(row['source'] as String),
      );

  // ── Esquema + migración ─────────────────────────────────────
  void _createdb(Database db) {
    final info = db.select("PRAGMA table_info(followed_artists)");
    final exists = info.isNotEmpty;
    final hasSource = info.any((c) => c['name'] == 'source');

    if (exists && !hasSource) {
      db.execute('ALTER TABLE followed_artists RENAME TO followed_artists_old');
    }

    db.execute('''
      CREATE TABLE IF NOT EXISTS followed_artists (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        source TEXT NOT NULL,
        bannerpath TEXT NOT NULL,
        url TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (id, source)
      )
    ''');

    if (exists && !hasSource) {
      db.execute('''
        INSERT OR IGNORE INTO followed_artists (id, name, source, bannerpath, url)
        SELECT CAST(id AS TEXT), name, 'legacy', '', '' FROM followed_artists_old
      ''');
      db.execute('DROP TABLE followed_artists_old');
    }

    // Migración: tablas creadas antes de existir la columna url
    final cols = db
        .select('PRAGMA table_info(followed_artists)')
        .map((c) => c['name'] as String)
        .toSet();
    if (!cols.contains('url')) {
      db.execute(
          "ALTER TABLE followed_artists ADD COLUMN url TEXT NOT NULL DEFAULT ''");
    }
  }

  // ── Escritura ───────────────────────────────────────────────
  Future<void> follow(SimplifiedArtist artist) async {
    final db = await _getConnection();
    db.execute(
      'INSERT OR REPLACE INTO followed_artists '
      '(id, name, source, bannerpath, url) VALUES (?, ?, ?, ?, ?)',
      [
        artist.id,
        artist.name,
        artist.source.name,
        artist.thumbnailUrl,
        artist.url,
      ],
    );
    await loadFArtist();
  }

  Future<void> unfollow(SimplifiedArtist artist) async {
    final db = await _getConnection();
    db.execute(
      'DELETE FROM followed_artists WHERE id = ? AND source = ?',
      [artist.id, artist.source.name],
    );
    await loadFArtist();
  }

  // ── Lectura ─────────────────────────────────────────────────
  Future<List<SimplifiedArtist>> getFollowedArtists() async {
    final db = await _getConnection();
    return db
        .select(
            'SELECT * FROM followed_artists ORDER BY name COLLATE NOCASE ASC')
        .map(_fromRow)
        .toList();
  }

  Future<bool> isFollowing(SimplifiedArtist artist) async {
    final db = await _getConnection();
    final rows = db.select(
      'SELECT 1 FROM followed_artists WHERE id = ? AND source = ? LIMIT 1',
      [artist.id, artist.source.name],
    );
    return rows.isNotEmpty;
  }

  Future<void> loadFArtist() async {
    followedartists = await getFollowedArtists();
    notifyListeners();
  }

  // ── Ciclo de vida ───────────────────────────────────────────
  Future<void> close() async {
    _db?.dispose();
    _db = null;
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}