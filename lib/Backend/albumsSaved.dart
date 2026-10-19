import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'providers/privdersenums.dart';
import 'songdata.dart';

class AlbumDatabase extends ChangeNotifier {
  Database? _db;
  Future<Database>? _connecting;
  
  List<Albumc> savedAlbums = [];
  List<Albumc> get albumsSaved => savedAlbums;

  Future<Database> _getConnection() {
    if (_db != null) return Future.value(_db!);
    return _connecting ??= _open();
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'mi_app.db');

    final db = sqlite3.open(dbPath);
    _createDb(db);

    _db = db;
    return db;
  }

  // ─────────────────────────────────────────────────────────────
  // Esquema
  // ─────────────────────────────────────────────────────────────
  void _createDb(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS savedAlbums (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        source TEXT NOT NULL,
        year TEXT NOT NULL,
        recordType TEXT NOT NULL,
        bannerpath TEXT NOT NULL,
        PRIMARY KEY (id, source)
      )
    ''');
  }
  

  static Albumc _fromRow(Row row) => Albumc(
        id: row['id'] as String,
        name: row['name'] as String,
        bannerurl: row['bannerpath'] as String,
        year: row['year'] as String,
        recordType: row['recordType'] as String,
        source: metadataprovider.values.byName(row['source'] as String),
      );

  // ── Escritura ───────────────────────────────────────────────
  Future<void> save(Albumc album) async {
    final db = await _getConnection();
    db.execute(
      'INSERT OR REPLACE INTO savedAlbums '
      '(id, name, source, year, recordType, bannerpath) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        album.id,
        album.name,
        album.source.name,
        album.year,
        album.recordType,
        album.bannerurl,
      ],
    );
    await loadAlbums();
  }

  Future<void> unfollow(Albumc album) async {
    final db = await _getConnection();
    db.execute(
      'DELETE FROM savedAlbums WHERE id = ? AND source = ?',
      [album.id, album.source.name],
    );
    await loadAlbums();
  }

  // ── Lectura ─────────────────────────────────────────────────
  Future<List<Albumc>> getSavedAlbums() async {
    final db = await _getConnection();
    return db
        .select('SELECT * FROM savedAlbums ORDER BY name COLLATE NOCASE ASC')
        .map(_fromRow)
        .toList();
  }

  Future<bool> isSaved(Albumc album) async {
    final db = await _getConnection();
    final rows = db.select(
      'SELECT 1 FROM savedAlbums WHERE id = ? AND source = ? LIMIT 1',
      [album.id, album.source.name],
    );
    return rows.isNotEmpty;
  }

  Future<void> loadAlbums() async {
    savedAlbums = await getSavedAlbums();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────
  // Ciclo de vida
  // ─────────────────────────────────────────────────────────────
  void close() {
    _db?.close();
    _db = null;
    _connecting = null;
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}