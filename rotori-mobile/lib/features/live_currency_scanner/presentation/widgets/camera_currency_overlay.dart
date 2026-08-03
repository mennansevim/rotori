import 'package:flutter/material.dart';

import '../../../viewer/viewer_theme.dart';
import '../../domain/currency_converter.dart';
import '../../domain/exchange_rate.dart';
import '../../domain/scanner_settings.dart';
import '../../domain/scanner_tuning.dart';
import '../../domain/tracked_price.dart';
import '../../infrastructure/camera/camera_coordinate_transformer.dart';
import 'currency_detection_label.dart';

/// İzlenen fiyatları kamera preview'i üzerine yerleştiren overlay katmanı.
///
/// Koordinat dönüşümü [CameraCoordinateTransformer] ile yapılır; en yüksek
/// güvenli [ScannerTuning.maxOverlays] etiket gösterilir, üst üste binenler
/// elenir, ekran kenarına taşanlar yön değiştirir.
class CameraCurrencyOverlay extends StatelessWidget {
  const CameraCurrencyOverlay({
    super.key,
    required this.tracks,
    required this.imageSize,
    required this.rotationDegrees,
    required this.mirrored,
    required this.rate,
    required this.settings,
    required this.palette,
    this.transformer = const CameraCoordinateTransformer(),
    this.converter = const CurrencyConverter(),
    this.onTap,
  });

  final List<TrackedPrice> tracks;
  final Size imageSize;
  final int rotationDegrees;
  final bool mirrored;
  final ExchangeRate? rate;
  final ScannerSettings settings;
  final ViewerPalette palette;
  final CameraCoordinateTransformer transformer;
  final CurrencyConverter converter;
  final void Function(TrackedPrice track)? onTap;

  @override
  Widget build(BuildContext context) {
    final activeRate = rate;
    if (activeRate == null || imageSize.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = Size(constraints.maxWidth, constraints.maxHeight);
        final ranked = [...tracks]
          ..sort((a, b) => b.price.confidence.compareTo(a.price.confidence));
        final shown = ranked.take(ScannerTuning.maxOverlays).toList();

        final placed = <Rect>[];
        final children = <Widget>[];

        for (final track in shown) {
          final screenBox = transformer.transform(
            sourceRect: track.smoothedBox,
            sourceImageSize: imageSize,
            previewSize: previewSize,
            rotationDegrees: rotationDegrees,
            mirrored: mirrored,
            fit: BoxFit.cover,
          );

          final conversion = converter.convert(
            amountInJpy: track.price.amountInJpy,
            rate: activeRate,
            settings: settings,
          );

          const labelH = 52.0;
          // Üstte yer yoksa altına yerleştir.
          final above = screenBox.top - labelH - 6;
          final top = above >= 0 ? above : screenBox.bottom + 6;
          var left = screenBox.left.clamp(4.0, previewSize.width - 140.0);

          final labelRect = Rect.fromLTWH(left, top, 140, labelH);
          if (placed.any((r) => r.overlaps(labelRect))) {
            continue; // üst üste binmeyi engelle
          }
          placed.add(labelRect);

          children.add(Positioned(
            left: left,
            top: top.clamp(0.0, previewSize.height - labelH),
            child: CurrencyDetectionLabel(
              amountInJpy: track.price.amountInJpy,
              converted: conversion.convertedAsDouble,
              targetCurrency: settings.targetCurrency,
              confidence: track.price.confidence,
              taxType: track.price.taxType,
              palette: palette,
              lowConfidenceThreshold: ScannerTuning.lowConfidenceThreshold,
              onTap: onTap == null ? null : () => onTap!(track),
            ),
          ));
        }

        return Stack(children: children);
      },
    );
  }
}
