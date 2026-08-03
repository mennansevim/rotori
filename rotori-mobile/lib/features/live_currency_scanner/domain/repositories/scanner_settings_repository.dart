import '../scanner_settings.dart';

/// Tarayıcı ayarlarının kalıcı depolanma sözleşmesi.
abstract interface class ScannerSettingsRepository {
  Future<ScannerSettings> load();
  Future<void> save(ScannerSettings settings);
}
