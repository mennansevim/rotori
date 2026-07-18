import 'package:flutter/material.dart';

import '../../../domain/types.dart';
import '../planner_theme.dart';

/// apps/planner/src/components/steps/WelcomeStep.tsx birebir port.
/// Üç görünüm: choose (hero + 2 kart), ticket (bilet formu), plan (mevsim seçimi).
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

enum _View { choose, ticket, plan }

class _WelcomeStepState extends State<WelcomeStep> {
  _View _view = _View.choose;

  // Ticket draft
  String _outboundDate = '';
  String _returnDate = '';
  String _airline = '';
  String _outFlightNo = '';
  String _retFlightNo = '';

  bool get _ticketReady => _outboundDate.trim().isNotEmpty;

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

  String _addDays(String iso, int days) {
    final d = DateTime.parse('${iso}T00:00:00Z').add(Duration(days: days));
    return d.toIso8601String().substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_view) {
      _View.choose => _buildChoose(),
      _View.ticket => _buildTicket(),
      _View.plan => _buildPlan(),
    };
  }

  // ---- choose ----------------------------------------------------------
  // Kaydırma YOK — hero + iki seçenek ekrana sığar (dar: alt alta, geniş: yan
  // yana). Kartlar kalan yüksekliği paylaşır (Expanded) → her cihazda tam sığar.
  Widget _buildChoose() {
    return LayoutBuilder(
      builder: (context, c) {
        final twoCol = c.maxWidth >= 560;
        final card0 = _WelcomeCard(
          icon: '✈️',
          title: 'Biletim var',
          desc: 'Uçuş bilgilerini gir ya da bilet fotoğrafını yükle',
          onTap: () {
            widget.onChange((t) => t.preferences.hasTicket = true);
            setState(() => _view = _View.ticket);
          },
        );
        final card1 = _WelcomeCard(
          icon: '📅',
          title: 'Gezi planla',
          desc: 'Sana en uygun tarihleri birlikte seçelim',
          onTap: () {
            widget.onChange((t) => t.preferences.hasTicket = false);
            setState(() => _view = _View.plan);
          },
        );
        final Widget choices = twoCol
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: card0),
                  const SizedBox(width: 16),
                  Expanded(child: card1),
                ],
              )
            : Column(
                // stretch: iki kart da tam genişlik — içerik uzunluğundan
                // bağımsız eşit. (Column varsayılanı center → içeriğe göre
                // boyutlanır ve genişlikler farklı çıkardı.)
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: card0),
                  const SizedBox(height: 14),
                  Expanded(child: card1),
                ],
              );
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              const Text('🇯🇵', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 10),
              const Text(
                "Japonya'yı planlayalım",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: PT.text,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Nereden başlayalım?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: PT.textSecondary),
              ),
              const SizedBox(height: 18),
              // Kartlar kalan alanı doldurur (maks ~380px, dikey ortalı).
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: choices,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- ticket ----------------------------------------------------------
  Widget _buildTicket() {
    final tooLong = _outboundDate.isNotEmpty &&
        _returnDate.isNotEmpty &&
        _daysBetween(_outboundDate, _returnDate) > kMaxTripDays;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        _BackButton(onTap: () => setState(() => _view = _View.choose)),
        const Text('Bilet bilgilerin',
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w700, color: PT.text)),
        const SizedBox(height: 4),
        Text(
          'Sadece tarihler zorunlu — diğer alanları boş bırakabilirsin. '
          'En fazla $kMaxTripDays günlük plan oluşturuyoruz.',
          style: const TextStyle(fontSize: 15, color: PT.textSecondary),
        ),
        const SizedBox(height: 24),
        PCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Gidiş tarihi',
                      value: _outboundDate,
                      onPick: (v) => setState(() => _outboundDate = v),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DateField(
                      label: 'Dönüş tarihi',
                      value: _returnDate,
                      minDate: _outboundDate.isEmpty ? null : _outboundDate,
                      maxDate: _outboundDate.isEmpty
                          ? null
                          : _addDays(_outboundDate, kMaxTripDays - 1),
                      onPick: (v) => setState(() => _returnDate = v),
                    ),
                  ),
                ],
              ),
              if (tooLong)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'En fazla $kMaxTripDays günlük plan oluşturuyoruz — '
                    '${_daysBetween(_outboundDate, _returnDate)} gün seçildi, otomatik kısaltılacak.',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFB45309), height: 1.4),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _TextField(
                      label: 'Havayolu',
                      hint: 'THY, JAL…',
                      onChanged: (v) => _airline = v,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _TextField(
                      label: 'Uçuş no (gidiş)',
                      hint: 'TK198',
                      onChanged: (v) => _outFlightNo = v,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _TextField(
                      label: 'Uçuş no (dönüş)',
                      hint: 'TK199',
                      onChanged: (v) => _retFlightNo = v,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(child: SizedBox()),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: PT.border),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: PButton(
                  label: '📷 Bilet fotoğrafı yükle',
                  primary: false,
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Bilet OCR (AI) sonraki iterasyonda bağlanacak.'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: PButton(
            label: 'Devam',
            onPressed: _ticketReady
                ? () {
                    final start = _outboundDate;
                    var end = _returnDate.isEmpty ? _outboundDate : _returnDate;
                    final maxEnd = _addDays(start, kMaxTripDays - 1);
                    if (end.compareTo(maxEnd) > 0) end = maxEnd;
                    _applyDates(start, end);
                    if (_airline.isNotEmpty || _outFlightNo.isNotEmpty) {
                      widget.onChange((t) {
                        t.preferences.returnFlightNo =
                            _retFlightNo.isEmpty ? null : _retFlightNo;
                      });
                    }
                    widget.onContinue();
                  }
                : null,
          ),
        ),
      ],
    );
  }

  // ---- plan (esnek gezi) ----------------------------------------------
  // Google Flights "esnek gezi" tarzı: Kalkış pili + hedef şehir kartları.
  // Her kartta hero görsel + 3 önerilen tarih aralığı; tıklayınca
  // Google Flights deep-link açılır (GERÇEK fiyata orada bakılır).
  Widget _buildPlan() {
    final trip = widget.trip;
    final origin = _resolveOrigin(trip);
    final year = _resolveYear(trip);
    final dests = _japanDestinations();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        _BackButton(onTap: () => setState(() => _view = _View.choose)),
        const Text("Japonya'da esnek gezi",
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: PT.text)),
        const SizedBox(height: 4),
        const Text(
          'Bir tarih aralığı seç — otomatik gidiş-dönüş olarak Rota adımına geçelim.',
          style: TextStyle(fontSize: 14, color: PT.textSecondary),
        ),
        const SizedBox(height: 12),
        _OriginPill(
          city: origin,
          onEdit: () => _editOrigin(origin),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < dests.length; i++) ...[
          _DestCard(
            dest: dests[i],
            year: year,
            fromCity: origin,
            onRangeTap: (r) => _onPickRange(dest: dests[i], range: r, year: year, from: origin),
          ),
          if (i < dests.length - 1) const SizedBox(height: 14),
        ],
        const SizedBox(height: 22),
        // Öneriler dışında kendi tarih aralığını seçmek isteyene çıkış:
        // native date-range picker → gidiş-dönüş olarak doldur + Rota'ya geç.
        PButton(
          label: '📅 Kendim seçmek istiyorum',
          block: true,
          primary: false,
          onPressed: _pickCustomRange,
        ),
      ],
    );
  }

  /// Native date-range picker; kullanıcı gidiş-dönüş seçer, tarihler
  /// otomatik doldurulur ve Rota adımına geçilir.
  Future<void> _pickCustomRange() async {
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
      helpText: 'Gidiş — Dönüş tarihlerini seç',
      cancelText: 'Vazgeç',
      confirmText: 'Uygula',
      saveText: 'Kaydet',
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

  int _resolveYear(Trip trip) {
    final ts = trip.tripStart;
    if (ts.length >= 4) {
      final y = int.tryParse(ts.substring(0, 4));
      if (y != null && y >= 2000) return y;
    }
    final now = DateTime.now();
    return now.year + 1;
  }

  Future<void> _editOrigin(String current) async {
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
              const Text('Kalkış şehri',
                  style: TextStyle(
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
                  hintText: 'İstanbul, İzmir, Ankara…',
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
                  label: 'Kaydet',
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
  void _onPickRange({
    required _JpDest dest,
    required _JpRange range,
    required int year,
    required String from,
  }) {
    final (start, end) = range.dates(year);
    _applyDates(_isoDate(start), _isoDate(end));
    widget.onContinue();
  }

  int _daysBetween(String a, String b) {
    final ms = DateTime.parse('${b}T00:00:00Z')
            .difference(DateTime.parse('${a}T00:00:00Z'))
            .inDays +
        1;
    return ms;
  }
}

// ===========================================================================
// Esnek gezi verileri + biçimleyiciler
// ===========================================================================

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "23 Ağu Paz" biçimi — Google Flights satırındaki tarih etiketi.
String formatTrShortDate(DateTime d) =>
    '${d.day} ${_trShortMonths[d.month]} ${_trShortWeekdays[d.weekday]}';

/// Google Flights derin bağlantısı. GERÇEK fiyata orada bakılır — sahte
/// fiyat üretmiyoruz.
String googleFlightsUrl({
  required String from,
  required String toIata,
  required DateTime start,
  required DateTime end,
}) {
  final startIso = _isoDate(start);
  final endIso = _isoDate(end);
  final q =
      'Flights from $from to $toIata on $startIso through $endIso';
  return 'https://www.google.com/travel/flights?q=${Uri.encodeComponent(q)}';
}

class _JpDest {
  final String city;
  final String country;
  final String emoji;
  final String tag;
  final String imageUrl;
  final String iataHint;
  final List<_JpRange> ranges;
  const _JpDest({
    required this.city,
    required this.country,
    required this.emoji,
    required this.tag,
    required this.imageUrl,
    required this.iataHint,
    required this.ranges,
  });
}

class _JpRange {
  final int monthStart;
  final int startDay;
  final int lengthDays;
  final String label;
  const _JpRange({
    required this.monthStart,
    required this.startDay,
    required this.lengthDays,
    required this.label,
  });

  (DateTime, DateTime) dates(int year) {
    final start = DateTime(year, monthStart, startDay);
    final end = start.add(Duration(days: lengthDays - 1));
    return (start, end);
  }

  String durationLabel() {
    if (lengthDays % 7 == 0) {
      final wk = lengthDays ~/ 7;
      return '~$wk hafta';
    }
    return '~$lengthDays gün';
  }
}

List<_JpDest> _japanDestinations() => const [
      _JpDest(
        city: 'Tokyo',
        country: 'Japonya',
        emoji: '🗼',
        tag: 'Meiji, İmparatorluk Sarayı ve müzeler',
        imageUrl:
            'https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800&q=60',
        iataHint: 'NRT',
        ranges: [
          _JpRange(
              monthStart: 3,
              startDay: 26,
              lengthDays: 10,
              label: '🌸 Sakura zirvesi'),
          _JpRange(
              monthStart: 4,
              startDay: 20,
              lengthDays: 7,
              label: '🌸 Geç sakura, ılıman'),
          _JpRange(
              monthStart: 11,
              startDay: 8,
              lengthDays: 10,
              label: '🍁 Sonbahar renkleri'),
        ],
      ),
      _JpDest(
        city: 'Osaka',
        country: 'Japonya',
        emoji: '🏯',
        tag: "Osaka Kalesi'nin bulunduğu liman şehri",
        imageUrl:
            'https://images.unsplash.com/photo-1590559899731-a382839e5549?w=800&q=60',
        iataHint: 'KIX',
        ranges: [
          _JpRange(
              monthStart: 3,
              startDay: 28,
              lengthDays: 8,
              label: '🌸 Sakura + Kansai'),
          _JpRange(
              monthStart: 5,
              startDay: 3,
              lengthDays: 7,
              label: 'Ilıman, kalabalık az'),
          _JpRange(
              monthStart: 11,
              startDay: 12,
              lengthDays: 10,
              label: '🍁 Sonbahar + gastronomi'),
        ],
      ),
    ];

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

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
  });
  final String icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PT.bgElevated,
      borderRadius: BorderRadius.circular(PT.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(PT.radiusLg),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PT.radiusLg),
            border: Border.all(color: PT.border),
            boxShadow: PT.shadowSm,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 38)),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: PT.text)),
              const SizedBox(height: 6),
              Text(desc,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, color: PT.textSecondary, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8),
            foregroundColor: PT.accent,
          ),
          child: const Text('← Geri', style: TextStyle(fontSize: 14)),
        ),
      );
}

/// "Kalkış: {city} ✎" — küçük kalem ikonu ile origin değiştirme pili.
class _OriginPill extends StatelessWidget {
  const _OriginPill({required this.city, required this.onEdit});
  final String city;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
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
                Text('Kalkış: $city',
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

/// Google Flights "esnek gezi" tarzı hedef kartı: üstte hero görsel +
/// altında 2-3 önerilen tarih aralığı satırı + Google Flights CTA.
class _DestCard extends StatelessWidget {
  const _DestCard({
    required this.dest,
    required this.year,
    required this.fromCity,
    required this.onRangeTap,
  });
  final _JpDest dest;
  final int year;
  final String fromCity;
  final void Function(_JpRange range) onRangeTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PT.bgElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PT.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DestHero(city: dest.city, country: dest.country,
              emoji: dest.emoji, imageUrl: dest.imageUrl),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Text(dest.tag,
                style: const TextStyle(
                    fontSize: 13,
                    color: PT.textSecondary,
                    height: 1.4)),
          ),
          const Divider(height: 1, color: PT.border),
          for (var i = 0; i < dest.ranges.length; i++) ...[
            _RangeRow(
              range: dest.ranges[i],
              year: year,
              onTap: () => onRangeTap(dest.ranges[i]),
            ),
            if (i < dest.ranges.length - 1)
              const Divider(height: 1, color: PT.border, indent: 14, endIndent: 14),
          ],
        ],
      ),
    );
  }
}

class _DestHero extends StatelessWidget {
  const _DestHero({
    required this.city,
    required this.country,
    required this.emoji,
    required this.imageUrl,
  });
  final String city;
  final String country;
  final String emoji;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return Container(color: const Color(0xFFEFEFF3));
            },
            errorBuilder: (ctx, err, stack) => _HeroFallback(
                city: city, emoji: emoji),
          ),
          // gradient overlay
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xB3000000)],
                stops: [0.4, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(city,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    )),
                Text(country,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback({required this.city, required this.emoji});
  final String city;
  final String emoji;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFB4C1), Color(0xFF7C6AEF)],
        ),
      ),
      child: Center(
        child: Text('$emoji $city',
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
    );
  }
}

class _RangeRow extends StatelessWidget {
  const _RangeRow({
    required this.range,
    required this.year,
    required this.onTap,
  });
  final _JpRange range;
  final int year;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (start, end) = range.dates(year);
    final startLabel = formatTrShortDate(start);
    final endLabel = formatTrShortDate(end);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$startLabel — $endLabel',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: PT.text,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${range.durationLabel()} · ${range.label}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: PT.textSecondary,
                        height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Text('›',
                style: TextStyle(
                    fontSize: 22,
                    color: PT.textTertiary,
                    fontWeight: FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

// ---- form primitifleri ----------------------------------------------------

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    this.minDate,
    this.maxDate,
  });
  final String label;
  final String value;
  final ValueChanged<String> onPick;
  final String? minDate;
  final String? maxDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: PT.textSecondary)),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            final now = DateTime.now();
            final initial = value.isEmpty ? now : DateTime.parse(value);
            final first = minDate != null ? DateTime.parse(minDate!) : now;
            final last = maxDate != null
                ? DateTime.parse(maxDate!)
                : DateTime(now.year + 3);
            final picked = await showDatePicker(
              context: context,
              initialDate: initial.isBefore(first) ? first : initial,
              firstDate: first,
              lastDate: last,
            );
            if (picked != null) {
              onPick(picked.toIso8601String().substring(0, 10));
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: PT.borderStrong),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(value.isEmpty ? 'gg.aa.yyyy' : value,
                style: TextStyle(
                    fontSize: 15,
                    color: value.isEmpty ? PT.textTertiary : PT.text)),
          ),
        ),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField(
      {required this.label, required this.hint, required this.onChanged});
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: PT.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          onChanged: onChanged,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            filled: true,
            fillColor: Colors.white,
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
      ],
    );
  }
}

