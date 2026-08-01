// Bu dosya plan_viewer_screen.dart kütüphanesinin parçasıdır (part of).
// Viewer sandvich (drawer) bileşen ailesi burada toplanır; ana ekran
// dosyasını sadeleştirmek için ayrıldı. Import gerekmez — parent paylaşır.
part of '../plan_viewer_screen.dart';

// ---------------------------------------------------------------------------
// 9) Sandvich (drawer) — kullanıcı bilgisi + uçuş özet + otel özet + metrikler
//    + tüm aksiyon butonları + nav kısayolları + çıkış. Viewer minimalize
//    edildiğinde bu drawer, top bar'daki aksiyon şeridinin ve hero'nun yerini
//    aldı: asıl "iş" (günler) hemen görünsün diye.
// ---------------------------------------------------------------------------

class _ViewerDrawer extends ConsumerWidget {
  const _ViewerDrawer({
    required this.palette,
    required this.trip,
    required this.dayCount,
    required this.onOpenThemePicker,
    required this.onOpenBudget,
    required this.onOpenPrep,
    required this.onOpenWeather,
    required this.onReportBug,
  });
  final ViewerPalette palette;
  final Trip trip;
  final int dayCount;
  final VoidCallback onOpenThemePicker;
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenPrep;
  final VoidCallback onOpenWeather;
  final VoidCallback onReportBug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = palette;
    final s = LanguageScope.of(context);
    String? email;
    try {
      email = ref.watch(currentUserProvider)?.email;
    } catch (_) {
      email = null;
    }
    final isGuest = email == null || email.isEmpty;
    final role =
        isGuest ? s.s('drawer.role.guest') : s.s('drawer.role.traveler');
    final avatarInitial =
        isGuest ? '?' : email.trim().substring(0, 1).toUpperCase();

    // KEŞFET — en sık kullanılan araçlar, yan yana dikey karolar.
    final discoverActions = <_DrawerActionSpec>[
      _DrawerActionSpec(
          icon: Icons.light_mode_outlined,
          label: s.s('viewer.tt.weather'),
          onTap: onOpenWeather),
      _DrawerActionSpec(
          icon: Icons.account_balance_wallet_outlined,
          label: s.s('viewer.tt.budget'),
          onTap: onOpenBudget),
      _DrawerActionSpec(
          icon: Icons.checklist_rounded,
          label: s.s('viewer.tt.checklist'),
          onTap: onOpenPrep),
    ];

    return Drawer(
      width: (MediaQuery.sizeOf(context).width * 0.9)
          .clamp(320.0, 400.0)
          .toDouble(),
      backgroundColor: p.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DrawerHero(palette: p, tripTitle: trip.title),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DrawerSectionLabel(
                    label: s.s('drawer.section.trip'),
                    palette: p,
                  ),
                  const SizedBox(height: 8),
                  _DrawerStaySummary(
                    trip: trip,
                    palette: p,
                    dayCount: dayCount,
                  ),
                  const SizedBox(height: 10),
                  _DrawerFlightsMini(trip: trip, palette: p),
                  const SizedBox(height: 8),
                  _DrawerHotelsMini(trip: trip, palette: p),
                  const SizedBox(height: 22),
                  _DrawerSectionLabel(
                    label: s.s('drawer.section.discover'),
                    palette: p,
                  ),
                  const SizedBox(height: 8),
                  _DrawerActionGrid(
                    actions: discoverActions,
                    palette: p,
                  ),
                  const SizedBox(height: 22),
                  _DrawerSectionLabel(
                    label: s.s('drawer.section.tools'),
                    palette: p,
                  ),
                  const SizedBox(height: 8),
                  _DrawerNavGroup(
                    palette: p,
                    children: [
                      _DrawerNavTile(
                        palette: p,
                        icon: Icons.palette_outlined,
                        label: s.s('viewer.tt.theme'),
                        onTap: () {
                          Navigator.of(context).pop();
                          onOpenThemePicker();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _DrawerSectionLabel(
                    label: s.s('drawer.section.account'),
                    palette: p,
                  ),
                  const SizedBox(height: 8),
                  _DrawerProfileCard(
                    palette: p,
                    avatarInitial: avatarInitial,
                    title: isGuest ? role : email,
                    subtitle: isGuest ? null : role,
                  ),
                  const SizedBox(height: 8),
                  _DrawerNavGroup(
                    palette: p,
                    children: [
                      _DrawerNavTile(
                        palette: p,
                        icon: Icons.list_alt_rounded,
                        label: s.s('drawer.nav.plans'),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go('/plans');
                        },
                      ),
                      _DrawerNavTile(
                        palette: p,
                        icon: Icons.bug_report_outlined,
                        label: s.s('bugReport.menu'),
                        onTap: () {
                          Navigator.of(context).pop();
                          onReportBug();
                        },
                      ),
                      _DrawerNavTile(
                        palette: p,
                        icon: Icons.logout_rounded,
                        label: s.s('drawer.signout'),
                        destructive: true,
                        onTap: () async {
                          Navigator.of(context).pop();
                          try {
                            await ref.read(authRepositoryProvider).signOut();
                          } catch (_) {
                            // Preview / Supabase yok — sessizce yut.
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yolculuk adı ve en önemli üç metriği tek bakışta gösterir.
class _DrawerStaySummary extends StatelessWidget {
  const _DrawerStaySummary({
    required this.trip,
    required this.palette,
    required this.dayCount,
  });

  final Trip trip;
  final ViewerPalette palette;
  final int dayCount;

  int get _hotelNights {
    var nights = 0;
    for (final hotel in trip.hotels) {
      final checkIn = DateTime.tryParse(hotel.checkIn);
      final checkOut = DateTime.tryParse(hotel.checkOut);
      if (checkIn != null && checkOut != null) {
        nights += checkOut.difference(checkIn).inDays.clamp(0, 60);
      }
    }
    return nights;
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final metrics = [
      (
        Icons.nights_stay_outlined,
        '$_hotelNights',
        s.s('viewer.metric.nights'),
        p.accent
      ),
      (
        Icons.location_on_outlined,
        '${trip.preferences.destinations.length}',
        s.s('viewer.metric.cities'),
        p.accent
      ),
      (
        Icons.calendar_month_outlined,
        '$dayCount',
        s.s('viewer.metric.days'),
        p.accent
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < metrics.length; i++) ...[
            Expanded(
              child: Column(
                children: [
                  Icon(metrics[i].$1, color: metrics[i].$4, size: 20),
                  const SizedBox(height: 7),
                  Text(
                    metrics[i].$2,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metrics[i].$3,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (i < metrics.length - 1)
              Container(width: 1, height: 44, color: p.border),
          ],
        ],
      ),
    );
  }
}

class _DrawerProfileCard extends StatelessWidget {
  const _DrawerProfileCard({
    required this.palette,
    required this.avatarInitial,
    required this.title,
    this.subtitle,
  });

  final ViewerPalette palette;
  final String avatarInitial;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: p.gradientSakura,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              avatarInitial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Drawer'ın 32x32 mor rozeti + 旅 karakteri.
class _DrawerBrandMark extends StatelessWidget {
  const _DrawerBrandMark({required this.palette, this.size = 32});
  final ViewerPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.accent, palette.fuji],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: Colors.white.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '旅',
        style: TextStyle(
          fontFamily: 'NotoSansJPRank',
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.56,
          height: 1.0,
        ),
      ),
    );
  }
}

/// Drawer'ın üst kısmı — Japonya hero görseli üzerinde marka, aktif gezi ve
/// kapatma aksiyonu. Görsel `cover` ile üst şeridi doldurur; alt kenarda
/// palete uygun bir gradient scrim ile drawer gövdesine kusursuz karışır.
class _DrawerHero extends StatelessWidget {
  const _DrawerHero({required this.palette, required this.tripTitle});
  final ViewerPalette palette;
  final String tripTitle;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    // Görsel 3:2 (900×600). Kutu daha geniş orana kaçmasın diye hero gövdesini
    // görselin doğal oranına yakın tutuyoruz; böylece cover kırpması minimum
    // kalır ve sahne (Fuji + gökyüzü) bozulmadan durur.
    const heroBody = 150.0;
    return SizedBox(
      height: topInset + heroBody,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1) Arka plan görseli — sahnenin üst kısmını koru (topCenter),
          //    alt kenar zaten scrim ile gövdeye eriyor.
          Image.asset(
            'assets/images/hamb-menu-top-bg.png',
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.35),
            // Görsel yüklenemezse palet gradyanına düş.
            errorBuilder: (_, __, ___) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [p.fuji, p.sakura],
                ),
              ),
            ),
          ),
          // 2) Okunabilirlik scrim'i — alt-ağırlıklı: üst neredeyse şeffaf,
          //    alta doğru koyulaşıp palet bg'sine erir. Beyaz başlık her
          //    temada net durur, hero gövdeye kusursuz akar.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .40, .78, 1],
                colors: [
                  Colors.black.withValues(alpha: .10),
                  Colors.black.withValues(alpha: .02),
                  Colors.black.withValues(alpha: .42),
                  p.bg,
                ],
              ),
            ),
          ),
          // 3a) Üst şerit — marka rozeti solda, kapatma sağda.
          Positioned(
            top: topInset + 10,
            left: 18,
            right: 10,
            child: Row(
              children: [
                _DrawerBrandMark(palette: p, size: 46),
                const Spacer(),
                _DrawerHeroCloseButton(
                  onTap: () => Navigator.of(context).pop(),
                  tooltip:
                      MaterialLocalizations.of(context).closeButtonTooltip,
                ),
              ],
            ),
          ),
          // 3b) Alt şerit — marka adı ve gezi başlığı.
          Positioned(
            left: 18,
            right: 18,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.s('drawer.brand'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                    shadows: [
                      Shadow(
                        color: Color(0x66000000),
                        blurRadius: 8,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tripTitle.isEmpty ? s.s('drawer.tagline') : tripTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .92),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      Shadow(
                        color: Color(0x59000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
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

/// Hero görseli üzerinde okunabilir, cam efektli kapatma düğmesi.
class _DrawerHeroCloseButton extends StatelessWidget {
  const _DrawerHeroCloseButton({required this.onTap, required this.tooltip});
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: .28),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

/// Küçük harfli bölüm başlığı — "KEŞFET", "ARAÇLAR" gibi drawer içi ayraçlar.
class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.label, required this.palette});
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

/// İlgili drawer satırlarını tek bir kartta gruplar.
class _DrawerNavGroup extends StatelessWidget {
  const _DrawerNavGroup({
    required this.palette,
    required this.children,
  });

  final ViewerPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: Divider(color: palette.border, height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

/// Drawer nav satırı — en az 48 px dokunma alanı ve belirgin yön işareti.
class _DrawerNavTile extends StatelessWidget {
  const _DrawerNavTile({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
  final ViewerPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final Color color = destructive ? p.sunset : p.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight:
                          destructive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (!destructive)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: p.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kompakt uçuş özeti — drawer içi. Gidiş/Dönüş yönlerini tek satırda
/// IATA + saat olarak gösterir.
class _DrawerFlightsMini extends StatefulWidget {
  const _DrawerFlightsMini({required this.trip, required this.palette});
  final Trip trip;
  final ViewerPalette palette;

  @override
  State<_DrawerFlightsMini> createState() => _DrawerFlightsMiniState();
}

class _DrawerFlightsMiniState extends State<_DrawerFlightsMini> {
  bool _expanded = false;

  static String _iata(FlightLeg l) {
    final ap = l.airport.trim();
    if (ap.isNotEmpty) return ap.toUpperCase();
    final c = l.city.trim();
    if (c.isEmpty) return '—';
    return c.length > 4 ? c.substring(0, 4).toUpperCase() : c.toUpperCase();
  }

  static String _time(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _dateShort(String iso, AppLang lang) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    const trMonths = [
      '',
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];
    const enMonths = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = lang == AppLang.en ? enMonths[d.month] : trMonths[d.month];
    return '${d.day} $m ${d.year}';
  }

  /// Aynı gün olmayan varış — "+1" göstermek için.
  int _dayOffset(String depIso, String arrIso) {
    final dep = DateTime.tryParse(depIso);
    final arr = DateTime.tryParse(arrIso);
    if (dep == null || arr == null) return 0;
    final depDate = DateTime(dep.year, dep.month, dep.day);
    final arrDate = DateTime(arr.year, arr.month, arr.day);
    return arrDate.difference(depDate).inDays;
  }

  Widget _legCard({
    required BuildContext context,
    required String tripLabel,
    required List<FlightLeg> legs,
  }) {
    final p = widget.palette;
    final s = LanguageScope.of(context);
    if (legs.isEmpty) return const SizedBox.shrink();
    final from = legs.first;
    final to = legs.last;
    final offset = _dayOffset(from.dateTime, to.dateTime);
    final hopsCount = legs.length - 1; // aktarma sayısı
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  tripLabel,
                  style: TextStyle(
                    color: p.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '·',
                  style: TextStyle(color: p.textMuted, fontSize: 11),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _dateShort(from.dateTime, s.lang),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _time(from.dateTime),
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        from.city.isNotEmpty
                            ? '${from.city} (${_iata(from)})'
                            : _iata(from),
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.flight, size: 18, color: p.accent),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _time(to.dateTime),
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            if (offset > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 2, top: 2),
                                child: Text(
                                  '+$offset',
                                  style: TextStyle(
                                    color: p.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        to.city.isNotEmpty
                            ? '${to.city} (${_iata(to)})'
                            : _iata(to),
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (hopsCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                s.p(
                  hopsCount == 1
                      ? 'drawer.flights.stops'
                      : 'drawer.flights.stops.plural',
                  {'n': '$hopsCount'},
                ),
                style: TextStyle(
                  color: p.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outbound = widget.trip.flights.outbound;
    final ret = widget.trip.flights.returnLegs;
    final tripsCount = (outbound.isNotEmpty ? 1 : 0) + (ret.isNotEmpty ? 1 : 0);
    final p = widget.palette;
    final s = LanguageScope.of(context);
    if (tripsCount == 0) {
      return _DrawerAddCard(
        palette: p,
        icon: Icons.flight_takeoff,
        iconColor: p.accent,
        title: s.s('drawer.flights.add'),
        planId: widget.trip.id,
      );
    }
    return _DrawerCollapsible(
      palette: p,
      expanded: _expanded,
      onToggle: () => setState(() => _expanded = !_expanded),
      icon: Icons.flight_takeoff,
      iconColor: p.accent,
      title: s.s('viewer.flights').replaceAll('✈️ ', ''),
      badge: tripsCount == 0
          ? s.s('drawer.flights.empty')
          : s.p('drawer.flights.count', {'n': '$tripsCount'}),
      child: tripsCount == 0
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (outbound.isNotEmpty)
                    _legCard(
                      context: context,
                      tripLabel: s.p('drawer.flights.leg', {'n': '1'}),
                      legs: outbound,
                    ),
                  if (ret.isNotEmpty)
                    _legCard(
                      context: context,
                      tripLabel: s.p(
                        'drawer.flights.leg',
                        {'n': outbound.isNotEmpty ? '2' : '1'},
                      ),
                      legs: ret,
                    ),
                ],
              ),
            ),
    );
  }
}

/// Drawer içi konaklama bölümü — default kapalı, "N otel" badge; açıldığında
/// her otel kartı (ad + şehir + check-in/out tarih aralığı).
class _DrawerHotelsMini extends StatefulWidget {
  const _DrawerHotelsMini({required this.trip, required this.palette});
  final Trip trip;
  final ViewerPalette palette;

  @override
  State<_DrawerHotelsMini> createState() => _DrawerHotelsMiniState();
}

class _DrawerHotelsMiniState extends State<_DrawerHotelsMini> {
  bool _expanded = false;

  static String _dateShort(String iso, AppLang lang) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    const trMonths = [
      '',
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];
    const enMonths = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = lang == AppLang.en ? enMonths[d.month] : trMonths[d.month];
    return '${d.day} $m';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = LanguageScope.of(context);
    final hotels = widget.trip.hotels;
    if (hotels.isEmpty) {
      return _DrawerAddCard(
        palette: p,
        icon: Icons.hotel_outlined,
        iconColor: p.accent,
        title: s.s('drawer.hotels.add'),
        planId: widget.trip.id,
      );
    }
    return _DrawerCollapsible(
      palette: p,
      expanded: _expanded,
      onToggle: () => setState(() => _expanded = !_expanded),
      icon: Icons.hotel_outlined,
      iconColor: p.accent,
      title: s.s('viewer.hotels').replaceAll('🏨 ', ''),
      badge: hotels.isEmpty
          ? s.s('drawer.hotels.empty')
          : s.p('drawer.hotels.count', {'n': '${hotels.length}'}),
      child: hotels.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final h in hotels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: p.gold.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.business_center_outlined,
                                size: 18,
                                color: p.gold,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    h.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: p.textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    h.city,
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today_outlined,
                                        size: 11,
                                        color: p.textMuted,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${_dateShort(h.checkIn, s.lang)} — ${_dateShort(h.checkOut, s.lang)}',
                                        style: TextStyle(
                                          color: p.textMuted,
                                          fontSize: 11,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures()
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (h.address.trim().isNotEmpty ||
                                      (h.mapsUrl?.trim().isNotEmpty ??
                                          false)) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      h.address.trim().isEmpty
                                          ? (h.mapsUrl ?? '')
                                          : h.address,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () async {
                                          final ok = await openGoogleMapsSearch(
                                            '${h.name}, ${h.address}, ${h.city}',
                                            mapsUrl: h.mapsUrl,
                                          );
                                          if (!context.mounted || ok) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                s.s('map.openFailed'),
                                              ),
                                            ),
                                          );
                                        },
                                        icon: Icon(
                                          Icons.map_outlined,
                                          size: 14,
                                          color: p.accent,
                                        ),
                                        label: Text(
                                          s.s('hotels.openMap'),
                                          style: TextStyle(
                                            color: p.accent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        style: TextButton.styleFrom(
                                          minimumSize: Size.zero,
                                          padding: EdgeInsets.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Uçuşlar/Konaklama gibi drawer içi açılabilir bölümler için ortak kabuk.
/// Başlıkta: ikon + başlık + badge (sağda) + döner chevron. AnimatedSize
/// ile smooth aç/kapa.
class _DrawerCollapsible extends StatelessWidget {
  const _DrawerCollapsible({
    required this.palette,
    required this.expanded,
    required this.onToggle,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.badge,
    required this.child,
  });

  final ViewerPalette palette;
  final bool expanded;
  final VoidCallback onToggle;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String badge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 16, color: iconColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: iconColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: p.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _DrawerActionSpec {
  const _DrawerActionSpec({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Uçuş/otel gibi henüz doldurulmamış bölümler için "ekle" kartı. Tıklanınca
/// planlayıcının düzenleme adımına gider. Boş bir collapsible yerine net bir
/// yönlendirici davranış sunar.
class _DrawerAddCard extends StatelessWidget {
  const _DrawerAddCard({
    required this.palette,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.planId,
  });

  final ViewerPalette palette;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String planId;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    return Material(
      color: p.elevated,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          context.push('/plans/$planId/edit');
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        s.s('drawer.add.hint'),
                        style: TextStyle(
                          color: p.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.add_circle_outline, size: 20, color: iconColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Drawer içi keşif şeridi — araçlar yan yana, iOS "hızlı aksiyon" tarzı
/// dikey karolar (ikon üstte, etiket altta). Eşit genişlikte dağılır.
class _DrawerActionGrid extends StatelessWidget {
  const _DrawerActionGrid({required this.actions, required this.palette});
  final List<_DrawerActionSpec> actions;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    // IntrinsicHeight: karolar farklı satır sayılarında bile eşit yükseklikte
    // kalır; SingleChildScrollView içinde unbounded-height patlamasını da önler.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _DrawerActionTile(spec: actions[i], palette: p)),
          ],
        ],
      ),
    );
  }
}

/// Tek bir dikey aksiyon karosu.
class _DrawerActionTile extends StatelessWidget {
  const _DrawerActionTile({required this.spec, required this.palette});
  final _DrawerActionSpec spec;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          spec.onTap();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(spec.icon, size: 20, color: p.accent),
                ),
                const SizedBox(height: 8),
                Text(
                  spec.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
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
