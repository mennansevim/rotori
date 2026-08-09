// Premium yetkilendirmesi — TEK doğru kaynak.
//
// **Why:** Bayrak SharedPreferences'ta ('debug_premium') tutuluyordu ve her
// ekran onu ayrı ayrı, kendi initState'inde okuyordu. Sonuç: drawer'dan
// premium'u açıyordun ama rota optimizasyonu bunu hiç okumadığı için paywall
// göstermeye devam ediyordu. Provider'a taşıyınca tek yazma noktası, tek
// okuma noktası ve anında güncellenme oluyor.
//
// Not: bu şimdilik DEBUG anahtarı. Gerçek satın alma entegrasyonu gelince
// yalnızca [PremiumNotifier.load] ve [PremiumNotifier.setPremium] gövdeleri
// değişecek; okuyan ekranlara dokunmaya gerek kalmayacak.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefs anahtarı — fiyat tarayıcı da aynı anahtarı okuyor.
const String kPremiumPrefsKey = 'debug_premium';

final premiumProvider =
    StateNotifierProvider<PremiumNotifier, bool>((ref) => PremiumNotifier());

class PremiumNotifier extends StateNotifier<bool> {
  PremiumNotifier() : super(false) {
    load();
  }

  /// Kullanıcı bu oturumda bayrağı elle değiştirdi mi?
  ///
  /// Açılıştaki [load] asenkron; kullanıcı o çözülmeden anahtarı çevirirse
  /// geç gelen load seçimi EZERDİ. Bayrak, elle yapılan seçimi korur.
  bool _userSet = false;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(kPremiumPrefsKey) ?? false;
      if (_userSet) return; // elle seçim kazanır
      state = stored;
    } catch (_) {
      // Depolama okunamazsa ücretsiz kabul et — kilidi yanlışlıkla açmayalım.
      if (!_userSet) state = false;
    }
  }

  Future<void> setPremium(bool value) async {
    _userSet = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kPremiumPrefsKey, value);
    } catch (_) {
      // Kalıcı yazılamasa da oturum içinde geçerli kalsın.
    }
  }

  Future<void> toggle() => setPremium(!state);
}
