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
    required this.flightExpansionRequest,
    required this.onOpenFlights,
    required this.onOpenThemePicker,
    required this.onOpenBudget,
    required this.onOpenPrep,
    required this.onOpenWeather,
    required this.onOpenFoodGuide,
    required this.onOpenExperienceGuide,
    required this.onReportBug,
  });
  final ViewerPalette palette;
  final Trip trip;
  final int dayCount;
  final int flightExpansionRequest;
  final VoidCallback onOpenFlights;
  final VoidCallback onOpenThemePicker;
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenPrep;
  final VoidCallback onOpenWeather;
  final VoidCallback onOpenFoodGuide;
  final VoidCallback onOpenExperienceGuide;
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
    final checklistTone = Color.lerp(p.sky, p.matcha, .48)!;

    // KEŞFET — bütün araçlar tek sakin inset-group içinde.
    //
    // **Why:** Gradyan vitrinler ile 2×2 renkli karolar, üstteki Yolculuk ve
    // alttaki Hesap bölümlerinin sade dilini bölüyordu. Satır düzeni hem daha
    // hızlı taranıyor hem de büyük yazı boyutunda daha güvenli genişliyor.
    final isPremium = ref.watch(premiumProvider);
    final discoverActions = <_DrawerActionSpec>[
      _DrawerActionSpec(
        itemKey: const ValueKey('drawer-scanner-hero'),
        icon: Icons.document_scanner_outlined,
        label: s.s('scanner.price_tag'),
        hint: s.s('drawer.discover.scanner.heroSub'),
        tone: p.fuji,
        badge: isPremium
            ? s.s('drawer.premium.active')
            : s.s('drawer.premium.label'),
        onTap: () => context.push('/price-tag-scanner'),
      ),
      _DrawerActionSpec(
        itemKey: const ValueKey('drawer-experience-guide'),
        icon: Icons.attractions_rounded,
        label: s.s('viewer.tt.experienceGuide'),
        hint: s.s('drawer.discover.experienceGuide.sub'),
        tone: p.sky,
        onTap: onOpenExperienceGuide,
      ),
      // Rotori Eats üçüncü sırada: yemek, yolculuk sırasında günde birkaç kez
      // açılan araç — hava/bütçe/checklist'in altında kalınca her seferinde
      // listenin sonuna kaydırmak gerekiyordu.
      _DrawerActionSpec(
        itemKey: ValueKey('drawer-action-${s.s('viewer.tt.eats')}'),
        icon: Icons.ramen_dining_rounded,
        label: s.s('viewer.tt.eats'),
        hint: s.s('drawer.discover.eats.short'),
        tone: p.sakura,
        onTap: onOpenFoodGuide,
      ),
      _DrawerActionSpec(
        itemKey: ValueKey('drawer-action-${s.s('viewer.tt.weather')}'),
        icon: Icons.cloud_outlined,
        label: s.s('viewer.tt.weather'),
        hint: s.s('drawer.discover.weather.sub'),
        tone: p.gold,
        onTap: onOpenWeather,
      ),
      _DrawerActionSpec(
        itemKey: ValueKey('drawer-action-${s.s('viewer.tt.budget')}'),
        icon: Icons.account_balance_wallet_outlined,
        label: s.s('viewer.tt.budget'),
        hint: s.s('drawer.discover.budget.sub'),
        tone: p.matcha,
        onTap: onOpenBudget,
      ),
      _DrawerActionSpec(
        itemKey: ValueKey('drawer-action-${s.s('viewer.tt.checklist')}'),
        icon: Icons.checklist_rounded,
        label: s.s('viewer.tt.checklist'),
        hint: s.s('drawer.discover.checklist.sub'),
        tone: checklistTone,
        onTap: onOpenPrep,
      ),
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
                  // "YOLCULUK" başlığı kaldırıldı: altındaki özet kartı zaten
                  // kendini anlatıyor, bir de bölüm etiketi taşımak drawer'ın
                  // en üstünü gereksiz uzatıyordu.
                  _DrawerStaySummary(
                    trip: trip,
                    palette: p,
                    dayCount: dayCount,
                  ),
                  const SizedBox(height: 10),
                  _DrawerFlightsMini(
                    trip: trip,
                    palette: p,
                    expansionRequest: flightExpansionRequest,
                    onAddFlight: onOpenFlights,
                  ),
                  const SizedBox(height: 8),
                  _DrawerHotelsMini(trip: trip, palette: p),
                  const SizedBox(height: 22),
                  _DrawerSectionLabel(
                    label: s.s('drawer.section.discover'),
                    palette: p,
                  ),
                  const SizedBox(height: 8),
                  _DrawerActionGroup(
                    actions: discoverActions,
                    palette: p,
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
                    icon: isGuest ? Icons.explore_rounded : null,
                    title: isGuest ? role : email,
                    subtitle: isGuest ? null : role,
                    onTap: isGuest
                        ? () {
                            Navigator.of(context).pop();
                            context.push('/auth');
                          }
                        : null,
                  ),
                  const SizedBox(height: 8),
                  _DrawerNavGroup(
                    widgetKey: const ValueKey('drawer-account-actions'),
                    palette: p,
                    children: [
                      _DrawerNavTile(
                        palette: p,
                        icon: Icons.palette_outlined,
                        iconColor: p.fuji,
                        label: s.s('viewer.tt.theme'),
                        onTap: () {
                          Navigator.of(context).pop();
                          onOpenThemePicker();
                        },
                      ),
                      _DrawerNavTile(
                        palette: p,
                        icon: Icons.shopping_bag_outlined,
                        iconColor: p.fuji,
                        label: s.s('drawer.nav.travelEssentials'),
                        onTap: () {
                          Navigator.of(context).pop();
                          onOpenPrep();
                        },
                      ),
                      _DrawerNavTile(
                        palette: p,
                        icon: Icons.list_alt_rounded,
                        iconColor: p.gold,
                        label: s.s('drawer.nav.plans'),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go('/plans');
                        },
                      ),
                      _DrawerNavTile(
                        palette: p,
                        icon: Icons.bug_report_outlined,
                        iconColor: p.sunset,
                        label: s.s('bugReport.menu'),
                        onTap: () {
                          Navigator.of(context).pop();
                          onReportBug();
                        },
                      ),
                      // `kDebugMode` yerine `showDebugTools`: önizleme hedefi
                      // release derlendiği için anahtar orada hiç
                      // görünmüyordu, yani premium arkasındaki ekranlar
                      // önizlemede denenemiyordu. Üretim girişi bayrağı hiç
                      // açmıyor — mağaza yapısında yine gizli.
                      if (showDebugTools) _DebugPremiumTile(palette: p),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _DrawerNavGroup(
                    widgetKey: const ValueKey('drawer-signout-group'),
                    palette: p,
                    backgroundColor: p.sakura.withValues(alpha: .07),
                    borderColor: p.sakura.withValues(alpha: .14),
                    children: [
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

  /// Gezinin gerçek gece sayısı — gün sayısının bir eksiği.
  ///
  /// **Why:** Eskiden bu değer yalnızca REZERVE EDİLMİŞ otellerden
  /// toplanıyordu. Yeni üretilen planda otel olmadığı için kart "0 Gece ·
  /// 10 Gün" gibi kendi içinde çelişen bir şey gösteriyordu. Gece sayısı
  /// gezinin uzunluğunun bir gerçeği; rezervasyon durumu ise hemen alttaki
  /// Konaklama satırının işi.
  int get _tripNights => dayCount > 0 ? dayCount - 1 : 0;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);

    // Üç metrik tek satırda. Her metriğin ikonu kendi renginde: göz sayıyı
    // renkten ayırt ediyor, böylece etiketler küçültülebiliyor.
    //
    // Rezervasyon metriği ("3/6 Rezerve") kaldırıldı: aynı bilgiyi hemen
    // alttaki Konaklama satırı otel adı ve tarihleriyle zaten veriyor.
    final metrics = <(IconData, Color, String, String)>[
      (
        Icons.nights_stay_outlined,
        p.fuji,
        '$_tripNights',
        s.s('viewer.metric.nights'),
      ),
      (
        Icons.location_on_outlined,
        p.sky,
        '${trip.preferences.destinations.length}',
        s.s('viewer.metric.cities'),
      ),
      (
        Icons.calendar_month_outlined,
        p.gold,
        '$dayCount',
        s.s('viewer.metric.days'),
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.border),
        boxShadow: [
          BoxShadow(
            color: p.textPrimary.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      // Metrikler genişliğe EŞİT dağıtılır (her biri Expanded).
      //
      // **Why:** Önceden şerit tek bir sola yapışık FittedBox içindeydi —
      // dördüncü metrik ve chevron kalkınca sağda kocaman bir boşluk kaldı.
      // Eşit paylar hem boşluğu bitirir hem ayraçları ortalar.
      child: Row(
        children: [
          for (var i = 0; i < metrics.length; i++) ...[
            if (i > 0) Container(width: 1, height: 30, color: p.border),
            Expanded(
              // Metrik başına scaleDown yalnızca aşırı yazı ölçeğinde devreye
              // girer; üç etiket (Gece/Şehir/Gün) benzer genişlikte olduğu
              // için normal ölçekte hiçbiri küçülmez, boyutlar eşit kalır.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(metrics[i].$1, color: metrics[i].$2, size: 17),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          metrics[i].$3,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        Text(
                          metrics[i].$4,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
    this.icon,
    this.subtitle,
    this.onTap,
  });

  final ViewerPalette palette;
  final String avatarInitial;
  final String title;
  final IconData? icon;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      key: const ValueKey('drawer-profile-card'),
      color: p.sakura.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.sakura.withValues(alpha: .14)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  child: icon == null
                      ? Text(
                          avatarInitial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : Icon(icon, color: Colors.white, size: 18),
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
                if (onTap != null)
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

/// Drawer'ın Rotori marka rozeti (torii).
///
/// Rebrand öncesi buraya gradient bir kutuya yazılmış 旅 karakteri
/// çiziliyordu — bu, ürünün eski **Tabi** kimliğiydi. Rotori logosu yalnız
/// platform launcher ikonu olarak kurulmuştu, yani uygulamanın *dışında*
/// görünüyordu; uygulama içinde hiçbir yer onu çizmiyordu.
///
/// Logo kaynağı opaktır (kendi beyaz yuvarlak zeminini taşır), bu yüzden
/// gradient dolgu gereksizdir; yalnız kırpma + hero fotoğrafı üzerinde
/// okunurluğu koruyan kenarlık ve gölge bırakıldı.
class _DrawerBrandMark extends StatelessWidget {
  const _DrawerBrandMark({required this.palette, this.size = 32});
  final ViewerPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.28);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          'assets/images/rotori-logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Asset çözülemezse rozet kaybolmasın: eski işaret geri düşer.
          errorBuilder: (context, error, stack) => Container(
            width: size,
            height: size,
            color: palette.accent,
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
          ),
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
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
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
            width: 40,
            height: 40,
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
    this.widgetKey,
    this.backgroundColor,
    this.borderColor,
  });

  final ViewerPalette palette;
  final List<Widget> children;
  final Key? widgetKey;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: widgetKey,
      decoration: BoxDecoration(
        color: backgroundColor ?? palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? palette.border),
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
    this.iconColor,
    this.destructive = false,
  });
  final ViewerPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final Color color = destructive ? p.sunset : p.textPrimary;
    final resolvedIconColor = iconColor ?? color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: resolvedIconColor.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: resolvedIconColor),
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
                Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: destructive ? p.sunset : p.textMuted,
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
  const _DrawerFlightsMini({
    required this.trip,
    required this.palette,
    required this.expansionRequest,
    required this.onAddFlight,
  });
  final Trip trip;
  final ViewerPalette palette;
  final int expansionRequest;
  final VoidCallback onAddFlight;

  @override
  State<_DrawerFlightsMini> createState() => _DrawerFlightsMiniState();
}

class _DrawerFlightsMiniState extends State<_DrawerFlightsMini> {
  bool _expanded = false;
  late int _handledExpansionRequest;

  @override
  void initState() {
    super.initState();
    _handledExpansionRequest = widget.expansionRequest;
    _expanded = widget.expansionRequest > 0;
  }

  @override
  void didUpdateWidget(covariant _DrawerFlightsMini oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expansionRequest != _handledExpansionRequest) {
      _handledExpansionRequest = widget.expansionRequest;
      _expanded = true;
    }
  }

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
    final m = L10n.monthsShortFor(lang)[d.month];
    final weekday = L10n.weekdaysFor(lang)[d.weekday];
    final shortWeekday = weekday.length > 3 ? weekday.substring(0, 3) : weekday;
    return '${d.day} $m ${d.year}, $shortWeekday';
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

  String _duration(String depIso, String arrIso) {
    final departure = DateTime.tryParse(depIso);
    final arrival = DateTime.tryParse(arrIso);
    if (departure == null || arrival == null) return '';
    final minutes = arrival.difference(departure).inMinutes;
    if (minutes <= 0) return '';
    return LanguageScope.of(context).p('viewer.flights.duration', {
      'h': '${minutes ~/ 60}',
      'm': (minutes % 60).toString().padLeft(2, '0'),
    });
  }

  Widget _airportBadge(String airport) {
    final p = widget.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        airport,
        style: TextStyle(
          color: p.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  String _tripLabel(String value, AppLang lang) {
    if (lang == AppLang.tr) {
      return value.replaceAll('Gezi', 'GEZİ').toUpperCase();
    }
    return value.toUpperCase();
  }

  Widget _endpoint({
    required FlightLeg leg,
    required bool alignRight,
  }) {
    final p = widget.palette;
    final city = leg.city.trim().isEmpty ? '—' : leg.city.trim();
    final alignment =
        alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          _time(leg.dateTime),
          maxLines: 1,
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 30,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment:
              alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (alignRight) _airportBadge(_iata(leg)),
            if (alignRight) const SizedBox(width: 6),
            Flexible(
              child: Text(
                city,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alignRight ? TextAlign.end : TextAlign.start,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (!alignRight) const SizedBox(width: 6),
            if (!alignRight) _airportBadge(_iata(leg)),
          ],
        ),
      ],
    );
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
    final duration = _duration(from.dateTime, to.dateTime);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _tripLabel(tripLabel, s.lang),
                    style: TextStyle(
                      color: p.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _dateShort(from.dateTime, s.lang),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _endpoint(leg: from, alignRight: false)),
                const SizedBox(width: 10),
                SizedBox(
                  width: 88,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 36,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 18,
                              child: SizedBox(
                                height: 2,
                                child: CustomPaint(
                                  painter: _FlightDashedLinePainter(
                                    color: p.textMuted.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              color: p.card,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              child: Icon(
                                Icons.flight_rounded,
                                color: p.accent,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (duration.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          duration,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: p.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _endpoint(leg: to, alignRight: true),
                      if (offset > 0)
                        Positioned(
                          right: 0,
                          top: -4,
                          child: Text(
                            '+$offset',
                            style: TextStyle(
                              color: p.accent,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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
    // "Uçuş var mı" kararı bacak SAYISINA bakamaz: createEmptyTrip ve
    // buildTripFromCities şehir/havaalanı boş bacaklar üretiyor, bu da
    // kullanıcı hiçbir şey girmemişken dolu bir liste gösteriyordu.
    // tripHasFlightInfo şehir VE havaalanı dolu bir bacak arar.
    // (Bacakların kendisi filtrelenmez — dateTime'ı dolu, detayı eksik bir
    // bacak listede "—" olarak görünmeye devam eder.)
    if (!tripHasFlightInfo(widget.trip)) {
      return _DrawerAddCard(
        palette: p,
        icon: Icons.flight_takeoff,
        iconColor: p.accent,
        title: s.s('drawer.flights.add'),
        planId: widget.trip.id,
        route: '/plans/${widget.trip.id}/flights',
        onTap: widget.onAddFlight,
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

class _FlightDashedLinePainter extends CustomPainter {
  const _FlightDashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dashWidth = 6.0;
    const gap = 6.0;
    for (var x = 0.0; x < size.width; x += dashWidth + gap) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(
            (x + dashWidth).clamp(0.0, size.width).toDouble(), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FlightDashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
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
        route: '/plans/${widget.trip.id}/hotels/new',
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
                  // Liste doluyken de ekleme yolu açık kalmalı.
                  //
                  // **Why:** `_DrawerAddCard` yalnız `hotels.isEmpty` dalında
                  // çiziliyordu ve `/plans/:id/hotels/new` rotasının uygulamada
                  // başka hiçbir girişi yok. Sonuç: ilk otel eklendiği anda
                  // ikinciyi eklemek imkânsız hale geliyordu — çok şehirli
                  // planlarda (Tokyo + Kyoto) rezervasyon yarım kalıyordu.
                  _DrawerInlineAddRow(
                    key: const ValueKey('drawer-hotels-add-another'),
                    palette: p,
                    icon: Icons.hotel_outlined,
                    label: s.s('hotels.addAnother'),
                    route: '/plans/${widget.trip.id}/hotels/new',
                  ),
                ],
              ),
            ),
    );
  }
}

/// Açılmış bir drawer bölümünün sonunda duran ince ekleme satırı.
///
/// `_DrawerAddCard`'ın boş-durum kartından kasten daha sakin: bölüm zaten
/// içerik gösteriyorken ekleme aksiyonu listenin kendisiyle görsel olarak
/// yarışmamalı.
class _DrawerInlineAddRow extends StatelessWidget {
  const _DrawerInlineAddRow({
    super.key,
    required this.palette,
    required this.icon,
    required this.label,
    required this.route,
  });

  final ViewerPalette palette;
  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          context.push(route);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.accent.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 16, color: p.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.add_circle_outline, size: 18, color: p.accent),
              ],
            ),
          ),
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
        color: p.card,
        borderRadius: BorderRadius.circular(18),
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
    required this.itemKey,
    required this.icon,
    required this.label,
    required this.hint,
    required this.tone,
    required this.onTap,
    this.badge,
  });
  final Key itemKey;
  final IconData icon;
  final String label;

  /// Tek satırlık açıklama — karonun ne işe yaradığını dokunmadan anlatır.
  final String hint;

  /// İkon rozetinin tonu; yüzeyin kendisi bütün satırlarda nötr kalır.
  final Color tone;
  final VoidCallback onTap;
  final String? badge;
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
    this.route,
    this.onTap,
  });

  final ViewerPalette palette;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String planId;

  /// Hedef route. Verilmezse eski wizard'a (`/plans/:id/edit`) düşer —
  /// bu, wizard sökülene kadar hâlâ bağlı olan kartlar için geçici bir
  /// güvenlik ağıdır.
  final String? route;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ??
            () {
              Navigator.of(context).pop();
              context.push(route ?? '/plans/$planId/edit');
            },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
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

/// Keşif araçlarını Hesap bölümüyle aynı sakin inset-group düzeninde toplar.
class _DrawerActionGroup extends StatelessWidget {
  const _DrawerActionGroup({required this.actions, required this.palette});
  final List<_DrawerActionSpec> actions;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('drawer-discover-group'),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            _DrawerActionTile(spec: actions[i], palette: palette),
            if (i < actions.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 64),
                child: Divider(color: palette.border, height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

/// Tek keşif satırı — görünür ad/açıklama, sakin ikon rozeti ve yön işareti.
class _DrawerActionTile extends StatelessWidget {
  const _DrawerActionTile({required this.spec, required this.palette});
  final _DrawerActionSpec spec;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      button: true,
      label: '${spec.label}. ${spec.hint}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: spec.itemKey,
          onTap: () {
            Navigator.of(context).pop();
            spec.onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: spec.tone.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Icon(spec.icon, size: 20, color: spec.tone),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                spec.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (spec.badge != null) ...[
                              const SizedBox(width: 7),
                              _DrawerPremiumChip(
                                label: spec.badge!,
                                palette: p,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          spec.hint,
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

class _DrawerPremiumChip extends StatelessWidget {
  const _DrawerPremiumChip({
    required this.label,
    required this.palette,
  });

  final String label;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.accentStrong,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Debug: premium mod aç/kapa. Sadece debug build'lerde görünür.
///
/// Durum artık [premiumProvider]'da — bu widget yalnızca onu okuyup yazıyor.
/// Eskiden kendi yerel state'i vardı ve prefs'i doğrudan yazıyordu; diğer
/// ekranlar değişiklikten haberdar olmadığı için premium açılmış olmasına
/// rağmen rota optimizasyonu paywall göstermeye devam ediyordu.
class _DebugPremiumTile extends ConsumerWidget {
  const _DebugPremiumTile({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = palette;
    final premium = ref.watch(premiumProvider);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(premiumProvider.notifier).toggle(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  premium ? Icons.workspace_premium : Icons.lock_outline,
                  size: 20,
                  color: premium ? p.gold : p.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Premium (debug)',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: premium,
                  activeThumbColor: p.gold,
                  onChanged: (v) =>
                      ref.read(premiumProvider.notifier).setPremium(v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
