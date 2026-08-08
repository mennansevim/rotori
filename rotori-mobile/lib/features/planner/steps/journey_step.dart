import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/city_places.dart';
import '../../../domain/japan_suggestions.dart';
import '../../../domain/types.dart';
import '../data/airlines.dart';
import '../data/airports.dart';
import '../planner_theme.dart';
import '../widgets/pickers.dart';

/// apps/planner/src/components/steps/JourneyStep.tsx birebir port (çekirdek).
/// Uçuş bacakları (gidiş + dönüş), havayolu/havaalanı pickerları, rota önizleme,
/// yolcu & tempo seçenekleri. Uçuş-arama API'si + OCR bu iterasyonda stub.
class JourneyStep extends StatefulWidget {
  const JourneyStep({
    super.key,
    required this.trip,
    required this.onChange,
    this.onLoadJapanPlan,
  });
  final Trip trip;
  final void Function(void Function(Trip)) onChange;
  final VoidCallback? onLoadJapanPlan;

  @override
  State<JourneyStep> createState() => _JourneyStepState();
}

/// Şehir adından parantez içi bölgeyi (ör. "(Narita)", "(Kansai)") temizler.
/// Dedup + eşleştirme için tek doğru merkez — havalimanı bilgisi zaten
/// TripDestination.airport alanında ayrı tutulur.
String _normalizeCity(String city) =>
    city.replaceAll(RegExp(r'\s*\(.*\)\s*$'), '').trim();

class _JourneyStepState extends State<JourneyStep> {
  /// Aktif şehir sekmesi (order index). Silme sonrası clamp'lenir.
  int _activeTab = 0;

  @override
  void initState() {
    super.initState();
    // Japonya-odaklı: destinasyon boşsa otomatik Tokyo/HND kur (JourneyStep useEffect).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.trip.preferences.destinations.isEmpty) {
        widget.onChange((t) {
          final start = t.preferences.travelDates.start;
          final end = t.preferences.travelDates.end;
          t.preferences.destinations.add(TripDestination(
            id: 'dest-${DateTime.now().millisecondsSinceEpoch}',
            countryCode: 'JP',
            countryName: 'Japonya',
            city: 'Tokyo',
            airport: 'HND',
            arrivalDate: start,
            departureDate: end,
            order: 0,
          ));
          _resync(t);
        });
      }
    });
  }

  Trip get trip => widget.trip;

  /// Uçuş/varış düzenlemeleri sonrası hafif senkron. Yalnızca order normalize +
  /// travelDates.start/end + tripStart/End senkronu yapar. Gün dağıtımı (tarih
  /// blokları + t.days üretimi) artık Plan adımına ait — burada TARİHLERE ve
  /// GÜNLERE dokunulmaz, böylece rota/sekmeler titremez.
  void _resync(Trip t) {
    final dests = [...t.preferences.destinations]..sort((a, b) => a.order.compareTo(b.order));
    for (var i = 0; i < dests.length; i++) {
      dests[i].order = i;
    }
    final start = dests.isNotEmpty ? dests.first.arrivalDate : t.preferences.travelDates.start;
    var end = t.preferences.travelDates.end;
    final lastArrival = dests.isNotEmpty ? dests.last.arrivalDate : start;
    if (end.compareTo(lastArrival) < 0) end = lastArrival;

    for (var i = 0; i < dests.length; i++) {
      dests[i].departureDate = i + 1 < dests.length ? dests[i + 1].arrivalDate : end;
    }
    t.preferences.travelDates
      ..start = start
      ..end = end;
    t.tripStart = '${start}T08:00:00';
    t.tripEnd = '${end}T20:00:00';
  }

  /// Silme/ekleme sonrası aktif sekmeyi güvenli aralığa çeker.
  void _clampActiveTab() {
    final n = trip.preferences.destinations.length;
    if (n == 0) {
      _activeTab = 0;
    } else if (_activeTab >= n) {
      _activeTab = n - 1;
    } else if (_activeTab < 0) {
      _activeTab = 0;
    }
  }

  bool get _hasTicket => trip.preferences.hasTicket != false;

  String get _origin =>
      trip.preferences.originCity ??
      (trip.flights.outbound.isNotEmpty ? trip.flights.outbound.first.city : '');
  String get _originAirport => trip.preferences.originAirport ?? '';

  List<TripDestination> get _dests {
    final d = [...trip.preferences.destinations]..sort((a, b) => a.order.compareTo(b.order));
    return d;
  }

  /// Bir şehrin gezilecek yerleri: önce kCityData'da alias/label ile bul → .places;
  /// yoksa kJapanPopular'dan p.city eşleşenler. (name + emoji minimal kaydı.)
  List<({String name, String emoji})> _placesForCity(String city) {
    // "Osaka (Kansai)" → "osaka": havaalanı/bölge ekini at ki kCityData eşleşsin.
    final key = city
        .replaceAll(RegExp(r'\s*\(.*\)\s*$'), '')
        .trim()
        .toLowerCase();
    if (key.isEmpty) return const [];
    for (final c in kCityData) {
      if (c.label.toLowerCase() == key || c.aliases.contains(key)) {
        return [for (final p in c.places) (name: p.name, emoji: p.emoji)];
      }
    }
    return [
      for (final p in kJapanPopular)
        if (p.city
                .replaceAll(RegExp(r'\s*\(.*\)\s*$'), '')
                .trim()
                .toLowerCase() ==
            key)
          (name: p.name, emoji: p.emoji),
    ];
  }

  /// Sekmeler için görüntü sırası: iniş şehri EN BAŞTA, dönüş şehri EN SONDA,
  /// diğerleri arada. Model sırası (destinations[].order) aynen kalır — bu
  /// yalnızca sekme/rota çubuğu gösterimini etkiler.
  ///
  /// Örnek: dests = [Tokyo(0), Kyoto(1), Osaka(2), Nara(3)], returnDepart=KIX
  /// → ordered = [Tokyo, Kyoto, Nara, Osaka] (Osaka dönüş olarak sona alınır).
  List<TripDestination> _orderedForTabs(List<TripDestination> dests) {
    if (dests.length <= 1) return dests;
    final arr = dests.first; // order 0 = iniş (outbound arrival)
    final retIata = (trip.preferences.returnDepartAirport ?? '').trim();
    TripDestination? ret;
    final middle = <TripDestination>[];
    for (var i = 1; i < dests.length; i++) {
      final d = dests[i];
      if (retIata.isNotEmpty && d.airport == retIata && ret == null) {
        ret = d;
      } else {
        middle.add(d);
      }
    }
    return [arr, ...middle, if (ret != null) ret];
  }

  /// Dönüş şehri iniş şehrinden farklı mı? (Aksi halde round-trip aynı şehir,
  /// dönüş rozeti gerekmez.)
  bool get _hasDistinctReturn {
    final r = (trip.preferences.returnDepartAirport ?? '').trim();
    if (r.isEmpty) return false;
    final arrIata = _dests.isEmpty ? '' : (_dests.first.airport ?? '');
    return r != arrIata;
  }

  /// Dönüş tarihini günceller — travelDates.end + tripEnd + son destinasyonun
  /// departureDate'i.
  void _setReturnDate(String v) {
    widget.onChange((t) {
      t.preferences.travelDates.end = v;
      t.tripEnd = '${v}T20:00:00';
      if (t.preferences.destinations.isNotEmpty) {
        final sorted = [...t.preferences.destinations]
          ..sort((a, b) => a.order.compareTo(b.order));
        sorted.last.departureDate = v;
        t.preferences.destinations = sorted;
      }
    });
  }

  bool _isMustSee(String name) => trip.preferences.mustSee
      .any((m) => m.trim().toLowerCase() == name.trim().toLowerCase());

  /// Yer adını mustSee listesine ekler/çıkarır. Rota/tarihlere dokunmaz.
  void _toggleMustSee(String name) {
    widget.onChange((t) {
      final idx = t.preferences.mustSee
          .indexWhere((m) => m.trim().toLowerCase() == name.trim().toLowerCase());
      if (idx >= 0) {
        t.preferences.mustSee.removeAt(idx);
      } else {
        t.preferences.mustSee.add(name);
      }
    });
    setState(() {});
  }

  void _setOrigin(Airport a) {
    widget.onChange((t) {
      t.preferences
        ..originCity = a.city
        ..originAirport = a.iata
        ..originLat = a.lat
        ..originLng = a.lng;
      _resync(t);
    });
  }

  void _updateLeg(int legIndex, void Function(TripDestination) patch) {
    widget.onChange((t) {
      final dests = [...t.preferences.destinations]..sort((a, b) => a.order.compareTo(b.order));
      while (legIndex >= dests.length) {
        dests.add(TripDestination(
          id: 'dest-${DateTime.now().millisecondsSinceEpoch}-${dests.length}',
          countryCode: '',
          countryName: '',
          city: '',
          airport: '',
          arrivalDate: t.preferences.travelDates.start,
          departureDate: t.preferences.travelDates.end,
          order: dests.length,
        ));
      }
      patch(dests[legIndex]);
      t.preferences.destinations = dests;
      _resync(t);
    });
  }

  void _setArrival(int legIndex, Airport a) {
    _updateLeg(legIndex, (d) {
      d.countryCode = a.countryCode;
      d.countryName = a.countryName;
      // "Tokyo (Narita)" → "Tokyo" — havalimanı zaten d.airport'ta.
      d.city = _normalizeCity(a.city);
      d.airport = a.iata;
      d.lat = a.lat;
      d.lng = a.lng;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final dests = _dests;
    final destCount = dests.length;
    // Görüntü sırası — iniş şehri BAŞTA, dönüş şehri SONDA. Model sırası
    // (destinations[].order) aynen kalır; bu sadece sekme/rota gösterimi için.
    final ordered = _orderedForTabs(dests);
    final displayActive =
        ordered.isEmpty ? 0 : _activeTab.clamp(0, ordered.length - 1);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        PageHeadline(s.s('journey.title')),
        PageSub(_hasTicket
            ? s.s('journey.sub.ticket')
            : s.s('journey.sub.plan')),

        if (widget.onLoadJapanPlan != null) _japanBanner(),

        // Gidiş uçuşu — uçağın indiği ilk Japon şehri (iniş).
        _flightLeg(0, dests.isEmpty ? null : dests.first),

        // Dönüş uçuşu — iniş şehrinden farklı bir şehirden de kalkabilirsin
        // (ör. Tokyo iniş, Osaka dönüş).
        _returnLeg(),

        if (destCount >= 2) _shinkansenReminder(),

        // Gezilecek şehirler — INERT chip listesi (seçmek yalnızca ekler).
        _cityPicker(dests),

        // Şehir sekmeleri + aktif şehrin gezilecek yerleri (ordered).
        if (destCount > 0) _cityTabs(ordered, displayActive),
        if (destCount > 0) _cityPlaces(ordered[displayActive]),

        // Sabit ROTA çubuğu — her zaman görünür (ordered).
        _routeBar(ordered),

        // Devam ipucu — yalnızca gerçekten eksikse.
        if (_originAirport.isEmpty || dests.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PT.accentSoft,
              borderRadius: BorderRadius.circular(PT.radius),
            ),
            child: Text(
              s.s('journey.continueHint'),
              style: const TextStyle(fontSize: 14, color: PT.accent),
            ),
          ),
      ],
    );
  }

  /// display-order[0] → "iniş"; ayrı dönüş şehri varsa display-order[son] →
  /// "dönüş"; aksi durumda dönüş rozeti yok (round-trip aynı şehir).
  String? _badgeFor(int i, int count, LanguageScope s) {
    if (i == 0) return s.s('journey.badge.arrival');
    if (i == count - 1 && count > 1 && _hasDistinctReturn) {
      return s.s('journey.badge.return');
    }
    return null;
  }

  /// Seçili destinasyonlar order sırasıyla yatay pill sekmeler.
  Widget _cityTabs(List<TripDestination> dests, int active) {
    final s = LanguageScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < dests.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CityTab(
                  label: dests[i].city.isNotEmpty
                      ? dests[i].city
                      : dests[i].countryName,
                  badge: _badgeFor(i, dests.length, s),
                  active: i == active,
                  onTap: () => setState(() => _activeTab = i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Aktif şehrin gezilecek yerleri — minimal check-row listesi.
  Widget _cityPlaces(TripDestination dest) {
    final s = LanguageScope.of(context);
    final city = dest.city.isNotEmpty ? dest.city : dest.countryName;
    final places = _placesForCity(city);
    final selected = places.where((p) => _isMustSee(p.name)).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: PT.bgElevated,
        borderRadius: BorderRadius.circular(PT.radius),
        border: Border.all(color: PT.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.p('journey.cityPlaces.title', {'city': city}),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: PT.text),
                ),
              ),
              Text(
                s.p('journey.cityPlaces.selected', {'n': '$selected'}),
                style: const TextStyle(fontSize: 12, color: PT.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final p in places)
            _PlaceCheckRow(
              emoji: p.emoji,
              name: p.name,
              checked: _isMustSee(p.name),
              onTap: () => _toggleMustSee(p.name),
            ),
        ],
      ),
    );
  }

  /// Sabit rota çubuğu: origin → dest1 (iniş) → … → son (dönüş).
  Widget _routeBar(List<TripDestination> dests) {
    final s = LanguageScope.of(context);
    final origin = _origin;
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PT.accentSoft,
        borderRadius: BorderRadius.circular(PT.radius),
        border: Border.all(color: PT.accent.withValues(alpha: 0.25)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _RouteNode(label: origin.isEmpty ? '—' : origin, muted: origin.isEmpty),
            for (var i = 0; i < dests.length; i++) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 14, color: PT.accent),
              ),
              _RouteNode(
                label: dests[i].city.isNotEmpty
                    ? dests[i].city
                    : dests[i].countryName,
                badge: _badgeFor(i, dests.length, s),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- parçalar ----

  Widget _shinkansenReminder() {
    final s = LanguageScope.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PT.accentSoft,
        borderRadius: BorderRadius.circular(PT.radius),
        border: Border.all(color: PT.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.s('journey.shinkansen.title'),
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: PT.accent)),
          const SizedBox(height: 6),
          Text(
              s.s('journey.shinkansen.body'),
              style:
                  const TextStyle(fontSize: 13, color: PT.text, height: 1.35)),
          const SizedBox(height: 4),
          Text(
              s.s('journey.shinkansen.note'),
              style: const TextStyle(fontSize: 12, color: PT.textSecondary, height: 1.35)),
        ],
      ),
    );
  }

  /// Japon şehirlerini chip listesi olarak sunar; kullanıcı seçtikçe
  /// destinasyonlara eklenir/çıkarılır. Shinkansen mantığı zaten
  /// destinations>=2 iken üstteki hatırlatma kartını gösterir.
  Widget _cityPicker(List<TripDestination> dests) {
    final s = LanguageScope.of(context);
    // Şu an rotadaki şehirleri normalize et — kolay karşılaştırma için.
    final selectedNames = {
      for (final d in dests) _normalizeCity(d.city).toLowerCase(),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: PT.bgElevated,
        borderRadius: BorderRadius.circular(PT.radius),
        border: Border.all(color: PT.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.s('journey.cities.title'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: PT.text)),
          const SizedBox(height: 2),
          Text(
              s.s('journey.cities.inertHint'),
              style: const TextStyle(
                  fontSize: 12, color: PT.textSecondary, height: 1.35)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in kCityData)
                _CityChip(
                  emoji: c.emoji,
                  label: c.label,
                  active: selectedNames.contains(c.label.toLowerCase()),
                  onTap: () => _toggleCity(c),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Listede olmayan şehirler için — Japon şehir picker'ı (havalimanı
          // olmayanlar dahil). Seçince custom destinasyon olur.
          _JpCityPickerField(
            onSelect: (c) => _addCustomCityFromJp(c),
          ),
          // Chip listesinde olmayan (custom eklenmiş) destinasyonları da göster.
          if (dests.any((d) => !_isKnownCity(d.city))) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in dests)
                  if (!_isKnownCity(d.city))
                    _CityChip(
                      emoji: '📍',
                      label:
                          '${d.city}${(d.airport ?? '').isNotEmpty ? ' (${d.airport})' : ''}',
                      active: true,
                      onTap: () => _removeCustomCity(d),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _isKnownCity(String city) => kCityData
      .any((c) => c.label.toLowerCase() == _normalizeCity(city).toLowerCase());

  /// Custom şehir: JpCity listesinden seçilen şehir ile destinasyon ekler.
  /// Havalimanı olan şehirlerde IATA otomatik atanır (uçuş bacağı için); yoksa
  /// airport boş — Shinkansen/tren ile gidilecek şehir olarak eklenir.
  void _addCustomCityFromJp(_JpCity c) {
    widget.onChange((t) {
      final list = [...t.preferences.destinations]
        ..sort((x, y) => x.order.compareTo(y.order));
      // Aynı şehir zaten varsa tekrar ekleme.
      if (list.any((d) =>
          _normalizeCity(d.city).toLowerCase() ==
          _normalizeCity(c.name).toLowerCase())) {
        return;
      }
      list.add(TripDestination(
        id: 'dest-${DateTime.now().millisecondsSinceEpoch}-${list.length}',
        countryCode: 'JP',
        countryName: 'Japonya',
        city: c.name,
        airport: c.iata ?? '',
        lat: c.lat,
        lng: c.lng,
        // Placeholder tarihler — gerçek gün dağılımı Plan adımından gelir.
        arrivalDate: t.preferences.travelDates.start,
        departureDate: t.preferences.travelDates.end,
        order: list.length,
      ));
      for (var i = 0; i < list.length; i++) {
        list[i].order = i;
      }
      t.preferences.destinations = list;
    });
    setState(_clampActiveTab);
  }

  void _removeCustomCity(TripDestination target) {
    widget.onChange((t) {
      final list = [...t.preferences.destinations]
        ..sort((x, y) => x.order.compareTo(y.order));
      list.removeWhere((d) => d.id == target.id);
      for (var i = 0; i < list.length; i++) {
        list[i].order = i;
      }
      t.preferences.destinations = list;
    });
    setState(_clampActiveTab);
  }

  /// Şehir chip'ine tıklanınca: rotada yoksa yeni destinasyon (ilk havalimanı
  /// varsa airport otomatik atanır), varsa listeden çıkarılır.
  void _toggleCity(CityData city) {
    widget.onChange((t) {
      final list = [...t.preferences.destinations]
        ..sort((a, b) => a.order.compareTo(b.order));
      final existingIdx = list.indexWhere(
          (d) => _normalizeCity(d.city).toLowerCase() == city.label.toLowerCase());
      if (existingIdx >= 0) {
        list.removeAt(existingIdx);
      } else {
        final ap = kAirports.firstWhere(
          (a) => a.countryCode == 'JP' &&
              a.city.toLowerCase().contains(city.label.toLowerCase()),
          orElse: () => Airport(
            iata: '',
            city: city.label,
            countryCode: 'JP',
            countryName: 'Japonya',
            lat: 0,
            lng: 0,
          ),
        );
        list.add(TripDestination(
          id: 'dest-${DateTime.now().millisecondsSinceEpoch}-${list.length}',
          countryCode: 'JP',
          countryName: 'Japonya',
          city: city.label,
          airport: ap.iata,
          lat: ap.iata.isNotEmpty ? ap.lat : null,
          lng: ap.iata.isNotEmpty ? ap.lng : null,
          // Placeholder tarihler — gerçek gün dağılımı Plan adımından gelir.
          arrivalDate: t.preferences.travelDates.start,
          departureDate: t.preferences.travelDates.end,
          order: list.length,
        ));
      }
      // Order'ları 0..n normalize et. travelDates/tripStart/End ve t.days'e
      // DOKUNMA — şehir seçimi inert; rota/tarih/sekmeler titremez.
      for (var i = 0; i < list.length; i++) {
        list[i].order = i;
      }
      t.preferences.destinations = list;
    });
    setState(_clampActiveTab);
  }

  Widget _japanBanner() {
    final s = LanguageScope.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PT.bgElevated,
        borderRadius: BorderRadius.circular(PT.radius),
        border: Border.all(color: PT.border),
        boxShadow: PT.shadowSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.s('journey.banner.title'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: PT.text)),
                const SizedBox(height: 2),
                Text(s.s('journey.banner.body'),
                    style: const TextStyle(fontSize: 13, color: PT.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PButton(label: s.s('journey.banner.load'), onPressed: widget.onLoadJapanPlan),
        ],
      ),
    );
  }

  Widget _legShell({required String title, required List<Widget> children, bool isReturn = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isReturn ? PT.bgSubtle : PT.bg,
        borderRadius: BorderRadius.circular(PT.radius),
        border: Border.all(color: PT.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: PT.text)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _field(String label, Widget control) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: PT.text)),
          const SizedBox(height: 8),
          control,
        ],
      ),
    );
  }

  Widget _flightLeg(int index, TripDestination? dest) {
    final s = LanguageScope.of(context);
    final airline = dest?.airline;
    final airlineSet = airline != null && airline.isNotEmpty;

    return _legShell(
      title: _hasTicket ? s.s('journey.leg.outbound') : s.s('journey.leg.route'),
      children: [
        if (_hasTicket)
          _field(
            s.s('journey.field.airline'),
            AirlinePickerField(
              valueCode: airline,
              valueLabel: airlineSet ? airlineLabel(airline) : null,
              onSelect: (a) => _updateLeg(index, (d) => d.airline = a.code),
            ),
          ),
        if (_hasTicket && airlineSet)
          _field(
            s.s('journey.field.flightNo'),
            _FlightNoInput(
              prefix: airline,
              value: dest?.flightNo ?? '',
              onChanged: (v) => _updateLeg(index, (d) => d.flightNo = v.replaceAll(RegExp(r'\s+'), '')),
            ),
          ),
        _field(
          s.s('journey.field.date'),
          _DateBox(
            value: dest?.arrivalDate ?? trip.preferences.travelDates.start,
            onPick: (v) => _updateLeg(index, (d) => d.arrivalDate = v),
          ),
        ),
        _field(
          s.s('journey.field.departureTr'),
          index == 0
              ? AirportPickerField(
                  // Dünyanın herhangi bir yerinden kalkış — ülke kısıtı yok.
                  valueCode: _originAirport.isEmpty ? null : _originAirport,
                  valueLabel: _origin.isEmpty ? null : _origin,
                  placeholder: 'IST · LHR · JFK · SIN · DXB…',
                  onSelect: _setOrigin,
                )
              : _FixedBox(text: _origin.isEmpty ? '—' : _origin),
        ),
        _field(
          s.s('journey.field.arrivalJp'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AirportPickerField(
                countryCodes: const ['JP'],
                valueCode: (dest?.airport ?? '').isNotEmpty ? dest!.airport : null,
                valueLabel: (dest?.city.isNotEmpty ?? false) ? dest!.city : null,
                placeholder: 'Tokyo Haneda (HND), Narita (NRT), Osaka (KIX)',
                onSelect: (a) => _setArrival(index, a),
              ),
              if (dest?.countryName.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('🇯🇵 ${dest!.countryName}',
                      style: const TextStyle(fontSize: 13, color: PT.textSecondary)),
                ),
            ],
          ),
        ),
        // İniş saati — varış günü akışı (havaalanı → transfer → check-in) bu
        // saate göre kurulur.
        _field(
          s.s('journey.field.arrivalTime'),
          _TimeBox(
            value: trip.preferences.outboundArrivalTime ?? '',
            onPick: (v) => widget.onChange((t) {
              t.preferences.outboundArrivalTime = v;
            }),
          ),
        ),
      ],
    );
  }

  /// Dönüş uçuşu — Google Flights tarzı 3 alan:
  ///  • Dönüş tarihi
  ///  • Japonya'da kalkış havaalanı (iniş şehrinden farklı olabilir)
  ///  • Kalkış ülkende varış havaalanı (varsayılan: gidiş kalkış havaalanı)
  Widget _returnLeg() {
    final s = LanguageScope.of(context);
    final dests = _dests;
    // Varsayılan: iniş şehrinin havaalanı (round-trip aynı yerden dönüş).
    final defaultDepIata =
        dests.isNotEmpty ? (dests.first.airport ?? '') : '';
    final returnDepIata =
        (trip.preferences.returnDepartAirport ?? '').isNotEmpty
            ? trip.preferences.returnDepartAirport!
            : defaultDepIata;
    final returnDep =
        kAirports.where((a) => a.iata == returnDepIata).toList();
    final returnArrIata =
        (trip.preferences.returnArrivalAirport ?? '').isNotEmpty
            ? trip.preferences.returnArrivalAirport!
            : _originAirport;
    final returnArr =
        kAirports.where((a) => a.iata == returnArrIata).toList();
    return _legShell(
      isReturn: true,
      title: s.s('journey.leg.return'),
      children: [
        _field(
          s.s('journey.field.date'),
          _DateBox(
            value: trip.preferences.travelDates.end,
            onPick: _setReturnDate,
          ),
        ),
        _field(
          s.s('journey.field.departureJp'),
          AirportPickerField(
            countryCodes: const ['JP'],
            valueCode: returnDep.isNotEmpty ? returnDep.first.iata : null,
            valueLabel: returnDep.isNotEmpty ? returnDep.first.city : null,
            placeholder: 'Tokyo (HND) · Osaka (KIX) · Fukuoka (FUK)…',
            onSelect: (a) => widget.onChange((t) {
              t.preferences.returnDepartAirport = a.iata;
            }),
          ),
        ),
        // Kalkış saati — ayrılış günü akışı (check-out → transfer → uçuş) bu
        // saate göre kurulur.
        _field(
          s.s('journey.field.departureTime'),
          _TimeBox(
            value: trip.preferences.returnDepartTime ?? '',
            onPick: (v) => widget.onChange((t) {
              t.preferences.returnDepartTime = v;
            }),
          ),
        ),
        _field(
          s.s('journey.field.arrivalTr'),
          AirportPickerField(
            valueCode: returnArr.isNotEmpty ? returnArr.first.iata : null,
            valueLabel: returnArr.isNotEmpty ? returnArr.first.city : null,
            placeholder: 'IST · LHR · JFK · DXB…',
            onSelect: (a) => widget.onChange((t) {
              t.preferences.returnArrivalAirport = a.iata;
            }),
          ),
        ),
      ],
    );
  }

}

// ---- küçük parçalar ----

class _FlightNoInput extends StatelessWidget {
  const _FlightNoInput({required this.prefix, required this.value, required this.onChanged});
  final String? prefix;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: PT.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PT.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            color: PT.bgSubtle,
            child: Text(prefix ?? '',
                style: const TextStyle(fontWeight: FontWeight.w700, color: PT.textSecondary)),
          ),
          Expanded(
            child: TextFormField(
              initialValue: value,
              keyboardType: TextInputType.number,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: s.s('journey.field.flightNo'),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FixedBox extends StatelessWidget {
  const _FixedBox({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: PT.bgSubtle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: PT.text)),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.value, required this.onPick});
  final String value;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final now = DateTime.now();
        final init = value.isEmpty ? now : (DateTime.tryParse(value) ?? now);
        final picked = await showDatePicker(
          context: context,
          initialDate: init,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 3),
        );
        if (picked != null) onPick(picked.toIso8601String().substring(0, 10));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: PT.bgSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PT.borderStrong),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 16, color: PT.textSecondary),
            const SizedBox(width: 10),
            Text(value.isEmpty ? s.s('journey.date.pick') : value,
                style: TextStyle(
                    fontSize: 15, color: value.isEmpty ? PT.textTertiary : PT.text)),
          ],
        ),
      ),
    );
  }
}

/// Saat picker'ı (HH:MM). Boşsa placeholder gösterir.
class _TimeBox extends StatelessWidget {
  const _TimeBox({required this.value, required this.onPick});
  final String value;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    TimeOfDay initial;
    if (value.isNotEmpty && value.contains(':')) {
      final parts = value.split(':');
      initial = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 10,
          minute: int.tryParse(parts[1]) ?? 0);
    } else {
      initial = const TimeOfDay(hour: 10, minute: 0);
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: initial,
        );
        if (picked != null) {
          final hh = picked.hour.toString().padLeft(2, '0');
          final mm = picked.minute.toString().padLeft(2, '0');
          onPick('$hh:$mm');
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: PT.bgSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PT.borderStrong),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time, size: 16, color: PT.textSecondary),
            const SizedBox(width: 10),
            Text(value.isEmpty ? s.s('journey.time.pick') : value,
                style: TextStyle(
                    fontSize: 15,
                    color: value.isEmpty ? PT.textTertiary : PT.text)),
          ],
        ),
      ),
    );
  }
}

/// Şehir chip'i — aktifse dolgulu, değilse çerçeveli. 44pt tap hedefi.
class _CityChip extends StatelessWidget {
  const _CityChip({
    required this.emoji,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String emoji;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? PT.accent : PT.bgSubtle,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: active ? PT.accent : PT.borderStrong,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : PT.text)),
            if (active) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check, size: 14, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}

/// Şehir sekmesi — aktifse accent dolgulu. Opsiyonel iniş/dönüş rozeti.
class _CityTab extends StatelessWidget {
  const _CityTab({
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? PT.accent : PT.bgSubtle,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: active ? PT.accent : PT.borderStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : PT.text)),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.22)
                      : PT.accentSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(badge!,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : PT.accent)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Şehir-içi gezilecek yer satırı — sağda yuvarlak seçim işareti.
class _PlaceCheckRow extends StatelessWidget {
  const _PlaceCheckRow({
    required this.emoji,
    required this.name,
    required this.checked,
    required this.onTap,
  });
  final String emoji;
  final String name;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(name,
                  style: const TextStyle(fontSize: 14, color: PT.text)),
            ),
            const SizedBox(width: 8),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? PT.accent : Colors.transparent,
                border: Border.all(
                    color: checked ? PT.accent : PT.borderStrong, width: 2),
              ),
              child: checked
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Rota çubuğu düğümü — şehir adı + opsiyonel iniş/dönüş rozeti.
class _RouteNode extends StatelessWidget {
  const _RouteNode({required this.label, this.badge, this.muted = false});
  final String label;
  final String? badge;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: muted ? PT.textTertiary : PT.text)),
        if (badge != null) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: PT.bgElevated,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: PT.accent.withValues(alpha: 0.4)),
            ),
            child: Text(badge!,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: PT.accent)),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Genişletilmiş Japon şehir listesi + picker (havalimanı olmayanlar dahil).
// AirportPickerField sadece 7 havalimanını gösterir; kullanıcının rotaya
// koymak isteyebileceği Hakone, Nikko, Kamakura, Takayama gibi şehirler
// havalimansız — bu picker onları da listeler.
// ---------------------------------------------------------------------------

class _JpCity {
  const _JpCity({
    required this.name,
    required this.lat,
    required this.lng,
    this.iata,
    this.airportLabel,
  });
  final String name;
  final double lat;
  final double lng;
  /// Havalimanı IATA (varsa) — uçuş bacağı olarak kullanılır.
  final String? iata;
  /// Havalimanı görüntü etiketi (örn. "Haneda").
  final String? airportLabel;
}

const List<_JpCity> _kJpCities = [
  // Havalimanlı büyük şehirler
  _JpCity(name: 'Tokyo', lat: 35.6762, lng: 139.6503, iata: 'HND', airportLabel: 'Haneda'),
  _JpCity(name: 'Osaka', lat: 34.6937, lng: 135.5023, iata: 'KIX', airportLabel: 'Kansai'),
  _JpCity(name: 'Sapporo', lat: 43.0621, lng: 141.3544, iata: 'CTS'),
  _JpCity(name: 'Fukuoka', lat: 33.5904, lng: 130.4017, iata: 'FUK'),
  _JpCity(name: 'Naha (Okinawa)', lat: 26.2124, lng: 127.6809, iata: 'OKA'),
  _JpCity(name: 'Nagoya', lat: 35.1815, lng: 136.9066, iata: 'NGO', airportLabel: 'Chubu Centrair'),
  _JpCity(name: 'Sendai', lat: 38.2682, lng: 140.8694, iata: 'SDJ'),
  _JpCity(name: 'Hiroshima', lat: 34.3853, lng: 132.4553, iata: 'HIJ'),
  _JpCity(name: 'Kagoshima', lat: 31.5966, lng: 130.5571, iata: 'KOJ'),
  _JpCity(name: 'Kumamoto', lat: 32.8032, lng: 130.7079, iata: 'KMJ'),
  _JpCity(name: 'Matsuyama', lat: 33.8416, lng: 132.7657, iata: 'MYJ'),
  _JpCity(name: 'Komatsu (Kanazawa)', lat: 36.5615, lng: 136.6567, iata: 'KMQ'),
  _JpCity(name: 'Miyazaki', lat: 31.9077, lng: 131.4202, iata: 'KMI'),
  _JpCity(name: 'Nagasaki', lat: 32.7503, lng: 129.8779, iata: 'NGS'),
  _JpCity(name: 'Aomori', lat: 40.8244, lng: 140.7400, iata: 'AOJ'),
  _JpCity(name: 'Akita', lat: 39.7186, lng: 140.1024, iata: 'AXT'),

  // Shinkansen / tren erişimli (havalimansız) turistik şehirler
  _JpCity(name: 'Kyoto', lat: 35.0116, lng: 135.7681),
  _JpCity(name: 'Nara', lat: 34.6851, lng: 135.8048),
  _JpCity(name: 'Kanazawa', lat: 36.5613, lng: 136.6562),
  _JpCity(name: 'Nikko', lat: 36.7194, lng: 139.6982),
  _JpCity(name: 'Hakone', lat: 35.2325, lng: 139.1069),
  _JpCity(name: 'Kamakura', lat: 35.3193, lng: 139.5466),
  _JpCity(name: 'Yokohama', lat: 35.4437, lng: 139.6380),
  _JpCity(name: 'Kobe', lat: 34.6901, lng: 135.1955),
  _JpCity(name: 'Himeji', lat: 34.8394, lng: 134.6939),
  _JpCity(name: 'Takayama', lat: 36.1461, lng: 137.2521),
  _JpCity(name: 'Shirakawa-go', lat: 36.2586, lng: 136.9060),
  _JpCity(name: 'Kurashiki', lat: 34.5851, lng: 133.7714),
  _JpCity(name: 'Matsumoto', lat: 36.2381, lng: 137.9720),
  _JpCity(name: 'Nagano', lat: 36.6486, lng: 138.1948),
  _JpCity(name: 'Miyajima (Itsukushima)', lat: 34.2960, lng: 132.3197),
  _JpCity(name: 'Fuji Kawaguchiko', lat: 35.5104, lng: 138.7626),
  _JpCity(name: 'Ise', lat: 34.4901, lng: 136.7098),
  _JpCity(name: 'Beppu', lat: 33.2846, lng: 131.4913),
  _JpCity(name: 'Otaru', lat: 43.1907, lng: 140.9947),
  _JpCity(name: 'Hakodate', lat: 41.7688, lng: 140.7288),
  _JpCity(name: 'Uji', lat: 34.8845, lng: 135.7999),
  _JpCity(name: 'Koyasan', lat: 34.2131, lng: 135.5843),
  _JpCity(name: 'Kinosaki Onsen', lat: 35.6262, lng: 134.8078),
  _JpCity(name: 'Yakushima', lat: 30.3583, lng: 130.5468),
  _JpCity(name: 'Ishigaki', lat: 24.3448, lng: 124.1571, iata: 'ISG'),
];

/// "+ Başka şehir" tetikleyicisi — dokununca aramalı şehir sheet'i açar.
class _JpCityPickerField extends StatelessWidget {
  const _JpCityPickerField({required this.onSelect});
  final ValueChanged<_JpCity> onSelect;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return InkWell(
      onTap: () async {
        final picked = await showModalBottomSheet<_JpCity>(
          context: context,
          isScrollControlled: true,
          backgroundColor: PT.bgElevated,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => const _JpCitySearchSheet(),
        );
        if (picked != null) onSelect(picked);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: PT.bgSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PT.borderStrong),
        ),
        child: Row(
          children: [
            const Icon(Icons.add, size: 20, color: PT.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.s('journey.city.other'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: PT.text),
              ),
            ),
            const Icon(Icons.chevron_right, color: PT.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _JpCitySearchSheet extends StatefulWidget {
  const _JpCitySearchSheet();
  @override
  State<_JpCitySearchSheet> createState() => _JpCitySearchSheetState();
}

class _JpCitySearchSheetState extends State<_JpCitySearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final q = _q.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _kJpCities
        : _kJpCities
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                (c.iata ?? '').toLowerCase().contains(q))
            .toList();
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: PT.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(s.s('journey.city.sheetTitle'),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: PT.text)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.s('journey.city.close'),
                        style: const TextStyle(color: PT.accent)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: s.s('journey.city.searchHint'),
                  prefixIcon: const Icon(Icons.search, color: PT.textSecondary),
                  filled: true,
                  fillColor: PT.bgSubtle,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(
                    height: 1, color: PT.border, indent: 16, endIndent: 16),
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  return ListTile(
                    onTap: () => Navigator.pop(context, c),
                    title: Text(c.name,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: PT.text)),
                    subtitle: Text(
                      c.iata != null
                          ? '${c.airportLabel ?? s.s('journey.city.airport')} · ${c.iata}'
                          : s.s('journey.city.byTrain'),
                      style: const TextStyle(
                          fontSize: 12, color: PT.textSecondary),
                    ),
                    trailing: c.iata != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: PT.accentSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(c.iata!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: PT.accent)),
                          )
                        : const Icon(Icons.train,
                            size: 20, color: PT.textTertiary),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

