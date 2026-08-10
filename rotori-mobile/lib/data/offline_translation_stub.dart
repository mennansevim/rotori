import 'offline_translation_contract.dart';

OfflineTranslationGateway createOfflineTranslationGateway() =>
    _UnsupportedOfflineTranslationGateway();

final class _UnsupportedOfflineTranslationGateway
    implements OfflineTranslationGateway {
  @override
  bool get isSupported => false;

  @override
  Future<bool> areModelsReady({
    required OfflineTranslationLanguage source,
    required OfflineTranslationLanguage target,
  }) async =>
      false;

  @override
  Future<void> downloadModels({
    required OfflineTranslationLanguage source,
    required OfflineTranslationLanguage target,
  }) =>
      Future<void>.error(
        UnsupportedError('Offline translation is available on iOS/Android.'),
      );

  @override
  Future<String> translate({
    required String text,
    required OfflineTranslationLanguage source,
    required OfflineTranslationLanguage target,
  }) =>
      Future<String>.error(
        UnsupportedError('Offline translation is available on iOS/Android.'),
      );

  @override
  Future<void> close() async {}
}
