/// Çok dilli kanonik mekan çözümleme katmanı.
///
/// Aynı mekan katalogda, kullanıcı girdisinde ve AI çıktısında üç ayrı yazı
/// sistemiyle görünebilir:
///
///   清水寺 · きよみずでら · Kiyomizu-dera · Kiyomizudera · Kiyomizu Temple
///
/// Bu katman hepsini tek bir **kanonik anahtara** indirger; `placeId`
/// bulunmayan eski planlarda bile ardışık gün tekrarını yakalar.
///
/// Tasarım kuralları:
/// - **Saf ve deterministik.** Aynı girdi her zaman aynı anahtar.
/// - **ASCII girdide geriye tam uyumlu.** Latin harfli bir başlık, bu katman
///   olmadan üretilen eski anahtarla birebir aynı sonucu verir; mevcut
///   deduplication regresyonları etkilenmez.
/// - **Sessiz yanlış eşleşme yok.** Bulanık (fuzzy) eşleşme yalnız eşik
///   üstünde ve yalnız `placeId` yokken devreye girer.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Yazı sistemi tespiti
// ---------------------------------------------------------------------------

enum JapaneseScript { latin, hiragana, katakana, kanji, mixed }

bool _isHiragana(int code) => code >= 0x3041 && code <= 0x3096;
bool _isKatakana(int code) => code >= 0x30A1 && code <= 0x30FA;
bool _isKanji(int code) =>
    (code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF);

JapaneseScript detectScript(String value) {
  var hiragana = false;
  var katakana = false;
  var kanji = false;
  var latin = false;
  for (final code in value.runes) {
    if (_isHiragana(code)) {
      hiragana = true;
    } else if (_isKatakana(code)) {
      katakana = true;
    } else if (_isKanji(code)) {
      kanji = true;
    } else if ((code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A)) {
      latin = true;
    }
  }
  final scripts = [hiragana, katakana, kanji, latin].where((v) => v).length;
  if (scripts > 1) return JapaneseScript.mixed;
  if (hiragana) return JapaneseScript.hiragana;
  if (katakana) return JapaneseScript.katakana;
  if (kanji) return JapaneseScript.kanji;
  return JapaneseScript.latin;
}

// ---------------------------------------------------------------------------
// Kana → Hepburn romaji
// ---------------------------------------------------------------------------

/// Digraph (拗音) tablosu — iki kana tek heceye çözülür.
const Map<String, String> _kanaDigraphs = {
  'きゃ': 'kya',
  'きゅ': 'kyu',
  'きょ': 'kyo',
  'ぎゃ': 'gya',
  'ぎゅ': 'gyu',
  'ぎょ': 'gyo',
  'しゃ': 'sha',
  'しゅ': 'shu',
  'しょ': 'sho',
  'じゃ': 'ja',
  'じゅ': 'ju',
  'じょ': 'jo',
  'ちゃ': 'cha',
  'ちゅ': 'chu',
  'ちょ': 'cho',
  'ぢゃ': 'ja',
  'ぢゅ': 'ju',
  'ぢょ': 'jo',
  'にゃ': 'nya',
  'にゅ': 'nyu',
  'にょ': 'nyo',
  'ひゃ': 'hya',
  'ひゅ': 'hyu',
  'ひょ': 'hyo',
  'びゃ': 'bya',
  'びゅ': 'byu',
  'びょ': 'byo',
  'ぴゃ': 'pya',
  'ぴゅ': 'pyu',
  'ぴょ': 'pyo',
  'みゃ': 'mya',
  'みゅ': 'myu',
  'みょ': 'myo',
  'りゃ': 'rya',
  'りゅ': 'ryu',
  'りょ': 'ryo',
  'ふぁ': 'fa',
  'ふぃ': 'fi',
  'ふぇ': 'fe',
  'ふぉ': 'fo',
  'ヴぁ': 'va',
  'ヴぃ': 'vi',
  'ヴぇ': 've',
  'ヴぉ': 'vo',
  'てぃ': 'ti',
  'でぃ': 'di',
  'とぅ': 'tu',
  'どぅ': 'du',
  'しぇ': 'she',
  'じぇ': 'je',
  'ちぇ': 'che',
  'うぃ': 'wi',
  'うぇ': 'we',
  'うぉ': 'wo',
};

const Map<String, String> _kanaMonographs = {
  'あ': 'a',
  'い': 'i',
  'う': 'u',
  'え': 'e',
  'お': 'o',
  'か': 'ka',
  'き': 'ki',
  'く': 'ku',
  'け': 'ke',
  'こ': 'ko',
  'が': 'ga',
  'ぎ': 'gi',
  'ぐ': 'gu',
  'げ': 'ge',
  'ご': 'go',
  'さ': 'sa',
  'し': 'shi',
  'す': 'su',
  'せ': 'se',
  'そ': 'so',
  'ざ': 'za',
  'じ': 'ji',
  'ず': 'zu',
  'ぜ': 'ze',
  'ぞ': 'zo',
  'た': 'ta',
  'ち': 'chi',
  'つ': 'tsu',
  'て': 'te',
  'と': 'to',
  'だ': 'da',
  'ぢ': 'ji',
  'づ': 'zu',
  'で': 'de',
  'ど': 'do',
  'な': 'na',
  'に': 'ni',
  'ぬ': 'nu',
  'ね': 'ne',
  'の': 'no',
  'は': 'ha',
  'ひ': 'hi',
  'ふ': 'fu',
  'へ': 'he',
  'ほ': 'ho',
  'ば': 'ba',
  'び': 'bi',
  'ぶ': 'bu',
  'べ': 'be',
  'ぼ': 'bo',
  'ぱ': 'pa',
  'ぴ': 'pi',
  'ぷ': 'pu',
  'ぺ': 'pe',
  'ぽ': 'po',
  'ま': 'ma',
  'み': 'mi',
  'む': 'mu',
  'め': 'me',
  'も': 'mo',
  'や': 'ya',
  'ゆ': 'yu',
  'よ': 'yo',
  'ら': 'ra',
  'り': 'ri',
  'る': 'ru',
  'れ': 're',
  'ろ': 'ro',
  'わ': 'wa',
  'ゐ': 'i',
  'ゑ': 'e',
  'を': 'o',
  'ん': 'n',
  'ゔ': 'vu',
  'ぁ': 'a',
  'ぃ': 'i',
  'ぅ': 'u',
  'ぇ': 'e',
  'ぉ': 'o',
  'ゃ': 'ya',
  'ゅ': 'yu',
  'ょ': 'yo',
  'ゎ': 'wa',
};

/// Katakana'yı hiragana'ya indirger (kod noktası farkı sabit 0x60).
/// `ー` uzatma işareti korunur; romanizasyon sırasında çözülür.
String katakanaToHiragana(String value) {
  final buffer = StringBuffer();
  for (final code in value.runes) {
    if (code >= 0x30A1 && code <= 0x30F6) {
      buffer.writeCharCode(code - 0x60);
    } else if (code == 0x30F4) {
      buffer.write('ゔ');
    } else {
      buffer.writeCharCode(code);
    }
  }
  return buffer.toString();
}

/// Kana metnini modifiye Hepburn romaji'ye çevirir.
///
/// Kana olmayan karakterler olduğu gibi geçer — karışık metin ("teamLab
/// ボーダレス") güvenle işlenir.
String kanaToRomaji(String value) {
  final source = katakanaToHiragana(value);
  final buffer = StringBuffer();
  var index = 0;
  var pendingSokuon = false;

  while (index < source.length) {
    final char = source[index];

    // 促音 っ — sonraki ünsüzü ikizler.
    if (char == 'っ') {
      pendingSokuon = true;
      index++;
      continue;
    }

    // 長音符 ー — önceki sesli harfi uzatır. Kanonikleştirmede uzun sesli
    // kısaya katlandığı için işaret düşürülür.
    if (char == 'ー' || char == 'ー') {
      index++;
      continue;
    }

    String? romaji;
    var consumed = 1;
    if (index + 1 < source.length) {
      final pair = source.substring(index, index + 2);
      final digraph = _kanaDigraphs[pair];
      if (digraph != null) {
        romaji = digraph;
        consumed = 2;
      }
    }
    romaji ??= _kanaMonographs[char];

    if (romaji == null) {
      // Kana değil — olduğu gibi aktar, bekleyen sokuon iptal olur.
      pendingSokuon = false;
      buffer.write(char);
      index++;
      continue;
    }

    if (pendingSokuon) {
      // Hepburn: っち → "tchi", diğerlerinde ilk ünsüz ikizlenir.
      buffer.write(romaji.startsWith('ch') ? 't' : romaji[0]);
      pendingSokuon = false;
    }

    // ん + b/m/p → "m" (Hepburn): 難波 なんば → namba.
    if (romaji == 'n' && index + consumed < source.length) {
      final nextChar = source[index + consumed];
      final next = _kanaDigraphs[source.substring(index + consumed,
              math.min(index + consumed + 2, source.length))] ??
          _kanaMonographs[nextChar];
      if (next != null &&
          (next.startsWith('b') ||
              next.startsWith('m') ||
              next.startsWith('p'))) {
        romaji = 'm';
      }
    }

    buffer.write(romaji);
    index += consumed;
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// Kanji okuma sözlüğü
// ---------------------------------------------------------------------------

/// Kanji → romaji okuma sözlüğü.
///
/// Genel kanji→okuma dönüşümü offline mümkün değildir (aynı karakterin
/// onyomi/kunyomi okumaları bağlama göre değişir). Bu yüzden **kapalı bir
/// sözlük** tutulur: önce tam mekan adları, sonra yaygın son ekler.
/// Sözlükte olmayan kanji, romaji üretmez ve kanonik anahtar kanji'nin
/// kendisine düşer — sessiz yanlış eşleşme yerine eşleşmeme.
const Map<String, String> kDefaultKanjiPlaceLexicon = {
  // --- Tam mekan adları ---
  '清水寺': 'kiyomizudera',
  '浅草寺': 'sensoji',
  '金閣寺': 'kinkakuji',
  '銀閣寺': 'ginkakuji',
  '伏見稲荷大社': 'fushimiinaritaisha',
  '伏見稲荷': 'fushimiinari',
  '明治神宮': 'meijijingu',
  '東大寺': 'todaiji',
  '大阪城': 'osakajo',
  '二条城': 'nijojo',
  '嵐山': 'arashiyama',
  '竹林の小径': 'chikurinnokomichi',
  '築地': 'tsukiji',
  '豊洲市場': 'toyosushijo',
  '黒門市場': 'kuromonichiba',
  '道頓堀': 'dotonbori',
  '心斎橋': 'shinsaibashi',
  '通天閣': 'tsutenkaku',
  '梅田': 'umeda',
  '難波': 'namba',
  '天王寺': 'tennoji',
  '新宿': 'shinjuku',
  '渋谷': 'shibuya',
  '池袋': 'ikebukuro',
  '秋葉原': 'akihabara',
  '銀座': 'ginza',
  '上野': 'ueno',
  '上野公園': 'uenokoen',
  '東京国立博物館': 'tokyokokuritsuhakubutsukan',
  '東京スカイツリー': 'tokyosukaitsuri',
  '東京タワー': 'tokyotawa',
  '皇居': 'kokyo',
  '奈良公園': 'narakoen',
  '春日大社': 'kasugataisha',
  '厳島神社': 'itsukushimajinja',
  '原爆ドーム': 'genbakudomu',
  '平和記念公園': 'heiwakinenkoen',
  '兼六園': 'kenrokuen',
  '白川郷': 'shirakawago',
  '新宿御苑': 'shinjukugyoen',
  'お台場': 'odaiba',
  '台場': 'daiba',
  // --- Şehirler ---
  '東京': 'tokyo',
  '京都': 'kyoto',
  '大阪': 'osaka',
  '奈良': 'nara',
  '広島': 'hiroshima',
  '名古屋': 'nagoya',
  '金沢': 'kanazawa',
  '札幌': 'sapporo',
  '福岡': 'fukuoka',
  '沖縄': 'okinawa',
  '横浜': 'yokohama',
  '神戸': 'kobe',
  '箱根': 'hakone',
  '日光': 'nikko',
  // --- Yaygın son ekler / genel adlar ---
  '神社': 'jinja',
  '大社': 'taisha',
  '寺': 'dera',
  '城': 'jo',
  '公園': 'koen',
  '庭園': 'teien',
  '博物館': 'hakubutsukan',
  '美術館': 'bijutsukan',
  '市場': 'ichiba',
  '駅': 'eki',
  '通り': 'dori',
  '橋': 'bashi',
  '山': 'yama',
  '川': 'kawa',
  '海': 'umi',
  '温泉': 'onsen',
  '商店街': 'shotengai',
};

// ---------------------------------------------------------------------------
// Kanonik anahtar
// ---------------------------------------------------------------------------

/// Bir mekanın kanonik kimliği — şehir kapsamlı yerel anahtar + kararlı hash.
class CanonicalPlaceHash {
  const CanonicalPlaceHash({
    required this.key,
    required this.cityKey,
    required this.localKey,
    required this.hash,
    required this.source,
  });

  /// `"tokyo:usj"` biçiminde tam anahtar. Boşsa kimlik çözülememiştir.
  final String key;
  final String cityKey;
  final String localKey;

  /// Kararlı 32-bit FNV-1a hash (hex). Depolama/telemetri için.
  final String hash;

  /// Anahtarın hangi kaynaktan türediği — güven seviyesini belirler.
  final CanonicalIdentitySource source;

  bool get isEmpty => key.isEmpty;
  bool get isNotEmpty => key.isNotEmpty;

  /// `placeId`'den türeyen anahtar güvenilirdir; başlıktan türeyen fallback'e
  /// bulanık eşleşme uygulanabilir.
  bool get isAuthoritative => source == CanonicalIdentitySource.placeId;

  @override
  bool operator ==(Object other) =>
      other is CanonicalPlaceHash && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'CanonicalPlaceHash($key, ${source.name})';
}

enum CanonicalIdentitySource {
  /// Katalog `placeId` alanından — en güvenilir.
  placeId,

  /// Başlıktan romanizasyon/normalizasyon ile — fallback.
  title,

  /// Hiçbir şey çözülemedi.
  none,
}

/// Kanonik çözümleyici.
class PlaceIdentityResolver {
  PlaceIdentityResolver({
    Map<String, String>? kanjiLexicon,
    Map<String, String>? aliasOverrides,
    this.fuzzyMatchThreshold = 0.88,
    this.minimumFuzzyLength = 6,
  })  : kanjiLexicon = Map.unmodifiable({
          ...kDefaultKanjiPlaceLexicon,
          ...?kanjiLexicon,
        }),
        _kanjiKeysByLength = ([
          ...kDefaultKanjiPlaceLexicon.keys,
          ...?kanjiLexicon?.keys,
        ]..sort((a, b) => b.length.compareTo(a.length)))
            .toList(growable: false),
        aliasOverrides = Map.unmodifiable(aliasOverrides ?? const {});

  final Map<String, String> kanjiLexicon;
  final List<String> _kanjiKeysByLength;
  final Map<String, String> aliasOverrides;

  /// Levenshtein benzerlik eşiği. Altındaki eşleşmeler reddedilir.
  final double fuzzyMatchThreshold;

  /// Bu uzunluğun altındaki anahtarlarda bulanık eşleşme yapılmaz — kısa
  /// adlarda tek harf farkı bile ayrı mekan demektir ("Ueno" / "Ueni").
  final int minimumFuzzyLength;

  /// Şehir kimliğini normalize eder.
  String normalizeCity(String? cityId) => _normalizeAscii(
        _transliterate(cityId ?? ''),
      );

  /// Herhangi bir metni ASCII kanonik forma indirger.
  ///
  /// Sıra önemlidir: önce kanji sözlüğü, sonra kana→romaji, sonra Latin
  /// katlama (Türkçe + macron), en sonda alfanümerik dışı temizliği.
  String normalize(String raw) => _normalizeAscii(_transliterate(raw));

  /// Kanji/kana içeren metni romaji'ye çevirir; Latin metni değiştirmez.
  String romanize(String raw) => _transliterate(raw);

  String _transliterate(String raw) {
    if (raw.isEmpty) return raw;
    var value = raw;
    if (value.runes.any(_isKanji)) {
      // Uzun anahtar önce denenir ki 東京国立博物館, 東京 + ... diye parçalanmasın.
      for (final key in _kanjiKeysByLength) {
        if (value.contains(key)) {
          value = value.replaceAll(key, ' ${kanjiLexicon[key]} ');
        }
      }
    }
    if (value.runes
        .any((c) => _isHiragana(c) || _isKatakana(c) || c == 0x30FC)) {
      value = kanaToRomaji(value);
    }
    return value;
  }

  /// Kanonik kimlik üretir.
  ///
  /// [placeId] varsa ondan; yoksa [title]'dan türetilir. Şehir öneki
  /// (`tk-`, `tokyo-`) katalog kimliklerinden ayıklanır.
  CanonicalPlaceHash resolve({
    required String title,
    String? placeId,
    String? cityId,
  }) {
    final city = normalizeCity(cityId);
    final fromId = _canonicalLocalId(placeId, city);
    final fromTitle = _canonicalTitle(title);
    final source = fromId.isNotEmpty
        ? CanonicalIdentitySource.placeId
        : (fromTitle.isNotEmpty
            ? CanonicalIdentitySource.title
            : CanonicalIdentitySource.none);
    final local = _applyAlias(fromId.isNotEmpty ? fromId : fromTitle);
    if (local.isEmpty) {
      return const CanonicalPlaceHash(
        key: '',
        cityKey: '',
        localKey: '',
        hash: '',
        source: CanonicalIdentitySource.none,
      );
    }
    final cityKey = city.isEmpty ? 'unknown' : city;
    final key = '$cityKey:$local';
    return CanonicalPlaceHash(
      key: key,
      cityKey: cityKey,
      localKey: local,
      hash: stableHash(key),
      source: source,
    );
  }

  /// İki kanonik anahtarın aynı mekanı gösterip göstermediği.
  ///
  /// Tam eşitlik her zaman kabul edilir. Bulanık eşleşme yalnız **iki taraf da
  /// başlıktan türemişse** ve aynı şehirdeyse denenir — `placeId` taşıyan
  /// güvenilir kayıtlar asla bulanık birleştirilmez.
  bool isSamePlace(CanonicalPlaceHash a, CanonicalPlaceHash b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a.key == b.key) return true;
    if (a.isAuthoritative && b.isAuthoritative) return false;
    if (a.cityKey != b.cityKey) return false;
    if (a.localKey.length < minimumFuzzyLength ||
        b.localKey.length < minimumFuzzyLength) {
      return false;
    }
    // Biri diğerinin öneki ise (Kiyomizudera / KiyomizuderaTemple) aynı mekan.
    if (a.localKey.startsWith(b.localKey) ||
        b.localKey.startsWith(a.localKey)) {
      return true;
    }
    return similarity(a.localKey, b.localKey) >= fuzzyMatchThreshold;
  }

  /// 0..1 arası normalize Levenshtein benzerliği.
  double similarity(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    final distance = levenshtein(a, b);
    final longest = math.max(a.length, b.length);
    return 1 - distance / longest;
  }

  String _canonicalLocalId(String? value, String city) {
    if (value == null || value.trim().isEmpty) return '';
    var raw = _transliterate(value).toLowerCase().trim().replaceAll('_', '-');
    final prefixes = _cityIdPrefixes(city);
    final parts = raw.split('-');
    if (parts.length > 1 && prefixes.contains(parts.first)) {
      raw = parts.skip(1).join('-');
    }
    return _normalizeAscii(raw);
  }

  String _canonicalTitle(String value) {
    // Baştaki emoji/işaretler atılır; "🗼 Tokyo Skytree" → "Tokyo Skytree".
    final stripped = _transliterate(value)
        .replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '');
    return _normalizeAscii(stripped);
  }

  String _applyAlias(String value) {
    if (value.isEmpty) return '';
    final override = aliasOverrides[value];
    if (override != null) return override;
    return _defaultAlias(value);
  }
}

/// Katalog kimliklerindeki şehir öneki kısaltmaları.
Set<String> _cityIdPrefixes(String city) => switch (city) {
      'tokyo' => const {'tk', 'tokyo'},
      'kyoto' => const {'ky', 'kyoto'},
      'osaka' => const {'os', 'osaka'},
      'nara' => const {'nr', 'nara'},
      'hiroshima' => const {'hr', 'hiroshima'},
      'sapporo' => const {'sp', 'sapporo'},
      'kanazawa' => const {'kn', 'kanazawa'},
      'nagoya' => const {'ng', 'nagoya'},
      'fukuoka' => const {'fk', 'fukuoka'},
      'okinawa' => const {'ok', 'okinawa'},
      _ => const {},
    };

/// Bilinen çoklu-isim kümeleri. Katalogdaki farklı yazımlar tek anahtara
/// indirgenir; `activity_identity.dart`'ın v2 davranışının üst kümesidir.
String _defaultAlias(String value) {
  if (value.isEmpty) return '';
  if (value == 'usj' || value.contains('universalstudios')) return 'usj';
  if (value.contains('tokyodisneysea') || value == 'disneysea') {
    return 'disneysea';
  }
  if (value.contains('tokyodisneyland') || value == 'disneyland') {
    return 'disneyland';
  }
  if (value.contains('teamlabplanets')) return 'teamlabplanets';
  if (value.contains('teamlabborderless')) return 'teamlabborderless';
  if (value.contains('teamlabbotanical')) return 'teamlabbotanical';
  if (value == 'castle' || value.contains('osakakalesi')) return 'castle';
  if (value == 'market' || value.contains('kuromon')) return 'kuromon';
  // Japonca varyantlar — romanizasyon sonrası yakalanır.
  if (value.contains('kiyomizu')) return 'kiyomizudera';
  if (value.contains('fushimiinari') || value.contains('inaritaisha')) {
    return 'fushimiinari';
  }
  if (value.contains('sensoji') || value.contains('asakusakannon')) {
    return 'sensoji';
  }
  if (value.contains('kinkakuji') || value.contains('goldenpavilion')) {
    return 'kinkakuji';
  }
  if (value.contains('ginkakuji') || value.contains('silverpavilion')) {
    return 'ginkakuji';
  }
  if (value.contains('meijijingu') || value.contains('meijishrine')) {
    return 'meijijingu';
  }
  if (value.contains('todaiji')) return 'todaiji';
  if (value.contains('osakajo') || value.contains('osakacastle')) {
    return 'castle';
  }
  // Bölge adları (Arashiyama, Dotonbori, Akihabara…) **kasten** alias
  // almaz: bir bölgede birden çok ayrı mekan bulunur ve tek anahtara
  // indirmek "Arashiyama Bambu" ile "Arashiyama Maymun Parkı"nı yanlışlıkla
  // aynı sayar. Bölge tekrarı `RepeatPolicy.repeatableZone` ile çözülür.
  return value;
}

/// Latin metni ASCII kanonik forma indirger.
///
/// Türkçe karakter katlaması ve macron/aksan temizliği burada yapılır; sonra
/// alfanümerik olmayan her şey atılır. `activity_identity` v2 ile birebir aynı
/// çıktıyı üretmesi geriye uyumluluk sözleşmesidir.
String _normalizeAscii(String value) {
  var out = value.toLowerCase();
  for (final entry in _latinFolding.entries) {
    if (out.contains(entry.key)) out = out.replaceAll(entry.key, entry.value);
  }
  return out.replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

const Map<String, String> _latinFolding = {
  // Türkçe
  'ı': 'i', 'ğ': 'g', 'ü': 'u', 'ş': 's', 'ö': 'o', 'ç': 'c',
  // Hepburn macron + yaygın aksanlar
  'ā': 'a', 'ī': 'i', 'ū': 'u', 'ē': 'e', 'ō': 'o',
  'â': 'a', 'î': 'i', 'û': 'u', 'ê': 'e', 'ô': 'o',
  'á': 'a', 'í': 'i', 'ú': 'u', 'é': 'e', 'ó': 'o',
  'à': 'a', 'ì': 'i', 'ù': 'u', 'è': 'e', 'ò': 'o',
};

/// Standart Levenshtein mesafesi (iki satırlı DP — O(min(n,m)) bellek).
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 0; i < a.length; i++) {
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      current[j + 1] = math.min(
        math.min(current[j] + 1, previous[j + 1] + 1),
        previous[j] + cost,
      );
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// 32-bit FNV-1a — platformlar arası kararlı (JS sayı sınırına güvenli).
String stableHash(String value) {
  var hash = 0x811C9DC5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

// ---------------------------------------------------------------------------
// Alias birleştirme (soft merge)
// ---------------------------------------------------------------------------

/// Birleştirmeye aday kayıt — katalog veya plan satırı.
class PlaceAliasRecord {
  const PlaceAliasRecord({
    required this.identity,
    required this.title,
    this.placeId,
    this.cityId,
    this.hasCoordinates = false,
    this.hasDescription = false,
    this.hasImage = false,
    this.userExplicitSelection = false,
  });

  final CanonicalPlaceHash identity;
  final String title;
  final String? placeId;
  final String? cityId;
  final bool hasCoordinates;
  final bool hasDescription;
  final bool hasImage;
  final bool userExplicitSelection;

  /// Hangi kaydın "ana" (primary) olacağını belirleyen kalite skoru.
  /// Yüksek olan kazanır; eşitlikte `placeId` ve alfabetik sıra tie-break.
  int get qualityScore {
    var score = 0;
    if (userExplicitSelection) score += 100;
    if (identity.isAuthoritative) score += 40;
    if (hasCoordinates) score += 10;
    if (hasDescription) score += 5;
    if (hasImage) score += 3;
    // Daha uzun/tam ad genelde daha bilgilidir ("Universal Studios Japan" >
    // "Universal Studios") ama tek başına belirleyici değildir.
    score += math.min(5, title.trim().length ~/ 10);
    return score;
  }
}

class PlaceAliasMerge {
  const PlaceAliasMerge({
    required this.primary,
    required this.absorbed,
    required this.identity,
  });

  final PlaceAliasRecord primary;
  final List<PlaceAliasRecord> absorbed;
  final CanonicalPlaceHash identity;

  bool get didMerge => absorbed.isNotEmpty;
}

/// Aynı mekana çözülen kayıtları tek ana kayda "soft merge" eder.
///
/// Kayıt silinmez; hangi kaydın kanonik olduğu ve hangilerinin ona
/// bağlandığı raporlanır — çağıran tarafın geri alabilmesi için.
List<PlaceAliasMerge> softMergeAliases(
  List<PlaceAliasRecord> records, {
  PlaceIdentityResolver? resolver,
}) {
  final engine = resolver ?? PlaceIdentityResolver();
  final buckets = <String, List<PlaceAliasRecord>>{};

  for (final record in records) {
    if (record.identity.isEmpty) continue;
    String? bucketKey;
    for (final key in buckets.keys) {
      final representative = buckets[key]!.first;
      if (engine.isSamePlace(representative.identity, record.identity)) {
        bucketKey = key;
        break;
      }
    }
    buckets.putIfAbsent(bucketKey ?? record.identity.key, () => []).add(record);
  }

  final merges = <PlaceAliasMerge>[];
  for (final entry in buckets.entries) {
    final sorted = [...entry.value]..sort((a, b) {
        final quality = b.qualityScore.compareTo(a.qualityScore);
        if (quality != 0) return quality;
        final id = (a.placeId ?? '').compareTo(b.placeId ?? '');
        if (id != 0) return id;
        return a.title.compareTo(b.title);
      });
    merges.add(PlaceAliasMerge(
      primary: sorted.first,
      absorbed: sorted.skip(1).toList(growable: false),
      identity: sorted.first.identity,
    ));
  }
  merges.sort((a, b) => a.identity.key.compareTo(b.identity.key));
  return merges;
}

/// Uygulama genelinde paylaşılan varsayılan çözümleyici — saf olduğu için
/// tekil örnek güvenlidir.
final PlaceIdentityResolver kPlaceIdentityResolver = PlaceIdentityResolver();
