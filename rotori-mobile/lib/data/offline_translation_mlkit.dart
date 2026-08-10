import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'offline_translation_contract.dart';

OfflineTranslationGateway createOfflineTranslationGateway() =>
    MlKitOfflineTranslationGateway();

final class MlKitOfflineTranslationGateway
    implements OfflineTranslationGateway {
  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();

  @override
  bool get isSupported => true;

  @override
  Future<bool> areModelsReady({
    required OfflineTranslationLanguage source,
    required OfflineTranslationLanguage target,
  }) async {
    final sourceReady =
        await _modelManager.isModelDownloaded(_toMlKit(source).bcpCode);
    final targetReady =
        await _modelManager.isModelDownloaded(_toMlKit(target).bcpCode);
    return sourceReady && targetReady;
  }

  @override
  Future<void> downloadModels({
    required OfflineTranslationLanguage source,
    required OfflineTranslationLanguage target,
  }) async {
    for (final language in {source, target}) {
      final code = _toMlKit(language).bcpCode;
      if (!await _modelManager.isModelDownloaded(code)) {
        // Resmî öneri: yaklaşık 30 MB'lık modelleri Wi-Fi üzerinden indir.
        final downloaded = await _modelManager.downloadModel(code);
        if (!downloaded) {
          throw StateError('Translation model download failed: $code');
        }
      }
    }
  }

  @override
  Future<String> translate({
    required String text,
    required OfflineTranslationLanguage source,
    required OfflineTranslationLanguage target,
  }) async {
    final translator = OnDeviceTranslator(
      sourceLanguage: _toMlKit(source),
      targetLanguage: _toMlKit(target),
    );
    try {
      return await translator.translateText(text);
    } finally {
      await translator.close();
    }
  }

  @override
  Future<void> close() async {}

  TranslateLanguage _toMlKit(OfflineTranslationLanguage language) =>
      switch (language) {
        OfflineTranslationLanguage.turkish => TranslateLanguage.turkish,
        OfflineTranslationLanguage.english => TranslateLanguage.english,
        OfflineTranslationLanguage.japanese => TranslateLanguage.japanese,
      };
}
