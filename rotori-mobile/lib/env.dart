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
  static const String _defineSentryDsn =
      String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  static const String _defineSentryEnvironment =
      String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: '');
  static const String _defineSentryTracesSampleRate = String.fromEnvironment(
    'SENTRY_TRACES_SAMPLE_RATE',
    defaultValue: '',
  );

  static String _supabaseUrl = _defineSupabaseUrl;
  static String _supabaseAnonKey = _defineSupabaseAnonKey;
  static String _sentryDsn = _defineSentryDsn;
  static String _sentryEnvironment = _defineSentryEnvironment;
  static double _sentryTracesSampleRate =
      double.tryParse(_defineSentryTracesSampleRate) ?? 0.1;

  static String get supabaseUrl => _supabaseUrl;
  static String get supabaseAnonKey => _supabaseAnonKey;
  static String get sentryDsn => _sentryDsn;
  static String get sentryEnvironment => _sentryEnvironment;
  static double get sentryTracesSampleRate => _sentryTracesSampleRate;

  static Future<void> load() async {
    Map<String, String> pairs = const {};
    try {
      pairs = _parseEnv(await rootBundle.loadString('.env'));
    } on Object {
      // Asset yoksa dart-define değerleriyle devam edilir.
    }

    _supabaseUrl = _pick(_defineSupabaseUrl, pairs['SUPABASE_URL']);
    _supabaseAnonKey =
        _pick(_defineSupabaseAnonKey, pairs['SUPABASE_ANON_KEY']);
    _sentryDsn = _pick(_defineSentryDsn, pairs['SENTRY_DSN']);
    _sentryEnvironment =
        _pick(_defineSentryEnvironment, pairs['SENTRY_ENVIRONMENT']);
    _sentryTracesSampleRate = double.tryParse(
          _pick(
            _defineSentryTracesSampleRate,
            pairs['SENTRY_TRACES_SAMPLE_RATE'],
          ),
        ) ??
        0.1;
  }

  static String _pick(String defineValue, String? assetValue) =>
      (defineValue.isNotEmpty ? defineValue : (assetValue ?? '')).trim();

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

  static bool get isSentryConfigured => sentryDsn.isNotEmpty;
}
