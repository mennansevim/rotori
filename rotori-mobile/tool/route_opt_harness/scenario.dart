import 'dart:math';

import 'poi_data.dart';

/// Bir şehir konaklaması: kaç gece kalınacak.
class CityStay {
  const CityStay(this.city, this.nights);
  final String city;
  final int nights;
}

/// Tek bir test senaryosunun girdi tanımı (henüz planlanmamış).
class ScenarioSpec {
  const ScenarioSpec({
    required this.id,
    required this.adults,
    required this.children,
    required this.stays,
    required this.profile,
    required this.entryAirport,
    required this.exitAirport,
    required this.startDate,
    required this.dailyStartHour,
    required this.dailyEndHour,
  });

  final int id;
  final int adults;
  final int children;
  final List<CityStay> stays;

  /// 'balanced' | 'fastest' | 'leastWalking' | 'cheapest'
  final String profile;
  final String entryAirport;
  final String exitAirport;
  final DateTime startDate;
  final int dailyStartHour;
  final int dailyEndHour;

  int get party => adults + children;
  bool get hasChild => children > 0;
  int get totalDays => stays.fold(0, (s, e) => s + e.nights);

  String get routeLabel => stays.map((s) => s.city).join('→');
  String get title =>
      '$party kişi${hasChild ? " ($children çocuk)" : ""} · $totalDays gün · $routeLabel';
}

/// ~100 deterministik ama çeşitlendirilmiş senaryo üretir.
class ScenarioGenerator {
  ScenarioGenerator({this.seed = 20260803, this.count = 100});

  final int seed;
  final int count;

  static const _profiles = ['balanced', 'fastest', 'leastWalking', 'cheapest'];

  // Giriş havaalanı Tokyo ise ilk şehir Tokyo, Kansai (KIX/ITM) ise Osaka/Kyoto.
  static const _tokyoEntries = ['NRT', 'HND'];
  static const _kansaiEntries = ['KIX', 'ITM'];

  List<ScenarioSpec> generate() {
    final rng = Random(seed);
    final specs = <ScenarioSpec>[];

    // Elle seçilmiş "imza" senaryolar (kullanıcının verdiği örnek dahil).
    specs.addAll(_signatureScenarios());

    var id = specs.length + 1;
    while (specs.length < count) {
      specs.add(_randomScenario(id, rng));
      id++;
    }
    return specs.take(count).toList();
  }

  List<ScenarioSpec> _signatureScenarios() {
    final base = DateTime(2026, 4, 6, 0, 0);
    return [
      // Kullanıcının verdiği birebir örnek: 3 kişi (1 çocuk), 14 gün,
      // Tokyo 6 / Osaka 6 / Kyoto 2, Tokyo'ya iniş.
      ScenarioSpec(
        id: 1,
        adults: 2,
        children: 1,
        stays: const [CityStay('Tokyo', 6), CityStay('Osaka', 6), CityStay('Kyoto', 2)],
        profile: 'balanced',
        entryAirport: 'NRT',
        exitAirport: 'KIX',
        startDate: base,
        dailyStartHour: 8,
        dailyEndHour: 21,
      ),
      // Çift, 10 gün, klasik altın üçgen.
      ScenarioSpec(
        id: 2,
        adults: 2,
        children: 0,
        stays: const [CityStay('Tokyo', 4), CityStay('Kyoto', 3), CityStay('Osaka', 3)],
        profile: 'fastest',
        entryAirport: 'HND',
        exitAirport: 'KIX',
        startDate: base,
        dailyStartHour: 8,
        dailyEndHour: 22,
      ),
      // Aile 4 kişi (2 çocuk), 7 gün, yürüyüş az profili.
      ScenarioSpec(
        id: 3,
        adults: 2,
        children: 2,
        stays: const [CityStay('Tokyo', 4), CityStay('Hakone', 1), CityStay('Kyoto', 2)],
        profile: 'leastWalking',
        entryAirport: 'NRT',
        exitAirport: 'NRT',
        startDate: base,
        dailyStartHour: 9,
        dailyEndHour: 20,
      ),
      // Tek gezgin, 5 gün, ucuz profili.
      ScenarioSpec(
        id: 4,
        adults: 1,
        children: 0,
        stays: const [CityStay('Osaka', 2), CityStay('Kyoto', 2), CityStay('Nara', 1)],
        profile: 'cheapest',
        entryAirport: 'KIX',
        exitAirport: 'KIX',
        startDate: base,
        dailyStartHour: 8,
        dailyEndHour: 21,
      ),
      // Büyük grup 6 kişi (2 çocuk), 16 gün, 5 şehir.
      ScenarioSpec(
        id: 5,
        adults: 4,
        children: 2,
        stays: const [
          CityStay('Tokyo', 5),
          CityStay('Hakone', 2),
          CityStay('Kyoto', 4),
          CityStay('Nara', 1),
          CityStay('Osaka', 4),
        ],
        profile: 'balanced',
        entryAirport: 'NRT',
        exitAirport: 'KIX',
        startDate: base,
        dailyStartHour: 8,
        dailyEndHour: 21,
      ),
    ];
  }

  ScenarioSpec _randomScenario(int id, Random rng) {
    final adults = 1 + rng.nextInt(4); // 1..4
    final children = rng.nextInt(3); // 0..2
    final profile = _profiles[rng.nextInt(_profiles.length)];

    final fromTokyo = rng.nextBool();
    final entry = fromTokyo
        ? _tokyoEntries[rng.nextInt(_tokyoEntries.length)]
        : _kansaiEntries[rng.nextInt(_kansaiEntries.length)];

    final stays = _buildStays(rng, startInTokyo: fromTokyo);
    // Çıkış: son şehir Tokyo bölgesindeyse Tokyo havaalanı, değilse Kansai.
    final lastCity = stays.last.city;
    final exit = (lastCity == 'Tokyo' || lastCity == 'Hakone')
        ? _tokyoEntries[rng.nextInt(_tokyoEntries.length)]
        : _kansaiEntries[rng.nextInt(_kansaiEntries.length)];

    final startHour = 8 + rng.nextInt(2); // 8..9
    final endHour = 20 + rng.nextInt(3); // 20..22

    return ScenarioSpec(
      id: id,
      adults: adults,
      children: children,
      stays: stays,
      profile: profile,
      entryAirport: entry,
      exitAirport: exit,
      startDate: DateTime(2026, 4, 6),
      dailyStartHour: startHour,
      dailyEndHour: endHour,
    );
  }

  List<CityStay> _buildStays(Random rng, {required bool startInTokyo}) {
    // Şehir sırası: giriş bölgesine göre coğrafi olarak mantıklı zincir.
    final tokyoChain = ['Tokyo', 'Hakone', 'Kyoto', 'Nara', 'Osaka', 'Hiroshima'];
    final kansaiChain = ['Osaka', 'Kyoto', 'Nara', 'Hiroshima', 'Hakone', 'Tokyo'];
    final chain = startInTokyo ? tokyoChain : kansaiChain;

    final cityCount = 2 + rng.nextInt(4); // 2..5 şehir
    final chosen = chain.take(cityCount).toList();

    return chosen.map((city) {
      // Nara/Hakone genelde 1-2 gece; büyük şehirler 2-6 gece.
      final isSmall = city == 'Nara' || city == 'Hakone';
      final nights = isSmall ? 1 + rng.nextInt(2) : 2 + rng.nextInt(5);
      return CityStay(city, nights);
    }).toList();
  }
}
