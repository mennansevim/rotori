// Uçuş bilgileri — plan oluşturulduktan SONRA, opsiyonel.
//
// Eskiden bu form Rota (journey) wizard adımının içindeydi ve Devam'ı
// bloklayan bir geçit gibi davranıyordu. Artık plan uçuşsuz da üretiliyor
// (varış 13:00 varsayılan); kullanıcı isterse buradan gerçek saatleri girer ve
// varış/dönüş günü akışı ona göre yeniden kurulur.
//
// Alanlar journey_step._flightLeg / _returnLeg portudur; PT teması korunmuştur
// (pickers.dart modalleri de PT'ye bağlı — tek tema, sıçrama yok).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n.dart';
import '../../../data/language_store.dart';
import '../../../data/plans_repository.dart';
import '../../../domain/plan_generation.dart';
import '../../../domain/types.dart';
import '../../planner/data/airlines.dart';
import '../../planner/data/airports.dart';
import '../../planner/planner_theme.dart';
import '../../planner/widgets/pickers.dart';
import '../plan_providers.dart';

class FlightDetailsPage extends ConsumerStatefulWidget {
  const FlightDetailsPage({super.key, required this.planId});
  final String planId;

  @override
  ConsumerState<FlightDetailsPage> createState() => _FlightDetailsPageState();
}

class _FlightDetailsPageState extends ConsumerState<FlightDetailsPage> {
  Trip? _trip;
  Timer? _saveDebounce;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  void _edit(void Function(Trip) mutate) {
    final trip = _trip;
    if (trip == null) return;
    setState(() => mutate(trip));
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      ref.read(plansRepositoryProvider)?.save(trip);
      ref.read(draftTripProvider.notifier).state = trip;
    });
  }

  /// Gidiş bacağı = ilk destinasyon (uçağın indiği şehir).
  TripDestination? get _arrival {
    final d = [..._trip?.preferences.destinations ?? <TripDestination>[]]
      ..sort((a, b) => a.order.compareTo(b.order));
    return d.isEmpty ? null : d.first;
  }

  String get _originCity => _trip?.preferences.originCity ?? '';
  String get _originAirport => _trip?.preferences.originAirport ?? '';

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(planByIdProvider(widget.planId));
    planAsync.whenData((t) => _trip ??= t);
    final s = LanguageScope.of(context);
    final trip = _trip;

    return Theme(
      data: PT.theme(),
      child: Scaffold(
        backgroundColor: PT.bg,
        appBar: AppBar(
          backgroundColor: PT.bgSubtle,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            s.s('flights.title'),
            style: const TextStyle(
              color: PT.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          iconTheme: const IconThemeData(color: PT.text),
        ),
        body: trip == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  Text(
                    s.s('flights.intro'),
                    style: const TextStyle(
                      fontSize: 14,
                      color: PT.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _outboundLeg(s),
                  _returnLeg(s),
                ],
              ),
      ),
    );
  }

  // --- gidiş ----------------------------------------------------------------

  Widget _outboundLeg(LanguageScope s) {
    final dest = _arrival;
    final airline = dest?.airline;
    final airlineSet = airline != null && airline.isNotEmpty;

    return _LegShell(
      title: s.s('journey.leg.outbound'),
      children: [
        _Field(
          label: s.s('journey.field.airline'),
          child: AirlinePickerField(
            valueCode: airline,
            valueLabel: airlineSet ? airlineLabel(airline) : null,
            onSelect: (a) => _edit((t) {
              final d = _arrival;
              if (d != null) d.airline = a.code;
            }),
          ),
        ),
        if (airlineSet)
          _Field(
            label: s.s('journey.field.flightNo'),
            child: _FlightNoInput(
              prefix: airline,
              value: dest?.flightNo ?? '',
              onChanged: (v) => _edit((t) {
                final d = _arrival;
                if (d != null) d.flightNo = v.replaceAll(RegExp(r'\s+'), '');
              }),
            ),
          ),
        _Field(
          label: s.s('journey.field.departureTr'),
          child: AirportPickerField(
            valueCode: _originAirport.isEmpty ? null : _originAirport,
            valueLabel: _originCity.isEmpty ? null : _originCity,
            placeholder: 'IST · LHR · JFK · SIN · DXB…',
            onSelect: (a) => _edit((t) => t.preferences
              ..originCity = a.city
              ..originAirport = a.iata
              ..originLat = a.lat
              ..originLng = a.lng),
          ),
        ),
        _Field(
          label: s.s('journey.field.arrivalJp'),
          child: AirportPickerField(
            countryCodes: const ['JP'],
            valueCode: (dest?.airport ?? '').isEmpty ? null : dest!.airport,
            valueLabel: (dest?.city.isNotEmpty ?? false) ? dest!.city : null,
            placeholder: 'Tokyo Haneda (HND), Narita (NRT), Osaka (KIX)',
            onSelect: (Airport a) => _edit((t) {
              final d = _arrival;
              if (d == null) return;
              d
                ..airport = a.iata
                ..lat = a.lat
                ..lng = a.lng;
            }),
          ),
        ),
        _Field(
          label: s.s('journey.field.arrivalTime'),
          child: _TimeBox(
            value: _trip?.preferences.outboundArrivalTime ?? '',
            onPick: (v) =>
                _edit((t) => t.preferences.outboundArrivalTime = v),
          ),
        ),
      ],
    );
  }

  // --- dönüş ----------------------------------------------------------------

  Widget _returnLeg(LanguageScope s) {
    final prefs = _trip!.preferences;
    final defaultDep = _arrival?.airport ?? '';
    final depIata = (prefs.returnDepartAirport ?? '').isNotEmpty
        ? prefs.returnDepartAirport!
        : defaultDep;
    final dep = kAirports.where((a) => a.iata == depIata).toList();
    final arrIata = (prefs.returnArrivalAirport ?? '').isNotEmpty
        ? prefs.returnArrivalAirport!
        : _originAirport;
    final arr = kAirports.where((a) => a.iata == arrIata).toList();

    return _LegShell(
      title: s.s('journey.leg.return'),
      isReturn: true,
      children: [
        _Field(
          label: s.s('journey.field.departureJp'),
          child: AirportPickerField(
            countryCodes: const ['JP'],
            valueCode: dep.isEmpty ? null : dep.first.iata,
            valueLabel: dep.isEmpty ? null : dep.first.city,
            placeholder: 'Tokyo (HND) · Osaka (KIX) · Fukuoka (FUK)…',
            onSelect: (a) =>
                _edit((t) => t.preferences.returnDepartAirport = a.iata),
          ),
        ),
        _Field(
          label: s.s('journey.field.departureTime'),
          child: _TimeBox(
            value: prefs.returnDepartTime ?? '',
            onPick: (v) => _edit((t) => t.preferences.returnDepartTime = v),
          ),
        ),
        _Field(
          label: s.s('journey.field.arrivalTr'),
          child: AirportPickerField(
            valueCode: arr.isEmpty ? null : arr.first.iata,
            valueLabel: arr.isEmpty ? null : arr.first.city,
            placeholder: 'IST · LHR · JFK · DXB…',
            onSelect: (a) =>
                _edit((t) => t.preferences.returnArrivalAirport = a.iata),
          ),
        ),
        const SizedBox(height: 4),
        _RegenerateHint(
          onRegenerate: () {
            final lang = ref.read(appLangProvider);
            _edit((t) => fillTripDays(t, lang: lang));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.s('flights.regenerated'))),
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Alan parçaları — journey_step portu (kullanıcının ortalanmış kutu stiliyle).
// ---------------------------------------------------------------------------

class _LegShell extends StatelessWidget {
  const _LegShell({
    required this.title,
    required this.children,
    this.isReturn = false,
  });
  final String title;
  final List<Widget> children;
  final bool isReturn;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isReturn ? PT.bgSubtle : PT.bgElevated,
        borderRadius: BorderRadius.circular(PT.radiusLg),
        border: Border.all(color: PT.border),
        boxShadow: PT.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: PT.text,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PT.text,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

class _FlightNoInput extends StatelessWidget {
  const _FlightNoInput({
    required this.prefix,
    required this.value,
    required this.onChanged,
  });
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
            child: Text(
              prefix ?? '',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: PT.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: TextFormField(
              initialValue: value,
              keyboardType: TextInputType.number,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: s.s('journey.field.flightNo'),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Saat seçici (HH:MM) — ortalanmış, tabular rakamlı.
class _TimeBox extends StatelessWidget {
  const _TimeBox({required this.value, required this.onPick});
  final String value;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    TimeOfDay initial = const TimeOfDay(hour: 10, minute: 0);
    if (value.contains(':')) {
      final parts = value.split(':');
      initial = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 10,
        minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked =
            await showTimePicker(context: context, initialTime: initial);
        if (picked == null) return;
        onPick('${picked.hour.toString().padLeft(2, '0')}:'
            '${picked.minute.toString().padLeft(2, '0')}');
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: PT.bgSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PT.borderStrong),
        ),
        child: Text(
          value.isEmpty ? s.s('journey.time.pick') : value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: value.isEmpty ? PT.textTertiary : PT.text,
          ),
        ),
      ),
    );
  }
}

/// "Saatleri girdim, planı bunlara göre yenile" aksiyonu.
class _RegenerateHint extends StatelessWidget {
  const _RegenerateHint({required this.onRegenerate});
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PT.accentSoft,
        borderRadius: BorderRadius.circular(PT.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.s('flights.regenHint'),
            style: const TextStyle(
              fontSize: 13,
              color: PT.text,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: PButton(
              label: s.s('flights.regenAction'),
              onPressed: onRegenerate,
            ),
          ),
        ],
      ),
    );
  }
}
