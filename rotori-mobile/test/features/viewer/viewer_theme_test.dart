import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/plans_repository.dart';
import 'package:japan_trip/features/viewer/viewer_theme.dart';
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
}
