import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/plans_repository.dart';
import 'package:rotori/features/viewer/viewer_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('tema tercihi olmayan yeni kurulum aydınlık başlar', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(viewerThemeProvider), ViewerThemeId.appleLight);
    await container.read(sharedPrefsProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(viewerThemeProvider), ViewerThemeId.appleLight);
  });

  test('önceden kaydedilmiş koyu tema tercihi korunur', () async {
    SharedPreferences.setMockInitialValues({
      'viewer:theme': ViewerThemeId.japanDark.storageKey,
    });
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(viewerThemeProvider);
    await container.read(sharedPrefsProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(viewerThemeProvider), ViewerThemeId.japanDark);
  });

  test('düzen tercihi olmayan yeni kurulum yolculuk tasarımıyla başlar',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(viewerTemplateProvider),
      ViewerTemplateId.journeyProgress,
    );
    await container.read(sharedPrefsProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(viewerTemplateProvider),
      ViewerTemplateId.journeyProgress,
    );
  });

  test('kullanıcı harita tasarımını seçebilir ve tercih kalıcılaşır', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(viewerTemplateProvider);
    await container
        .read(viewerTemplateProvider.notifier)
        .set(ViewerTemplateId.mapFocus);

    expect(
      container.read(viewerTemplateProvider),
      ViewerTemplateId.mapFocus,
    );
    final prefs = await container.read(sharedPrefsProvider.future);
    expect(
      prefs.getString('viewer:template'),
      ViewerTemplateId.mapFocus.storageKey,
    );
  });

  test('bilinmeyen eski düzen anahtarı güvenli varsayılana düşer', () async {
    SharedPreferences.setMockInitialValues({'viewer:template': 'unknown-v0'});
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(viewerTemplateProvider);
    await container.read(sharedPrefsProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(viewerTemplateProvider),
      ViewerTemplateId.journeyProgress,
    );
  });

  test('geliştirme sürümündeki eski düzen anahtarları yeni tasarımlara taşınır',
      () {
    expect(
      ViewerTemplateIdX.fromStorage('calm-cards'),
      ViewerTemplateId.journeyProgress,
    );
    expect(
      ViewerTemplateIdX.fromStorage('compact-timeline'),
      ViewerTemplateId.mapFocus,
    );
  });
}
