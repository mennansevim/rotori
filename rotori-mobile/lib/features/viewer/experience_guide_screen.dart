// Eğlence rehberi — indeks.
//
// **Neden yeniden yazıldı:** Eski ekran tek sayfada 1317 satırdı; 324px'lik
// bir hero ilk ekranın %40'ını yiyor, altında dört satırlık yasal uyarı
// kartı geliyor ve içeriğe ancak bir posteri geçtikten sonra ulaşılıyordu.
// Seçili rehber doygun kırmızı bir blok, özet kartı ayrı bir kırmızı
// gradyandı; hero'nunkiyle birlikte üç kırmızı yarışıyordu. Hiç `Semantics`
// yoktu.
//
// **Neden aciliyete göre sıralı:** Liste "tema parkı / dijital sanat" diye
// bölününce kullanıcının asıl sorusunu ("şimdi ne yapmam lazım") cevapsız
// bırakıyordu. Artık gruplar bilet penceresinden geliyor (bkz.
// experience_urgency.dart) ve liste kendisi bir yapılacaklar sırası.
//
// Yüzeyler nötr, renk sadece 38px ikon rozetinde `@.11` alpha ile —
// uygulamanın drawer'da belgelenmiş deseni.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/language_store.dart';
import '../../domain/experience_guides.dart';
import '../../domain/types.dart';
import '../../domain/localized_text.dart';
import '../plans/premium_provider.dart';
import '../reminders/reminder_composer_sheet.dart';
import 'experience_add_to_plan.dart';
import 'experience_detail_screen.dart';
import 'experience_urgency.dart';
import 'experience_visuals.dart';
import 'viewer_theme.dart';

class ExperienceGuideScreen extends ConsumerWidget {
  const ExperienceGuideScreen({super.key, this.trip});

  /// Açık plan. null ise ekran plan bağlamı olmadan açılmıştır ve detayda
  /// "Plana ekle" gösterilmez — çalışmayan bir buton göstermektense hiç
  /// göstermemek doğru.
  final Trip? trip;

  void _openDetail(
    BuildContext context,
    ViewerPalette palette,
    ExperienceGuide guide,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: ExperienceDetailScreen(guide: guide, trip: trip),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(viewerPaletteProvider);
    final lang = ref.watch(appLangProvider);
    final isPremium = ref.watch(premiumProvider);
    final groups = groupExperiencesByUrgency();

    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(
            backgroundColor: palette.card,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: const BackButton(),
            title: Text(
              const LText('Eğlence rehberi', 'Adventure guide').of(lang),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(height: 20),
                _UrgencyHeader(
                  key: ValueKey(
                    'experience-section-${groups[i].urgency.name}',
                  ),
                  urgency: groups[i].urgency,
                  palette: palette,
                  lang: lang,
                ),
                const SizedBox(height: 8),
                ExperienceGroup(
                  guides: groups[i].guides,
                  palette: palette,
                  lang: lang,
                  onOpen: (g) => _openDetail(context, palette, g),
                  onAddToPlan: trip == null
                      ? null
                      : (g) => addExperienceToPlan(
                            context: context,
                            ref: ref,
                            trip: trip!,
                            guide: g,
                            palette: palette,
                            lang: lang,
                          ),
                  onRemind: (g) => showReminderComposerSheet(
                    context,
                    isPremium: isPremium,
                    initialWindowId: g.reminderWindowId,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              ExperienceFreshnessNote(palette: palette, lang: lang),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aciliyet başlığı: renkli nokta + etiket.
///
/// Nokta rengi trafik ışığı mantığında — `sunset` en acil, `gold` orta,
/// `matcha` rahat. Renk tek başına anlam taşımıyor; etiket zaten söylüyor.
class _UrgencyHeader extends StatelessWidget {
  const _UrgencyHeader({
    super.key,
    required this.urgency,
    required this.palette,
    required this.lang,
  });

  final ExperienceUrgency urgency;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final (Color dot, String label) = switch (urgency) {
      ExperienceUrgency.early => (
          p.sunset,
          const LText('ÖNCE BUNU AL · ~2 AY ÖNCE', 'BOOK FIRST · ~2 MONTHS')
              .of(lang),
        ),
      ExperienceUrgency.weeks => (
          p.gold,
          const LText('BİRKAÇ HAFTA ÖNCE', 'A FEW WEEKS AHEAD').of(lang),
        ),
      ExperienceUrgency.late_ => (
          p.matcha,
          const LText('SON HAFTALARDA YETER', 'LAST WEEKS ARE FINE').of(lang),
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bir aciliyet kovasının inset-group'u.
class ExperienceGroup extends StatelessWidget {
  const ExperienceGroup({
    super.key,
    required this.guides,
    required this.palette,
    required this.lang,
    required this.onOpen,
    required this.onAddToPlan,
    required this.onRemind,
  });

  final List<ExperienceGuide> guides;
  final ViewerPalette palette;
  final AppLang lang;
  final ValueChanged<ExperienceGuide> onOpen;

  /// null ise plan bağlamı yok; çip hiç çizilmez.
  final ValueChanged<ExperienceGuide>? onAddToPlan;
  final ValueChanged<ExperienceGuide> onRemind;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < guides.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border, indent: 61),
            ExperienceRow(
              key: ValueKey('experience-guide-card-${guides[i].id}'),
              guide: guides[i],
              palette: p,
              lang: lang,
              onOpen: () => onOpen(guides[i]),
              onAddToPlan: onAddToPlan == null
                  ? null
                  : () => onAddToPlan!(guides[i]),
              onRemind: () => onRemind(guides[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tek rehber satırı.
///
/// Satırın gövdesi detaya gider; sağdaki zil AYRI bir dokunma hedefi ve
/// hatırlatıcı sheet'ini açar. Eskiden her kartın altında tekrar eden mavi
/// "Bilet zamanını hatırlat" satırı vardı — altı kez tekrarlanınca listeyi
/// gürültüye boğuyordu; 18px'lik zil aynı işi sessizce yapıyor.
class ExperienceRow extends StatelessWidget {
  const ExperienceRow({
    super.key,
    required this.guide,
    required this.palette,
    required this.lang,
    required this.onOpen,
    required this.onAddToPlan,
    required this.onRemind,
  });

  final ExperienceGuide guide;
  final ViewerPalette palette;
  final AppLang lang;
  final VoidCallback onOpen;

  /// null ise plan bağlamı yok; çip hiç çizilmez.
  final VoidCallback? onAddToPlan;
  final VoidCallback onRemind;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final visual = experienceVisual(guide, p);

    // Zil, satır InkWell'inin İÇİNDE.
    //
    // **Why:** Dışarıda dururken satırın basılı-durum vurgusu yalnız sol
    // kısmı kaplıyor, zilin olduğu yerde beyaz bir çentik kalıyordu. İçeride
    // vurgu tam genişliğe yayılır; zilin kendi IconButton'ı o alandaki
    // dokunuşu zaten soğurduğu için satır açılmaz.
    return Semantics(
      // explicitChildNodes: içteki zil ayrı bir düğüm olarak kalsın, dış
      // etiketle birleşip tek bir buton gibi okunmasın.
      explicitChildNodes: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              // Sağda artık İKİ ikon var (plana ekle + zil); 6px'lik sağ
              // boşluk "Universal Studios Japan" başlığını kırpacak kadar yer
              // yiyordu. İkonların kendi 40px genişliği dokunma boşluğunu
              // zaten sağlıyor.
              padding: const EdgeInsets.fromLTRB(12, 8, 2, 8),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: visual.tone.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Icon(visual.icon, size: 20, color: visual.tone),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: '${guide.title}. ${guide.tagline.of(lang)}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            guide.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${guide.city} · ${guide.duration.of(lang)}',
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
                  ),
                  // Listede ETİKETSİZ, detayda etiketli.
                  //
                  // **Why:** Etiketli çip altı satırda tekrarlanınca sayfanın
                  // en yüksek sesli öğesi oluyor ve başlıkları kırpıyordu
                  // ("Universal Studios …"). Burada eylem zilin yanında ikinci
                  // bir ikon; anlamı `tooltip` ve `Semantics` taşıyor. Detay
                  // kartında tek başına durduğu için orada etiket kalıyor.
                  if (onAddToPlan != null)
                    Semantics(
                      button: true,
                      label:
                          '${guide.title}. ${const LText('Plana ekle', 'Add to plan').of(lang)}',
                      child: IconButton(
                        key: ValueKey('experience-add-to-plan-${guide.id}'),
                        onPressed: onAddToPlan,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 44,
                        ),
                        tooltip:
                            const LText('Plana ekle', 'Add to plan').of(lang),
                        icon: Icon(
                          Icons.playlist_add_rounded,
                          size: 21,
                          color: p.accent,
                        ),
                      ),
                    ),
                  Semantics(
                    button: true,
                    label:
                        '${guide.title}. ${const LText('Bilet zamanını hatırlat', 'Remind me about tickets').of(lang)}',
                    child: IconButton(
                      key: ValueKey('experience-reminder-${guide.id}'),
                      onPressed: onRemind,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 44,
                      ),
                      tooltip: const LText(
                        'Bilet zamanını hatırlat',
                        'Remind me about tickets',
                      ).of(lang),
                      icon: Icon(
                        Icons.notifications_active_outlined,
                        size: 20,
                        color: p.accent,
                      ),
                    ),
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

/// Tazelik uyarısı.
///
/// **Why kart değil:** Eskiden 16px radius'lu, ikon rozetli dolu bir kartla
/// listenin EN ÜSTÜNDEYDİ; kullanıcı içeriğe ulaşmadan önce dört satır yasal
/// metin okuyordu. Bilgi doğru ama önceliği yanlıştı — artık listenin altında
/// sessiz bir dipnot.
class ExperienceFreshnessNote extends StatelessWidget {
  const ExperienceFreshnessNote({
    super.key,
    required this.palette,
    required this.lang,
  });

  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('experience-freshness-note'),
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(
        const LText(
          'Buradaki süreler planlama aralığıdır. Fiyat, açılış, bakım ve erişim kuralları değişebilir; satın almadan ve gitmeden önce resmî bağlantıyı kontrol et.',
          'These are planning ranges. Prices, hours, closures and access rules change; check the official link before buying and before visiting.',
        ).of(lang),
        style: TextStyle(
          color: palette.textMuted,
          fontSize: 11.5,
          height: 1.45,
        ),
      ),
    );
  }
}

/// CAPS bölüm ayracı — detay ekranı da kullanıyor.
class ExperienceSectionLabel extends StatelessWidget {
  const ExperienceSectionLabel({
    super.key,
    required this.label,
    required this.palette,
  });

  final String label;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}
