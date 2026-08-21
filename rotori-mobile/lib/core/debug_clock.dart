// Debug/önizleme saati — uygulamanın "şimdi"sini elle kaydırmak için.
//
// **Neden:** Viewer'daki "sıradaki aktivite", aktif gün ve "ilerlemen"
// sayacı gerçek saate (`DateTime.now()`) bağlı. Bu davranışı denemek için
// gerçek zamanı beklemek yerine, debug/önizleme yapısında gün/saat ileri-geri
// alınabilen bir ofset tutuyoruz. Üretim girişi bu ofsete hiç dokunmaz →
// daima `Duration.zero`, yani gerçek saat.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Gerçek saate eklenen debug ofseti. Yalnız debug/önizleme kontrolü değiştirir.
final debugClockOffsetProvider =
    StateProvider<Duration>((ref) => Duration.zero);

/// Uygulamanın "şimdi"si. Ofset sıfırsa gerçek saatle birebir aynı.
///
/// Bunu izleyen (`ref.watch`) widget'lar, ofset değişince yeniden kurulur;
/// böylece gün/saat ilerledikçe sıradaki aktivite ve sayaç güncellenir.
final nowProvider = Provider<DateTime>(
  (ref) => DateTime.now().add(ref.watch(debugClockOffsetProvider)),
);

/// Debug saat barının görünürlüğü. Varsayılan `false` → viewer'ı derleyen
/// her yerde (üretim VE widget testleri) bar gizli. Önizleme girişi
/// (`preview_main.dart`) bunu `true`'ya override eder; saat testleri de öyle.
///
/// **Neden default false:** Widget testleri `kDebugMode` altında koşuyor; bar
/// `kDebugMode`'a bağlansaydı testlerde de çizilip koordinat tabanlı sürükleme
/// testlerinin düzenini kaydırırdı. Opt-in bayrak bunu tümden önler.
final debugClockBarEnabledProvider = Provider<bool>((ref) => false);
