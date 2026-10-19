import 'package:flutter/material.dart';

import 'Backend/settings.dart';

class AppColors {
  static AppTheme get _t => AppSettings.instance.palette.theme;

  // ── Dinámicos: cambian con la paleta elegida en Ajustes ──
  static Color get accent => _t.accent;
  static Color get accentTeammate => _t.onAccent;
  static Color get background => _t.background;
  static Color get surface => _t.surface;
  static Color get surface2 => _t.surface2;
  static Color get bordier => _t.bordier;
  static Color get bordierlight => _t.bordierlight;

  // ── Fijos (neutros, iguales en todas las paletas) ──
  static const text = Color(0xFFEDEFF4);
  static const text2 = Color(0xFFA0A8B8);
  static const text2disabled = Color(0xFF5C6473);
}
