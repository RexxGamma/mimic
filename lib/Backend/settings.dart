import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adaptivepalette.dart';
import 'providers/privdersenums.dart'; // metadataprovider

/// Colores de la app para una paleta. Todos los tonos de fondo y el acento
/// salen de aquí; los textos son fijos y viven en AppColors.
class AppTheme {
  const AppTheme({
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.surface,
    required this.surface2,
    required this.bordier,
    required this.bordierlight,
  });

  final Color accent;
  final Color onAccent;
  final Color background;
  final Color surface;
  final Color surface2;
  final Color bordier;
  final Color bordierlight;

  static const original = AppTheme(
    accent: Color(0xFFFF5C8A),
    onAccent: Color(0xFF2A1822),
    background: Color(0xFF161A22),
    surface: Color(0xFF0F1218),
    surface2: Color(0xFF141821),
    bordier: Color(0xFF1A1F29),
    bordierlight: Color(0xFF20252F),
  );

  /// Blanco y negro: fondo negro puro (ideal para pantallas OLED) y acento blanco.
  static const monochrome = AppTheme(
    accent: Color(0xFFFFFFFF),
    onAccent: Color(0xFF000000),
    background: Color(0xFF000000),
    surface: Color(0xFF000000),
    surface2: Color(0xFF0B0B0B),
    bordier: Color(0xFF151515),
    bordierlight: Color(0xFF242424),
  );

  factory AppTheme.fromScheme(ColorScheme s) {
    return AppTheme(
      accent: s.primary,
      onAccent: s.onPrimary,
      background: s.surfaceContainerLow,
      surface: s.surfaceContainerLowest,
      surface2: s.surface,
      bordier: s.surfaceContainer,
      bordierlight: s.surfaceContainerHigh,
    );
  }

  factory AppTheme.fromSeed(Color seed) => AppTheme.fromScheme(
    ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
  );

  /// Para la paleta adaptativa. Si el color es casi gris (una portada en
  /// blanco y negro), usa la variante neutral; si no, el tema se teñiría
  /// de un tono que la portada no tiene.
  factory AppTheme.fromAdaptiveSeed(Color seed) {
    final gray = HSLColor.fromColor(seed).saturation < 0.15;
    return AppTheme.fromScheme(
      ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        dynamicSchemeVariant: gray
            ? DynamicSchemeVariant.neutral
            : DynamicSchemeVariant.tonalSpot,
      ),
    );
  }
}

class AppPalette {
  AppPalette(
    this.id,
    this.name, {
    Color? seed,
    AppTheme? fixed,
    this.adaptive = false,
  }) : _seed = seed,
       _fixed = fixed;

  final String id;
  final String name;
  final bool adaptive;
  final Color? _seed;
  final AppTheme? _fixed;

  late final AppTheme _static =
      _fixed ?? (_seed == null ? AppTheme.original : AppTheme.fromSeed(_seed!));

  /// La adaptativa cambia con el banner; las demás son fijas.
  AppTheme get theme => adaptive
      ? (AppSettings.instance.adaptiveTheme ?? AppTheme.original)
      : _static;
}

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kSaveHistory = 'set_save_search_history';
  static const _kLyrics = 'set_show_lyrics';
  static const _kConcurrency = 'set_download_concurrency';
  static const _kPalette = 'set_color_palette';
  static const _kCrossfade = 'set_crossfade_seconds';
  static const _kDefaultMetadata = 'set_default_metadata_provider';

  // ── Fondo del reproductor ─────────────────────────────
  static const _kBlurBg = 'set_player_blur_background';
  static const _kLargeBannerBg = 'set_player_large_banner_background';
  Color? adaptiveSeed;
  AppTheme? adaptiveTheme;
  static const _kAdaptiveSeed = 'set_adaptive_seed';

  static final List<AppPalette> palettes = [
    AppPalette('original', 'Original'),
    AppPalette('blue', 'Blue', seed: Colors.blue),
    AppPalette('orange', 'Orange', seed: Colors.orange),
    AppPalette('purple', 'Purple', seed: Colors.purple),
    AppPalette('pink', 'Pink', seed: Colors.pink),
    AppPalette('red', 'Red', seed: Colors.red),
    AppPalette('brown', 'Brown', seed: Colors.brown),
    AppPalette('amber', 'Amber', seed: Colors.amber),
    AppPalette('yellow', 'Yellow', seed: Colors.yellow),
    AppPalette('lime', 'Lime', seed: Colors.lime),
    AppPalette('lightGreen', 'Light green', seed: Colors.lightGreen),
    AppPalette('green', 'Green', seed: Colors.green),
    AppPalette('teal', 'Teal', seed: Colors.teal),
    AppPalette('cyan', 'Cyan', seed: Colors.cyan),
    AppPalette('lightBlue', 'Light blue', seed: Colors.lightBlue),
    AppPalette('indigo', 'Indigo', seed: Colors.indigo),
    AppPalette('deepPurple', 'Deep purple', seed: Colors.deepPurple),
    AppPalette('mono', 'B&W', fixed: AppTheme.monochrome),
    AppPalette('adaptive', 'Adaptive', adaptive: true),
  ];

  AppPalette palette = palettes.first;
  bool saveSearchHistory = true;
  bool showLyrics = true;
  int downloadConcurrency = 2;
  int crossfadeSeconds = 0;
  metadataprovider defaultMetadataProvider = metadataprovider.deezer;

  // ── Fondos del reproductor ────────────────────────────
  /// Banner desenfocado a pantalla completa detrás del reproductor.
  bool playerBlurBackground = true;

  /// Banner grande a sangre entre el header y el nombre del track.
  bool playerLargeBannerBackground = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    saveSearchHistory = p.getBool(_kSaveHistory) ?? true;
    showLyrics = p.getBool(_kLyrics) ?? true;
    downloadConcurrency = (p.getInt(_kConcurrency) ?? 2).clamp(1, 3).toInt();
    crossfadeSeconds = (p.getInt(_kCrossfade) ?? 0).clamp(0, 12).toInt();

    playerBlurBackground = p.getBool(_kBlurBg) ?? true;
    playerLargeBannerBackground = p.getBool(_kLargeBannerBg) ?? false;

    final id = p.getString(_kPalette);
    palette = palettes.firstWhere(
      (x) => x.id == id,
      orElse: () => palettes.first,
    );

    final providerName = p.getString(_kDefaultMetadata);
    defaultMetadataProvider = metadataprovider.values.firstWhere(
      (e) => e.name == providerName,
      orElse: () => metadataprovider.deezer,
    );

    notifyListeners();
  }

  Future<void> setSaveSearchHistory(bool v) async {
    saveSearchHistory = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSaveHistory, v);
  }

  Future<void> setShowLyrics(bool v) async {
    showLyrics = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kLyrics, v);
  }

  Future<void> setDownloadConcurrency(int v) async {
    downloadConcurrency = v.clamp(1, 3).toInt();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kConcurrency, downloadConcurrency);
  }

  Future<void> setCrossfadeSeconds(int v) async {
    crossfadeSeconds = v.clamp(0, 12).toInt();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCrossfade, crossfadeSeconds);
  }

  Future<void> setDefaultMetadataProvider(metadataprovider v) async {
    defaultMetadataProvider = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDefaultMetadata, v.name);
  }

  // ── Setters de fondos del reproductor ─────────────────
  Future<void> setPlayerBlurBackground(bool v) async {
    if (playerBlurBackground == v) return;
    playerBlurBackground = v;
    notifyListeners();
    _rebuildApp();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBlurBg, v);
  }

  Future<void> setPlayerLargeBannerBackground(bool v) async {
    if (playerLargeBannerBackground == v) return;
    playerLargeBannerBackground = v;
    notifyListeners();
    _rebuildApp();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kLargeBannerBg, v);
  }

  /// Lo llama AdaptiveTheme cuando cambia el banner de la canción.
  Future<void> setAdaptiveSeed(Color seed) async {
    if (adaptiveSeed?.toARGB32() == seed.toARGB32())
      return; // mismo color: nada que hacer
    adaptiveSeed = seed;
    adaptiveTheme = AppTheme.fromAdaptiveSeed(seed);

    if (palette.adaptive) {
      notifyListeners();
      _rebuildApp();
    }
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kAdaptiveSeed, seed.toARGB32());
  }

  Future<void> setPalette(AppPalette v) async {
    if (v.id == palette.id) return;
    palette = v;
    notifyListeners();
    _rebuildApp();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPalette, v.id);
  }

  void _rebuildApp() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(mark);
  }
}
