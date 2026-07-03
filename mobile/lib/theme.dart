import 'package:flutter/material.dart';

/// Mevcut React viewer'ın koyu temasına yakın bir Material 3 teması.
/// Renkler apps/viewer/src/styles.css içindeki :root token'larından alındı.
class AppTheme {
  const AppTheme._();

  static const Color _bg = Color(0xFF0A0A0F);
  static const Color _card = Color(0xFF12121A);
  static const Color _accent = Color(0xFF7C6AEF); // fuji/night
  static const Color _sakura = Color(0xFFFF8FAB);

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          secondary: _sakura,
          surface: _card,
        ),
        cardTheme: CardThemeData(
          color: _card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
}
