import 'dart:io';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import 'metadatamanager.dart';
import 'settings.dart';
import 'songdata.dart';

/// Escucha la canción actual y, si la paleta Adaptive está activa,
/// saca un color representativo del banner y se lo pasa a AppSettings.
class AdaptiveTheme {
  AdaptiveTheme._();

  static final Map<String, Color> _seedCache = {};
  static String? _lastId;
  static int _run = 0;

  /// Llamar una vez en main, después de AppSettings.instance.load().
  static void init() {
    Metadatamanager.instance.addListener(_update);
    AppSettings.instance.addListener(_update);
    _update();
  }

  /// Banner de la canción: archivo local si existe, si no la miniatura de red.
  /// Null si no tiene ninguna (por ejemplo, una canción local sin portada).
  static ImageProvider? bannerProvider(SongInfo song) {
    final local = song.downloadBannerPath;
    if (local != null && File(local).existsSync()) {
      return FileImage(File(local));
    }
    if (song.thumbnails.isEmpty) return null;
    final i = song.thumbnails.length > 3 ? 3 : song.thumbnails.length - 1;
    final url = song.thumbnails[i].url;
    return url.isEmpty ? null : NetworkImage(url);
  }

  static Future<void> _update() async {
    if (!AppSettings.instance.palette.adaptive) return;

    final song = Metadatamanager.instance.currentSong;
    if (song == null || song.id == _lastId) return;
    _lastId = song.id;

    final run = ++_run;
    final seed = await _seedFor(song);
    if (seed == null || run != _run)
      return; // otra canción llegó mientras tanto

    await AppSettings.instance.setAdaptiveSeed(seed);
  }

  static Future<Color?> _seedFor(SongInfo song) async {
    final cached = _seedCache[song.id];
    if (cached != null) return cached;

    final provider = bannerProvider(song);
    if (provider == null) return null;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(
          provider,
          width: 128,
        ), // con 128 px sobra para sacar colores
        maximumColorCount: 24,
        filters: const <PaletteFilter>[], // sin filtros: el default descarta negros, blancos y tonos piel
      );
      final seed = _pickSeed(palette);
      if (seed != null) {
        _seedCache[song.id] = seed;
        if (_seedCache.length > 200) _seedCache.remove(_seedCache.keys.first);
      }
      return seed;
    } catch (e) {
      debugPrint(
        'AdaptiveTheme: no se pudo leer el banner de ${song.name} -> $e',
      );
      return null;
    }
  }

  /// Elige el color que mejor representa a la portada: el que más pesa,
  /// favoreciendo los vivos sobre los apagados.
  static Color? _pickSeed(PaletteGenerator p) {
    final colors = p.paletteColors;
    if (colors.isEmpty) return null;

    final total = colors.fold<int>(0, (sum, c) => sum + c.population);
    if (total == 0) return null;

    Color? best;
    var bestScore = 0.0;
    for (final c in colors) {
      final hsl = HSLColor.fromColor(c.color);
      // Casi negro y casi blanco no le dan carácter a un tema
      if (hsl.lightness < 0.12 || hsl.lightness > 0.92) continue;

      final share = c.population / total;
      final score = share * (0.3 + hsl.saturation);
      if (score > bestScore) {
        bestScore = score;
        best = c.color;
      }
    }

    // Portada casi toda negra o blanca: un gris, que dispara el tema neutral
    return best ?? const Color(0xFF9E9E9E);
  }
}
