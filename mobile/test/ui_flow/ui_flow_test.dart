// UI Otomasyon — "Uygulamayı aç, menüye gir, gezin" tarzı gerçek kullanıcı
// jestleriyle koşulan testler. `flutter test integration_test/ui_flow_test.dart`
// ile headless VM'de çalışır; cihaz/simulator gerektirmez çünkü Supabase
// çağrıları yapan servisleri ProviderScope override ile sahte veriyoruz.
//
// Her test gerçek widget tree'yi mount eder ve şunları yapar:
//   • find.byType / find.text ile elemanları BULUR
//   • tester.enterText / tester.tap ile kullanıcı gibi yazı GİRER ve BASAR
//   • tester.pump() ile frame ilerletir, sonraki ekranı görür
//   • expect ile "kullanıcı bunu görmeli" senaryosunu doğrular
//
// Dashboard'da "UI Otomasyon" suite'i olarak görünür.
//
// NOT: bu dosya @Tags(['uiflow']) ile işaretlidir; refresh-dashboard.sh
// Flutter genel suite'ini `--exclude-tags uiflow` ile koşar ve UI Otomasyon
// suite'ini ayrıca çalıştırır — böylece 6 test iki kez sayılmaz.
@Tags(['uiflow'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:japan_trip/core/l10n.dart';
import 'package:japan_trip/data/reminders_store.dart';
import 'package:japan_trip/features/auth/auth_screen.dart';
import 'package:japan_trip/features/notifications/notifications_service.dart';
import 'package:japan_trip/features/reminders/reminders_screen.dart';

// ---------------------------------------------------------------------------
// Fake bildirim servisi — RemindersScreen içindeki cancel/cancelAll çağrıları
// gerçek platform kanalını çalıştırmasın. Yalnız çağrı sayacı tutar.
// ---------------------------------------------------------------------------
class _FakeNotifs implements NotificationsService {
  int cancelAllCalls = 0;
  final cancelledIds = <String>[];
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermissionIfNeeded() async => true;
  @override
  Future<void> schedule(Reminder r) async {}
  @override
  Future<void> cancel(Reminder r) async => cancelledIds.add(r.id);
  @override
  Future<void> cancelAll() async => cancelAllCalls++;
}

Widget _wrap(
  Widget child, {
  AppLang lang = AppLang.tr,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: LanguageScope(
      lang: lang,
      child: MaterialApp(
        // Router olmadan doğrudan çocuğu göster — testler tek ekran odaklı.
        home: child,
      ),
    ),
  );
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

// ===========================================================================
// AUTH EKRANI — form validation gesture'ları
// ===========================================================================
void main() {
  setUpAll(() {
    // Bazı testlerde küçük telefon ekranı yerine geniş viewport gerekli
    // (SingleChildScrollView içinde formun tümü görünsün).
  });

  group('UI Otomasyon · Auth ekranı', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('UI1 · Geçersiz e-posta ile Giriş → validation mesajı görünür',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const AuthScreen()));
      await _settle(tester);

      // AuthScreen alanları dev kolaylığı için önden dolu geliyor
      // (demo@japantrip.app / Demo1234!). Kullanıcı simülasyonu için ikisini
      // de geçersiz değerlerle ez.
      final emailField = find.widgetWithText(TextFormField, 'E-posta');
      final passField = find.widgetWithText(TextFormField, 'Şifre');
      await tester.enterText(emailField, 'gecersizmail');
      await tester.enterText(passField, '123');
      await _settle(tester);

      final signInBtn = find.widgetWithText(FilledButton, 'Giriş yap');
      expect(signInBtn, findsOneWidget, reason: 'giriş butonu görünmeli');
      await tester.tap(signInBtn);
      await _settle(tester);

      expect(find.text('Geçerli bir e-posta gir'), findsOneWidget);
      expect(find.text('En az 6 karakter'), findsOneWidget);
    });

    testWidgets('UI2 · "Hesabın yok mu?" → Kayıt moduna geçer', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const AuthScreen()));
      await _settle(tester);

      // Başlangıç: Giriş modu → alttaki TextButton "Hesabın yok mu? Kayıt ol"
      final toggle = find.text('Hesabın yok mu? Kayıt ol');
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await _settle(tester);

      // Şimdi buton "Kayıt ol" olmalı ve alt link "Zaten hesabın var mı? Giriş yap"
      expect(find.widgetWithText(FilledButton, 'Kayıt ol'), findsOneWidget);
      expect(find.text('Zaten hesabın var mı? Giriş yap'), findsOneWidget);
    });

    testWidgets('UI3 · Kullanıcı e-posta ve şifre alanlarına yazı girer',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const AuthScreen()));
      await _settle(tester);

      final emailField = find.widgetWithText(TextFormField, 'E-posta');
      final passField = find.widgetWithText(TextFormField, 'Şifre');
      expect(emailField, findsOneWidget);
      expect(passField, findsOneWidget);

      await tester.enterText(emailField, 'demo@rotori.app');
      await tester.enterText(passField, 'Demo1234!');
      await _settle(tester);

      // Girdilerin TextField controller'ında olduğunu doğrula.
      expect(find.text('demo@rotori.app'), findsOneWidget);
      // Şifre obscureText olduğu için görsel olarak bulunmaz — TextField
      // widget'ının controller.text'ini doğrula.
      final pass = tester.widget<TextFormField>(passField);
      expect(pass.controller?.text, 'Demo1234!');
    });

    testWidgets('UI4 · Google ile Giriş butonu her platformda görünür',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const AuthScreen()));
      await _settle(tester);

      // Google butonu iOS/Android/web hepsinde görünmeli (Apple sadece iOS/macOS).
      expect(find.text('G Google ile Giriş Yap'), findsOneWidget,
          reason: 'Google butonu tüm platformlarda görünmeli');
    });
  });

  // ===========================================================================
  // REMINDERS EKRANI — end-to-end gesture akışı
  // ===========================================================================
  group('UI Otomasyon · Reminders akışı', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets(
        'UI10 · Boş ekran → hatırlatma eklenir → listede görünür → X ile silinir → tekrar boş',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fake = _FakeNotifs();
      final container = ProviderContainer(overrides: [
        notificationsServiceProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LanguageScope(
            lang: AppLang.tr,
            child: const MaterialApp(home: RemindersScreen()),
          ),
        ),
      );
      await _settle(tester);

      // 1) Başlangıç boş ekran doğrulaması
      expect(find.text('Henüz hatırlatma yok'), findsOneWidget,
          reason: 'boş state başlıkı görünmeli');

      // 2) Kullanıcı bir hatırlatma ekliyor (drawer/başka ekrandan gelmiş
      //    gibi düşün) — store'a doğrudan ekliyoruz, UI otomatik yenilenir.
      final r = Reminder(
        id: 'ui10-r1',
        windowId: 'w-usj',
        title: 'USJ Express Pass',
        subtitle: 'Satışa açılıyor',
        icon: '🎢',
        fireAt: DateTime.now().add(const Duration(days: 45)),
        tip: 'Cuma sabah 09:00',
        tripId: 'trip-1',
      );
      await container.read(remindersProvider.notifier).add(r);
      await _settle(tester);

      // 3) Listede tile görünmeli, empty gitmeli
      expect(find.text('Henüz hatırlatma yok'), findsNothing);
      expect(find.text('USJ Express Pass'), findsOneWidget);
      expect(find.text('Satışa açılıyor'), findsOneWidget);

      // 4) X (kapat) butonuna basılınca kayıt silinir, notifs.cancel çağrılır
      final closeBtn = find.byTooltip('Sil');
      expect(closeBtn, findsWidgets);
      // Tümünü sil değil, ilk tile'daki kapat butonuna bas.
      // (AppBar'daki "Tümünü sil" de aynı tooltip'i kullanmıyor — trash2 icon
      // üzerinden ayrılır. İlk `find.byTooltip('Sil')` tile butonu değil,
      // AppBar action olabilir; iki tanesi varsa ilkine bas.)
      await tester.tap(closeBtn.first);
      await _settle(tester);

      expect(find.text('USJ Express Pass'), findsNothing);
      expect(find.text('Henüz hatırlatma yok'), findsOneWidget);
      expect(fake.cancelledIds, contains('ui10-r1'));
    });

    testWidgets('UI11 · 3 hatırlatma eklenir, çöp kutusu → onay → hepsi silinir',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fake = _FakeNotifs();
      final container = ProviderContainer(overrides: [
        notificationsServiceProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LanguageScope(
            lang: AppLang.tr,
            child: const MaterialApp(home: RemindersScreen()),
          ),
        ),
      );
      await _settle(tester);

      for (var i = 1; i <= 3; i++) {
        await container.read(remindersProvider.notifier).add(Reminder(
              id: 'r$i',
              windowId: 'w$i',
              title: 'Test Reminder $i',
              subtitle: 'Alt',
              icon: '🔔',
              fireAt: DateTime.now().add(Duration(days: 10 * i)),
              tip: '',
              tripId: 't1',
            ));
      }
      await _settle(tester);
      expect(find.text('Test Reminder 1'), findsOneWidget);
      expect(find.text('Test Reminder 3'), findsOneWidget);

      // Kullanıcı AppBar'daki "Tümünü temizle" tooltip'ine basar.
      final clearAll = find.byTooltip('Tümünü temizle');
      expect(clearAll, findsOneWidget);
      await tester.tap(clearAll);
      await _settle(tester);

      // Onay dialogu — "Sil" butonuna bas.
      final confirmDelete = find.widgetWithText(FilledButton, 'Sil');
      expect(confirmDelete, findsOneWidget);
      await tester.tap(confirmDelete);
      await _settle(tester);

      expect(find.text('Test Reminder 1'), findsNothing);
      expect(find.text('Henüz hatırlatma yok'), findsOneWidget);
      expect(fake.cancelAllCalls, 1,
          reason: 'notif servisinin cancelAll fonksiyonu çağrılmalı');
    });
  });

  // ===========================================================================
  // DİL DEĞİŞİMİ — LanguageScope re-mount
  // ===========================================================================
  group('UI Otomasyon · Dil değişimi', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('UI20 · Reminders ekranı EN dilinde İngilizce metin gösterir',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fake = _FakeNotifs();
      final container = ProviderContainer(overrides: [
        notificationsServiceProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LanguageScope(
            lang: AppLang.en,
            child: const MaterialApp(home: RemindersScreen()),
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('No reminders yet'), findsOneWidget);
      expect(find.text('Reminders'), findsOneWidget);
    });
  });
}
