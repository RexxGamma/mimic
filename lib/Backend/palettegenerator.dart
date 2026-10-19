import 'package:flutter/material.dart';

class ColorContraste {
  static const double _deltaVariante = 0.18; // qué tan separadas quedan claro/oscuro entre sí

  static Color claro(Color fondo, {double contrasteMinimo = 4.5}) {
    return _generarPar(fondo, contrasteMinimo).claro;
  }

  static Color oscuro(Color fondo, {double contrasteMinimo = 4.5}) {
    return _generarPar(fondo, contrasteMinimo).oscuro;
  }

  static _Par _generarPar(Color fondo, double contrasteMinimo) {
    final candidatoClaro = _empujar(fondo, 1.0, contrasteMinimo);
    final candidatoOscuro = _empujar(fondo, -1.0, contrasteMinimo);

    final claroOk = _contraste(candidatoClaro, fondo) >= contrasteMinimo;
    final oscuroOk = _contraste(candidatoOscuro, fondo) >= contrasteMinimo;

    if (claroOk && oscuroOk) {
      // fondo "normal": ambos funcionan de forma independiente
      return _Par(candidatoClaro, candidatoOscuro);
    }

    if (claroOk && !oscuroOk) {
      // fondo muy oscuro: no hay margen para un oscuro real →
      // el oscuro pasa a ser una variante MÁS OSCURA del claro, no del negro
      return _Par(candidatoClaro, _oscurecer(candidatoClaro, _deltaVariante));
    }

    if (!claroOk && oscuroOk) {
      // fondo muy claro: simétrico → el claro es una variante MÁS CLARA del oscuro
      return _Par(_aclarar(candidatoOscuro, _deltaVariante), candidatoOscuro);
    }

    // caso extremo raro (fondo gris medio sin margen en ninguna dirección)
    return _Par(Colors.white, Colors.black);
  }

  static Color _aclarar(Color color, double delta) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
  }

  static Color _oscurecer(Color color, double delta) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness - delta).clamp(0.0, 1.0)).toColor();
  }

  static Color _empujar(Color base, double direccion, double contrasteMinimo) {
    final hsl = HSLColor.fromColor(base);
    double lightness = hsl.lightness;
    Color candidato = hsl.toColor();

    const paso = 0.03;
    while (_contraste(candidato, base) < contrasteMinimo &&
        lightness > 0.0 &&
        lightness < 1.0) {
      lightness = (lightness + direccion * paso).clamp(0.0, 1.0);
      candidato = hsl.withLightness(lightness).toColor();
    }
    return candidato;
  }

  static double _contraste(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final claro = l1 > l2 ? l1 : l2;
    final oscuro = l1 > l2 ? l2 : l1;
    return (claro + 0.05) / (oscuro + 0.05);
  }
}

class _Par {
  final Color claro;
  final Color oscuro;
  _Par(this.claro, this.oscuro);
}