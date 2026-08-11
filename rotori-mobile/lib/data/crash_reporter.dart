import 'package:sentry_flutter/sentry_flutter.dart';

/// Sentry çağrılarını ürün kodundan ayıran küçük sınır.
///
/// DSN tanımlı değilse bütün metotlar no-op olur. Rota JSON'u veya serbest
/// kullanıcı metni Sentry'ye gönderilmez; yalnız hata bağlamındaki düşük
/// kardinaliteli teknik alanlar kabul edilir.
class CrashReporter {
  const CrashReporter._();

  static bool _enabled = false;

  static bool get isEnabled => _enabled;

  static void enable() => _enabled = true;

  static Future<void> setUser(String? userId) async {
    if (!_enabled) return;
    try {
      await Sentry.configureScope(
        (scope) => scope.setUser(
          userId == null ? null : SentryUser(id: userId),
        ),
      );
    } on Object {
      // Gözlem altyapısı ürün akışını asla durdurmaz.
    }
  }

  static Future<void> capture(
    Object error,
    StackTrace stackTrace, {
    required String operation,
    Map<String, Object?> context = const {},
  }) async {
    if (!_enabled) return;
    try {
      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (scope) async {
          await scope.setTag('operation', operation);
          if (context.isNotEmpty) {
            await scope.setContexts('rotori', context);
          }
        },
      );
    } on Object {
      // Crash reporter hatası yeni bir crash üretmemeli.
    }
  }

  static Future<void> breadcrumb(
    String message, {
    required String category,
    Map<String, Object?> data = const {},
  }) async {
    if (!_enabled) return;
    try {
      await Sentry.addBreadcrumb(
        Breadcrumb(
          message: message,
          category: category,
          data: data,
          level: SentryLevel.info,
        ),
      );
    } on Object {
      // Breadcrumb başarısızlığı kullanıcı akışını etkilemez.
    }
  }
}
