import 'package:flutter/material.dart';

import '../../../domain/types.dart';
import '../data/japan_seasonality.dart';
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

  // ---- plan (mevsim) ---------------------------------------------------
  Widget _buildPlan() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        _BackButton(onTap: () => setState(() => _view = _View.choose)),
        const Text("Japonya'da hangi mevsim?",
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w700, color: PT.text)),
        const SizedBox(height: 4),
        const Text(
          'Aylar bir bakışta. Aşağıdaki önerilen aralıklardan birini seç, '
          'tarihleri otomatik dolduralım.',
          style: TextStyle(fontSize: 15, color: PT.textSecondary),
        ),
        const SizedBox(height: 20),
        // season-grid → içeriğe göre boyutlanan Wrap (CSS grid minmax(220,1fr))
        LayoutBuilder(
          builder: (context, c) {
            const gap = 12.0;
            final cols = (c.maxWidth / 232).floor().clamp(1, 4);
            final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
            final now = DateTime.now().toUtc();
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final m in kMonths)
                  SizedBox(
                    width: cardW,
                    child: Builder(
                      builder: (_) {
                        final year = m.month >= now.month ? now.year : now.year + 1;
                        final start = '$year-${m.month.toString().padLeft(2, '0')}-01';
                        final end = _addDays(start, 13);
                        return _SeasonMonthCard(
                          month: m,
                          year: year,
                          onTap: () {
                            _applyDates(start, end);
                            widget.onContinue();
                          },
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 32),
        const Text('Önerilen 2 haftalık aralıklar',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600, color: PT.text)),
        const SizedBox(height: 12),
        for (final r in kSuggestedRanges) ...[
          _RangeCard(
            range: r,
            onTap: () {
              _applyDates(r.startISO, r.endISO);
              widget.onContinue();
            },
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 20),
        const Text('⚠️ Bu pencerelerden uzak dur',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB45309))),
        const SizedBox(height: 12),
        for (final r in kAvoidRanges) ...[
          _AvoidCard(range: r),
          const SizedBox(height: 10),
        ],
      ],
    );
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

/// styles.css .season-badge + tone renkleri
class SeasonBadgeChip extends StatelessWidget {
  const SeasonBadgeChip(this.tag, {super.key});
  final String tag;
  @override
  Widget build(BuildContext context) {
    final b = kBadges[tag];
    if (b == null) return const SizedBox.shrink();
    final (bg, fg) = switch (b.tone) {
      SeasonTone.good => (const Color(0xFFDCFCE7), const Color(0xFF166534)),
      SeasonTone.warn => (const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      SeasonTone.bad => (const Color(0xFFFEE2E2), const Color(0xFF991B1B)),
      SeasonTone.info => (const Color(0xFFE0E7FF), const Color(0xFF3730A3)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text('${b.emoji} ${b.label}',
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}

class _SeasonMonthCard extends StatelessWidget {
  const _SeasonMonthCard(
      {required this.month, required this.year, required this.onTap});
  final SeasonMonth month;
  final int year;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PT.bgElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: PT.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${month.month}',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: PT.textTertiary)),
                  const SizedBox(width: 8),
                  Text(month.label,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: PT.text)),
                  const SizedBox(width: 2),
                  Text('$year',
                      style: const TextStyle(
                          fontSize: 12, color: PT.textTertiary)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [for (final t in month.tags) SeasonBadgeChip(t)],
              ),
              const SizedBox(height: 8),
              Text(month.note,
                  style: const TextStyle(
                      fontSize: 12, color: PT.textSecondary, height: 1.45)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangeCard extends StatelessWidget {
  const _RangeCard({required this.range, required this.onTap});
  final SuggestedRange range;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final leftColor = switch (range.tone) {
      SeasonTone.good => const Color(0xFF16A34A),
      SeasonTone.warn => const Color(0xFFD97706),
      SeasonTone.bad => const Color(0xFFDC2626),
      SeasonTone.info => const Color(0xFF3730A3),
    };
    // CSS: border 1px + border-left 4px renkli + border-radius.
    // Flutter'da non-uniform border + radius yasak → dış uniform border +
    // içeride sol renkli çubuğu ayrı strip olarak (ClipRRect + IntrinsicHeight).
    return Material(
      color: PT.bgElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: PT.borderStrong),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: leftColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(range.label,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: PT.text)),
                              Wrap(
                                spacing: 4,
                                children: [
                                  for (final b in range.badges)
                                    SeasonBadgeChip(b),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('${_fmt(range.startISO)} — ${_fmt(range.endISO)}',
                              style: const TextStyle(
                                  fontSize: 13, color: PT.textTertiary)),
                          const SizedBox(height: 6),
                          Text(range.reason,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: PT.textSecondary,
                                  height: 1.45)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvoidCard extends StatelessWidget {
  const _AvoidCard({required this.range});
  final AvoidRange range;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFFED7AA)),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(range.label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9A3412))),
              Wrap(
                spacing: 4,
                children: [for (final b in range.badges) SeasonBadgeChip(b)],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(range.reason,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF7C2D12), height: 1.45)),
        ],
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

const _trMonths = [
  '',
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

String _fmt(String iso) {
  final d = DateTime.parse('${iso}T00:00:00Z');
  return '${d.day} ${_trMonths[d.month]} ${d.year}';
}
