enum OfflineTranslationLanguage { turkish, english, japanese }

/// Cihaz-üstü çeviri motorunu UI'dan ve ML Kit paketinden ayıran sözleşme.
///
/// Böylece web ön izlemesi mobil-only paketi yüklemez; widget testleri de
/// gerçek dil modeli indirmeden çeviri akışını doğrulayabilir.
abstract interface class OfflineTranslationGateway {
  bool get isSupported;

  Future<bool> areModelsReady({
    required OfflineTranslationLanguage source,
    required OfflineTranslationLanguage target,
  });

  Future<void> downloadModels({
    required OfflineTranslationLanguage source,
    required OfflineTranslationLanguage target,
  });

  Future<String> translate({
    required String text,
    required OfflineTranslationLanguage source,
    required OfflineTranslationLanguage target,
  });

  Future<void> close();
}
