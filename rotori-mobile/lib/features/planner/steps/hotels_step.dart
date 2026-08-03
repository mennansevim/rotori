import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/trip_factory.dart';
import '../../../domain/types.dart';
import '../planner_theme.dart';

/// apps/planner/src/components/steps/HotelsStep.tsx birebir portu.
/// Otel kartları + ekle/düzenle bottom-sheet + Booking/Hostelworld link parse.
class HotelsStep extends StatefulWidget {
  const HotelsStep({super.key, required this.trip, required this.onChange});
  final Trip trip;
  final void Function(void Function(Trip)) onChange;

  @override
  State<HotelsStep> createState() => _HotelsStepState();
}

/// parseBookingUrl çıktısı (React ParsedBooking karşılığı).
class ParsedBooking {
  const ParsedBooking({
    this.name,
    this.city,
    this.checkIn,
    this.checkOut,
    this.mapsUrl,
    required this.source,
  });
  final String? name;
  final String? city;
  final String? checkIn;
  final String? checkOut;
  final String? mapsUrl;

  /// 'booking' | 'hostelworld' | 'booking-mytrips' | 'unknown'
  final String source;
}

String _titleCase(String slug) => slug
    .replaceAll(RegExp(r'[-_]+'), ' ')
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

/// HotelsStep.tsx parseBookingUrl birebir.
ParsedBooking? parseBookingUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final Uri url;
  try {
    url = Uri.parse(text);
    if (!url.hasScheme || url.host.isEmpty) return null;
  } catch (_) {
    return null;
  }
  final host = url.host.toLowerCase();
  final checkIn = url.queryParameters['checkin'];
  final checkOut = url.queryParameters['checkout'];

  if (host.contains('booking.com')) {
    final path = url.path.toLowerCase();
    if (path.contains('mytrips') ||
        path.contains('myreservations') ||
        path.contains('myaccount')) {
      return const ParsedBooking(source: 'booking-mytrips');
    }
    final m = RegExp(r'/hotel/([a-z]{2})/([^./]+)', caseSensitive: false)
        .firstMatch(url.path);
    if (m == null) {
      return ParsedBooking(
          source: 'booking', checkIn: checkIn, checkOut: checkOut);
    }
    return ParsedBooking(
      source: 'booking',
      name: _titleCase(m.group(2)!),
      checkIn: checkIn,
      checkOut: checkOut,
    );
  }

  if (host.contains('hostelworld.com')) {
    final segs = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final idx = segs.indexWhere((s) => RegExp(r'hosteldetails', caseSensitive: false).hasMatch(s));
    final nameSlug = idx >= 0
        ? (idx + 1 < segs.length ? segs[idx + 1] : null)
        : (segs.length >= 3 ? segs[segs.length - 3] : null);
    final citySlug = idx >= 0
        ? (idx + 2 < segs.length ? segs[idx + 2] : null)
        : (segs.length >= 2 ? segs[segs.length - 2] : null);
    return ParsedBooking(
      source: 'hostelworld',
      name: nameSlug != null ? _titleCase(nameSlug) : null,
      city: citySlug != null ? _titleCase(citySlug) : null,
      checkIn: checkIn,
      checkOut: checkOut,
    );
  }

  return ParsedBooking(source: 'unknown', checkIn: checkIn, checkOut: checkOut);
}

/// HotelsStep.tsx hotelsComplete — otel zorunlu değil: kullanıcı otel
/// eklemek yerine yalnızca konaklanacak bölge yazmışsa da tamamlanmış sayılır.
/// (Taksi/rehber semtin adını bilirse yeter.)
bool hotelsComplete(Trip trip) {
  if (trip.preferences.destinations.isEmpty) return false;
  final stayArea = trip.preferences.stayArea?.trim() ?? '';
  if (stayArea.isNotEmpty) return true;
  if (trip.hotels.isEmpty) return false;
  return trip.hotels.every((h) =>
      h.city.trim().isNotEmpty &&
      h.name.trim().isNotEmpty &&
      h.address.trim().isNotEmpty &&
      h.checkIn.isNotEmpty &&
      h.checkOut.isNotEmpty);
}

class _HotelsStepState extends State<HotelsStep> {
  Trip get trip => widget.trip;

  void _addHotel() {
    widget.onChange((t) {
      t.hotels.add(HotelStay(
        id: newHotelId(),
        city: '',
        name: '',
        checkIn: t.preferences.travelDates.start,
        checkOut: t.preferences.travelDates.end,
        address: '',
      ));
    });
    // Yeni eklenen oteli düzenlemeye aç.
    _editHotel(trip.hotels.length - 1);
  }

  void _removeHotel(int idx) async {
    final s = LanguageScope.of(context);
    final name = trip.hotels[idx].name.isEmpty
        ? s.p('hotels.hotelN', {'n': '${idx + 1}'})
        : trip.hotels[idx].name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.s('hotels.deleteTitle')),
        content: Text(s.p('hotels.deleteConfirm', {'name': name})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.s('hotels.cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.s('hotels.delete'),
                  style: const TextStyle(color: PT.danger))),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onChange((t) => t.hotels.removeAt(idx));
    }
  }

  void _editHotel(int idx) {
    if (idx < 0 || idx >= trip.hotels.length) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PT.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PT.radiusLg)),
      ),
      builder: (ctx) => _HotelEditSheet(
        hotel: trip.hotels[idx],
        tripStart: trip.preferences.travelDates.start,
        tripEnd: trip.preferences.travelDates.end,
        index: idx,
        onPatch: (mutate) => widget.onChange((t) => mutate(t.hotels[idx])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        PageHeadline(s.s('hotels.title')),
        PageSub(s.s('hotels.subtitle')),

        PCard(
          child: PField(
            label: s.s('hotels.stayArea'),
            hint: Text(
                s.s('hotels.stayAreaHint'),
                style: const TextStyle(fontSize: 12, color: PT.textTertiary)),
            child: PTextField(
              value: trip.preferences.stayArea ?? '',
              hint: s.s('hotels.stayAreaPlaceholder'),
              onChanged: (v) => widget
                  .onChange((t) => t.preferences.stayArea = v.trim().isEmpty ? null : v),
            ),
          ),
        ),

        if (trip.hotels.isEmpty)
          PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    s.s('hotels.emptyHint'),
                    style: const TextStyle(fontSize: 14, color: PT.textSecondary)),
                const SizedBox(height: 16),
                PButton(
                    label: s.s('hotels.addHotel'),
                    block: true,
                    onPressed: _addHotel),
              ],
            ),
          ),

        for (var idx = 0; idx < trip.hotels.length; idx++)
          _HotelCard(
            hotel: trip.hotels[idx],
            index: idx,
            onEdit: () => _editHotel(idx),
            onRemove: () => _removeHotel(idx),
          ),

        if (trip.hotels.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: PButton(
                label: s.s('hotels.addAnother'),
                primary: false,
                block: true,
                onPressed: _addHotel),
          ),
      ],
    );
  }
}

/// Bir otelin özet kartı — tıklanınca düzenleme sheet'i açılır.
class _HotelCard extends StatelessWidget {
  const _HotelCard({
    required this.hotel,
    required this.index,
    required this.onEdit,
    required this.onRemove,
  });
  final HotelStay hotel;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final addrMissing = hotel.address.trim().isEmpty;
    return PCard(
      padding: const EdgeInsets.all(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(PT.radius),
        onTap: onEdit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    hotel.name.isEmpty
                        ? s.p('hotels.hotelN', {'n': '${index + 1}'})
                        : hotel.name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: PT.text),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: const Icon(Icons.close, size: 20, color: PT.textTertiary),
                  tooltip: s.s('hotels.delete'),
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (hotel.city.trim().isNotEmpty) hotel.city.trim(),
                if (hotel.checkIn.isNotEmpty && hotel.checkOut.isNotEmpty)
                  '${hotel.checkIn} → ${hotel.checkOut}',
              ].join(' · '),
              style: const TextStyle(fontSize: 13, color: PT.textSecondary),
            ),
            const SizedBox(height: 8),
            if (addrMissing)
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 15, color: PT.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(s.s('hotels.addressRequired'),
                        style: const TextStyle(fontSize: 12, color: PT.danger)),
                  ),
                ],
              )
            else
              Text(hotel.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: PT.textTertiary)),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(s.s('hotels.edit'),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: PT.accent)),
                const Icon(Icons.chevron_right, size: 16, color: PT.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Otel ekle/düzenle bottom-sheet.
class _HotelEditSheet extends StatefulWidget {
  const _HotelEditSheet({
    required this.hotel,
    required this.tripStart,
    required this.tripEnd,
    required this.index,
    required this.onPatch,
  });
  final HotelStay hotel;
  final String tripStart;
  final String tripEnd;
  final int index;
  final void Function(void Function(HotelStay)) onPatch;

  @override
  State<_HotelEditSheet> createState() => _HotelEditSheetState();
}

class _HotelEditSheetState extends State<_HotelEditSheet> {
  HotelStay get h => widget.hotel;

  Future<void> _pickDate({
    required String current,
    required String minDate,
    required String maxDate,
    required ValueChanged<String> onPick,
  }) async {
    final min = DateTime.tryParse(minDate) ?? DateTime.now();
    final max = DateTime.tryParse(maxDate) ?? DateTime(min.year + 3);
    var init = DateTime.tryParse(current) ?? min;
    if (init.isBefore(min)) init = min;
    if (init.isAfter(max)) init = max;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: min,
      lastDate: max,
    );
    if (picked != null) {
      onPick(picked.toIso8601String().substring(0, 10));
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) => SafeArea(
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: PT.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(s.p('hotels.hotelN', {'n': '${widget.index + 1}'}),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: PT.text)),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PField(
                      label: s.s('hotels.city'),
                      child: PTextField(
                        value: h.city,
                        hint: 'Tokyo',
                        invalid: h.city.trim().isEmpty,
                        onChanged: (v) => widget.onPatch((x) => x.city = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: PField(
                      label: s.s('hotels.hotelName'),
                      child: PTextField(
                        value: h.name,
                        hint: 'Hotel Grand City',
                        invalid: h.name.trim().isEmpty,
                        onChanged: (v) => widget.onPatch((x) => x.name = v),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PField(
                      label: s.s('hotels.checkIn'),
                      child: _SheetDateBox(
                        value: h.checkIn,
                        onTap: () => _pickDate(
                          current: h.checkIn,
                          minDate: widget.tripStart,
                          maxDate: widget.tripEnd,
                          onPick: (v) => widget.onPatch((x) => x.checkIn = v),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: PField(
                      label: s.s('hotels.checkOut'),
                      child: _SheetDateBox(
                        value: h.checkOut,
                        onTap: () => _pickDate(
                          current: h.checkOut,
                          minDate:
                              h.checkIn.isNotEmpty ? h.checkIn : widget.tripStart,
                          maxDate: widget.tripEnd,
                          onPick: (v) => widget.onPatch((x) => x.checkOut = v),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              PField(
                label: s.s('hotels.address'),
                hint: h.address.trim().isEmpty
                    ? Text(s.s('hotels.addressRequired'),
                        style: const TextStyle(fontSize: 12, color: PT.danger))
                    : null,
                child: PTextField(
                  value: h.address,
                  hint: '2-37-6 Ikebukuro, Toshima-ku, Tokyo 171-0014',
                  invalid: h.address.trim().isEmpty,
                  onChanged: (v) => widget.onPatch((x) => x.address = v),
                ),
              ),
              PField(
                label: s.s('hotels.addressLocal'),
                hint: Text(s.s('hotels.addressLocalHint'),
                    style: const TextStyle(fontSize: 12, color: PT.textTertiary)),
                child: PTextField(
                  value: h.addressLocal ?? '',
                  hint: 'ホテルグランドシティ池袋 東京都豊島区...',
                  onChanged: (v) => widget.onPatch((x) => x.addressLocal = v),
                ),
              ),
              PField(
                label: s.s('hotels.mapsUrl'),
                child: PTextField(
                  value: h.mapsUrl ?? '',
                  hint: 'https://maps.google.com/...',
                  onChanged: (v) => widget.onPatch((x) => x.mapsUrl = v),
                ),
              ),
              PField(
                label: s.s('hotels.phone'),
                child: PTextField(
                  value: h.phone ?? '',
                  hint: '+81 ...',
                  keyboardType: TextInputType.phone,
                  onChanged: (v) => widget.onPatch((x) => x.phone = v),
                ),
              ),
              PField(
                label: s.s('hotels.notes'),
                child: PTextField(
                  value: h.notes ?? '',
                  hint: s.s('hotels.notesPlaceholder'),
                  onChanged: (v) => widget.onPatch((x) => x.notes = v),
                ),
              ),
              const SizedBox(height: 8),
              PButton(
                label: s.s('hotels.done'),
                block: true,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetDateBox extends StatelessWidget {
  const _SheetDateBox({required this.value, required this.onTap});
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 44),
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
            Text(value.isEmpty ? s.s('hotels.pickDate') : value,
                style: TextStyle(
                    fontSize: 15,
                    color: value.isEmpty ? PT.textTertiary : PT.text)),
          ],
        ),
      ),
    );
  }
}
