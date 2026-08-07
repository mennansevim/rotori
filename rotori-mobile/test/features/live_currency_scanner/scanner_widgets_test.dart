import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:japan_trip/core/l10n.dart';
import 'package:japan_trip/features/live_currency_scanner/application/live_currency_scanner_state.dart';
import 'package:japan_trip/features/live_currency_scanner/domain/currency_code.dart';
import 'package:japan_trip/features/live_currency_scanner/domain/exchange_rate.dart';
import 'package:japan_trip/features/live_currency_scanner/domain/japanese_price_tax_type.dart';
import 'package:japan_trip/features/live_currency_scanner/presentation/pages/scanner_settings_page.dart';
import 'package:japan_trip/features/live_currency_scanner/presentation/widgets/camera_permission_view.dart';
import 'package:japan_trip/features/live_currency_scanner/presentation/widgets/currency_detection_label.dart';
import 'package:japan_trip/features/live_currency_scanner/presentation/widgets/exchange_rate_status.dart';
import 'package:japan_trip/features/viewer/viewer_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, {AppLang lang = AppLang.tr}) => ProviderScope(
      child: LanguageScope(
        lang: lang,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

void main() {
  const palette = ViewerPalette.appleLight;

  testWidgets('izin reddedildi görünümü başlık + tekrar dene', (tester) async {
    var retried = false;
    await tester.pumpWidget(_wrap(CameraPermissionView(
      status: ScannerStatus.permissionDenied,
      palette: palette,
      onRetry: () => retried = true,
    )));
    expect(find.text('Kamera izni gerekli'), findsOneWidget);
    await tester.tap(find.text('Tekrar dene'));
    expect(retried, isTrue);
  });

  testWidgets('kalıcı izin reddinde sistem ayarları butonu', (tester) async {
    await tester.pumpWidget(_wrap(CameraPermissionView(
      status: ScannerStatus.permissionPermanentlyDenied,
      palette: palette,
      onRetry: () {},
      onOpenSettings: () {},
    )));
    expect(find.text('Sistem ayarlarını aç'), findsOneWidget);
  });

  testWidgets('eski kur uyarısı gösterilir', (tester) async {
    await tester.pumpWidget(_wrap(ExchangeRateStatus(
      rate: ExchangeRate(
        baseCurrency: 'JPY',
        targetCurrency: 'TRY',
        rate: Decimal.parse('0.25'),
        fetchedAt: DateTime.utc(2020),
        source: 'test',
      ),
      freshness: RateFreshness.stale,
      palette: palette,
    )));
    expect(find.text('Kur eski olabilir'), findsOneWidget);
  });

  testWidgets('manuel kur rozeti gösterilir', (tester) async {
    await tester.pumpWidget(_wrap(ExchangeRateStatus(
      rate: ExchangeRate(
        baseCurrency: 'JPY',
        targetCurrency: 'TRY',
        rate: Decimal.parse('0.30'),
        fetchedAt: DateTime.now().toUtc(),
        source: 'manual',
        isManual: true,
      ),
      freshness: RateFreshness.fresh,
      palette: palette,
    )));
    expect(find.text('Manuel kur'), findsOneWidget);
    expect(find.text('Kur güncel'), findsOneWidget);
  });

  testWidgets('çeviri etiketi orijinal + çevrilen fiyatı gösterir',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(CurrencyDetectionLabel(
      amountInJpy: 12800,
      converted: 3260,
      exchangeRate: 0.30,
      targetCurrency: CurrencyCode.tryl,
      confidence: 0.9,
      taxType: JapanesePriceTaxType.taxIncluded,
      palette: palette,
      lowConfidenceThreshold: 0.55,
      onTap: () => tapped = true,
    )));
    expect(find.text('¥12.800'), findsOneWidget);
    expect(find.text('₺3.260,00'), findsOneWidget);
    await tester.tap(find.byType(CurrencyDetectionLabel));
    expect(tapped, isTrue);
  });

  testWidgets('ayarlar ekranı hedef para birimi ve manuel kur alanı',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_wrap(const ScannerSettingsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Hedef para birimi'), findsOneWidget);
    expect(find.text('Otomatik kur güncelleme'), findsOneWidget);

    // Manuel kuru aç → alan görünür.
    await tester.tap(find.text('Manuel kur'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 JPY ='), findsOneWidget);
  });
}
