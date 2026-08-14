// Eğlence rehberi — detay.
//
// Eski tek-sayfa tasarımda bilet adımları, akış, öne çıkanlar ve ipuçları
// hep birlikte açıktı: sekiz kart üst üste, hepsi aynı ağırlıkta. Burada
// özet ÜSTTE ve tek; gerisi katlanır satır — kullanıcı yalnız ihtiyacını açar.
//
// Yüzey kuralı drawer ile aynı: `card` + radius + `border`, gölge yok, renk
// sadece 38px ikon rozetinde `@.11` alpha.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../data/language_store.dart';
import '../../domain/experience_guides.dart';
import '../../domain/localized_text.dart';
import '../../domain/types.dart';
import '../plans/premium_provider.dart';
import '../reminders/reminder_composer_sheet.dart';
import 'experience_add_to_plan.dart';
import 'experience_guide_screen.dart'
    show ExperienceFreshnessNote, ExperienceSectionLabel;
import 'experience_visuals.dart';
import 'viewer_theme.dart';

class ExperienceDetailScreen extends ConsumerStatefulWidget {
  const ExperienceDetailScreen({super.key, required this.guide, this.trip});

  final ExperienceGuide guide;

  /// Açık plan. null ise "Plana ekle" gösterilmez.
  final Trip? trip;

  @override
  ConsumerState<ExperienceDetailScreen> createState() =>
      _ExperienceDetailScreenState();
}

class _ExperienceDetailScreenState
    extends ConsumerState<ExperienceDetailScreen> {
  /// Açık bölümün indeksi; hiçbiri açık değilse null. Aynı anda tek bölüm
  /// açık kalır — sekiz kartlık duvara geri dönmemek için.
  int? _open;

  Future<void> _openExternal(String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      final lang = ref.read(appLangProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            const LText(
              'Bağlantı açılamadı. İnternetini kontrol edip tekrar dene.',
              'Could not open the link. Check your connection and try again.',
            ).of(lang),
          ),
        ),
      );
    }
  }

  Future<void> _addToPlan(ViewerPalette palette, AppLang lang) {
    final trip = widget.trip;
    if (trip == null) return Future<void>.value();
    return addExperienceToPlan(
      context: context,
      ref: ref,
      trip: trip,
      guide: widget.guide,
      palette: palette,
      lang: lang,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(viewerPaletteProvider);
    final lang = ref.watch(appLangProvider);
    final isPremium = ref.watch(premiumProvider);
    final guide = widget.guide;
    final p = palette;

    final sections = <_Section>[
      _Section(
        icon: Icons.confirmation_number_outlined,
        tone: p.accent,
        title: const LText('Biletten kapıya', 'From ticket to gate').of(lang),
        count: guide.ticketSteps.length,
        body: _TicketSteps(steps: guide.ticketSteps, palette: p, lang: lang),
      ),
      _Section(
        icon: Icons.schedule_rounded,
        tone: p.fuji,
        title: const LText('Örnek akış', 'Sample flow').of(lang),
        count: guide.timeline.length,
        body: _Timeline(stops: guide.timeline, palette: p, lang: lang),
      ),
      _Section(
        icon: Icons.star_outline_rounded,
        tone: p.gold,
        title: const LText('Kaçırma', 'Do not miss').of(lang),
        count: guide.highlights.length,
        body: _Highlights(
          key: ValueKey('experience-highlights-${guide.id}'),
          highlights: guide.highlights,
          palette: p,
          lang: lang,
        ),
      ),
      _Section(
        icon: Icons.tips_and_updates_outlined,
        tone: p.matcha,
        title: const LText('İşi kurtaran ipuçları', 'Tips that save the day')
            .of(lang),
        count: guide.tips.length,
        body: _TipsCard(tips: guide.tips, palette: p, lang: lang),
      ),
    ];

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(),
        title: Text(
          guide.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _SummaryCard(
            guide: guide,
            palette: p,
            lang: lang,
            onAddToPlan:
                widget.trip == null ? null : () => _addToPlan(palette, lang),
          ),
          const SizedBox(height: 22),
          ExperienceSectionLabel(
            label: const LText('REHBER', 'GUIDE').of(lang),
            palette: p,
          ),
          const SizedBox(height: 8),
          _DisclosureGroup(
            sections: sections,
            openIndex: _open,
            palette: p,
            onToggle: (i) => setState(() => _open = _open == i ? null : i),
          ),
          const SizedBox(height: 22),
          ExperienceSectionLabel(
            label: const LText('RESMÎ KAYNAK', 'OFFICIAL SOURCE').of(lang),
            palette: p,
          ),
          const SizedBox(height: 8),
          _OfficialActions(
            guide: guide,
            palette: p,
            lang: lang,
            onOpenExternal: _openExternal,
          ),
          // Hatırlatıcı EN ALTTA: kullanıcı önce rehberi okur, sonra karar
          // verir. Yukarıdayken özet ile içerik arasına giriyor ve okumayı
          // bölüyordu. "Plana ekle" ise özet kartının başlık satırında —
          // aksiyon, uygulanacağı şeyin yanında duruyor.
          const SizedBox(height: 22),
          _ReminderCard(
            guide: guide,
            palette: p,
            lang: lang,
            isPremium: isPremium,
            onTap: () => showReminderComposerSheet(
              context,
              isPremium: isPremium,
              initialWindowId: guide.reminderWindowId,
            ),
          ),
          ExperienceFreshnessNote(palette: p, lang: lang),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Özet
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.guide,
    required this.palette,
    required this.lang,
    required this.onAddToPlan,
  });

  final ExperienceGuide guide;
  final ViewerPalette palette;
  final AppLang lang;

  /// null ise plan bağlamı yok — çalışmayan bir çip göstermektense hiç
  /// göstermemek doğru.
  final VoidCallback? onAddToPlan;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final visual = experienceVisual(guide, p);
    final metrics = <(IconData, String, String)>[
      (
        Icons.timelapse_rounded,
        guide.duration.of(lang),
        const LText('Süre', 'Duration').of(lang),
      ),
      (
        Icons.door_front_door_outlined,
        guide.arrivalBuffer.of(lang),
        const LText('Erken git', 'Arrive early').of(lang),
      ),
      (
        Icons.calendar_month_outlined,
        guide.bookingWindow.of(lang),
        const LText('Rezerve', 'Book').of(lang),
      ),
    ];

    return Container(
      key: const ValueKey('experience-overview-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      guide.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.3,
                      ),
                    ),
                    Text(
                      guide.city,
                      style: TextStyle(
                        color: p.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (onAddToPlan != null) ...[
                const SizedBox(width: 8),
                ExperienceAddToPlanChip(
                  key: const ValueKey('experience-add-to-plan'),
                  palette: p,
                  lang: lang,
                  onTap: onAddToPlan!,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            guide.tagline.of(lang),
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 13),
          Divider(height: 1, color: p.border),
          const SizedBox(height: 11),
          // Etiket → değer SATIRLARI, üç kolonluk metrik şeridi değil.
          //
          // **Why:** Bu alanlar sayı değil CÜMLE — `arrivalBuffer` "Kapıdan
          // 45–60 dk önce", `bookingWindow` "45–60 gün önce kontrol et".
          // Üçe bölünmüş dar bir şeritte ya taşıyorlar ya da okunamayacak
          // kadar küçülüyorlardı. Satır düzeni değeri tam genişlikte verir.
          for (var i = 0; i < metrics.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(metrics[i].$1, size: 15, color: p.textMuted),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 74,
                    child: Text(
                      metrics[i].$3,
                      style: TextStyle(
                        color: p.textMuted,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      metrics[i].$2,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 11),
          Divider(height: 1, color: p.border),
          const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.person_search_outlined, size: 15, color: p.textMuted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  guide.bestFor.of(lang),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hatırlatıcı
// ---------------------------------------------------------------------------

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.guide,
    required this.palette,
    required this.lang,
    required this.isPremium,
    required this.onTap,
  });

  final ExperienceGuide guide;
  final ViewerPalette palette;
  final AppLang lang;
  final bool isPremium;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      key: const ValueKey('experience-reminder-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: p.gold.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(
              isPremium
                  ? Icons.notifications_active_rounded
                  : Icons.lock_rounded,
              size: 20,
              color: p.gold,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  const LText(
                    'Bilet zamanını kaçırma',
                    'Do not miss the ticket window',
                  ).of(lang),
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                // `bookingWindow` zaten tam bir ifade ("45–60 gün önce
                // kontrol et"); başına/sonuna fiil eklemek "kontrol et
                // kontrol et" üretiyordu.
                Text(
                  lang == AppLang.tr
                      ? '${guide.bookingWindow.of(lang)}. Rotori satış gününün sabahı 09:00’da hatırlatsın.'
                      : '${guide.bookingWindow.of(lang)}. Rotori can remind you at 09:00 on the sale day.',
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const ValueKey('experience-add-reminder'),
                  onPressed: onTap,
                  icon: Icon(
                    isPremium ? Icons.add_alert_rounded : Icons.lock_rounded,
                    size: 17,
                  ),
                  label: Text(
                    const LText(
                      'Rotori hatırlatıcısı ekle',
                      'Add a Rotori reminder',
                    ).of(lang),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Katlanır bölümler
// ---------------------------------------------------------------------------

class _Section {
  const _Section({
    required this.icon,
    required this.tone,
    required this.title,
    required this.count,
    required this.body,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final int count;
  final Widget body;
}

class _DisclosureGroup extends StatelessWidget {
  const _DisclosureGroup({
    required this.sections,
    required this.openIndex,
    required this.palette,
    required this.onToggle,
  });

  final List<_Section> sections;
  final int? openIndex;
  final ViewerPalette palette;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      key: const ValueKey('experience-sections'),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border, indent: 64),
            _DisclosureRow(
              section: sections[i],
              open: openIndex == i,
              palette: p,
              onTap: () => onToggle(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _DisclosureRow extends StatelessWidget {
  const _DisclosureRow({
    required this.section,
    required this.open,
    required this.palette,
    required this.onTap,
  });

  final _Section section;
  final bool open;
  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      children: [
        Semantics(
          button: true,
          expanded: open,
          label: section.title,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: section.tone.withValues(alpha: .11),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          section.icon,
                          size: 20,
                          color: section.tone,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          section.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${section.count}',
                        style: TextStyle(
                          color: p.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: open ? .5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 21,
                          color: p.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // **Why AnimatedCrossFade değil:** O, kapalı olanı da dâhil HER İKİ
        // çocuğu inşa eder. Dört bölümün gövdesi sürekli ağaçta durur, ekran
        // okuyucu kapalı içeriği okur ve katlamanın anlamı kalmazdı.
        // AnimatedSize gövdeyi yalnız açıkken kurar.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: section.body,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bölüm gövdeleri
// ---------------------------------------------------------------------------

class _TicketSteps extends StatelessWidget {
  const _TicketSteps({
    required this.steps,
    required this.palette,
    required this.lang,
  });

  final List<LText> steps;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: p.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    steps[i].of(lang),
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.stops,
    required this.palette,
    required this.lang,
  });

  final List<ExperienceTimelineStop> stops;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      children: [
        for (var i = 0; i < stops.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    stops[i].time,
                    style: TextStyle(
                      color: p.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                SizedBox(
                  width: 16,
                  child: Column(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(top: 3),
                        decoration: BoxDecoration(
                          color: i == 0 ? p.accent : p.borderStrong,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (i < stops.length - 1)
                        Expanded(
                          child: Container(width: 1.5, color: p.border),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i == stops.length - 1 ? 0 : 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stops[i].title.of(lang),
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stops[i].detail.of(lang),
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Öne çıkanlar.
///
/// **Why dikey:** Eskiden 205px yükseklikte yatay kaydırmalı bir şeritti;
/// kaç öğe olduğu görünmüyor ve keşfedilmesi dokunuşa bağlıydı. Katlanır
/// bölümün içinde dikey liste hem sayıyı önden söyler hem kaydırma
/// yönlerini çakıştırmaz.
class _Highlights extends StatelessWidget {
  const _Highlights({
    super.key,
    required this.highlights,
    required this.palette,
    required this.lang,
  });

  final List<ExperienceHighlight> highlights;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      children: [
        for (var i = 0; i < highlights.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        highlights[i].title.of(lang),
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      highlights[i].duration.of(lang),
                      style: TextStyle(
                        color: p.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  highlights[i].strategy.of(lang),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard({
    required this.tips,
    required this.palette,
    required this.lang,
  });

  final List<LText> tips;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      key: const ValueKey('experience-tips-card'),
      children: [
        for (var i = 0; i < tips.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.bolt_rounded, size: 16, color: p.matcha),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tips[i].of(lang),
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12.2,
                      height: 1.42,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Resmî aksiyonlar
// ---------------------------------------------------------------------------

/// Resmî bağlantılar.
///
/// **Why buton yığını değil satır grubu:** Eskiden dolu mavi buton +
/// çerçeveli buton + ayrı bir video kartı alt alta duruyordu — üç farklı
/// görsel dil, tek bir bölümde. Üçü de aynı şeyi yapıyor (dışarı açıyor),
/// bu yüzden üçü de aynı satır anatomisini kullanır ve ekranın geri
/// kalanıyla aynı ritimde durur.
class _OfficialActions extends StatelessWidget {
  const _OfficialActions({
    required this.guide,
    required this.palette,
    required this.lang,
    required this.onOpenExternal,
  });

  final ExperienceGuide guide;
  final ViewerPalette palette;
  final AppLang lang;
  final ValueChanged<String> onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final links = <({Key key, IconData icon, Color tone, String label, String url})>[
      (
        key: const ValueKey('experience-official-link'),
        icon: Icons.confirmation_number_outlined,
        tone: p.accent,
        label: const LText(
          'Resmî bilet ve ziyaret bilgisi',
          'Official tickets and visit info',
        ).of(lang),
        url: guide.officialUrl,
      ),
      if (guide.appUrl != null)
        (
          key: const ValueKey('experience-official-app'),
          icon: Icons.phone_iphone_rounded,
          tone: p.fuji,
          label: const LText('Resmî uygulama rehberi', 'Official app guide')
              .of(lang),
          url: guide.appUrl!,
        ),
      if (guide.videoUrl != null)
        (
          key: const ValueKey('experience-official-video'),
          icon: Icons.play_arrow_rounded,
          tone: p.sakura,
          label: const LText(
            'Gitmeden kısa bir tur izle',
            'Watch a quick preview before you go',
          ).of(lang),
          url: guide.videoUrl!,
        ),
    ];

    return Container(
      key: const ValueKey('experience-official-actions'),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < links.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border, indent: 64),
            Semantics(
              button: true,
              label: links[i].label,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: links[i].key,
                  onTap: () => onOpenExternal(links[i].url),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: links[i].tone.withValues(alpha: .11),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              links[i].icon,
                              size: 20,
                              color: links[i].tone,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              links[i].label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 18,
                            color: p.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
