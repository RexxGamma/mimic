import 'package:flutter/material.dart';

import 'dart:math' as math;
import 'dart:ui' show PathOperation;

class RoundedRectThumbShape extends SliderComponentShape {
  const RoundedRectThumbShape({
    this.width = 21,
    this.height = 30,
    this.pressedHeight = 33,
    this.radius = 60,
    this.elevation = 2.0,
    this.pressedElevation = 5.0,
  });

  final double width;
  final double height;
  final double pressedHeight;
  final double radius;
  final double elevation;
  final double pressedElevation;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(
      width + pressedElevation * 2,
      pressedHeight + pressedElevation * 2,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    final double t = activationAnimation.value.clamp(0.0, 1.0);
    final double enabled = enableAnimation.value.clamp(0.0, 1.0);

    final double w = width;
    final double h = height + (pressedHeight - height) * t;

    if (w <= 0 || h <= 0 || !w.isFinite || !h.isFinite || enabled <= 0) {
      return;
    }

    final Color baseColor =
        sliderTheme.thumbColor ??
        sliderTheme.activeTrackColor ??
        const Color(0xFF6750A4);
    final int alpha = (baseColor.alpha * enabled).round().clamp(0, 255);
    final Color color = baseColor.withAlpha(alpha);

    final double currentElevation =
        (elevation + (pressedElevation - elevation) * t).clamp(0.0, 24.0);

    final RRect rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      Radius.circular(radius),
    );

    if (currentElevation > 0.01) {
      final int shadowAlpha = (0.22 * 255 * enabled).round().clamp(0, 255);
      canvas.drawRRect(
        rect.shift(Offset(0, currentElevation / 2)),
        Paint()
          ..color = Color.fromARGB(shadowAlpha, 0, 0, 0)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, currentElevation),
      );
    }

    canvas.drawRRect(
      rect,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }
}

class GappedRectSliderTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  const GappedRectSliderTrackShape({
    this.trackCornerRadius = 3.0,
    this.gapHorizontalPadding = 3.0,
    this.gapVerticalPadding = 3.0,
    required this.thumbWidth,
    required this.thumbHeight,
  });

  final double trackCornerRadius;
  final double gapHorizontalPadding;
  final double gapVerticalPadding;
  final double thumbWidth;
  final double thumbHeight;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final Canvas canvas = context.canvas;

    final Paint activePaint = Paint()
      ..color = Color.lerp(
        sliderTheme.disabledActiveTrackColor,
        sliderTheme.activeTrackColor,
        enableAnimation.value,
      )!;
    final Paint inactivePaint = Paint()
      ..color = Color.lerp(
        sliderTheme.disabledInactiveTrackColor,
        sliderTheme.inactiveTrackColor,
        enableAnimation.value,
      )!;

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final double trackHeight = trackRect.height;
    final double centerY = trackRect.center.dy;

    final double thumbDx = thumbCenter.dx.clamp(
      trackRect.left,
      trackRect.right,
    );
    final bool isRtl = textDirection == TextDirection.rtl;

    final Rect activeRect = isRtl
        ? Rect.fromLTRB(
            thumbDx,
            centerY - trackHeight / 2,
            trackRect.right,
            centerY + trackHeight / 2,
          )
        : Rect.fromLTRB(
            trackRect.left,
            centerY - trackHeight / 2,
            thumbDx,
            centerY + trackHeight / 2,
          );

    final Rect gapRect = Rect.fromCenter(
      center: Offset(thumbCenter.dx, centerY),
      width: thumbWidth + gapHorizontalPadding * 2,
      height: math.max(thumbHeight + gapVerticalPadding * 2, trackHeight),
    );

    // 1) Construimos un clip que EXCLUYE el gapRect.
    //    - Rect grande que cubre todo el track.
    //    - RRect del hueco dentro.
    //    - evenOdd → todo lo que esté DENTRO del hueco queda FUERA del clip.
    canvas.save();
    final Path clipPath = Path()
      ..addRect(trackRect.inflate(100))
      ..addRRect(
        RRect.fromRectAndRadius(
          gapRect,
          Radius.circular(gapRect.shortestSide / 2),
        ),
      )
      ..fillType = PathFillType.evenOdd;
    canvas.clipPath(clipPath);

    // 2) Track inactivo completo (el clip le recorta el hueco).
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, Radius.circular(trackCornerRadius)),
      inactivePaint,
    );

    // 3) Track activo (mitad izquierda). El clip también le recorta el hueco,
    //    así que ya no aparece la franja accent en el lado derecho del thumb.
    if (activeRect.width > 0.01) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, Radius.circular(trackCornerRadius)),
        activePaint,
      );
    }

    canvas.restore();
  }
}
