// Deneyim rehberlerinin görsel kimliği: ikon + ton.
//
// **Why UI katmanında:** `IconData` ve `Color` Flutter tipleri. Bunları
// `domain/experience_guides.dart` içine koymak saf katalog dosyasına
// `material.dart` import ettirirdi.
//
// **Why emoji değil:** Altı rehberin tamamı 40–48px emoji ile ayrışıyordu
// (🎢 🏰 🌊 💧 ✨ 🌿). Emoji platformdan platforma değişir, ton alamaz,
// tema paletine uymaz ve rozet içinde yer paylaşımı tutarsız durur.
//
// İkon seçimleri `reminders/reminder_composer_sheet.dart` `_presetIcon` ile
// bilinçli olarak aynı: aynı deneyim iki ekranda aynı ikonla görünsün.

import 'package:flutter/material.dart';

import '../../domain/experience_guides.dart';
import 'viewer_theme.dart';

/// Bir rehberin ikonu ve tonu.
typedef ExperienceVisual = ({IconData icon, Color tone});

/// [guide] için ikon + ton döndürür.
///
/// Bilinmeyen id (katalog büyürse) [ExperienceGuideKind] üzerinden makul bir
/// varsayılana düşer — ekran asla ikonsuz kalmaz.
ExperienceVisual experienceVisual(ExperienceGuide guide, ViewerPalette p) {
  return switch (guide.id) {
    'usj' => (icon: Icons.attractions_rounded, tone: p.sunset),
    'disneyland' => (icon: Icons.castle_rounded, tone: p.fuji),
    'disneysea' => (icon: Icons.sailing_rounded, tone: p.sky),
    'teamlab-planets' => (icon: Icons.water_drop_rounded, tone: p.sky),
    'teamlab-borderless' => (icon: Icons.auto_awesome_rounded, tone: p.fuji),
    'teamlab-botanical' => (icon: Icons.local_florist_rounded, tone: p.matcha),
    _ => switch (guide.kind) {
        ExperienceGuideKind.themePark => (
            icon: Icons.attractions_rounded,
            tone: p.sunset,
          ),
        ExperienceGuideKind.digitalArt => (
            icon: Icons.auto_awesome_rounded,
            tone: p.fuji,
          ),
      },
  };
}
