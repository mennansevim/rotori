// "Plana ekle" — deneyim rehberinin plana yazma yolu.
//
// **Why ayrı dosya:** Akış (gün seçici + devralma + kalıcılaştırma) önce
// detay ekranının State'inin içindeydi, dolayısıyla yalnız orada
// çağrılabiliyordu. Aynı aksiyon artık rehber LİSTESİNDE de var; ortak yer
// tek kopya bırakıyor ve iki ekranı birbirine bağımlı kılmıyor.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/plans_repository.dart';
import '../../domain/experience_guides.dart';
import '../../domain/experience_plan.dart';
import '../../domain/localized_text.dart';
import '../../domain/types.dart';
import '../plans/plan_providers.dart';
import 'viewer_theme.dart';

/// Kompakt "Plana ekle" çipi — başlığın hizasında, satırın en sağında.
///
/// **Why tam genişlikte buton değil:** Aksiyon sayfanın EN ALTINDA dolu bir
/// FilledButton'dı; kullanıcı deneyimi eklemek için önce bütün rehberi
/// geçmek zorundaydı. Çip aksiyonu adının yanına koyar — ne yapacağı ile
/// neye yapacağı aynı satırda. Renk kartın geri kalanıyla aynı kuralda:
/// dolu değil, `@.11` alpha tint.
class ExperienceAddToPlanChip extends StatelessWidget {
  const ExperienceAddToPlanChip({
    super.key,
    required this.palette,
    required this.lang,
    required this.onTap,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final label = const LText('Plana ekle', 'Add to plan').of(lang);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: p.accent.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          borderRadius: BorderRadius.circular(100),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.playlist_add_rounded, size: 15, color: p.accent),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: p.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Plana ekle" akışı: gün seçtirir, seçilen günü deneyime ayırır.
///
/// **Why gün devralma:** USJ ve iki Disney 10–13 saat sürüyor.
/// `addHighlightsToPlan` bunları 09:00–20:00 arasındaki bir boşluğa
/// sığdırmaya çalışıp hepsini reddederdi. Tam günlük bir deneyimin
/// gerçeği günü kaplamasıdır.
Future<void> addExperienceToPlan({
  required BuildContext context,
  required WidgetRef ref,
  required Trip trip,
  required ExperienceGuide guide,
  required ViewerPalette palette,
  required AppLang lang,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  final options = experienceDayOptions(trip, guide);
  if (options.isEmpty) {
    messenger.showSnackBar(SnackBar(
      content: Text(
        lang == AppLang.tr
            ? '${guide.city} planında yok; bu deneyim için uygun gün bulunamadı.'
            : '${guide.city} is not in this plan; no suitable day found.',
      ),
    ));
    return;
  }

  final picked = await showModalBottomSheet<ExperienceDayOption>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => ViewerPaletteScope(
      palette: palette,
      child: _DayPickerSheet(
        options: options,
        guide: guide,
        palette: palette,
        lang: lang,
      ),
    ),
  );
  if (picked == null || !context.mounted) return;

  final result = applyExperienceToDay(
    trip: trip,
    guide: guide,
    dayNumber: picked.day.dayNumber,
    title: guide.title,
    description: guide.tagline.of(lang),
    durationText: guide.duration.of(lang),
  );
  if (result == null) return;

  // Kalıcılaştırma en iyi çabadır — başarısız olursa seçim ekranda durur ve
  // bir sonraki kayıtta senkronlanır.
  try {
    final repo = ref.read(plansRepositoryProvider);
    if (repo != null) {
      await repo.saveLocal(trip);
      unawaited(repo.save(trip).catchError((_) => null));
    }
    ref.read(draftTripProvider.notifier).state = trip;
  } on Object {
    // yut
  }

  if (!context.mounted) return;
  messenger.showSnackBar(SnackBar(
    content: Text(
      lang == AppLang.tr
          ? '${result.dayNumber}. gün ${guide.title} için ayrıldı'
              '${result.removed > 0 ? ' · ${result.removed} durak kaldırıldı' : ''}'
              '${result.keptLocked > 0 ? ' · ${result.keptLocked} kilitli durak korundu' : ''}'
          : 'Day ${result.dayNumber} is now ${guide.title}'
              '${result.removed > 0 ? ' · ${result.removed} stops removed' : ''}'
              '${result.keptLocked > 0 ? ' · ${result.keptLocked} locked kept' : ''}',
    ),
  ));
}

// ---------------------------------------------------------------------------
// Gün seçici
// ---------------------------------------------------------------------------

/// "Hangi güne eklensin?" sayfası.
///
/// Her satır o günün ne kaybedeceğini ÖNDEN söyler: kaç durak silinecek, kaç
/// kilitli durak korunacak. Kullanıcı sürprizle karşılaşmamalı.
class _DayPickerSheet extends StatelessWidget {
  const _DayPickerSheet({
    required this.options,
    required this.guide,
    required this.palette,
    required this.lang,
  });

  final List<ExperienceDayOption> options;
  final ExperienceGuide guide;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: BorderRadius.circular(22),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    const LText('Hangi güne eklensin?', 'Which day?').of(lang),
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    lang == AppLang.tr
                        ? 'Seçtiğin gün ${guide.title} için ayrılır.'
                        : 'The day you pick becomes ${guide.title}.',
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: Container(
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: p.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < options.length; i++) ...[
                        if (i > 0)
                          Divider(height: 1, color: p.border, indent: 16),
                        _DayOptionRow(
                          key: ValueKey(
                            'experience-day-${options[i].day.dayNumber}',
                          ),
                          option: options[i],
                          palette: p,
                          lang: lang,
                        ),
                      ],
                    ],
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

class _DayOptionRow extends StatelessWidget {
  const _DayOptionRow({
    super.key,
    required this.option,
    required this.palette,
    required this.lang,
  });

  final ExperienceDayOption option;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final day = option.day;

    final parts = <String>[option.city];
    if (option.replaceableCount > 0) {
      parts.add(lang == AppLang.tr
          ? '${option.replaceableCount} durak kaldırılacak'
          : '${option.replaceableCount} stops removed');
    } else {
      parts.add(lang == AppLang.tr ? 'gün boş' : 'day is free');
    }
    if (option.lockedCount > 0) {
      parts.add(lang == AppLang.tr
          ? '${option.lockedCount} kilitli korunur'
          : '${option.lockedCount} locked kept');
    }

    return Semantics(
      button: true,
      label: '${day.dayNumber}. ${parts.join('. ')}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(option),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          lang == AppLang.tr
                              ? '${day.dayNumber}. Gün'
                              : 'Day ${day.dayNumber}',
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          parts.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 11.5,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 21,
                    color: p.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
