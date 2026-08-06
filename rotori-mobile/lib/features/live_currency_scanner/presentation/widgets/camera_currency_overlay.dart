import 'dart:math' as math;

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

          // AR yerinde çeviri: etiketi tam algılanan fiyat kutusunun ÜZERİNE
          // yerleştir; opak zemin orijinal ¥ metnini örter, böylece kamera
          // canlı görüntüde fiyat sanki TL yazıyormuş gibi görünür.
          final w = screenBox.width.clamp(56.0, previewSize.width).toDouble();
          final h = screenBox.height.clamp(24.0, 140.0).toDouble();
          final left = screenBox.left
              .clamp(0.0, math.max(0.0, previewSize.width - w))
              .toDouble();
          final top = screenBox.top
              .clamp(0.0, math.max(0.0, previewSize.height - h))
              .toDouble();

          final labelRect = Rect.fromLTWH(left, top, w, h);
          if (placed.any((r) => r.overlaps(labelRect))) {
            continue; // üst üste binmeyi engelle
          }
          placed.add(labelRect);

          children.add(Positioned(
            left: left,
            top: top,
            width: w,
            height: h,
            child: CurrencyDetectionLabel(
              inPlace: true,
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
