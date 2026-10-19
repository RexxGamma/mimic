import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

/// Máximo de textos medidos que se guardan en caché.
const int _maxCacheEntries = 500;

/// Caché LRU: el primer elemento es el menos usado recientemente.
final LinkedHashMap<(String, TextStyle, TextScaler), double> _spanCache =
    LinkedHashMap();

/// Ancho (px lógicos) que ocupa [text] en una sola línea.
/// OJO: [style] debe ser el estilo EFECTIVO (ver [needsMarquee]); si le pasas
/// un estilo "crudo" mide menos de lo que realmente dibuja el Text.
double calculateSpan(
  String text,
  TextStyle style, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (text.isEmpty) return 0;

  final key = (text, style, textScaler);

  final cached = _spanCache.remove(key);
  if (cached != null) {
    _spanCache[key] = cached; // lo marcamos como recién usado
    return cached;
  }

  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  final width = painter.width;
  painter.dispose();

  if (_spanCache.length >= _maxCacheEntries) {
    _spanCache.remove(_spanCache.keys.first);
  }
  _spanCache[key] = width;
  return width;
}

void clearSpanCache() => _spanCache.clear();

/// Decide si [text] NO cabe en [maxWidth] y por lo tanto necesita marquee.
/// Mide con el mismo estilo y la misma escala de texto que usará el Text real.
bool needsMarquee(
  BuildContext context,
  String text,
  TextStyle style,
  double maxWidth,
) {
  if (!maxWidth.isFinite) return false;

  final effective = DefaultTextStyle.of(context).style.merge(style);
  final scaler = MediaQuery.textScalerOf(context);

  // -1 de margen: preferimos activar el marquee un pelín antes
  // a que el texto se corte o se parta.
  return calculateSpan(text, effective, textScaler: scaler) > maxWidth - 1;
}

/// Texto de UNA sola línea: si cabe se ve normal; si no cabe y [enabled] es
/// true, hace marquee; si [enabled] es false, corta con "...".
/// Nunca salta a una segunda línea.
class AutoMarquee extends StatelessWidget {
  const AutoMarquee({
    super.key,
    required this.text,
    required this.style,
    this.enabled = true,
  });

  final String text;
  final TextStyle style;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final lineHeight = (style.fontSize ?? 14) * 1.5;

    return LayoutBuilder(
      builder: (context, constraints) {
        final marquee =
            enabled && needsMarquee(context, text, style, constraints.maxWidth);

        // Altura fija en ambos casos para que el layout no salte.
        return SizedBox(
          height: lineHeight,
          child: marquee
              ? Marquee(
                  text: text,
                  style: style,
                  blankSpace: 50,
                  velocity: 30,
                  pauseAfterRound: const Duration(seconds: 2),
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    style: style,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
        );
      },
    );
  }
}

