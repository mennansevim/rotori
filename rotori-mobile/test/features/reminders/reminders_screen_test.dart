import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/data/reminders_store.dart';
import 'package:rotori/features/notifications/notifications_service.dart';
import 'package:rotori/features/plans/premium_provider.dart';
import 'package:rotori/features/reminders/reminders_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotifications implements NotificationsService {
  final List<Reminder> scheduled = [];

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermissionIfNeeded() async => true;

  @override
  Future<void> schedule(Reminder reminder) async => scheduled.add(reminder);

  @override
  Future<void> cancel(Reminder reminder) async {}

  @override
  Future<void> cancelAll() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({kPremiumPrefsKey: true}));

  testWidgets('ücretsiz kullanıcı ekleme yerine Rotori Pro kapısını görür',
      (tester) async {
    SharedPreferences.setMockInitialValues({kPremiumPrefsKey: false});
    tester.view.physicalSize = const Size(430, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: LanguageScope(
          lang: AppLang.tr,
          child: MaterialApp(home: RemindersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-reminder')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('reminder-premium-sheet')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rotori-premium-sheet')),
      findsOneWidget,
    );
    expect(find.text('Rotori Pro özelliği'), findsWidgets);
    expect(find.byKey(const ValueKey('reminder-preset-shinkansen-smartex')),
        findsNothing);
  });

  testWidgets('hazır seçimler ve özel hatırlatıcı sonradan eklenebilir',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notifications = _FakeNotifications();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsServiceProvider.overrideWithValue(notifications),
        ],
        child: const LanguageScope(
          lang: AppLang.tr,
          child: MaterialApp(home: RemindersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-reminder')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reminder-preset-shinkansen-smartex')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-preset-tokyo-disney')),
        findsOneWidget);
    expect(find.textContaining('09:00'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('custom-reminder-toggle')),
      450,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(
      find.byType(Scrollable).last,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-reminder-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('custom-reminder-title')),
      'Ghibli bileti',
    );
    await tester.tap(find.byKey(const ValueKey('custom-reminder-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-reminders')));
    await tester.pumpAndSettle();

    expect(find.text('Ghibli bileti'), findsOneWidget);
    expect(notifications.scheduled, hasLength(1));
  });

  // REGRESYON: hazır seçim işaretlendiğinde "Seçilen hatırlatıcıları ekle"
  // pasif kalıyordu ve NEDENİ hiçbir yerde yazmıyordu. `_canSave` her seçim
  // için ziyaret tarihi şart koşuyor; tarih alanı ise altı kartlık ızgaranın
  // altında, kaydırmadan görünmüyor. Kullanıcı için buton sebepsiz bozuktu.
  testWidgets('seçim yapılıp tarih girilmeyince eksik açıkça söylenir',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notifications = _FakeNotifications();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsServiceProvider.overrideWithValue(notifications),
        ],
        child: const LanguageScope(
          lang: AppLang.tr,
          child: MaterialApp(home: RemindersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-reminder')));
    await tester.pumpAndSettle();

    // Hiçbir şey seçilmemişken de buton pasif — ama nedeni yazılı.
    expect(_saveButton(tester).onPressed, isNull);
    expect(find.textContaining('Bir hazır seçim işaretle'), findsOneWidget);

    // Bir hazır seçim işaretle.
    await tester
        .tap(find.byKey(const ValueKey('reminder-preset-tokyo-disney')));
    await tester.pumpAndSettle();

    // Buton hâlâ pasif — çünkü ziyaret tarihi yok. Artık BUNU söylüyor.
    expect(_saveButton(tester).onPressed, isNull);
    expect(find.textContaining('ziyaret tarihi gerekiyor'), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-blocked-hint')), findsOneWidget);

    // İpucuna dokununca tarih bölümü görünür olur.
    await tester.tap(find.byKey(const ValueKey('reminder-blocked-hint')));
    await tester.pumpAndSettle();
    expect(find.text('Ziyaret tarihleri'), findsOneWidget);

    // Tarih girilince buton aktifleşir ve engel açıklaması kalkar.
    await tester.tap(find.text('Ziyaret tarihini seç'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(_saveButton(tester).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('reminder-blocked-hint')), findsNothing);
  });

  testWidgets(
      'hatırlatıcılar biletler gibi net bir başlık ve ekleme aksiyonu sunar',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: LanguageScope(
          lang: AppLang.tr,
          child: MaterialApp(home: RemindersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reminders-scroll')), findsOneWidget);
    expect(find.byKey(const ValueKey('reminders-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-reminder')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-first-reminder')), findsOneWidget);
  });

  testWidgets('390pt ve büyük yazı ölçeğinde taşma üretmez', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: LanguageScope(
          lang: AppLang.tr,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
              ),
              child: child!,
            ),
            home: const RemindersScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

FilledButton _saveButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-reminders')),
    );
