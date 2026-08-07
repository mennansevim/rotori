import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/l10n.dart';
import '../../../viewer/viewer_theme.dart';
import '../../domain/currency_converter.dart';
import '../../domain/exchange_rate.dart';
import '../../domain/product_price_query.dart';
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
    this.queryCandidate,
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
  final ProductQueryCandidate? queryCandidate;
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
        final previewCenter = Offset(previewSize.width / 2, previewSize.height / 2);
        final candidates = <_OverlayCandidate>[];

        for (final track in tracks) {
          final screenBox = transformer.transform(
            sourceRect: track.smoothedBox,
            sourceImageSize: imageSize,
            previewSize: previewSize,
            rotationDegrees: rotationDegrees,
            mirrored: mirrored,
            fit: BoxFit.cover,
          );
          final score = _rankScore(
            track: track,
            screenBox: screenBox,
            previewSize: previewSize,
            previewCenter: previewCenter,
          );
          candidates.add(_OverlayCandidate(
            track: track,
            screenBox: screenBox,
            score: score,
          ));
        }

        candidates.sort((a, b) => b.score.compareTo(a.score));

        final visibleLimit = math.min(4, ScannerTuning.maxOverlays);
        final shown = candidates.take(visibleLimit).toList();

        final placed = <Rect>[];
        final children = <Widget>[];
        final previewBounds = Offset.zero & previewSize;

        final candidate = queryCandidate;
        if (candidate != null) {
          final queryBox = transformer.transform(
            sourceRect: candidate.boundingBox,
            sourceImageSize: imageSize,
            previewSize: previewSize,
            rotationDegrees: rotationDegrees,
            mirrored: mirrored,
            fit: BoxFit.cover,
          );
          final clipped = queryBox.intersect(previewBounds.deflate(2));
          if (!clipped.isEmpty && clipped.width > 10 && clipped.height > 10) {
            children.add(
              _QueryHighlightFrame(
                box: clipped,
                confidence: candidate.confidence,
                palette: palette,
              ),
            );
          }
        }

        for (final candidate in shown) {
          final track = candidate.track;
          final screenBox = candidate.screenBox;
          final emphasis = candidate.score.clamp(0.0, 1.0);

          final conversion = converter.convert(
            amountInJpy: track.price.amountInJpy,
            rate: activeRate,
            settings: settings,
          );

          final labelWidth = (screenBox.width * 1.34)
              .clamp(128.0, math.min(192.0, previewSize.width - 16))
              .toDouble();
          const labelHeight = 84.0;
          final placement = _pickPlacement(
            screenBox: screenBox,
            labelSize: Size(labelWidth, labelHeight),
            previewBounds: previewBounds,
            placed: placed,
          );
          if (placement == null) {
            continue;
          }
          placed.add(placement);

          final connector = _buildConnector(
            source: screenBox,
            target: placement,
            color: palette.accent.withValues(
              alpha: 0.18 + (0.46 * emphasis),
            ),
          );
          if (connector != null) {
            children.add(connector);
          }

          children.add(AnimatedPositioned(
            key: ValueKey<String>('label-${track.id}'),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: placement.left,
            top: placement.top,
            width: placement.width,
            height: placement.height,
            child: _AnimatedOverlayEntry(
              emphasis: emphasis,
              child: CurrencyDetectionLabel(
                amountInJpy: track.price.amountInJpy,
                converted: conversion.convertedAsDouble,
                exchangeRate: activeRate.rate.toDouble(),
                targetCurrency: settings.targetCurrency,
                confidence: track.price.confidence,
                taxType: track.price.taxType,
                palette: palette,
                lowConfidenceThreshold: ScannerTuning.lowConfidenceThreshold,
                onTap: onTap == null ? null : () => onTap!(track),
              ),
            ),
          ));
        }

        return Stack(children: children);
      },
    );
  }

  double _rankScore({
    required TrackedPrice track,
    required Rect screenBox,
    required Size previewSize,
    required Offset previewCenter,
  }) {
    final confidence = track.price.confidence.clamp(0.0, 1.0);
    final stability = (track.seenCount / 6).clamp(0.0, 1.0).toDouble();

    final dx = screenBox.center.dx - previewCenter.dx;
    final dy = screenBox.center.dy - previewCenter.dy;
    final distance = math.sqrt((dx * dx) + (dy * dy));
    final maxDistance = math.sqrt(
      (previewSize.width * previewSize.width) +
          (previewSize.height * previewSize.height),
    );
    final centerFocus = (1 - (distance / (maxDistance * 0.5))).clamp(0.0, 1.0);

    final areaRatio = (screenBox.width * screenBox.height) /
        math.max(1.0, previewSize.width * previewSize.height);
    final sizeSignal = (areaRatio * 10).clamp(0.0, 1.0);

    return (confidence * 0.58) +
        (stability * 0.24) +
        (centerFocus * 0.14) +
        (sizeSignal * 0.04);
  }

  Rect? _pickPlacement({
    required Rect screenBox,
    required Size labelSize,
    required Rect previewBounds,
    required List<Rect> placed,
  }) {
    const gap = 8.0;
    const sideGap = 10.0;
    final w = labelSize.width;
    final h = labelSize.height;

    final candidates = <Rect>[
      Rect.fromLTWH(screenBox.left - 4, screenBox.bottom + gap, w, h),
      Rect.fromLTWH(screenBox.left - 4, screenBox.top - h - gap, w, h),
      Rect.fromLTWH(screenBox.right + sideGap, screenBox.center.dy - h / 2, w, h),
      Rect.fromLTWH(screenBox.left - w - sideGap, screenBox.center.dy - h / 2, w, h),
    ];

    for (final candidate in candidates) {
      if (_fitsInside(candidate, previewBounds) &&
          placed.every((p) => !p.overlaps(candidate))) {
        return candidate;
      }
    }

    final clamped = _clampToBounds(candidates.first, previewBounds);
    if (placed.any((p) => p.overlaps(clamped))) {
      return null;
    }
    return clamped;
  }

  bool _fitsInside(Rect rect, Rect bounds) {
    return rect.left >= bounds.left &&
        rect.top >= bounds.top &&
        rect.right <= bounds.right &&
        rect.bottom <= bounds.bottom;
  }

  Rect _clampToBounds(Rect rect, Rect bounds) {
    final left = rect.left.clamp(bounds.left, bounds.right - rect.width);
    final top = rect.top.clamp(bounds.top, bounds.bottom - rect.height);
    return Rect.fromLTWH(left.toDouble(), top.toDouble(), rect.width, rect.height);
  }

  Widget? _buildConnector({
    required Rect source,
    required Rect target,
    required Color color,
  }) {
    final from = source.center;
    final to = target.center;
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < 24) return null;

    final angle = math.atan2(dy, dx);
    final length = math.min(distance - 18, 52.0);
    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);

    return Positioned(
      left: mid.dx - length / 2,
      top: mid.dy - 0.9,
      width: length,
      height: 1.8,
      child: Transform.rotate(
        angle: angle,
        alignment: Alignment.center,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.0),
                color,
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QueryHighlightFrame extends StatelessWidget {
  const _QueryHighlightFrame({
    required this.box,
    required this.confidence,
    required this.palette,
  });

  final Rect box;
  final double confidence;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final accent = palette.accent.withValues(
      alpha: (0.68 + (confidence * 0.24)).clamp(0.68, 0.92).toDouble(),
    );
    return Positioned.fromRect(
      rect: box,
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent, width: 2.2),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.34),
                    blurRadius: 20,
                    spreadRadius: 0.6,
                  ),
                ],
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.12),
                    accent.withValues(alpha: 0.03),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: -14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withValues(alpha: 0.88)),
                ),
                child: Text(
                  s.s('scanner.market.queryReadyBadge'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayCandidate {
  const _OverlayCandidate({
    required this.track,
    required this.screenBox,
    required this.score,
  });

  final TrackedPrice track;
  final Rect screenBox;
  final double score;
}

class _AnimatedOverlayEntry extends StatelessWidget {
  const _AnimatedOverlayEntry({
    required this.child,
    required this.emphasis,
  });

  final Widget child;
  final double emphasis;

  @override
  Widget build(BuildContext context) {
    final fadeTarget = (0.74 + (0.26 * emphasis)).clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) {
        final opacity = fadeTarget * (0.58 + (0.42 * t));
        final scale = 0.965 + (0.035 * t);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}
