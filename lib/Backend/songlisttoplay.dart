import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'providers/privdersenums.dart';
import 'convertplaylisttocolumn.dart';
import 'songdata.dart';
import 'playlistsmanager.dart';

import 'dart:io';

class SongDatabase extends ChangeNotifier {
  static final int favoritesId = AppDatabase.favoritesId;
  static final int downloadsId = AppDatabase.downloadsId;

  /// Instancia global
  static SongDatabase? instance;

  Database? _db;
  final Set<String> _favoriteIds = {};
  final Set<String> _downloadedIds = {};

  /// Cache síncrona: id
  final Map<String, SongInfo> _downloadedCache = {};

  bool _cacheLoaded = false;
  bool _loadingCache = false;

  SongDatabase() {
    instance = this;
  }

  bool isFavoriteSync(String songId) => _favoriteIds.contains(songId);
  bool isDownloadedSync(String songId) => _downloadedIds.contains(songId);

  // ─────────────────────────────────────────────────────────────
  //  RESOLUCIÓN: provider ↔ descarga local
  // ─────────────────────────────────────────────────────────────

  SongInfo resolveDownloaded(SongInfo song) {
    if (!_cacheLoaded) {
      _ensureCacheLoaded();
      return song;
    }

    final cached = _downloadedCache[song.id];
    if (cached == null) return song;

    final path = cached.downloadPath;
    if (path == null || path.isEmpty) return song;

    if (!File(path).existsSync()) return song;

    return cached;
  }

  Future<void> init() async {
    await _getConnection();
    _cacheLoaded = true;
  }

  Future<void> _ensureCacheLoaded() async {
    if (_cacheLoaded || _loadingCache) return;
    _loadingCache = true;
    try {
      await _getConnection();
      _cacheLoaded = true;
      notifyListeners();
    } finally {
      _loadingCache = false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Conexión
  // ─────────────────────────────────────────────────────────────

  Future<Database> _getConnection() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'songs_v2.db');
    _db = sqlite3.open(dbPath);
    _crearTabla(_db!);
    _readFavorites(_db!);
    _readDownloads(_db!);
    return _db!;
  }

  // ─────────────────────────────────────────────────────────────
  //  Lecturas
  // ─────────────────────────────────────────────────────────────

  void _readFavorites(Database db) {
    final rows = db.select(
      'SELECT song_id FROM playlist_songs WHERE playlist_id = ?',
      [favoritesId],
    );
    _favoriteIds
      ..clear()
      ..addAll(rows.map((r) => r['song_id'] as String));
  }

  void _readDownloads(Database db) {
    final rows = db.select(
      '''
    SELECT songs.* FROM songs
    JOIN playlist_songs ON songs.id = playlist_songs.song_id
    WHERE playlist_songs.playlist_id = ?
    ''',
      [downloadsId],
    );

    _downloadedIds.clear();
    _downloadedCache.clear();

    for (final row in rows) {
      final s = SongInfoFromMap.fromMap(row);
      if (s.downloadPath != null && s.downloadPath!.isNotEmpty) {
        _downloadedIds.add(s.id);
        _downloadedCache[s.id] = s;
      }
    }

    _cacheLoaded = true;
  }

  Future<void> loadFavorites() async {
    final db = await _getConnection();
    _readFavorites(db);
    notifyListeners();
  }

  Future<void> loadDownloads() async {
    final db = await _getConnection();
    _readDownloads(db);
    notifyListeners();
  }

  Future<List<SongInfo>> getTracks(int playlistId) async {
    final db = await _getConnection();
    final order = (playlistId == favoritesId || playlistId == downloadsId)
        ? 'DESC'
        : 'ASC';
    final result = db.select(
      '''
      SELECT songs.* FROM songs
      JOIN playlist_songs ON songs.id = playlist_songs.song_id
      WHERE playlist_songs.playlist_id = ?
      ORDER BY playlist_songs.position $order
    ''',
      [playlistId],
    );
    return result.map((row) => SongInfoFromMap.fromMap(row)).toList();
  }

  // ─────────────────────────────────────────────────────────────
  //  Escrituras
  // ─────────────────────────────────────────────────────────────

  Future<bool> toggleFavorite(SongInfo song) async {
    if (_favoriteIds.contains(song.id)) {
      await deleteTracks(song.id, favoritesId);
      return false;
    }
    await addTracks(song, favoritesId);
    return true;
  }

  void _crearTabla(Database db) {
    db.execute('PRAGMA foreign_keys = ON');

    db.execute('''
      CREATE TABLE IF NOT EXISTS songs (
        id                 TEXT PRIMARY KEY,
        name               TEXT NOT NULL,
        artists            TEXT NOT NULL,
        thumbnails         TEXT NOT NULL,
        duration_ms        INTEGER NOT NULL,
        release_date       INTEGER,
        bpm                INTEGER,
        isrc               TEXT,
        genre              TEXT,
        streaming_url      TEXT,
        album              TEXT,
        share_url          TEXT,
        source             TEXT,
        streaming_source   TEXT,
        downloadpath       TEXT,
        downloadbannerpath TEXT
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_songs (
        playlist_id INTEGER NOT NULL,
        song_id     TEXT NOT NULL,
        position    INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (playlist_id, song_id),
        FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS album_meta (
        album_key     TEXT PRIMARY KEY,
        creator_id    TEXT NOT NULL,
        creator_name  TEXT NOT NULL,
        creator_thumb TEXT NOT NULL DEFAULT '',
        creator_url   TEXT NOT NULL DEFAULT '',
        record_type   TEXT NOT NULL DEFAULT '',
        source        TEXT NOT NULL
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS album_tracks (
        album_key TEXT NOT NULL,
        song_id   TEXT NOT NULL,
        position  INTEGER NOT NULL,
        PRIMARY KEY (album_key, song_id),
        FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
      )
    ''');
  }

  void _upsertSong(Database db, SongInfo song) {
    final m = song.toMap();
    db.execute(
      '''
      INSERT INTO songs
        (id, name, artists, thumbnails, duration_ms, release_date,
         bpm, isrc, genre, streaming_url, album, share_url,
         source, streaming_source, downloadpath, downloadbannerpath)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name               = excluded.name,
        artists            = excluded.artists,
        thumbnails         = excluded.thumbnails,
        duration_ms        = excluded.duration_ms,
        release_date       = excluded.release_date,
        bpm                = excluded.bpm,
        isrc               = excluded.isrc,
        genre              = excluded.genre,
        streaming_url      = excluded.streaming_url,
        album              = excluded.album,
        share_url          = excluded.share_url,
        source             = excluded.source,
        streaming_source   = excluded.streaming_source,
        downloadpath       = COALESCE(excluded.downloadpath, songs.downloadpath),
        downloadbannerpath = COALESCE(excluded.downloadbannerpath, songs.downloadbannerpath)
    ''',
      [
        m['id'],
        m['name'],
        m['artists'],
        m['thumbnails'],
        m['duration_ms'],
        m['release_date'],
        m['bpm'],
        m['isrc'],
        m['genre'],
        m['streaming_url'],
        m['album'],
        m['share_url'],
        m['source'],
        m['streaming_source'],
        m['downloadpath'],
        m['downloadbannerpath'],
      ],
    );
  }

  Future<void> addTracks(SongInfo song, int playlistId) async {
    final db = await _getConnection();

    _upsertSong(db, song);
    final posRow = db.select(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next '
      'FROM playlist_songs WHERE playlist_id = ?',
      [playlistId],
    );
    final nextPos = (posRow.first['next'] as int?) ?? 0;

    db.execute(
      '''
      INSERT OR IGNORE INTO playlist_songs (playlist_id, song_id, position)
      VALUES (?, ?, ?)
    ''',
      [playlistId, song.id, nextPos],
    );

    if (playlistId == favoritesId) _favoriteIds.add(song.id);

    if (playlistId == downloadsId) {
      if (song.downloadPath != null && song.downloadPath!.isNotEmpty) {
        _downloadedIds.add(song.id);
        _downloadedCache[song.id] = song;
      }
    }

    notifyListeners();
  }

  /// Inserta muchas canciones en una playlist con una sola transacción.
  Future<void> addManyTracks(List<SongInfo> songs, int playlistId) async {
    if (songs.isEmpty) return;
    final db = await _getConnection();

    db.execute('BEGIN');
    try {
      final posRow = db.select(
        'SELECT COALESCE(MAX(position), -1) + 1 AS next '
        'FROM playlist_songs WHERE playlist_id = ?',
        [playlistId],
      );
      var pos = (posRow.first['next'] as int?) ?? 0;

      for (final song in songs) {
        _upsertSong(db, song);
        db.execute(
          'INSERT OR IGNORE INTO playlist_songs (playlist_id, song_id, position) '
          'VALUES (?, ?, ?)',
          [playlistId, song.id, pos++],
        );
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }

    if (playlistId == favoritesId) {
      _favoriteIds.addAll(songs.map((s) => s.id));
    }
    notifyListeners();
  }

  Future<void> deleteTracks(String songId, int playlistId) async {
    final db = await _getConnection();
    db.execute(
      'DELETE FROM playlist_songs WHERE song_id = ? AND playlist_id = ?',
      [songId, playlistId],
    );

    if (playlistId == favoritesId) _favoriteIds.remove(songId);
    if (playlistId == downloadsId) {
      _downloadedIds.remove(songId);
      _downloadedCache.remove(songId);
    }
    notifyListeners();
  }

  Future<void> setDownloads(
    SongInfo song, {
    String? path,
    String? bannerPath,
    int? playlistId,
  }) async {
    if (path != null) song.downloadPath = path;
    if (bannerPath != null) song.downloadBannerPath = bannerPath;

    // Siempre agregar a Descargas para mantener consistencia
    await addTracks(song, downloadsId);

    // Si se indica otra playlist, agregar también allí
    if (playlistId != null && playlistId != downloadsId) {
      await addTracks(song, playlistId);
    }
  }

  Future<void> removeDownload(SongInfo song, {bool deleteFile = true}) async {
    await deleteTracks(song.id, downloadsId);

    if (!deleteFile) return;

    final path = song.downloadPath;
    if (path == null || path.isEmpty) return;

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      // Limpiar rutas en la DB porque el archivo ya no existe
      final db = await _getConnection();
      db.execute(
        'UPDATE songs SET downloadpath = NULL, downloadbannerpath = NULL WHERE id = ?',
        [song.id],
      );
      song.downloadPath = null;
      song.downloadBannerPath = null;
    } catch (e) {
      debugPrint('No se pudo borrar el archivo $path: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Álbumes guardados
  // ─────────────────────────────────────────────────────────────

  static String albumKey(String source, String albumId) => '${source}_$albumId';

  metadataprovider _providerFromName(String name) =>
      metadataprovider.values.firstWhere(
        (e) => e.name == name,
        orElse: () => metadataprovider.values.first,
      );

  /// Guarda (o reemplaza) el álbum completo: encabezado + tracks en orden.
  Future<void> saveAlbum(String albumKey, AlbumInfo album) async {
    final db = await _getConnection();
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM album_tracks WHERE album_key = ?', [albumKey]);

      db.execute(
        '''
        INSERT OR REPLACE INTO album_meta
          (album_key, creator_id, creator_name, creator_thumb, creator_url,
           record_type, source)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          albumKey,
          album.creator.id,
          album.creator.name,
          album.creator.thumbnailUrl,
          album.creator.url,
          album.recordType,
          album.source.name,
        ],
      );

      for (var i = 0; i < album.content.length; i++) {
        final song = album.content[i];
        _upsertSong(db, song);
        db.execute(
          '''
          INSERT OR REPLACE INTO album_tracks (album_key, song_id, position)
          VALUES (?, ?, ?)
        ''',
          [albumKey, song.id, i],
        );
      }

      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      debugPrint('SongDatabase.saveAlbum falló: $e');
      rethrow;
    }
  }

  /// Devuelve el álbum guardado, o null si no está en la DB.
  Future<AlbumInfo?> getAlbum(String albumKey) async {
    final db = await _getConnection();

    final meta = db.select('SELECT * FROM album_meta WHERE album_key = ?', [
      albumKey,
    ]);
    if (meta.isEmpty) return null;

    final rows = db.select(
      '''
      SELECT songs.* FROM songs
      JOIN album_tracks ON songs.id = album_tracks.song_id
      WHERE album_tracks.album_key = ?
      ORDER BY album_tracks.position ASC
    ''',
      [albumKey],
    );
    if (rows.isEmpty) return null;

    final songs = rows.map((r) => SongInfoFromMap.fromMap(r)).toList();

    // Si el archivo descargado ya no existe, que la canción vuelva a
    // streamear en vez de intentar reproducir una ruta muerta.
    for (final s in songs) {
      final p = s.downloadPath;
      if (p != null && p.isNotEmpty && !File(p).existsSync()) {
        s.downloadPath = null;
        s.downloadBannerPath = null;
      }
    }

    final m = meta.first;
    final source = _providerFromName(m['source'] as String);
    final totalMs = songs.fold<int>(
      0,
      (sum, s) => sum + s.duration.inMilliseconds,
    );

    return AlbumInfo(
      creator: SimplifiedArtist(
        id: m['creator_id'] as String,
        name: m['creator_name'] as String,
        thumbnailUrl: m['creator_thumb'] as String,
        url: m['creator_url'] as String,
        source: source,
      ),
      content: songs,
      recordType: m['record_type'] as String,
      source: source,
      duration: Duration(milliseconds: totalMs),
    );
  }

  Future<void> deleteAlbum(String albumKey) async {
    final db = await _getConnection();
    db.execute('DELETE FROM album_tracks WHERE album_key = ?', [albumKey]);
    db.execute('DELETE FROM album_meta WHERE album_key = ?', [albumKey]);

    // Limpia canciones que quedaron sin ninguna playlist ni álbum que las use.
    // No toca las que tienen archivo descargado.
    db.execute('''
      DELETE FROM songs
      WHERE id NOT IN (SELECT song_id FROM playlist_songs)
        AND id NOT IN (SELECT song_id FROM album_tracks)
        AND (downloadpath IS NULL OR downloadpath = '')
    ''');
  }

  void close() {
    _db?.dispose();
    _db = null;
    if (identical(instance, this)) instance = null;
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
