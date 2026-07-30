import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/types.dart';
import '../planner_theme.dart';

/// Welcome adımı — esnek gezi (Google Flights tarzı). "Biletim var" akışı
/// kaldırıldı; kullanıcı doğrudan hedef şehir kartları + tarih önerileri
/// ekranına girer.
class WelcomeStep extends StatefulWidget {
  const WelcomeStep({
    super.key,
    required this.trip,
    required this.onChange,
    required this.onContinue,
  });

  final Trip trip;
  final void Function(void Function(Trip)) onChange;
  final VoidCallback onContinue;

  @override
  State<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<WelcomeStep> {
  /// Adıma ilk giriş: hemen native date-range picker açılır. Böylece
  /// kullanıcı `Başla` sekmesinden hızla tarih girip Rota'ya geçer. Bir kez
  /// tetiklenir; kullanıcı geri gelirse veya iptal ederse tekrar açılmaz —
  /// büyük "Tarih aralığı seç" butonu kullanılır.
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // "Biletim var" akışı yok — hasTicket her zaman false.
      if (widget.trip.preferences.hasTicket != false) {
        widget.onChange((t) => t.preferences.hasTicket = false);
      }
      if (!_autoOpened) {
        _autoOpened = true;
        final dates = widget.trip.preferences.travelDates;
        if (dates.start.isEmpty || dates.end.isEmpty) {
          _pickCustomRange();
        }
      }
    });
  }

  void _applyDates(String start, String end) {
    widget.onChange((t) {
      t.tripStart = '${start}T08:00:00';
      t.tripEnd = '${end}T20:00:00';
      t.preferences.travelDates
        ..start = start
        ..end = end;
      for (final d in t.preferences.destinations) {
        d.arrivalDate = start;
        d.departureDate = end;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final trip = widget.trip;
    final origin = _resolveOrigin(trip);
    final travelDates = trip.preferences.travelDates;
    final hasDates =
        travelDates.start.isNotEmpty && travelDates.end.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        Text(s.s('welcome.plan.title'),
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: PT.text)),
        const SizedBox(height: 4),
        Text(
          s.s('welcome.plan.sub'),
          style: const TextStyle(fontSize: 14, color: PT.textSecondary),
        ),
        const SizedBox(height: 16),
        _OriginPill(
          city: origin,
          onEdit: () => _editOrigin(origin),
        ),
        const SizedBox(height: 20),
        if (hasDates) ...[
          _DateSummaryCard(
            startIso: travelDates.start,
            endIso: travelDates.end,
            lang: s.lang,
            onEdit: _pickCustomRange,
          ),
          const SizedBox(height: 14),
          PButton(
            label: s.s('welcome.continue'),
            block: true,
            primary: true,
            onPressed: widget.onContinue,
          ),
        ] else ...[
          PButton(
            label: s.s('welcome.plan.customRange'),
            block: true,
            primary: true,
            onPressed: _pickCustomRange,
          ),
        ],
      ],
    );
  }

  /// Native date-range picker; kullanıcı gidiş-dönüş seçer, tarihler
  /// otomatik doldurulur ve Rota adımına geçilir.
  Future<void> _pickCustomRange() async {
    final s = LanguageScope.of(context);
    final now = DateTime.now();
    final trip = widget.trip;
    final existingStart = DateTime.tryParse(trip.preferences.travelDates.start);
    final existingEnd = DateTime.tryParse(trip.preferences.travelDates.end);
    final initialStart = existingStart ?? DateTime(now.year, now.month + 2, 1);
    final initialEnd = existingEnd ?? initialStart.add(const Duration(days: 9));

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      helpText: s.s('welcome.range.help'),
      cancelText: s.s('welcome.range.cancel'),
      confirmText: s.s('welcome.range.confirm'),
      saveText: s.s('welcome.save'),
      currentDate: now,
    );
    if (picked == null) return;
    _applyDates(_isoDate(picked.start), _isoDate(picked.end));
    if (!mounted) return;
    widget.onContinue();
  }

  String _resolveOrigin(Trip trip) {
    final c = (trip.preferences.originCity ?? '').trim();
    return c.isEmpty ? 'İstanbul' : c;
  }

  Future<void> _editOrigin(String current) async {
    final s = LanguageScope.of(context);
    final controller = TextEditingController(text: current);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PT.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final insets = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + insets),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.s('welcome.origin.title'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: PT.text)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
                decoration: InputDecoration(
                  hintText: s.s('welcome.origin.hint'),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: PT.borderStrong),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: PT.accent),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: PButton(
                  label: s.s('welcome.save'),
                  onPressed: () =>
                      Navigator.of(ctx).pop(controller.text.trim()),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    final v = result.trim();
    widget.onChange((t) {
      t.preferences.originCity = v.isEmpty ? null : v;
    });
    if (mounted) setState(() {});
  }

  /// Bir tarih aralığını gidiş-dönüş olarak uygula ve Rota adımına geç.
  /// Harici link AÇMAZ — uçuşları planner'ın Rota adımı listeler.
}

// ===========================================================================
// Esnek gezi verileri + biçimleyiciler
// ===========================================================================

/// Google Flights derin bağlantısı. Uçuş özelliği yeniden devreye girdiğinde
/// kullanılacak — şu an test ile korunuyor.
String googleFlightsUrl({
  required String from,
  required String toIata,
  required DateTime start,
  required DateTime end,
}) {
  final startIso = _isoDate(start);
  final endIso = _isoDate(end);
  final q = 'Flights from $from to $toIata on $startIso through $endIso';
  return 'https://www.google.com/travel/flights?q=${Uri.encodeComponent(q)}';
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "23 Ağu Paz" biçimi — Google Flights satırındaki tarih etiketi.
String formatTrShortDate(DateTime d) =>
    '${d.day} ${_trShortMonths[d.month]} ${_trShortWeekdays[d.weekday]}';

const _trShortMonths = [
  '',
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];

const _trShortWeekdays = [
  '',
  'Pzt',
  'Sal',
  'Çar',
  'Per',
  'Cum',
  'Cmt',
  'Paz',
];

// ===========================================================================
// Alt bileşenler
// ===========================================================================

/// Seçilen kalkış/dönüş tarihi özet kartı. Sağda "Değiştir" TextButton'u
/// picker'ı yeniden açar. Görsel: iki sütun, üstte küçük etiket (Kalkış / Dönüş)
/// altta büyük tarih. Böylece kullanıcı seçtiği aralığı bir bakışta görür.
class _DateSummaryCard extends StatelessWidget {
  const _DateSummaryCard({
    required this.startIso,
    required this.endIso,
    required this.lang,
    required this.onEdit,
  });

  final String startIso;
  final String endIso;
  final AppLang lang;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final start = DateTime.tryParse(startIso);
    final end = DateTime.tryParse(endIso);
    if (start == null || end == null) return const SizedBox.shrink();
    final nights = end.difference(start).inDays;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: PT.bgElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PT.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _DatePart(
                  labelKey: 'welcome.originPill',
                  fallback: 'Kalkış',
                  date: start,
                  lang: lang,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 16, color: PT.textTertiary),
              ),
              Expanded(
                child: _DatePart(
                  labelKey: 'welcome.plan.dateSummary.title',
                  fallback: 'Dönüş',
                  date: end,
                  lang: lang,
                  isReturn: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                nights <= 0
                    ? ''
                    : (lang == AppLang.en
                        ? '$nights night${nights == 1 ? '' : 's'}'
                        : '$nights gece'),
                style: const TextStyle(
                    fontSize: 12,
                    color: PT.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: PT.accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: onEdit,
                child: Text(
                  s.s('welcome.plan.dateSummary.edit'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DatePart extends StatelessWidget {
  const _DatePart({
    required this.labelKey,
    required this.fallback,
    required this.date,
    required this.lang,
    this.isReturn = false,
  });

  final String labelKey;
  final String fallback;
  final DateTime date;
  final AppLang lang;
  final bool isReturn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isReturn
              ? (lang == AppLang.en ? 'Return' : 'Dönüş')
              : (lang == AppLang.en ? 'Departure' : 'Kalkış'),
          style: const TextStyle(
              fontSize: 11,
              color: PT.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4),
        ),
        const SizedBox(height: 2),
        Text(
          formatTrShortDate(date),
          style: const TextStyle(
              fontSize: 15,
              color: PT.text,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

/// "Kalkış: {city} ✎" — küçük kalem ikonu ile origin değiştirme pili.
class _OriginPill extends StatelessWidget {
  const _OriginPill({required this.city, required this.onEdit});
  final String city;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: PT.bgElevated,
        borderRadius: BorderRadius.circular(PT.radiusPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(PT.radiusPill),
          onTap: onEdit,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PT.radiusPill),
              border: Border.all(color: PT.borderStrong),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.p('welcome.originPill', {'city': city}),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: PT.text)),
                const SizedBox(width: 6),
                const Text('✎',
                    style: TextStyle(fontSize: 12, color: PT.accent)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

