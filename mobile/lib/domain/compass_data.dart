// Pusula (compass) verisi — React viewer'daki Pusula.tsx içeriğinin birebir
// portu. Japonca fraz kartları, acil numaralar ve pratik bilgiler.
//
// Kaynak: apps/viewer/src/components/Pusula.tsx (inline PHRASE_CATEGORIES +
// EMERGENCY_NUMBERS). React'te veriler bileşen içinde tutuluyordu; Flutter'da
// tek izinli domain veri dosyasına taşındı.
//
// i18n: Kullanıcıya görünen etiket/anlam alanları artık düz metin değil,
// `compassData.*` i18n ANAHTARI tutar; ekranda LanguageScope.of(context).s(key)
// ile çözülür. Japonca metin, romaji ve telefon numaraları literal kalır.

/// Tek bir Japonca fraz kartı: Japonca metin + (varsa) romaji + anlam anahtarı.
class CompassPhrase {
  const CompassPhrase({
    required this.jp,
    required this.meaning,
    this.romaji,
  });

  /// Japonca metin (kopyalanacak olan) — literal, çevrilmez.
  final String jp;

  /// Anlam / etiket için i18n anahtarı (LanguageScope.s ile çözülür).
  final String meaning;

  /// Latin harfli okunuş (bazı frazlarda yok) — literal, çevrilmez.
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

  /// Kararlı kimlik (i18n değil) — durum/seçim için kullanılır.
  final String id;

  /// Başlık için i18n anahtarı (LanguageScope.s ile çözülür).
  final String title;
  final String emoji;
  final List<CompassPhrase> phrases;
}

/// Acil durum telefon numarası + etiketi.
class CompassEmergencyNumber {
  const CompassEmergencyNumber({required this.number, required this.label});

  /// Telefon numarası — literal, çevrilmez.
  final String number;

  /// Etiket için i18n anahtarı (LanguageScope.s ile çözülür).
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

  /// Başlık için i18n anahtarı.
  final String title;

  /// Alt başlık için i18n anahtarı.
  final String subtitle;

  /// Her satır (label, text) çifti — label boş olabilir.
  final List<CompassInfoLine> lines;
}

class CompassInfoLine {
  const CompassInfoLine({this.label, required this.text});

  /// Satır etiketi için i18n anahtarı (opsiyonel).
  final String? label;

  /// Satır metni için i18n anahtarı.
  final String text;
}

/// Japonca fraz kartları — React PHRASE_CATEGORIES birebir.
const List<CompassPhraseCategory> kCompassPhraseCategories = [
  CompassPhraseCategory(
    id: 'basic',
    title: 'compassData.cat.basic',
    emoji: '🗣️',
    phrases: [
      CompassPhrase(
        jp: 'すみません',
        romaji: 'Sumimasen',
        meaning: 'compassData.phrase.basic.excuseMe',
      ),
      CompassPhrase(
        jp: 'ありがとうございます',
        romaji: 'Arigatou gozaimasu',
        meaning: 'compassData.phrase.basic.thanks',
      ),
      CompassPhrase(
        jp: '英語が話せますか？',
        romaji: 'Eigo ga hanasemasu ka?',
        meaning: 'compassData.phrase.basic.english',
      ),
      CompassPhrase(
        jp: 'いくらですか？',
        romaji: 'Ikura desu ka?',
        meaning: 'compassData.phrase.basic.howMuch',
      ),
      CompassPhrase(
        jp: 'お手洗いはどこ？',
        romaji: 'Otearai wa doko?',
        meaning: 'compassData.phrase.basic.toilet',
      ),
    ],
  ),
  CompassPhraseCategory(
    id: 'food',
    title: 'compassData.cat.food',
    emoji: '🍽️',
    phrases: [
      CompassPhrase(
        jp: 'この料理に豚肉は入っていますか？',
        meaning: 'compassData.phrase.food.pork',
      ),
      CompassPhrase(
        jp: 'ラードは使われていますか？',
        meaning: 'compassData.phrase.food.lard',
      ),
      CompassPhrase(
        jp: 'お酒は入っていますか？',
        meaning: 'compassData.phrase.food.alcohol',
      ),
      CompassPhrase(
        jp: '鶏肉のメニューはありますか？',
        meaning: 'compassData.phrase.food.chicken',
      ),
      CompassPhrase(
        jp: '海鮮は入っていますか？',
        meaning: 'compassData.phrase.food.seafood',
      ),
      CompassPhrase(
        jp: 'お子様用に辛くないものはありますか？',
        meaning: 'compassData.phrase.food.kidMild',
      ),
      CompassPhrase(
        jp: 'ベジタリアンメニューはありますか？',
        meaning: 'compassData.phrase.food.vegetarian',
      ),
    ],
  ),
  CompassPhraseCategory(
    id: 'directions',
    title: 'compassData.cat.directions',
    emoji: '🗺️',
    phrases: [
      CompassPhrase(
        jp: '駅はどこですか？',
        romaji: 'Eki wa doko desu ka?',
        meaning: 'compassData.phrase.directions.station',
      ),
      CompassPhrase(
        jp: 'この電車は○○行きですか？',
        romaji: 'Kono densha wa __ iki desu ka?',
        meaning: 'compassData.phrase.directions.trainGoes',
      ),
      CompassPhrase(
        jp: '○○まで行ってください',
        romaji: '__ made itte kudasai',
        meaning: 'compassData.phrase.directions.takeMeTo',
      ),
      CompassPhrase(
        jp: '地図を見せてもらえますか？',
        meaning: 'compassData.phrase.directions.showMap',
      ),
    ],
  ),
  CompassPhraseCategory(
    id: 'emergency',
    title: 'compassData.cat.emergency',
    emoji: '🚨',
    phrases: [
      CompassPhrase(
        jp: '助けて！',
        romaji: 'Tasukete!',
        meaning: 'compassData.phrase.emergency.help',
      ),
      CompassPhrase(
        jp: '救急車を呼んでください',
        romaji: 'Kyuukyuusha o yonde kudasai',
        meaning: 'compassData.phrase.emergency.ambulance',
      ),
      CompassPhrase(
        jp: '警察を呼んでください',
        romaji: 'Keisatsu o yonde kudasai',
        meaning: 'compassData.phrase.emergency.police',
      ),
      CompassPhrase(
        jp: '気分が悪いです',
        romaji: 'Kibun ga warui desu',
        meaning: 'compassData.phrase.emergency.feelSick',
      ),
      CompassPhrase(
        jp: 'パスポートをなくしました',
        meaning: 'compassData.phrase.emergency.lostPassport',
      ),
    ],
  ),
];

/// Acil numaralar — React EMERGENCY_NUMBERS birebir.
const List<CompassEmergencyNumber> kCompassEmergencyNumbers = [
  CompassEmergencyNumber(number: '110', label: 'compassData.emergency.police'),
  CompassEmergencyNumber(
    number: '119',
    label: 'compassData.emergency.ambulanceFire',
  ),
  CompassEmergencyNumber(
    number: '03-3501-0110',
    label: 'compassData.emergency.foreignHelp',
  ),
  CompassEmergencyNumber(
    number: '+81-3-3470-5131',
    label: 'compassData.emergency.trEmbassy',
  ),
];

/// Pratik bilgi kartları — React'teki Para & Döviz + Kültür kuralları.
const List<CompassInfoCard> kCompassInfoCards = [
  CompassInfoCard(
    emoji: '💴',
    title: 'compassData.money.title',
    subtitle: 'compassData.money.subtitle',
    lines: [
      CompassInfoLine(
        text: 'compassData.money.line',
      ),
    ],
  ),
  CompassInfoCard(
    emoji: '🎌',
    title: 'compassData.culture.title',
    subtitle: 'compassData.culture.subtitle',
    lines: [
      CompassInfoLine(
        label: 'compassData.culture.metro.label',
        text: 'compassData.culture.metro.text',
      ),
      CompassInfoLine(
        label: 'compassData.culture.tipping.label',
        text: 'compassData.culture.tipping.text',
      ),
      CompassInfoLine(
        label: 'compassData.culture.temple.label',
        text: 'compassData.culture.temple.text',
      ),
      CompassInfoLine(
        label: 'compassData.culture.trash.label',
        text: 'compassData.culture.trash.text',
      ),
    ],
  ),
];
