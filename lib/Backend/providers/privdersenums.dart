import 'package:flutter/material.dart';

enum metadataprovider {
  deezer('Deezer', Color(0xFF9B7BFF)),
  soundcloud('SoundCloud', Color(0xFFFF7A3A)),
  itunes('iTunes', Color(0xFFFC3C44)),
  musicbrainz('MusicBrainz', Color(0xFFBA478F)),
  local('Device', Color(0xFF4DB6AC));

  const metadataprovider(this.label, this.color);
  final String label;
  final Color color;

  /// Las fuentes que el usuario puede elegir (excluye "local").
  static List<metadataprovider> get selectable =>
      values.where((p) => p != local).toList();
}

enum StreamingProvider {
  youtube('YouTube', Color(0xFFFF0033)),
  soundcloud('SoundCloud', Color(0xFFFF7A3A)),
  local('Local file', Color(0xFF4DB6AC));

  const StreamingProvider(this.label, this.color);
  final String label;
  final Color color;

  static List<StreamingProvider> get selectable =>
      values.where((p) => p != local).toList();
}
