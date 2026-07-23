// Pratik Japonca kelimeler & cümleler verisi — seyahatte en çok işe yarayan
// frazlar kategori kategori. Görev #8.
//
// i18n: compass_data.dart'taki CompassPhrase/CompassPhraseCategory modeli anlam
// alanları için `compassData.*` L10n ANAHTARI tutuyor. Bu sayfadaki içerik uzun
// ve serbest olduğundan (l10n.dart'a dokunmamak için) BENZER ama LText tabanlı
// kendi modelimizi tanımlıyoruz: anlam/başlık doğrudan TR+EN olarak burada.
//
// Japonca metin (kopyalanan) ve Hepburn romaji literal kalır, çevrilmez.

import 'localized_text.dart';

/// Tek bir Japonca fraz: Japonca metin + (varsa) Hepburn romaji + iki dilli anlam.
class JpPhrase {
  const JpPhrase({
    required this.jp,
    required this.meaning,
    this.romaji,
  });

  /// Japonca metin (kopyalanacak olan) — literal, çevrilmez.
  final String jp;

  /// Latin harfli okunuş (Hepburn) — literal, çevrilmez.
  final String? romaji;

  /// Anlam (TR + EN bir arada) — aktif dile göre çözülür.
  final LText meaning;
}

/// Frazların kategori grubu (Temel, Yemek, Yön, Alışveriş, Ulaşım, Acil, Sayılar).
class JpPhraseCategory {
  const JpPhraseCategory({
    required this.id,
    required this.emoji,
    required this.title,
    required this.phrases,
  });

  /// Kararlı kimlik (i18n değil) — sekme seçimi için.
  final String id;
  final String emoji;

  /// Başlık (TR + EN) — aktif dile göre çözülür.
  final LText title;
  final List<JpPhrase> phrases;
}

/// Pratik Japonca fraz kategorileri — kapsamlı ve doğru içerik.
const List<JpPhraseCategory> kJapanesePhraseCategories = [
  // -------------------------------------------------------------------------
  // Temel
  // -------------------------------------------------------------------------
  JpPhraseCategory(
    id: 'basic',
    emoji: '🗣️',
    title: LText('Temel', 'Basics'),
    phrases: [
      JpPhrase(
        jp: 'こんにちは',
        romaji: 'Konnichiwa',
        meaning: LText('Merhaba (gündüz)', 'Hello (daytime)'),
      ),
      JpPhrase(
        jp: 'ありがとうございます',
        romaji: 'Arigatou gozaimasu',
        meaning: LText('Teşekkür ederim', 'Thank you'),
      ),
      JpPhrase(
        jp: 'すみません',
        romaji: 'Sumimasen',
        meaning: LText('Affedersiniz / pardon', 'Excuse me / sorry'),
      ),
      JpPhrase(
        jp: 'はい',
        romaji: 'Hai',
        meaning: LText('Evet', 'Yes'),
      ),
      JpPhrase(
        jp: 'いいえ',
        romaji: 'Iie',
        meaning: LText('Hayır', 'No'),
      ),
      JpPhrase(
        jp: 'わかりません',
        romaji: 'Wakarimasen',
        meaning: LText('Anlamıyorum', "I don't understand"),
      ),
      JpPhrase(
        jp: 'お願いします',
        romaji: 'Onegaishimasu',
        meaning: LText('Lütfen / rica ederim', 'Please'),
      ),
      JpPhrase(
        jp: '大丈夫です',
        romaji: 'Daijoubu desu',
        meaning: LText('Sorun değil / iyiyim', "It's fine / I'm okay"),
      ),
      JpPhrase(
        jp: '英語を話せますか？',
        romaji: 'Eigo o hanasemasu ka?',
        meaning: LText('İngilizce konuşuyor musunuz?', 'Do you speak English?'),
      ),
      JpPhrase(
        jp: 'ゆっくり話してください',
        romaji: 'Yukkuri hanashite kudasai',
        meaning: LText('Yavaş konuşur musunuz?', 'Please speak slowly'),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // Yemek & restoran
  // -------------------------------------------------------------------------
  JpPhraseCategory(
    id: 'food',
    emoji: '🍽️',
    title: LText('Yemek & restoran', 'Food & dining'),
    phrases: [
      JpPhrase(
        jp: 'メニューをください',
        romaji: 'Menyuu o kudasai',
        meaning: LText('Menü alabilir miyim?', 'The menu, please'),
      ),
      JpPhrase(
        jp: 'お会計をお願いします',
        romaji: 'Okaikei o onegaishimasu',
        meaning: LText('Hesap lütfen', 'The bill, please'),
      ),
      JpPhrase(
        jp: 'お水をください',
        romaji: 'Omizu o kudasai',
        meaning: LText('Su alabilir miyim?', 'Water, please'),
      ),
      JpPhrase(
        jp: 'これは何ですか？',
        romaji: 'Kore wa nan desu ka?',
        meaning: LText('Bu nedir?', 'What is this?'),
      ),
      JpPhrase(
        jp: 'とても美味しいです',
        romaji: 'Totemo oishii desu',
        meaning: LText('Çok lezzetli', "It's very delicious"),
      ),
      JpPhrase(
        jp: 'ベジタリアンです',
        romaji: 'Bejitarian desu',
        meaning: LText('Vejetaryenim', "I'm vegetarian"),
      ),
      JpPhrase(
        jp: 'アレルギーがあります',
        romaji: 'Arerugii ga arimasu',
        meaning: LText('Alerjim var', 'I have an allergy'),
      ),
      JpPhrase(
        jp: 'おすすめは何ですか？',
        romaji: 'Osusume wa nan desu ka?',
        meaning: LText('Ne tavsiye edersiniz?', 'What do you recommend?'),
      ),
      JpPhrase(
        jp: '辛くないものはありますか？',
        romaji: 'Karakunai mono wa arimasu ka?',
        meaning: LText('Acı olmayan bir şey var mı?', 'Do you have something not spicy?'),
      ),
      JpPhrase(
        jp: 'お持ち帰りできますか？',
        romaji: 'Omochikaeri dekimasu ka?',
        meaning: LText('Paket yaptırabilir miyim?', 'Can I get this to go?'),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // Yön & konum
  // -------------------------------------------------------------------------
  JpPhraseCategory(
    id: 'directions',
    emoji: '🗺️',
    title: LText('Yön & konum', 'Directions & places'),
    phrases: [
      JpPhrase(
        jp: '〜はどこですか？',
        romaji: '~ wa doko desu ka?',
        meaning: LText('... nerede?', 'Where is ~?'),
      ),
      JpPhrase(
        jp: '駅はどこですか？',
        romaji: 'Eki wa doko desu ka?',
        meaning: LText('İstasyon nerede?', 'Where is the station?'),
      ),
      JpPhrase(
        jp: 'トイレはどこですか？',
        romaji: 'Toire wa doko desu ka?',
        meaning: LText('Tuvalet nerede?', 'Where is the toilet?'),
      ),
      JpPhrase(
        jp: '右です',
        romaji: 'Migi desu',
        meaning: LText('Sağda', "It's on the right"),
      ),
      JpPhrase(
        jp: '左です',
        romaji: 'Hidari desu',
        meaning: LText('Solda', "It's on the left"),
      ),
      JpPhrase(
        jp: 'まっすぐです',
        romaji: 'Massugu desu',
        meaning: LText('Düz ileride', 'Straight ahead'),
      ),
      JpPhrase(
        jp: 'ここからどれくらいですか？',
        romaji: 'Koko kara dorekurai desu ka?',
        meaning: LText('Buradan ne kadar uzak?', 'How far is it from here?'),
      ),
      JpPhrase(
        jp: '道に迷いました',
        romaji: 'Michi ni mayoimashita',
        meaning: LText('Kayboldum', "I'm lost"),
      ),
      JpPhrase(
        jp: '歩いて行けますか？',
        romaji: 'Aruite ikemasu ka?',
        meaning: LText('Yürüyerek gidilir mi?', 'Can I walk there?'),
      ),
      JpPhrase(
        jp: 'この住所へ行きたいです',
        romaji: 'Kono juusho e ikitai desu',
        meaning: LText('Bu adrese gitmek istiyorum', 'I want to go to this address'),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // Alışveriş
  // -------------------------------------------------------------------------
  JpPhraseCategory(
    id: 'shopping',
    emoji: '🛍️',
    title: LText('Alışveriş', 'Shopping'),
    phrases: [
      JpPhrase(
        jp: 'いくらですか？',
        romaji: 'Ikura desu ka?',
        meaning: LText('Ne kadar?', 'How much is it?'),
      ),
      JpPhrase(
        jp: 'カードは使えますか？',
        romaji: 'Kaado wa tsukaemasu ka?',
        meaning: LText('Kart geçer mi?', 'Do you accept cards?'),
      ),
      JpPhrase(
        jp: '免税できますか？',
        romaji: 'Menzei dekimasu ka?',
        meaning: LText('Vergisiz (tax-free) olur mu?', 'Can I get this tax-free?'),
      ),
      JpPhrase(
        jp: '袋をください',
        romaji: 'Fukuro o kudasai',
        meaning: LText('Poşet alabilir miyim?', 'A bag, please'),
      ),
      JpPhrase(
        jp: '試着してもいいですか？',
        romaji: 'Shichaku shite mo ii desu ka?',
        meaning: LText('Deneyebilir miyim? (giysi)', 'Can I try this on?'),
      ),
      JpPhrase(
        jp: 'これを見てもいいですか？',
        romaji: 'Kore o mite mo ii desu ka?',
        meaning: LText('Buna bakabilir miyim?', 'Can I take a look at this?'),
      ),
      JpPhrase(
        jp: 'もっと安いのはありますか？',
        romaji: 'Motto yasui no wa arimasu ka?',
        meaning: LText('Daha ucuzu var mı?', 'Do you have a cheaper one?'),
      ),
      JpPhrase(
        jp: '別の色はありますか？',
        romaji: 'Betsu no iro wa arimasu ka?',
        meaning: LText('Başka renk var mı?', 'Do you have another color?'),
      ),
      JpPhrase(
        jp: 'これをください',
        romaji: 'Kore o kudasai',
        meaning: LText('Bunu alıyorum', "I'll take this"),
      ),
      JpPhrase(
        jp: 'レシートをください',
        romaji: 'Reshiito o kudasai',
        meaning: LText('Fiş alabilir miyim?', 'A receipt, please'),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // Ulaşım
  // -------------------------------------------------------------------------
  JpPhraseCategory(
    id: 'transport',
    emoji: '🚃',
    title: LText('Ulaşım', 'Transport'),
    phrases: [
      JpPhrase(
        jp: '切符はどこで買えますか？',
        romaji: 'Kippu wa doko de kaemasu ka?',
        meaning: LText('Bilet nereden alınır?', 'Where can I buy a ticket?'),
      ),
      JpPhrase(
        jp: 'この電車は〜に行きますか？',
        romaji: 'Kono densha wa ~ ni ikimasu ka?',
        meaning: LText('Bu tren ...e gider mi?', 'Does this train go to ~?'),
      ),
      JpPhrase(
        jp: '何番線ですか？',
        romaji: 'Nanbansen desu ka?',
        meaning: LText('Hangi peron?', 'Which platform?'),
      ),
      JpPhrase(
        jp: '何時に出発しますか？',
        romaji: 'Nanji ni shuppatsu shimasu ka?',
        meaning: LText('Kaçta kalkar?', 'What time does it leave?'),
      ),
      JpPhrase(
        jp: 'スイカにチャージしたいです',
        romaji: 'Suika ni chaaji shitai desu',
        meaning: LText('Suica kartıma yükleme yapmak istiyorum', "I'd like to top up my Suica"),
      ),
      JpPhrase(
        jp: '次の駅はどこですか？',
        romaji: 'Tsugi no eki wa doko desu ka?',
        meaning: LText('Sonraki istasyon neresi?', "What's the next station?"),
      ),
      JpPhrase(
        jp: '乗り換えが必要ですか？',
        romaji: 'Norikae ga hitsuyou desu ka?',
        meaning: LText('Aktarma gerekiyor mu?', 'Do I need to transfer?'),
      ),
      JpPhrase(
        jp: 'タクシー乗り場はどこですか？',
        romaji: 'Takushii noriba wa doko desu ka?',
        meaning: LText('Taksi durağı nerede?', 'Where is the taxi stand?'),
      ),
      JpPhrase(
        jp: '空港までお願いします',
        romaji: 'Kuukou made onegaishimasu',
        meaning: LText('Havalimanına lütfen', 'To the airport, please'),
      ),
      JpPhrase(
        jp: '終電は何時ですか？',
        romaji: 'Shuuden wa nanji desu ka?',
        meaning: LText('Son tren kaçta?', 'What time is the last train?'),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // Acil
  // -------------------------------------------------------------------------
  JpPhraseCategory(
    id: 'emergency',
    emoji: '🚨',
    title: LText('Acil', 'Emergency'),
    phrases: [
      JpPhrase(
        jp: '助けて！',
        romaji: 'Tasukete!',
        meaning: LText('İmdat! / Yardım edin!', 'Help!'),
      ),
      JpPhrase(
        jp: '救急車を呼んでください',
        romaji: 'Kyuukyuusha o yonde kudasai',
        meaning: LText('Ambulans çağırın', 'Call an ambulance'),
      ),
      JpPhrase(
        jp: '警察を呼んでください',
        romaji: 'Keisatsu o yonde kudasai',
        meaning: LText('Polis çağırın', 'Call the police'),
      ),
      JpPhrase(
        jp: '病院はどこですか？',
        romaji: 'Byouin wa doko desu ka?',
        meaning: LText('Hastane nerede?', 'Where is the hospital?'),
      ),
      JpPhrase(
        jp: '医者が必要です',
        romaji: 'Isha ga hitsuyou desu',
        meaning: LText('Doktora ihtiyacım var', 'I need a doctor'),
      ),
      JpPhrase(
        jp: '痛いです',
        romaji: 'Itai desu',
        meaning: LText('Ağrım var / acıyor', 'It hurts'),
      ),
      JpPhrase(
        jp: '気分が悪いです',
        romaji: 'Kibun ga warui desu',
        meaning: LText('Kendimi kötü hissediyorum', 'I feel sick'),
      ),
      JpPhrase(
        jp: 'パスポートをなくしました',
        romaji: 'Pasupooto o nakushimashita',
        meaning: LText('Pasaportumu kaybettim', 'I lost my passport'),
      ),
      JpPhrase(
        jp: '財布を盗まれました',
        romaji: 'Saifu o nusumaremashita',
        meaning: LText('Cüzdanım çalındı', 'My wallet was stolen'),
      ),
      JpPhrase(
        jp: 'トルコ大使館に連絡したいです',
        romaji: 'Toruko taishikan ni renraku shitai desu',
        meaning: LText('Türk büyükelçiliğine ulaşmak istiyorum', 'I want to contact the Turkish embassy'),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // Sayılar & zaman
  // -------------------------------------------------------------------------
  JpPhraseCategory(
    id: 'numbers',
    emoji: '🔢',
    title: LText('Sayılar & zaman', 'Numbers & time'),
    phrases: [
      JpPhrase(
        jp: '一',
        romaji: 'Ichi',
        meaning: LText('Bir (1)', 'One (1)'),
      ),
      JpPhrase(
        jp: '二',
        romaji: 'Ni',
        meaning: LText('İki (2)', 'Two (2)'),
      ),
      JpPhrase(
        jp: '三',
        romaji: 'San',
        meaning: LText('Üç (3)', 'Three (3)'),
      ),
      JpPhrase(
        jp: '四',
        romaji: 'Yon (Shi)',
        meaning: LText('Dört (4)', 'Four (4)'),
      ),
      JpPhrase(
        jp: '五',
        romaji: 'Go',
        meaning: LText('Beş (5)', 'Five (5)'),
      ),
      JpPhrase(
        jp: '六',
        romaji: 'Roku',
        meaning: LText('Altı (6)', 'Six (6)'),
      ),
      JpPhrase(
        jp: '七',
        romaji: 'Nana (Shichi)',
        meaning: LText('Yedi (7)', 'Seven (7)'),
      ),
      JpPhrase(
        jp: '八',
        romaji: 'Hachi',
        meaning: LText('Sekiz (8)', 'Eight (8)'),
      ),
      JpPhrase(
        jp: '九',
        romaji: 'Kyuu (Ku)',
        meaning: LText('Dokuz (9)', 'Nine (9)'),
      ),
      JpPhrase(
        jp: '十',
        romaji: 'Juu',
        meaning: LText('On (10)', 'Ten (10)'),
      ),
      JpPhrase(
        jp: '今何時ですか？',
        romaji: 'Ima nanji desu ka?',
        meaning: LText('Saat kaç?', 'What time is it?'),
      ),
      JpPhrase(
        jp: '今日',
        romaji: 'Kyou',
        meaning: LText('Bugün', 'Today'),
      ),
      JpPhrase(
        jp: '明日',
        romaji: 'Ashita',
        meaning: LText('Yarın', 'Tomorrow'),
      ),
      JpPhrase(
        jp: '朝',
        romaji: 'Asa',
        meaning: LText('Sabah', 'Morning'),
      ),
      JpPhrase(
        jp: '夜',
        romaji: 'Yoru',
        meaning: LText('Akşam / gece', 'Evening / night'),
      ),
    ],
  ),
];
