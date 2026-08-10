import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../data/language_store.dart';
import '../../domain/experience_guides.dart';
import '../../domain/localized_text.dart';
import '../plans/premium_provider.dart';
import '../reminders/reminder_composer_sheet.dart';
import 'viewer_theme.dart';

class ExperienceGuideScreen extends ConsumerStatefulWidget {
  const ExperienceGuideScreen({super.key});

  @override
  ConsumerState<ExperienceGuideScreen> createState() =>
      _ExperienceGuideScreenState();
}

class _ExperienceGuideScreenState extends ConsumerState<ExperienceGuideScreen> {
  String _selectedId = kExperienceGuides.first.id;

  ExperienceGuide get _selected => kExperienceGuides.firstWhere(
        (guide) => guide.id == _selectedId,
        orElse: () => kExperienceGuides.first,
      );

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

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(viewerPaletteProvider);
    final lang = ref.watch(appLangProvider);
    final isPremium = ref.watch(premiumProvider);
    final guide = _selected;

    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: Scaffold(
          backgroundColor: palette.bg,
          body: CustomScrollView(
            slivers: [
              _ExperienceHero(palette: palette, lang: lang),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 44),
                sliver: SliverList.list(
                  children: [
                    _FreshnessNote(palette: palette, lang: lang),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 154,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: kExperienceGuides.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final item = kExperienceGuides[index];
                          return _GuideSelectorCard(
                            key: ValueKey('experience-guide-card-${item.id}'),
                            guide: item,
                            palette: palette,
                            lang: lang,
                            selected: item.id == guide.id,
                            onTap: () => setState(() => _selectedId = item.id),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _GuideBody(
                        key: ValueKey(guide.id),
                        guide: guide,
                        palette: palette,
                        lang: lang,
                        onOpenExternal: _openExternal,
                        onAddReminder: () => showReminderComposerSheet(
                          context,
                          isPremium: ref.read(premiumProvider),
                          initialWindowId: guide.reminderWindowId,
                        ),
                        isPremium: isPremium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExperienceHero extends StatelessWidget {
  const _ExperienceHero({required this.palette, required this.lang});

  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 324,
      backgroundColor: palette.fuji,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(
        const LText('Japonya Eğlence Rehberi', 'Japan Experience Guide')
            .of(lang),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/experience-guide-hero.webp',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .38, 1],
                  colors: [
                    Color(0x59000000),
                    Color(0x14000000),
                    Color(0xE3000920),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .3),
                      ),
                    ),
                    child: Text(
                      const LText(
                        '6 DENEYİM · SIFIRDAN TAM GÜNE',
                        '6 EXPERIENCES · FROM ZERO TO A FULL DAY',
                      ).of(lang),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    const LText(
                      'Bilet Hazır,\nMacera Başlasın!',
                      'Ticket Ready.\nLet the Adventure Begin!',
                    ).of(lang),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      height: 1.03,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    const LText(
                      'USJ, Tokyo Disney ve teamLab için bilet, süre, sıra ve içerideki rota.',
                      'Tickets, timing, queues and inside strategy for USJ, Tokyo Disney and teamLab.',
                    ).of(lang),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .9),
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FreshnessNote extends StatelessWidget {
  const _FreshnessNote({required this.palette, required this.lang});

  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.gold.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.gold.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.update_rounded, color: palette.gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              const LText(
                'Buradaki süreler planlama aralığıdır. Fiyat, açılış, bakım ve erişim kuralları değişebilir; satın almadan ve gitmeden önce resmî bağlantıyı kontrol et.',
                'These are planning ranges. Prices, hours, closures and access rules change; check the official link before buying and before visiting.',
              ).of(lang),
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideSelectorCard extends StatelessWidget {
  const _GuideSelectorCard({
    super.key,
    required this.guide,
    required this.palette,
    required this.lang,
    required this.selected,
    required this.onTap,
  });

  final ExperienceGuide guide;
  final ViewerPalette palette;
  final AppLang lang;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = guide.kind == ExperienceGuideKind.themePark
        ? [palette.sunset, palette.sakura]
        : [palette.sky, palette.fuji];
    return SizedBox(
      width: 184,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? null : palette.card,
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    )
                  : null,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? Colors.transparent : palette.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(guide.emoji, style: const TextStyle(fontSize: 25)),
                    const Spacer(),
                    if (selected)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  guide.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : palette.textPrimary,
                    fontSize: 14,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${guide.city} · ${guide.duration.of(lang)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? Colors.white.withValues(alpha: .86)
                        : palette.textMuted,
                    fontSize: 10.8,
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

class _GuideBody extends StatelessWidget {
  const _GuideBody({
    super.key,
    required this.guide,
    required this.palette,
    required this.lang,
    required this.onOpenExternal,
    required this.onAddReminder,
    required this.isPremium,
  });

  final ExperienceGuide guide;
  final ViewerPalette palette;
  final AppLang lang;
  final ValueChanged<String> onOpenExternal;
  final VoidCallback onAddReminder;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverviewCard(guide: guide, palette: palette, lang: lang),
        if (guide.reminderWindowId != null) ...[
          const SizedBox(height: 12),
          _BookingReminderCard(
            guide: guide,
            palette: palette,
            lang: lang,
            onTap: onAddReminder,
            isPremium: isPremium,
          ),
        ],
        const SizedBox(height: 18),
        _SectionTitle(
          icon: Icons.confirmation_number_outlined,
          title: const LText('Biletten kapıya', 'Ticket to gate').of(lang),
          subtitle: const LText(
            'İlk kez alan biri için doğru sıra',
            'The right order for a first-time buyer',
          ).of(lang),
          palette: palette,
        ),
        const SizedBox(height: 10),
        _TicketSteps(steps: guide.ticketSteps, palette: palette, lang: lang),
        const SizedBox(height: 22),
        _SectionTitle(
          icon: Icons.schedule_rounded,
          title: const LText('Örnek akış', 'Sample flow').of(lang),
          subtitle: const LText(
            'Süreleri kendi giriş saatine kaydır',
            'Shift the timing to your actual entry',
          ).of(lang),
          palette: palette,
        ),
        const SizedBox(height: 10),
        _Timeline(stops: guide.timeline, palette: palette, lang: lang),
        const SizedBox(height: 22),
        _SectionTitle(
          icon: guide.kind == ExperienceGuideKind.themePark
              ? Icons.attractions_rounded
              : Icons.auto_awesome_rounded,
          title: guide.kind == ExperienceGuideKind.themePark
              ? const LText('Oyuncak stratejisi', 'Ride strategy').of(lang)
              : const LText('Deneyim stratejisi', 'Experience strategy')
                  .of(lang),
          subtitle: const LText(
            'Kartları yana kaydır; süre ve uygulama taktiğini birlikte gör.',
            'Swipe sideways for timing and a practical strategy.',
          ).of(lang),
          palette: palette,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 205,
          child: ListView.separated(
            key: ValueKey('experience-highlights-${guide.id}'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 12),
            itemCount: guide.highlights.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _HighlightCard(
              highlight: guide.highlights[index],
              index: index,
              total: guide.highlights.length,
              palette: palette,
              lang: lang,
            ),
          ),
        ),
        const SizedBox(height: 22),
        _SectionTitle(
          icon: Icons.tips_and_updates_outlined,
          title:
              const LText('İşi kurtaran ipuçları', 'Day-saving tips').of(lang),
          subtitle: const LText(
            'Gitmeden ekran görüntüsü al',
            'Screenshot these before you go',
          ).of(lang),
          palette: palette,
        ),
        const SizedBox(height: 10),
        _TipsCard(tips: guide.tips, palette: palette, lang: lang),
        const SizedBox(height: 18),
        _OfficialActions(
          guide: guide,
          palette: palette,
          lang: lang,
          onOpenExternal: onOpenExternal,
        ),
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.guide,
    required this.palette,
    required this.lang,
  });

  final ExperienceGuide guide;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final gradient = guide.kind == ExperienceGuideKind.themePark
        ? [palette.sunset, palette.sakura]
        : [palette.sky, palette.fuji];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withValues(alpha: .24),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white.withValues(alpha: .3)),
                ),
                child: Text(guide.emoji, style: const TextStyle(fontSize: 25)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      guide.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${guide.city} · ${guide.tagline.of(lang)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .9),
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricPill(
                icon: Icons.timelapse_rounded,
                label: guide.duration.of(lang),
              ),
              _MetricPill(
                icon: Icons.door_front_door_outlined,
                label: guide.arrivalBuffer.of(lang),
              ),
              _MetricPill(
                icon: Icons.calendar_month_outlined,
                label: guide.bookingWindow.of(lang),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            '${const LText('Kime göre?', 'Best for').of(lang)}  ${guide.bestFor.of(lang)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .92),
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingReminderCard extends StatelessWidget {
  const _BookingReminderCard({
    required this.guide,
    required this.palette,
    required this.lang,
    required this.onTap,
    required this.isPremium,
  });

  final ExperienceGuide guide;
  final ViewerPalette palette;
  final AppLang lang;
  final VoidCallback onTap;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.fuji.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.fuji.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: palette.brandGradient),
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Colors.white,
              size: 21,
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
                    color: palette.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: palette.gold.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: palette.gold.withValues(alpha: .32),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPremium
                            ? Icons.workspace_premium_rounded
                            : Icons.lock_rounded,
                        color: palette.gold,
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        const LText('ROTORI PRO', 'ROTORI PRO').of(lang),
                        style: TextStyle(
                          color: palette.gold,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  lang == AppLang.tr
                      ? '${guide.title} için ${guide.bookingWindow.of(lang)} kontrol et. Rotori satış gününün sabahı 09:00 cihaz saatinde hatırlatsın.'
                      : 'Check ${guide.bookingWindow.of(lang)} for ${guide.title}. Rotori can remind you at 09:00 device time on the sale day.',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 11.8,
                    height: 1.4,
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
                    backgroundColor: palette.fuji,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: palette.fuji.withValues(alpha: .11),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: palette.fuji),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(color: palette.textMuted, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.fuji,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      steps[i].of(lang),
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12.5,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < stops.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      stops[i].time,
                      style: TextStyle(
                        color: palette.fuji,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 18,
                    child: Column(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: i == 0 ? palette.sakura : palette.fuji,
                            shape: BoxShape.circle,
                          ),
                        ),
                        if (i < stops.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: palette.borderStrong,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 17),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stops[i].title.of(lang),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            stops[i].detail.of(lang),
                            style: TextStyle(
                              color: palette.textSecondary,
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
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.highlight,
    required this.index,
    required this.total,
    required this.palette,
    required this.lang,
  });

  final ExperienceHighlight highlight;
  final int index;
  final int total;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final tones = [palette.sky, palette.sakura, palette.matcha, palette.gold];
    final tone = tones[index % tones.length];
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 54).clamp(282.0, 370.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tone.withValues(alpha: .24)),
          boxShadow: [
            BoxShadow(
              color: tone.withValues(alpha: .08),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
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
                    color: tone.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${index + 1}/$total',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.swipe_left_rounded,
                  color: palette.textMuted,
                  size: 17,
                ),
              ],
            ),
            const SizedBox(height: 13),
            Text(
              highlight.title.of(lang),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                height: 1.15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              highlight.duration.of(lang),
              style: TextStyle(
                color: tone,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Expanded(
              child: Text(
                highlight.strategy.of(lang),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12.2,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.gold.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.gold.withValues(alpha: .25)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < tips.length; i++) ...[
            if (i > 0) const SizedBox(height: 11),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.bolt_rounded,
                  color: palette.gold,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tips[i].of(lang),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12.2,
                      height: 1.42,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined, color: palette.matcha, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  const LText(
                    'Son kontrolü resmî kaynaktan yap',
                    'Do the final check at the official source',
                  ).of(lang),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('experience-official-link'),
            onPressed: () => onOpenExternal(guide.officialUrl),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(
              const LText('Resmî bilet ve ziyaret bilgisi',
                      'Official tickets and visit info')
                  .of(lang),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: palette.fuji,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          if (guide.appUrl != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => onOpenExternal(guide.appUrl!),
              icon: const Icon(Icons.phone_iphone_rounded, size: 18),
              label: Text(
                const LText('Resmî uygulama rehberi', 'Official app guide')
                    .of(lang),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.textPrimary,
                side: BorderSide(color: palette.borderStrong),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
          if (guide.videoUrl != null) ...[
            const SizedBox(height: 10),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('experience-official-video'),
                onTap: () => onOpenExternal(guide.videoUrl!),
                child: Ink(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        palette.sakura.withValues(alpha: .13),
                        palette.fuji.withValues(alpha: .08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: palette.sakura.withValues(alpha: .25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: palette.sakura,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              const LText(
                                'Gitmeden kısa bir tur izle',
                                'Watch a quick preview before you go',
                              ).of(lang),
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              const LText(
                                'Ücretsiz · resmî YouTube kanalı',
                                'Free · official YouTube channel',
                              ).of(lang),
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 10.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.open_in_new_rounded,
                        color: palette.sakura,
                        size: 18,
                      ),
                    ],
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
