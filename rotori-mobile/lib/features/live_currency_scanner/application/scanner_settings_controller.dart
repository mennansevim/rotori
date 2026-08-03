import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/currency_code.dart';
import '../domain/repositories/scanner_settings_repository.dart';
import '../domain/scanner_settings.dart';
import 'providers.dart';

/// Ayar controller'ının UI durumu — yüklenme + ayarlar.
class ScannerSettingsUiState {
  const ScannerSettingsUiState({
    required this.settings,
    this.loaded = false,
  });

  final ScannerSettings settings;
  final bool loaded;

  ScannerSettingsUiState copyWith({ScannerSettings? settings, bool? loaded}) =>
      ScannerSettingsUiState(
        settings: settings ?? this.settings,
        loaded: loaded ?? this.loaded,
      );
}

/// Tarayıcı ayarlarını yükler, günceller ve kalıcı yazar.
class ScannerSettingsController extends StateNotifier<ScannerSettingsUiState> {
  ScannerSettingsController(this._ref)
      : super(const ScannerSettingsUiState(settings: ScannerSettings())) {
    _load();
  }

  final Ref _ref;

  ScannerSettingsRepository? get _repo =>
      _ref.read(scannerSettingsRepositoryProvider);

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    final loaded = await repo.load();
    if (!mounted) return;
    state = ScannerSettingsUiState(settings: loaded, loaded: true);
  }

  Future<void> _update(ScannerSettings next) async {
    state = state.copyWith(settings: next);
    await _repo?.save(next);
  }

  Future<void> setTargetCurrency(CurrencyCode code) =>
      _update(state.settings.copyWith(targetCurrency: code));

  Future<void> setAutoUpdate(bool value) =>
      _update(state.settings.copyWith(autoUpdateRate: value));

  Future<void> setUseManualRate(bool value) =>
      _update(state.settings.copyWith(useManualRate: value));

  Future<void> setManualRate(String? value) => _update(
        value == null || value.isEmpty
            ? state.settings.copyWith(clearManualRate: true)
            : state.settings.copyWith(manualRate: value),
      );

  Future<void> setCardMarkup(double percent) =>
      _update(state.settings.copyWith(cardMarkupPercent: percent));

  Future<void> setRounding(RoundingPreference rounding) =>
      _update(state.settings.copyWith(rounding: rounding));

  Future<void> setPerformanceProfile(ScannerPerformanceProfile profile) =>
      _update(state.settings.copyWith(performanceProfile: profile));
}
