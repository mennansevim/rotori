import 'package:flutter/material.dart';

import '../../../domain/city_places.dart';
import '../../../domain/trip_factory.dart';
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

class _JourneyStepState extends State<JourneyStep> {
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

  String _addDays(String iso, int days) {
    final d = DateTime.parse('${iso}T00:00:00Z').add(Duration(days: days));
    return d.toIso8601String().substring(0, 10);
  }

  /// Tarih/gün senkronu — React commitDests'in hafif karşılığı.
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
    // Günleri tarih aralığından üret (boş iskelet — Plan adımı doldurur).
    t.days = generateDaysBetween(start, end);
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
      d.city = a.city;
      d.airport = a.iata;
      d.lat = a.lat;
      d.lng = a.lng;
    });
  }

  void _setReturnDate(String date) {
    widget.onChange((t) {
      final start = t.preferences.travelDates.start;
      final maxEnd = start.isNotEmpty ? _addDays(start, kMaxTripDays - 1) : date;
      t.preferences.travelDates.end = date.compareTo(maxEnd) > 0 ? maxEnd : date;
      _resync(t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dests = _dests;
    final lastDest = dests.isNotEmpty ? dests.last : null;
    final showReturn = (lastDest?.airport ?? '').isNotEmpty;
    final routePreview = _routePreview();

    final destCount = dests.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        const PageHeadline('🇯🇵 Japonya rotası'),
        PageSub(_hasTicket
            ? 'Türkiye\'den Japonya\'ya gidiş ve dönüş uçuşlarını gir. Her uçuş kartında havayolu, uçuş no, tarih ve havaalanları var.'
            : 'Türkiye\'den nereden kalkacaksın ve Japonya\'da hangi şehre ineceksin? Şimdilik şehir ve tarih yeter.'),

        if (widget.onLoadJapanPlan != null) _japanBanner(),

        // Gidiş bacağı (tek durak — çoklu durak Plan/rota editörü sonraki iterasyon)
        for (var i = 0; i < (dests.isEmpty ? 1 : dests.length); i++)
          _flightLeg(i, dests.isEmpty ? null : dests[i]),

        if (showReturn) _returnLeg(lastDest!),

        if (destCount >= 2) _shinkansenReminder(),
        _cityPicker(dests),

        if (routePreview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 14, color: PT.text),
                children: [
                  const TextSpan(
                      text: 'Rota: ',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: routePreview),
                ],
              ),
            ),
          ),

        const SizedBox(height: 12),
        if (dests.isNotEmpty) _passengerOptions(),

        if (!_canContinue())
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PT.accentSoft,
              borderRadius: BorderRadius.circular(PT.radius),
            ),
            child: const Text(
              'Devam için: kalkış (Türkiye) ve varış (Japonya) havaalanını seç.',
              style: TextStyle(fontSize: 14, color: PT.accent),
            ),
          ),
      ],
    );
  }

  bool _canContinue() =>
      _originAirport.isNotEmpty &&
      _dests.isNotEmpty &&
      _dests.every((d) => d.city.trim().isNotEmpty);

  String _routePreview() {
    final dests = _dests;
    if (dests.isEmpty || _origin.isEmpty) return '';
    final parts = <String>[
      '$_origin${_originAirport.isNotEmpty ? ' ($_originAirport)' : ''}',
      ...dests.map((d) => '${d.city}${(d.airport ?? '').isNotEmpty ? ' (${d.airport})' : ''}'),
    ];
    return parts.join(' → ');
  }

  // ---- parçalar ----

  Widget _shinkansenReminder() {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PT.accentSoft,
        borderRadius: BorderRadius.circular(PT.radius),
        border: Border.all(color: PT.accent.withValues(alpha: 0.4)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🚄 Şehirler arası Shinkansen',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: PT.accent)),
          SizedBox(height: 6),
          Text(
              'Birden fazla şehir gezeceksin → Shinkansen (yüksek hızlı tren) en pratiği.',
              style:
                  TextStyle(fontSize: 13, color: PT.text, height: 1.35)),
          SizedBox(height: 4),
          Text(
              'JR Pass / Smart-EX önerilir. Plan adımında otomatik şehir geçiş kartları çıkar.',
              style: TextStyle(fontSize: 12, color: PT.textSecondary, height: 1.35)),
        ],
      ),
    );
  }

  /// Japon şehirlerini chip listesi olarak sunar; kullanıcı seçtikçe
  /// destinasyonlara eklenir/çıkarılır. Shinkansen mantığı zaten
  /// destinations>=2 iken üstteki hatırlatma kartını gösterir.
  Widget _cityPicker(List<TripDestination> dests) {
    // Şu an rotadaki şehirleri normalize et — kolay karşılaştırma için.
    final selectedNames = {
      for (final d in dests) d.city.trim().toLowerCase(),
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
          const Text('🏙️ Gezilecek şehirler',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: PT.text)),
          const SizedBox(height: 2),
          const Text(
              'Listeden seç — rotana eklenir. Tekrar dokun → çıkar. '
              'İkinci şehri seçtiğinde şehirler arası Shinkansen önerilir.',
              style: TextStyle(
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
          // Listede olmayan şehirler için — Japon havalimanı picker'ı ile
          // custom destinasyon eklenir (Fukuoka, Okinawa, Hakone çevresi vb.).
          AirportPickerField(
            countryCodes: const ['JP'],
            valueLabel: '+ Başka şehir',
            placeholder: 'Diğer şehir/havalimanı ara',
            onSelect: (a) => _addCustomCity(a),
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
      .any((c) => c.label.toLowerCase() == city.trim().toLowerCase());

  /// Custom şehir: havalimanı seçicisinden gelen Airport ile destinasyon ekler.
  void _addCustomCity(Airport a) {
    if (a.iata.isEmpty) return;
    widget.onChange((t) {
      final list = [...t.preferences.destinations]
        ..sort((x, y) => x.order.compareTo(y.order));
      // Aynı şehir zaten varsa (havalimanı farklı olsa da) tekrar ekleme.
      if (list.any((d) =>
          d.city.trim().toLowerCase() == a.city.trim().toLowerCase())) {
        return;
      }
      list.add(TripDestination(
        id: 'dest-${DateTime.now().millisecondsSinceEpoch}-${list.length}',
        countryCode: a.countryCode,
        countryName: a.countryName,
        city: a.city,
        airport: a.iata,
        lat: a.lat,
        lng: a.lng,
        arrivalDate: t.preferences.travelDates.start,
        departureDate: t.preferences.travelDates.end,
        order: list.length,
      ));
      t.preferences.destinations = list;
      _resync(t);
    });
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
      _resync(t);
    });
  }

  /// Şehir chip'ine tıklanınca: rotada yoksa yeni destinasyon (ilk havalimanı
  /// varsa airport otomatik atanır), varsa listeden çıkarılır.
  void _toggleCity(CityData city) {
    widget.onChange((t) {
      final list = [...t.preferences.destinations]
        ..sort((a, b) => a.order.compareTo(b.order));
      final existingIdx =
          list.indexWhere((d) => d.city.trim().toLowerCase() == city.label.toLowerCase());
      if (existingIdx >= 0) {
        list.removeAt(existingIdx);
        for (var i = 0; i < list.length; i++) {
          list[i].order = i;
        }
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
          arrivalDate: t.preferences.travelDates.start,
          departureDate: t.preferences.travelDates.end,
          order: list.length,
        ));
      }
      t.preferences.destinations = list;
      _resync(t);
    });
  }

  Widget _japanBanner() {
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
                const Text('🇯🇵 Japonya 14 günlük tam plan',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: PT.text)),
                const SizedBox(height: 2),
                Text('Tokyo → Kyoto → Nara → Osaka rotası; günler, tarihler ve oteller hazır.',
                    style: const TextStyle(fontSize: 13, color: PT.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PButton(label: 'Planı yükle', onPressed: widget.onLoadJapanPlan),
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
    final airline = dest?.airline;
    final airlineSet = airline != null && airline.isNotEmpty;

    return _legShell(
      title: _hasTicket ? '✈︎ Gidiş — Türkiye → Japonya' : '📍 Rota — Türkiye → Japonya',
      children: [
        if (_hasTicket)
          _field(
            'Havayolu',
            AirlinePickerField(
              valueCode: airline,
              valueLabel: airlineSet ? airlineLabel(airline) : null,
              onSelect: (a) => _updateLeg(index, (d) => d.airline = a.code),
            ),
          ),
        if (_hasTicket && airlineSet)
          _field(
            'Uçuş numarası',
            _FlightNoInput(
              prefix: airline,
              value: dest?.flightNo ?? '',
              onChanged: (v) => _updateLeg(index, (d) => d.flightNo = v.replaceAll(RegExp(r'\s+'), '')),
            ),
          ),
        _field(
          'Tarih',
          _DateBox(
            value: dest?.arrivalDate ?? trip.preferences.travelDates.start,
            onPick: (v) => _updateLeg(index, (d) => d.arrivalDate = v),
          ),
        ),
        _field(
          'Kalkış (Türkiye)',
          index == 0
              ? AirportPickerField(
                  countryCodes: const ['TR'],
                  valueCode: _originAirport.isEmpty ? null : _originAirport,
                  valueLabel: _origin.isEmpty ? null : _origin,
                  placeholder: 'İstanbul (IST), Sabiha (SAW)...',
                  onSelect: _setOrigin,
                )
              : _FixedBox(text: _origin.isEmpty ? '—' : _origin),
        ),
        _field(
          'Varış (Japonya)',
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
      ],
    );
  }

  Widget _returnLeg(TripDestination lastDest) {
    final returnDepIata =
        trip.preferences.returnDepartAirport ?? (lastDest.airport ?? '');
    final returnDep = kAirports.where((a) => a.iata == returnDepIata).toList();
    final returnArrIata =
        trip.preferences.returnArrivalAirport ?? _originAirport;
    final returnArr = kAirports.where((a) => a.iata == returnArrIata).toList();
    return _legShell(
      isReturn: true,
      title: '🏠 Dönüş — Japonya → Türkiye',
      children: [
        _field(
          'Tarih',
          _DateBox(
            value: trip.preferences.travelDates.end,
            onPick: _setReturnDate,
          ),
        ),
        _field(
          'Kalkış (Japonya)',
          AirportPickerField(
            countryCodes: const ['JP'],
            valueCode: returnDep.isNotEmpty ? returnDep.first.iata : null,
            valueLabel: returnDep.isNotEmpty ? returnDep.first.city : null,
            placeholder: 'Japonya\'dan kalkış havalimanı',
            onSelect: (a) => widget.onChange((t) {
              t.preferences.returnDepartAirport = a.iata;
              _resync(t);
            }),
          ),
        ),
        _field(
          'Varış (Türkiye)',
          AirportPickerField(
            countryCodes: const ['TR'],
            valueCode: returnArr.isNotEmpty ? returnArr.first.iata : null,
            valueLabel: returnArr.isNotEmpty ? returnArr.first.city : null,
            placeholder: 'Türkiye\'ye varış havalimanı',
            onSelect: (a) => widget.onChange((t) {
              t.preferences.returnArrivalAirport = a.iata;
              _resync(t);
            }),
          ),
        ),
      ],
    );
  }

  Widget _passengerOptions() {
    final prefs = trip.preferences;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: PT.border),
        borderRadius: BorderRadius.circular(PT.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text('Yolcu & seçenekler',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: PT.text)),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text('Kaç kişi + kaç çocuk?',
              style: TextStyle(fontSize: 12, color: PT.textSecondary)),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: _DropdownField<int>(
                  label: 'Yetişkin',
                  value: prefs.partySize ?? 2,
                  items: const [1, 2, 3, 4, 5, 6],
                  onChanged: (v) => widget.onChange((t) => t.preferences.partySize = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DropdownField<int>(
                  label: 'Çocuk',
                  value: prefs.childrenCount ?? 0,
                  items: const [0, 1, 2, 3, 4],
                  onChanged: (v) => widget.onChange((t) => t.preferences.childrenCount = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DropdownField<Pace>(
                  label: 'Tempo',
                  value: prefs.pace,
                  items: const [Pace.relaxed, Pace.moderate, Pace.intense],
                  labelFor: (p) => switch (p) {
                    Pace.relaxed => 'Rahat',
                    Pace.moderate => 'Dengeli',
                    Pace.intense => 'Yoğun',
                  },
                  onChanged: (v) => widget.onChange((t) => t.preferences.pace = v),
                ),
              ),
            ],
          ),
        ],
      ),
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
              decoration: const InputDecoration(
                hintText: 'Uçuş numarası',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            Text(value.isEmpty ? 'Tarih seç' : value,
                style: TextStyle(
                    fontSize: 15, color: value.isEmpty ? PT.textTertiary : PT.text)),
          ],
        ),
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelFor,
  });
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelFor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: PT.text)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: PT.bgSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PT.borderStrong),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              items: [
                for (final it in items)
                  DropdownMenuItem(value: it, child: Text(labelFor?.call(it) ?? '$it')),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
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
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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

