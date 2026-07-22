import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
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

    // BUG 1: Yeni eklenen destinasyonlar hep `start` ile geliyor — hepsi aynı
    // güne çökmesin diye tarih aralığını eşit dağıt. Heuristik: tüm arrivalDate
    // değerleri `start`'a eşitse → kullanıcı elle düzenlememiş, güvenle dağıt.
    // Aksi halde kullanıcının elle koyduğu tarihleri koru.
    if (dests.length >= 2 && dests.every((d) => d.arrivalDate == start)) {
      distributeDates(dests, start, end);
    }

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
    final s = LanguageScope.of(context);
    final dests = _dests;
    final lastDest = dests.isNotEmpty ? dests.last : null;
    final showReturn = (lastDest?.airport ?? '').isNotEmpty;
    final routePreview = _routePreview();

    final destCount = dests.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        PageHeadline(s.s('journey.title')),
        PageSub(_hasTicket
            ? s.s('journey.sub.ticket')
            : s.s('journey.sub.plan')),

        if (widget.onLoadJapanPlan != null) _japanBanner(),

        // Gidiş uçuşu SADECE ilk destinasyona. Ara şehirler Shinkansen/tren
        // ile — her seçilen şehir için ayrı uçuş kartı çıkarmıyoruz.
        _flightLeg(0, dests.isEmpty ? null : dests.first),

        // Dönüş uçuşu son destinasyondan (varsa).
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
                  TextSpan(
                      text: s.s('journey.routeLabel'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
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
            child: Text(
              s.s('journey.continueHint'),
              style: const TextStyle(fontSize: 14, color: PT.accent),
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
          Text(s.s('journey.cities.title'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: PT.text)),
          const SizedBox(height: 2),
          Text(
              s.s('journey.cities.hint'),
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
      .any((c) => c.label.toLowerCase() == city.trim().toLowerCase());

  /// Custom şehir: JpCity listesinden seçilen şehir ile destinasyon ekler.
  /// Havalimanı olan şehirlerde IATA otomatik atanır (uçuş bacağı için); yoksa
  /// airport boş — Shinkansen/tren ile gidilecek şehir olarak eklenir.
  void _addCustomCityFromJp(_JpCity c) {
    widget.onChange((t) {
      final list = [...t.preferences.destinations]
        ..sort((x, y) => x.order.compareTo(y.order));
      // Aynı şehir zaten varsa tekrar ekleme.
      if (list.any((d) =>
          d.city.trim().toLowerCase() == c.name.trim().toLowerCase())) {
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
      ],
    );
  }

  Widget _returnLeg(TripDestination lastDest) {
    final s = LanguageScope.of(context);
    final returnDepIata =
        trip.preferences.returnDepartAirport ?? (lastDest.airport ?? '');
    final returnDep = kAirports.where((a) => a.iata == returnDepIata).toList();
    final returnArrIata =
        trip.preferences.returnArrivalAirport ?? _originAirport;
    final returnArr = kAirports.where((a) => a.iata == returnArrIata).toList();
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
            placeholder: s.s('journey.ph.returnDep'),
            onSelect: (a) => widget.onChange((t) {
              t.preferences.returnDepartAirport = a.iata;
              _resync(t);
            }),
          ),
        ),
        _field(
          s.s('journey.field.arrivalTr'),
          AirportPickerField(
            // Dönüş varış = kalkış ülken (herhangi bir yer) — kısıt yok.
            valueCode: returnArr.isNotEmpty ? returnArr.first.iata : null,
            valueLabel: returnArr.isNotEmpty ? returnArr.first.city : null,
            placeholder: s.s('journey.ph.returnArr'),
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
    final s = LanguageScope.of(context);
    final prefs = trip.preferences;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: PT.border),
        borderRadius: BorderRadius.circular(PT.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(s.s('journey.pax.title'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: PT.text)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(s.s('journey.pax.subtitle'),
              style: const TextStyle(fontSize: 12, color: PT.textSecondary)),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: _DropdownField<int>(
                  label: s.s('journey.pax.adult'),
                  value: prefs.partySize ?? 2,
                  items: const [1, 2, 3, 4, 5, 6],
                  onChanged: (v) => widget.onChange((t) => t.preferences.partySize = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DropdownField<int>(
                  label: s.s('journey.pax.child'),
                  value: prefs.childrenCount ?? 0,
                  items: const [0, 1, 2, 3, 4],
                  onChanged: (v) => widget.onChange((t) => t.preferences.childrenCount = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DropdownField<Pace>(
                  label: s.s('journey.pax.pace'),
                  value: prefs.pace,
                  items: const [Pace.relaxed, Pace.moderate, Pace.intense],
                  labelFor: (p) => switch (p) {
                    Pace.relaxed => s.s('journey.pace.relaxed'),
                    Pace.moderate => s.s('journey.pace.moderate'),
                    Pace.intense => s.s('journey.pace.intense'),
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

