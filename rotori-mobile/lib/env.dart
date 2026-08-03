import 'package:flutter/services.dart' show rootBundle;

/// Ortam değişkenleri:
/// 1) Öncelik `--dart-define` (CI/prod için ideal)
/// 2) Fallback: `.env` asset dosyası (lokal hızlı geliştirme)
class Env {
  const Env._();

    static const String _defineSupabaseUrl =
            String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    static const String _defineSupabaseAnonKey =
            String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

    static String _supabaseUrl = _defineSupabaseUrl;
    static String _supabaseAnonKey = _defineSupabaseAnonKey;

    static String get supabaseUrl => _supabaseUrl;
    static String get supabaseAnonKey => _supabaseAnonKey;

    static Future<void> load() async {
        if (_defineSupabaseUrl.isNotEmpty && _defineSupabaseAnonKey.isNotEmpty) {
            _supabaseUrl = _defineSupabaseUrl;
            _supabaseAnonKey = _defineSupabaseAnonKey;
            return;
        }

        try {
            final raw = await rootBundle.loadString('.env');
            final pairs = _parseEnv(raw);
            _supabaseUrl = (_defineSupabaseUrl.isNotEmpty
                            ? _defineSupabaseUrl
                            : (pairs['SUPABASE_URL'] ?? ''))
                    .trim();
            _supabaseAnonKey = (_defineSupabaseAnonKey.isNotEmpty
                            ? _defineSupabaseAnonKey
                            : (pairs['SUPABASE_ANON_KEY'] ?? ''))
                    .trim();
        } catch (_) {
            // .env asset yoksa sessizce boş kalsın; UI zaten yönlendirme gösterir.
        }
    }

    static Map<String, String> _parseEnv(String content) {
        final map = <String, String>{};
        for (final line in content.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
            final idx = trimmed.indexOf('=');
            if (idx <= 0) continue;
            final key = trimmed.substring(0, idx).trim();
            final value = trimmed.substring(idx + 1).trim();
            map[key] = value;
        }
        return map;
    }

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
