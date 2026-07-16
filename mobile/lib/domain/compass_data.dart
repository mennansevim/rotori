// Pusula (compass) verisi — React viewer'daki Pusula.tsx içeriğinin birebir
// portu. Japonca fraz kartları, acil numaralar ve pratik bilgiler.
//
// Kaynak: apps/viewer/src/components/Pusula.tsx (inline PHRASE_CATEGORIES +
// EMERGENCY_NUMBERS). React'te veriler bileşen içinde tutuluyordu; Flutter'da
// tek izinli domain veri dosyasına taşındı.

/// Tek bir Japonca fraz kartı: Japonca metin + (varsa) romaji + Türkçe anlam.
class CompassPhrase {
  const CompassPhrase({
    required this.jp,
    required this.meaning,
    this.romaji,
  });

  /// Japonca metin (kopyalanacak olan).
  final String jp;

  /// Türkçe anlam / etiket.
  final String meaning;

  /// Latin harfli okunuş (bazı frazlarda yok).
  final String? romaji;
}

/// Frazların kategori grubu (Temel, Yemekte sor, Yol sor, Acil).
class CompassPhraseCategory {
  const CompassPhraseCategory({
    required this.id,
    required this.title,
    required this.emoji,
    required this.phrases,
  });

  final String id;
  final String title;
  final String emoji;
  final List<CompassPhrase> phrases;
}

/// Acil durum telefon numarası + etiketi.
class CompassEmergencyNumber {
  const CompassEmergencyNumber({required this.number, required this.label});

  final String number;
  final String label;
}

/// Pratik bilgi kartı (Para & Döviz, Kültür kuralları).
class CompassInfoCard {
  const CompassInfoCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.lines,
  });

  final String emoji;
  final String title;
  final String subtitle;

  /// Her satır (label, text) çifti — label boş olabilir.
  final List<CompassInfoLine> lines;
}

class CompassInfoLine {
  const CompassInfoLine({this.label, required this.text});
  final String? label;
  final String text;
}

/// Japonca fraz kartları — React PHRASE_CATEGORIES birebir.
const List<CompassPhraseCategory> kCompassPhraseCategories = [
  CompassPhraseCategory(
    id: 'basic',
    title: 'Temel',
    emoji: '🗣️',
    phrases: [
      CompassPhrase(
        jp: 'すみません',
        romaji: 'Sumimasen',
        meaning: 'Affedersiniz / Pardon',
      ),
      CompassPhrase(
        jp: 'ありがとうございます',
        romaji: 'Arigatou gozaimasu',
        meaning: 'Çok teşekkürler',
      ),
      CompassPhrase(
        jp: '英語が話せますか？',
        romaji: 'Eigo ga hanasemasu ka?',
        meaning: 'İngilizce biliyor musunuz?',
      ),
      CompassPhrase(
        jp: 'いくらですか？',
        romaji: 'Ikura desu ka?',
        meaning: 'Kaç para?',
      ),
      CompassPhrase(
        jp: 'お手洗いはどこ？',
        romaji: 'Otearai wa doko?',
        meaning: 'Tuvalet nerede?',
      ),
    ],
  ),
  CompassPhraseCategory(
    id: 'food',
    title: 'Yemekte sor',
    emoji: '🍽️',
    phrases: [
      CompassPhrase(
        jp: 'この料理に豚肉は入っていますか？',
        meaning: 'Bu yemekte domuz eti var mı?',
      ),
      CompassPhrase(
        jp: 'ラードは使われていますか？',
        meaning: 'Domuz yağı kullanılıyor mu?',
      ),
      CompassPhrase(
        jp: 'お酒は入っていますか？',
        meaning: 'Alkol içeriyor mu?',
      ),
      CompassPhrase(
        jp: '鶏肉のメニューはありますか？',
        meaning: 'Tavuklu seçenek var mı?',
      ),
      CompassPhrase(
        jp: '海鮮は入っていますか？',
        meaning: 'Deniz ürünü içeriyor mu?',
      ),
      CompassPhrase(
        jp: 'お子様用に辛くないものはありますか？',
        meaning: 'Çocuk için acısız bir seçenek var mı?',
      ),
      CompassPhrase(
        jp: 'ベジタリアンメニューはありますか？',
        meaning: 'Vejetaryen menü var mı?',
      ),
    ],
  ),
  CompassPhraseCategory(
    id: 'directions',
    title: 'Yol sor',
    emoji: '🗺️',
    phrases: [
      CompassPhrase(
        jp: '駅はどこですか？',
        romaji: 'Eki wa doko desu ka?',
        meaning: 'İstasyon nerede?',
      ),
      CompassPhrase(
        jp: 'この電車は○○行きですか？',
        romaji: 'Kono densha wa __ iki desu ka?',
        meaning: 'Bu tren __ a gidiyor mu?',
      ),
      CompassPhrase(
        jp: '○○まで行ってください',
        romaji: '__ made itte kudasai',
        meaning: 'Lütfen __ a kadar',
      ),
      CompassPhrase(
        jp: '地図を見せてもらえますか？',
        meaning: 'Haritayı gösterir misiniz?',
      ),
    ],
  ),
  CompassPhraseCategory(
    id: 'emergency',
    title: 'Acil',
    emoji: '🚨',
    phrases: [
      CompassPhrase(
        jp: '助けて！',
        romaji: 'Tasukete!',
        meaning: 'İmdat!',
      ),
      CompassPhrase(
        jp: '救急車を呼んでください',
        romaji: 'Kyuukyuusha o yonde kudasai',
        meaning: 'Ambulans çağırın',
      ),
      CompassPhrase(
        jp: '警察を呼んでください',
        romaji: 'Keisatsu o yonde kudasai',
        meaning: 'Polis çağırın',
      ),
      CompassPhrase(
        jp: '気分が悪いです',
        romaji: 'Kibun ga warui desu',
        meaning: 'Kendimi iyi hissetmiyorum',
      ),
      CompassPhrase(
        jp: 'パスポートをなくしました',
        meaning: 'Pasaportumu kaybettim',
      ),
    ],
  ),
];

/// Acil numaralar — React EMERGENCY_NUMBERS birebir.
const List<CompassEmergencyNumber> kCompassEmergencyNumbers = [
  CompassEmergencyNumber(number: '110', label: 'Polis'),
  CompassEmergencyNumber(number: '119', label: 'Ambulans / İtfaiye'),
  CompassEmergencyNumber(
    number: '03-3501-0110',
    label: 'Yabancı danışma (Tokyo)',
  ),
  CompassEmergencyNumber(
    number: '+81-3-3470-5131',
    label: 'TR Tokyo Büyükelçiliği',
  ),
];

/// Pratik bilgi kartları — React'teki Para & Döviz + Kültür kuralları.
const List<CompassInfoCard> kCompassInfoCards = [
  CompassInfoCard(
    emoji: '💴',
    title: 'Para & Döviz',
    subtitle: 'JPY',
    lines: [
      CompassInfoLine(
        text: '1.000 ¥ ≈ kur değişir · 7-Eleven ATM yabancı kart kabul · '
            'Suica/Pasmo IC kart metro + konbini için pratik.',
      ),
    ],
  ),
  CompassInfoCard(
    emoji: '🎌',
    title: 'Kültür kuralları',
    subtitle: 'Yerel etiket',
    lines: [
      CompassInfoLine(
        label: 'Metro:',
        text: 'Sessiz ol, telefonda konuşma; önce inenlere yol ver.',
      ),
      CompassInfoLine(
        label: 'Bahşiş:',
        text: 'Verilmez — hakaret sayılabilir.',
      ),
      CompassInfoLine(
        label: 'Tapınak:',
        text: 'Bazı yerlerde ayakkabı çıkarılır; çekim yasaklarına dikkat.',
      ),
      CompassInfoLine(
        label: 'Çöp:',
        text: 'Sokakta çöp kutusu yok; yanında taşı, otele götür.',
      ),
    ],
  ),
];
