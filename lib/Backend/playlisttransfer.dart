import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'convertplaylisttocolumn.dart'; // SongInfoFromMap / toMap
import 'playlistsmanager.dart';
import 'songdata.dart';
import 'songlisttoplay.dart';

typedef PlaylistExport = ({String title, List<SongInfo> songs, bool favorites});

class PlaylistTransfer {
  PlaylistTransfer._();

  static const _format = 'mimic-playlist';
  static const _version = 1;
  static const _maxBytes = 20 * 1024 * 1024;

  static bool _isLocal(SongInfo s) => s.id.startsWith('local_');

  /// Mismas columnas que la DB, sin lo que solo vale en este teléfono.
  static Map<String, dynamic> _songToJson(SongInfo s) {
    final m = Map<String, dynamic>.from(s.toMap());
    m.remove('downloadpath');
    m.remove('downloadbannerpath');
    m.remove('streaming_url'); // las URLs de streaming caducan
    return m;
  }

  static String fileNameFor(String title) {
    final clean = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    return 'mimic_${clean.isEmpty ? 'playlist' : clean}.json';
  }

  // ───────────────────────── Exportar ─────────────────────────

  /// Devuelve el mensaje a mostrar, o null si el usuario canceló.
  static Future<String?> exportPlaylists(
    List<PlaylistExport> playlists, {
    required String fileName,
  }) async {
    var exported = 0;
    var skippedLocal = 0;
    final out = <Map<String, dynamic>>[];

    for (final p in playlists) {
      final usable = p.songs.where((s) => !_isLocal(s)).toList();
      skippedLocal += p.songs.length - usable.length;
      if (usable.isEmpty) continue;

      exported += usable.length;
      out.add({
        'title': p.title,
        'favorites': p.favorites,
        'tracks': usable.map(_songToJson).toList(),
      });
    }

    if (out.isEmpty) return 'Nothing to export';

    final doc = {
      'format': _format,
      'version': _version,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'playlists': out,
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(doc)));

    final saved = await FilePicker.saveFile(
      dialogTitle: 'Export playlist',
      fileName: fileName,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (saved == null) return null; // canceló

    return skippedLocal == 0
        ? 'Exported $exported tracks'
        : 'Exported $exported tracks ($skippedLocal local tracks skipped)';
  }

  /// Favoritos + todas las playlists, en un solo archivo (sirve de respaldo).
  static Future<String?> exportAll(
    AppDatabase appDb,
    SongDatabase songDb,
  ) async {
    // Favoritos se guarda de más nuevo a más viejo; en el archivo va al revés
    // para que al importar conserve el orden cronológico.
    final favs = (await songDb.getTracks(AppDatabase.favoritesId)).reversed
        .toList();

    final list = <PlaylistExport>[
      (title: 'Favorites', songs: favs, favorites: true),
    ];
    for (final p in await appDb.getPlaylists()) {
      list.add((
        title: p['title'] as String,
        songs: await songDb.getTracks(p['id'] as int),
        favorites: false,
      ));
    }
    return exportPlaylists(list, fileName: 'mimic_playlists.json');
  }

  // ───────────────────────── Importar ─────────────────────────

  static Future<String?> importFromPicker(
    AppDatabase appDb,
    SongDatabase songDb,
  ) async {
    // Sin filtro de extensión a propósito: los gestores de archivos y Drive
    // marcan los .json con tipos MIME distintos, y a veces los deshabilitan.
    // El contenido se valida de todos modos.
    final files = await FilePicker.pickFiles();
    if (files == null || files.isEmpty) return null; // canceló

    final bytes = await files.first.readAsBytes();
    return importBytes(bytes, appDb, songDb);
  }

  static Future<String> importBytes(
    Uint8List bytes,
    AppDatabase appDb,
    SongDatabase songDb,
  ) async {
    if (bytes.length > _maxBytes) return 'That file is too large';

    final Map<String, dynamic> doc;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> || decoded['format'] != _format) {
        throw const FormatException('not a playlist file');
      }
      doc = decoded;
    } catch (_) {
      return 'That file is not a Mimic playlist';
    }

    final version = doc['version'];
    if (version is! int || version > _version) {
      return 'That file was made by a newer version of the app';
    }

    final playlists = doc['playlists'];
    if (playlists is! List) return 'That file is not a Mimic playlist';

    var importedPlaylists = 0;
    var importedTracks = 0;
    var skipped = 0;

    for (final p in playlists) {
      if (p is! Map || p['tracks'] is! List) continue;

      final songs = <SongInfo>[];
      for (final t in p['tracks'] as List) {
        try {
          if (t is! Map) {
            skipped++;
            continue;
          }
          final m = Map<String, dynamic>.from(t);
          final id = m['id'];
          if (id is! String || id.startsWith('local_')) {
            skipped++;
            continue;
          }
          songs.add(SongInfoFromMap.fromMap(m));
        } catch (_) {
          skipped++; // fila dañada: se salta, no tumba la importación
        }
      }
      if (songs.isEmpty) continue;

      final int playlistId;
      if (p['favorites'] == true) {
        playlistId = AppDatabase.favoritesId; // se suma a tus favoritos
      } else {
        final title = (p['title'] as String?)?.trim() ?? '';
        playlistId = await appDb.createPlaylist(
          title.isEmpty ? 'Imported playlist' : title,
        );
      }

      await songDb.addManyTracks(songs, playlistId);
      importedPlaylists++;
      importedTracks += songs.length;
    }

    if (importedTracks == 0) return 'Nothing could be imported';

    final plural = importedPlaylists == 1 ? 'playlist' : 'playlists';
    return skipped == 0
        ? 'Imported $importedPlaylists $plural ($importedTracks tracks)'
        : 'Imported $importedPlaylists $plural ($importedTracks tracks, $skipped skipped)';
  }
}
