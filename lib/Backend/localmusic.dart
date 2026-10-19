import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query_forked/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/privdersenums.dart';
import 'songdata.dart';

class LocalMusicManager extends ChangeNotifier {
  LocalMusicManager._();
  static final LocalMusicManager instance = LocalMusicManager._();

  static const _kEnabled = 'set_local_music_enabled';

  final OnAudioQuery _query = OnAudioQuery();

  bool enabled = false;
  bool scanning = false;
  String? error;
  List<SongInfo> songs = [];

  // ── Portadas ──────────────────────────────────────────────
  Directory? _artDir;
  final Set<String> _noArt = {}; // álbumes/canciones sin portada embebida
  int _artRun = 0; // invalida la extracción en curso al reescanear/ocultar

  Future<Directory> _getArtDir() async {
    final cached = _artDir;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/local_art');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _artDir = dir;
  }

  /// Canciones del mismo álbum comparten portada.
  String _artKey(SongModel m) =>
      m.albumId != null ? 'album_${m.albumId}' : 'song_${m.id}';

  // ── Ciclo de vida ─────────────────────────────────────────

  /// Llamar al iniciar la app, justo después de AppSettings.instance.load().
  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(_kEnabled) ?? false;
    if (enabled) {
      if (await _query.permissionsStatus()) {
        await _loadSongs();
      } else {
        enabled = false; // le quitaron el permiso
      }
    }
    notifyListeners();
  }

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    error = null;
    notifyListeners();
    try {
      var granted = await _query.permissionsStatus();
      if (!granted) granted = await _query.permissionsRequest();

      if (!granted) {
        error = 'Permission denied';
      } else {
        await _loadSongs();
        enabled = true;
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kEnabled, true);
      }
    } catch (e) {
      debugPrint('LocalMusic: scan failed -> $e');
      error = 'Scan failed';
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> disable() async {
    _artRun++; // cancela la extracción de portadas
    enabled = false;
    songs = [];
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, false);

    // Libera el espacio de las portadas guardadas
    try {
      final dir = await _getArtDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    _artDir = null;

    notifyListeners();
  }

  // ── Carga ─────────────────────────────────────────────────

  Future<void> _loadSongs() async {
    final artDir = await _getArtDir();
    _noArt.clear(); // un rescan reintenta las que no tenían portada

    final models = await _query.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final valid = models
        .where(
          (m) =>
              (m.isMusic ?? true) &&
              (m.duration ?? 0) > 30000 &&
              m.data.isNotEmpty,
        )
        .toList();

    songs = valid.map((m) {
      final song = _toSongInfo(m);
      // Si la portada ya está en disco, se asigna al instante
      final file = File('${artDir.path}/${_artKey(m)}.jpg');
      if (file.existsSync()) song.downloadBannerPath = file.path;
      return song;
    }).toList();

    // Las que faltan se extraen en segundo plano, sin bloquear
    unawaited(_extractArtwork(valid, artDir));
  }

  Future<void> _extractArtwork(List<SongModel> models, Directory dir) async {
    final run = ++_artRun;
    var sinceNotify = 0;

    for (var i = 0; i < models.length; i++) {
      if (run != _artRun) return; // llegó un rescan o se ocultó la sección

      final m = models[i];
      final song = songs[i]; // mismo orden que `models`
      if (song.downloadBannerPath != null) continue;

      final key = _artKey(m);
      if (_noArt.contains(key)) continue;

      final file = File('${dir.path}/$key.jpg');

      try {
        // Otra canción del mismo álbum ya la guardó en esta corrida
        if (await file.exists()) {
          song.downloadBannerPath = file.path;
          continue;
        }

        final bytes = await _query.queryArtwork(
          m.id,
          ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG,
          size: 600,
          quality: 90,
        );

        if (bytes == null || bytes.isEmpty) {
          _noArt.add(key);
          continue;
        }

        await file.writeAsBytes(bytes, flush: true);
        song.downloadBannerPath = file.path;

        // Avisar cada tanto, no en cada una, para no reconstruir de más
        if (++sinceNotify >= 25) {
          sinceNotify = 0;
          notifyListeners();
        }
      } catch (e) {
        debugPrint('LocalMusic: artwork failed for ${m.title} -> $e');
        _noArt.add(key);
      }
    }

    if (run == _artRun) notifyListeners();
  }

  SongInfo _toSongInfo(SongModel m) {
    final artist = (m.artist == null || m.artist == '<unknown>')
        ? 'Unknown artist'
        : m.artist!;

    return SongInfo(
      id: 'local_${m.id}',
      name: m.title,
      artists: [
        Artist(
          id: 'local_artist_$artist',
          name: artist,
          source: metadataprovider.local,
        ),
      ],
      thumbnails: const <Thumbnail>[],
      duration: Duration(milliseconds: m.duration ?? 0),
      source: metadataprovider.local,
      streamingSource: StreamingProvider.local,
      downloadPath: m.data,
    );
  }
}
