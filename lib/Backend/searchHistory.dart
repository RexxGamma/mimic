import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Historial de búsquedas guardado en disco (más reciente primero).
class SearchHistory {
  static const _key = 'search_history';
  static const int maxItems = 15;

  /// Sube cada vez que el historial se borra desde fuera del buscador
  /// (por ejemplo, desde Ajustes) para que el buscador lo recargue.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.from(prefs.getStringList(_key) ?? const []);
  }

  static Future<void> save(List<String> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, items);
  }

  /// Borra todo y avisa al buscador (vía [revision]) para que se recargue.
  static Future<void> clear() async {
    await save(<String>[]);
    revision.value++;
  }

  /// Lista nueva con [query] al inicio, sin duplicados (ignora mayúsculas)
  /// y recortada a [maxItems].
  static List<String> withQuery(List<String> current, String query) {
    final q = query.trim();
    if (q.isEmpty) return current;

    final next = current
        .where((e) => e.toLowerCase() != q.toLowerCase())
        .toList();
    next.insert(0, q);
    return next.length > maxItems ? next.sublist(0, maxItems) : next;
  }

  static List<String> without(List<String> current, String query) =>
      current.where((e) => e != query).toList();
}
