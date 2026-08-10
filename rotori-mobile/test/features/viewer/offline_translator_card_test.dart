import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/data/offline_translation.dart';
import 'package:rotori/features/viewer/offline_translator_card.dart';
import 'package:rotori/features/viewer/viewer_theme.dart';

void main() {
  testWidgets('ücretsiz kullanıcıda çevirmen premium kilidiyle açılır',
      (tester) async {
    final gateway = _FakeTranslationGateway(supported: true, ready: true);

    await tester.pumpWidget(_app(gateway, isPremium: false));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offline-translator-premium-lock')),
        findsOneWidget);
    expect(find.text('Premium ile çevrimdışı çeviri'), findsOneWidget);
    expect(find.byKey(const Key('offline-translator-input')), findsNothing);
    expect(gateway.modelCheckCalls, 0);
  });

  testWidgets('premium açılınca kilit kalkar ve model kontrolü başlar',
      (tester) async {
    final gateway = _FakeTranslationGateway(supported: true, ready: true);
    final premium = ValueNotifier<bool>(false);
    addTearDown(premium.dispose);

    await tester.pumpWidget(_appWithPremium(gateway, premium));
    expect(find.byKey(const Key('offline-translator-input')), findsNothing);

    premium.value = true;
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offline-translator-premium-lock')),
        findsNothing);
    expect(find.byKey(const Key('offline-translator-input')), findsOneWidget);
    expect(gateway.modelCheckCalls, 1);
  });

  testWidgets('web/unsupported durumda mobil kullanım bilgisini gösterir',
      (tester) async {
    final gateway = _FakeTranslationGateway(supported: false, ready: false);

    await tester.pumpWidget(_app(gateway));

    expect(find.text('Cepte Çevirmen'), findsOneWidget);
    expect(find.textContaining('iPhone ve Android'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('offline-translator-input')),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('hazır modellerle Türkçeden Japoncaya cihazda çevirir',
      (tester) async {
    final gateway = _FakeTranslationGateway(
      supported: true,
      ready: true,
      translatedText: '東京駅はどこですか？',
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('offline-translator-input')),
      'Tokyo İstasyonu nerede?',
    );
    await tester.ensureVisible(
      find.byKey(const Key('offline-translator-submit')),
    );
    await tester.tap(find.byKey(const Key('offline-translator-submit')));
    await tester.pumpAndSettle();

    expect(find.text('東京駅はどこですか？'), findsOneWidget);
    expect(gateway.translateCalls, 1);
    expect(gateway.lastSource, OfflineTranslationLanguage.turkish);
    expect(gateway.lastTarget, OfflineTranslationLanguage.japanese);
  });

  testWidgets('ilk kullanımda dil paketlerini indirir ve yönü değiştirebilir',
      (tester) async {
    final gateway = _FakeTranslationGateway(supported: true, ready: false);

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(find.textContaining('yaklaşık 60 MB'), findsOneWidget);
    await tester.tap(find.byKey(const Key('offline-translator-download')));
    await tester.pumpAndSettle();
    expect(gateway.downloadCalls, 1);

    await tester.tap(find.byKey(const Key('offline-translator-swap')));
    await tester.pump();
    expect(find.text('日本語'), findsWidgets);
    expect(find.text('Türkçe'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('offline-translator-input')),
      '東京駅はどこですか？',
    );
    await tester.ensureVisible(
      find.byKey(const Key('offline-translator-submit')),
    );
    await tester.tap(find.byKey(const Key('offline-translator-submit')));
    await tester.pumpAndSettle();

    expect(gateway.lastSource, OfflineTranslationLanguage.japanese);
    expect(gateway.lastTarget, OfflineTranslationLanguage.turkish);
  });
}

Widget _app(
  OfflineTranslationGateway gateway, {
  bool isPremium = true,
}) {
  const palette = ViewerPalette.appleLight;
  return MaterialApp(
    home: Scaffold(
      backgroundColor: palette.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: OfflineTranslatorCard(
          palette: palette,
          lang: AppLang.tr,
          isPremium: isPremium,
          gateway: gateway,
        ),
      ),
    ),
  );
}

Widget _appWithPremium(
  OfflineTranslationGateway gateway,
  ValueNotifier<bool> premium,
) {
  const palette = ViewerPalette.appleLight;
  return MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: premium,
        builder: (_, value, __) => OfflineTranslatorCard(
          palette: palette,
          lang: AppLang.tr,
          isPremium: value,
          gateway: gateway,
        ),
      ),
    ),
  );
}

final class _FakeTranslationGateway implements OfflineTranslationGateway {
  _FakeTranslationGateway({
    required this.supported,
    required this.ready,
    this.translatedText = 'Tokyo İstasyonu nerede?',
  });

  final bool supported;
  bool ready;
  final String translatedText;
  int downloadCalls = 0;
  int translateCalls = 0;
  int modelCheckCalls = 0;
  OfflineTranslationLanguage? lastSource;
  OfflineTranslationLanguage? lastTarget;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> areModelsReady({
    required OfflineTranslationLanguage source,
    required OfflineTranslationLanguage target,
  }) async {
    modelCheckCalls += 1;
    return ready;
  }

  @override
  Future<void> downloadModels({
    required OfflineTranslationLanguage source,
    required OfflineTranslationLanguage target,
  }) async {
    downloadCalls += 1;
    ready = true;
  }

  @override
  Future<String> translate({
    required String text,
    required OfflineTranslationLanguage source,
    required OfflineTranslationLanguage target,
  }) async {
    translateCalls += 1;
    lastSource = source;
    lastTarget = target;
    return translatedText;
  }

  @override
  Future<void> close() async {}
}
