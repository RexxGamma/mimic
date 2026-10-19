import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class AppDatabase extends ChangeNotifier {
  static const int favoritesId = 0; // los ids autoincrementales empiezan en 1
  static const int downloadsId =
      -1; // id reservado para la playlist de descargas

  Database? _db;
  List<Map<String, dynamic>> _playlists = [];
  List<Map<String, dynamic>> _radios = [];
  List<Map<String, dynamic>> get radios => _radios;
  List<Map<String, dynamic>> get playlists => _playlists;

  Future<Database> _getConnection() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'mi_app.db');
    final db = sqlite3.open(dbPath);
    _createdb(db);
    _db = db;
    return db;
  }

  void _createdb(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS playlist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        cover TEXT NOT NULL DEFAULT '' ,
        created_at TEXT NOT NULL
      )
    ''');

    db.execute('''
  CREATE TABLE IF NOT EXISTS radio (
    artist_id TEXT NOT NULL,
    source TEXT NOT NULL,
    name TEXT NOT NULL,
    thumbnail TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    PRIMARY KEY (artist_id, source)
  )
''');
    db.execute('''
  CREATE TABLE IF NOT EXISTS radio (
    artist_id TEXT NOT NULL,
    source TEXT NOT NULL,
    name TEXT NOT NULL,
    thumbnail TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    PRIMARY KEY (artist_id, source)
  )
''');

    // Favoritos: existe siempre; IGNORE evita duplicarla
    db.execute(
      'INSERT OR IGNORE INTO playlist (id, title, cover, created_at) VALUES (?, ?, ?, ?)',
      [favoritesId, 'Favorites', '', DateTime.now().toIso8601String()],
    );

    // Descargas: existe siempre; IGNORE evita duplicarla
    db.execute(
      'INSERT OR IGNORE INTO playlist (id, title, cover, created_at) VALUES (?, ?, ?, ?)',
      [downloadsId, 'Downloads', '', DateTime.now().toIso8601String()],
    );
  }

  Future<int> createPlaylist(String title) async {
    final db = await _getConnection();
    db.execute(
      'INSERT INTO playlist (title, cover, created_at) VALUES (?, ?, ?)',
      [title, "", DateTime.now().toIso8601String()],
    );
    final id = db.lastInsertRowId;
    await loadPlaylists();
    return id;
  }

  // Sin Favorites ni Downloads: esas se dibujan aparte en library.dart
  Future<List<Map<String, dynamic>>> getPlaylists() async {
    final db = await _getConnection();
    return db.select(
      'SELECT * FROM playlist WHERE id NOT IN (?, ?) ORDER BY id DESC',
      [favoritesId, downloadsId],
    ).toList();
  }

  Future<void> loadPlaylists() async {
    _playlists = await getPlaylists();
    notifyListeners();
  }

  Future<void> deletePlaylist(int id) async {
    if (id == favoritesId || id == downloadsId) return; // permanentes
    final db = await _getConnection();
    db.execute('DELETE FROM playlist WHERE id = ?', [id]);
    await loadPlaylists();
  }

  Future<List<Map<String, dynamic>>> getRadios() async {
    final db = await _getConnection();
    return db.select('SELECT * FROM radio ORDER BY created_at DESC').toList();
  }

  Future<bool> isRadioSaved(String artistId, String source) async {
    final db = await _getConnection();
    final rows = db.select(
      'SELECT 1 FROM radio WHERE artist_id = ? AND source = ?',
      [artistId, source],
    );
    return rows.isNotEmpty;
  }

  Future<void> saveRadio({
    required String artistId,
    required String source,
    required String name,
    String thumbnail = '',
  }) async {
    final db = await _getConnection();
    db.execute(
      'INSERT OR IGNORE INTO radio (artist_id, source, name, thumbnail, created_at) VALUES (?, ?, ?, ?, ?)',
      [artistId, source, name, thumbnail, DateTime.now().toIso8601String()],
    );
    await loadPlaylists();
  }

  Future<void> removeRadio(String artistId, String source) async {
    final db = await _getConnection();
    db.execute('DELETE FROM radio WHERE artist_id = ? AND source = ?', [
      artistId,
      source,
    ]);
    await loadPlaylists();
  }

  Future<void> renamePlaylist(int id, String newTitle) async {
    if (id == favoritesId || id == downloadsId) return; // permanentes
    final title = newTitle.trim();
    if (title.isEmpty) return;
    final db = await _getConnection();
    db.execute('UPDATE playlist SET title = ? WHERE id = ?', [title, id]);
    await loadPlaylists();
  }

  Future<void> setPlaylistCover(int id, String cover) async {
    if (id == favoritesId || id == downloadsId) return;
    final db = await _getConnection();
    db.execute('UPDATE playlist SET cover = ? WHERE id = ?', [cover, id]);
    await loadPlaylists();
  }

  Future<String> getPlaylistCover(int id) async {
    final db = await _getConnection();
    final rows = db.select('SELECT cover FROM playlist WHERE id = ?', [id]);
    if (rows.isEmpty) return '';
    return rows.first['cover'] as String;
  }

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
