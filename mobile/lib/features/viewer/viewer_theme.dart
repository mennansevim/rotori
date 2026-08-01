// Viewer tema sistemi — React viewer'ın `data-theme` üç temasının 1:1 portu.
//
// - `ViewerThemeId`: japanDark, appleLight (varsayılan), sakuraSoft.
// - `ViewerPalette`: her temanın renk token'ları (React styles.css ile birebir).
//   Ayrıca `toThemeData()` ile Material3 ThemeData üretir; böylece alt widget'lar
//   (place_detail_sheet, RewardMapScreen) `Theme.of(context)` üzerinden uyumlanır.
// - `viewerThemeProvider`: seçili temayı SharedPreferences'a ('viewer:theme')
//   kalıcı yazan StateNotifierProvider.
// - `ViewerPaletteScope` / `ViewerPalette.of(context)`: ThemeData'ya sığmayan
//   gradient/özel token'ları alt ağaca taşıyan InheritedWidget.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/plans_repository.dart';

enum ViewerThemeId { japanDark, appleLight, sakuraSoft }

extension ViewerThemeIdX on ViewerThemeId {
  /// SharedPreferences / React ile uyumlu string anahtar.
  String get storageKey => switch (this) {
        ViewerThemeId.japanDark => 'japan-dark',
        ViewerThemeId.appleLight => 'apple-light',
        ViewerThemeId.sakuraSoft => 'sakura-soft',
      };

  /// Tema seçici için Türkçe etiket.
  String get label => switch (this) {
        ViewerThemeId.japanDark => 'Japon Gecesi',
        ViewerThemeId.appleLight => 'Apple Aydınlık',
        ViewerThemeId.sakuraSoft => 'Sakura Yumuşak',
      };

  static ViewerThemeId fromStorage(String? raw) => switch (raw) {
        'japan-dark' => ViewerThemeId.japanDark,
        'apple-light' => ViewerThemeId.appleLight,
        'sakura-soft' => ViewerThemeId.sakuraSoft,
        _ => ViewerThemeId.appleLight,
      };
}

/// Temaya özel renk/gradient token'ları (React styles.css birebir).
class ViewerPalette {
  const ViewerPalette({
    required this.id,
    required this.brightness,
    required this.bg,
    required this.card,
    required this.cardHover,
    required this.elevated,
    required this.accent,
    required this.accentStrong,
    required this.sakura,
    required this.fuji,
    required this.sky,
    required this.gold,
    required this.matcha,
    required this.sunset,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderStrong,
    required this.gradientTitle,
    required this.gradientNight,
    required this.gradientSakura,
    required this.topBar,
    required this.topBarOnColor,
  });

  final ViewerThemeId id;
  final Brightness brightness;
  final Color bg;
  final Color card;
  final Color cardHover;
  final Color elevated;
  final Color accent;
  final Color accentStrong;
  final Color sakura;
  final Color fuji;
  final Color sky;
  final Color gold;
  final Color matcha;
  final Color sunset;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color borderStrong;
  final List<Color> gradientTitle;
  final List<Color> gradientNight;
  final List<Color> gradientSakura;

  /// Üst durum barının gradient renkleri (tek renk ise iki eşit değer).
  final List<Color> topBar;

  /// Üst durum barındaki metin/ikon rengi.
  final Color topBarOnColor;

  static const ViewerPalette japanDark = ViewerPalette(
    id: ViewerThemeId.japanDark,
    brightness: Brightness.dark,
    bg: Color(0xFF0A0A0F),
    card: Color(0xFF12121A),
    cardHover: Color(0xFF1A1A25),
    elevated: Color(0xFF1A1A25),
    accent: Color(0xFF7C6AEF),
    accentStrong: Color(0xFF5C4DBD),
    sakura: Color(0xFFFF8FAB),
    fuji: Color(0xFF7C6AEF),
    sky: Color(0xFF64B5F6),
    gold: Color(0xFFFFD54F),
    matcha: Color(0xFF81C784),
    sunset: Color(0xFFFF7043),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF9E9EB3),
    textMuted: Color(0xFF6B6B80),
    border: Color(0x14FFFFFF), // white @ 0.08
    borderStrong: Color(0x29FFFFFF), // white @ 0.16
    gradientTitle: [Color(0xFFFFFFFF), Color(0xFFFF8FAB), Color(0xFF7C6AEF)],
    gradientNight: [Color(0xFF7C6AEF), Color(0xFF5C4DBD)],
    gradientSakura: [Color(0xFFFF8FAB), Color(0xFFFFC3D7)],
    topBar: [Color(0xF27C6AEF), Color(0xEBFF8FAB)], // 0.95 / 0.92
    topBarOnColor: Color(0xFFFFFFFF),
  );

  static const ViewerPalette appleLight = ViewerPalette(
    id: ViewerThemeId.appleLight,
    brightness: Brightness.light,
    bg: Color(0xFFF5F5F7),
    card: Color(0xFFFFFFFF),
    cardHover: Color(0xFFFBFBFD),
    elevated: Color(0xFFFFFFFF),
    accent: Color(0xFF0071E3),
    accentStrong: Color(0xFF0A6DCA),
    sakura: Color(0xFFFF375F),
    fuji: Color(0xFF5856D6),
    sky: Color(0xFF007AFF),
    gold: Color(0xFFFF9500),
    matcha: Color(0xFF34C759),
    sunset: Color(0xFFFF3B30),
    textPrimary: Color(0xFF1D1D1F),
    textSecondary: Color(0xFF515154),
    textMuted: Color(0xFF86868B),
    border: Color(0x14000000), // black @ 0.08
    borderStrong: Color(0x29000000), // black @ 0.16
    gradientTitle: [Color(0xFF1D1D1F), Color(0xFF5856D6)],
    gradientNight: [Color(0xFF5856D6), Color(0xFF3634A3)],
    gradientSakura: [Color(0xFFFF375F), Color(0xFFFF9AA5)],
    topBar: [Color(0xE6FBFBFD), Color(0xE6FBFBFD)], // solid 0.9
    topBarOnColor: Color(0xFF1D1D1F),
  );

  static const ViewerPalette sakuraSoft = ViewerPalette(
    id: ViewerThemeId.sakuraSoft,
    brightness: Brightness.light,
    bg: Color(0xFFFFF5F8),
    card: Color(0xFFFFFFFF),
    cardHover: Color(0xFFFFF0F4),
    elevated: Color(0xFFFFFFFF),
    accent: Color(0xFFD6477F),
    accentStrong: Color(0xFFB53266),
    sakura: Color(0xFFFF8FAB),
    fuji: Color(0xFFB07CD6),
    sky: Color(0xFF5EB9D6),
    gold: Color(0xFFD9A44A),
    matcha: Color(0xFF7FB87F),
    sunset: Color(0xFFE07A5F),
    textPrimary: Color(0xFF3D1A2B),
    textSecondary: Color(0xFF6C4253),
    textMuted: Color(0xFF9A7585),
    border: Color(0x1FD6477F), // rgba(214,71,127,0.12)
    borderStrong: Color(0x47D6477F), // rgba(214,71,127,0.28)
    gradientTitle: [Color(0xFFD6477F), Color(0xFFB07CD6)],
    gradientNight: [Color(0xFFB07CD6), Color(0xFFD6477F)],
    gradientSakura: [Color(0xFFFF8FAB), Color(0xFFFFD0DD)],
    topBar: [Color(0xEBD6477F), Color(0xE0FF8FAB)], // 0.92 / 0.88
    topBarOnColor: Color(0xFFFFFFFF),
  );

  static ViewerPalette forId(ViewerThemeId id) => switch (id) {
        ViewerThemeId.japanDark => japanDark,
        ViewerThemeId.appleLight => appleLight,
        ViewerThemeId.sakuraSoft => sakuraSoft,
      };

  /// En yakın [ViewerPaletteScope] üzerinden paleti çöz.
  static ViewerPalette of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ViewerPaletteScope>();
    return scope?.palette ?? appleLight;
  }

  /// Alt widget'ların (place_detail_sheet, RewardMapScreen) uyumlanması için
  /// Material3 ThemeData üretir.
  ThemeData toThemeData() {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      secondary: sakura,
      surface: card,
      onSurface: textPrimary,
    );
    return base.copyWith(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: colorScheme,
      canvasColor: bg,
      cardColor: card,
      dividerColor: border,
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      iconTheme: IconThemeData(color: textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: card,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
    );
  }
}

/// Paleti alt ağaca taşıyan InheritedWidget (gradient token'lar ThemeData'ya
/// sığmadığı için).
class ViewerPaletteScope extends InheritedWidget {
  const ViewerPaletteScope({
    super.key,
    required this.palette,
    required super.child,
  });

  final ViewerPalette palette;

  @override
  bool updateShouldNotify(ViewerPaletteScope oldWidget) =>
      oldWidget.palette.id != palette.id;
}

// ---------------------------------------------------------------------------
// Riverpod — seçili tema (kalıcı).
// ---------------------------------------------------------------------------

class ViewerThemeNotifier extends StateNotifier<ViewerThemeId> {
  ViewerThemeNotifier(this._ref) : super(ViewerThemeId.appleLight) {
    _load();
  }

  final Ref _ref;
  static const _key = 'viewer:theme';

  Future<void> _load() async {
    final prefs = await _ref.read(sharedPrefsProvider.future);
    state = ViewerThemeIdX.fromStorage(prefs.getString(_key));
  }

  Future<void> set(ViewerThemeId id) async {
    state = id;
    final prefs = await _prefs();
    await prefs.setString(_key, id.storageKey);
  }

  Future<SharedPreferences> _prefs() async {
    final cached = _ref.read(sharedPrefsProvider).valueOrNull;
    if (cached != null) return cached;
    return _ref.read(sharedPrefsProvider.future);
  }
}

final viewerThemeProvider =
    StateNotifierProvider<ViewerThemeNotifier, ViewerThemeId>(
  (ref) => ViewerThemeNotifier(ref),
);

/// Seçili temanın paleti.
final viewerPaletteProvider = Provider<ViewerPalette>((ref) {
  return ViewerPalette.forId(ref.watch(viewerThemeProvider));
});
