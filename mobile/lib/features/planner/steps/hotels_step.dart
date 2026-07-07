import 'package:flutter/material.dart';

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

/// HotelsStep.tsx hotelsComplete birebir (planner_screen'de de var, burada
/// export edilir ki testler tek kaynaktan kontrol edebilsin).
bool hotelsComplete(Trip trip) {
  if (trip.hotels.isEmpty) return false;
  return trip.hotels.every((h) =>
      h.city.trim().isNotEmpty &&
      h.name.trim().isNotEmpty &&
      h.address.trim().isNotEmpty &&
      h.checkIn.isNotEmpty &&
      h.checkOut.isNotEmpty);
}

class _HotelsStepState extends State<HotelsStep> {
  final TextEditingController _importCtrl = TextEditingController();
  // {kind: 'success'|'error'|'idle', message}
  String _importKind = 'idle';
  String _importMessage = '';

  Trip get trip => widget.trip;

  @override
  void dispose() {
    _importCtrl.dispose();
    super.dispose();
  }

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

  void _importFromUrl() {
    final parsed = parseBookingUrl(_importCtrl.text);
    if (parsed == null) {
      setState(() {
        _importKind = 'error';
        _importMessage = 'Geçerli bir URL yapıştır (Booking veya Hostelworld).';
      });
      return;
    }
    if (parsed.source == 'booking-mytrips') {
      setState(() {
        _importKind = 'error';
        _importMessage =
            'Bu link Booking hesabındaki rezervasyon listesine gidiyor (üye girişi gerekir, tek bir otel bilgisi yok). Onaylama e-postandan veya rezervasyon detayından otelin sayfa linkini kopyala — örn. booking.com/hotel/jp/hotel-adi.html';
      });
      return;
    }
    if (parsed.source == 'unknown') {
      setState(() {
        _importKind = 'error';
        _importMessage =
            'Bu site desteklenmiyor. Booking.com veya Hostelworld linki yapıştır.';
      });
      return;
    }
    final start = trip.preferences.travelDates.start;
    final end = trip.preferences.travelDates.end;
    final urlTrim = _importCtrl.text.trim();
    widget.onChange((t) {
      t.hotels.add(HotelStay(
        id: newHotelId(),
        city: parsed.city ?? '',
        name: parsed.name ?? '',
        checkIn: parsed.checkIn ?? start,
        checkOut: parsed.checkOut ?? end,
        address: '',
        mapsUrl: urlTrim,
      ));
    });
    final label = parsed.source == 'booking' ? 'Booking' : 'Hostelworld';
    setState(() {
      _importCtrl.clear();
      _importKind = 'success';
      _importMessage =
          '$label\'dan içe aktarıldı: ${parsed.name ?? 'isimsiz'}. Eksik alanları doldurmayı unutma.';
    });
  }

  void _removeHotel(int idx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oteli sil'),
        content: Text(
            '"${trip.hotels[idx].name.isEmpty ? 'Otel ${idx + 1}' : trip.hotels[idx].name}" silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil', style: TextStyle(color: PT.danger))),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        const PageHeadline('Konaklama'),
        const PageSub(
            'Her otel için açık adres zorunludur — taksi ve pusulada kullanılır. '
            'Yerel dilde adresi de ekleyin (Japonca, Korece vb.).'),

        // Booking import kartı
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🔗 Rezervasyondan içe aktar',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: PT.text)),
              const SizedBox(height: 6),
              const Text(
                'Booking.com veya Hostelworld\'de yaptığın rezervasyonun linkini '
                'yapıştır — otel adı ve tarihler otomatik dolar. Manuel ekleme '
                'her zaman aşağıdadır.',
                style: TextStyle(fontSize: 13, color: PT.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _importCtrl,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'https://www.booking.com/hotel/jp/...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        filled: true,
                        fillColor: PT.bgSubtle,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: PT.borderStrong),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: PT.accent),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _importFromUrl(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PButton(
                    label: 'İçe aktar',
                    primary: true,
                    onPressed:
                        _importCtrl.text.trim().isEmpty ? null : _importFromUrl,
                  ),
                ],
              ),
              if (_importKind != 'idle')
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _importMessage,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: _importKind == 'error' ? PT.danger : const Color(0xFF15803D),
                    ),
                  ),
                ),
            ],
          ),
        ),

        if (trip.hotels.isEmpty)
          PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Henüz otel yok. En az bir konaklama ekleyin.',
                    style: TextStyle(fontSize: 14, color: PT.textSecondary)),
                const SizedBox(height: 16),
                PButton(
                    label: '+ Otel ekle',
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
                label: '+ Başka otel ekle',
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
                    hotel.name.isEmpty ? 'Otel ${index + 1}' : hotel.name,
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
                  tooltip: 'Sil',
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
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 15, color: PT.danger),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text('Taksi ve harita için adres gerekli',
                        style: TextStyle(fontSize: 12, color: PT.danger)),
                  ),
                ],
              )
            else
              Text(hotel.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: PT.textTertiary)),
            const SizedBox(height: 6),
            const Row(
              children: [
                Text('Düzenle',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: PT.accent)),
                Icon(Icons.chevron_right, size: 16, color: PT.accent),
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
              Text('Otel ${widget.index + 1}',
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
                      label: 'Şehir *',
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
                      label: 'Otel adı *',
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
                      label: 'Giriş *',
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
                      label: 'Çıkış *',
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
                label: 'Açık adres (sokak, posta kodu) *',
                hint: h.address.trim().isEmpty
                    ? const Text('Taksi ve harita için adres gerekli',
                        style: TextStyle(fontSize: 12, color: PT.danger))
                    : null,
                child: PTextField(
                  value: h.address,
                  hint: '2-37-6 Ikebukuro, Toshima-ku, Tokyo 171-0014',
                  invalid: h.address.trim().isEmpty,
                  onChanged: (v) => widget.onPatch((x) => x.address = v),
                ),
              ),
              PField(
                label: 'Adres (yerel dil)',
                hint: const Text('Japonca — taksiciye göster',
                    style: TextStyle(fontSize: 12, color: PT.textTertiary)),
                child: PTextField(
                  value: h.addressLocal ?? '',
                  hint: 'ホテルグランドシティ池袋 東京都豊島区...',
                  onChanged: (v) => widget.onPatch((x) => x.addressLocal = v),
                ),
              ),
              PField(
                label: 'Google Maps linki',
                child: PTextField(
                  value: h.mapsUrl ?? '',
                  hint: 'https://maps.google.com/...',
                  onChanged: (v) => widget.onPatch((x) => x.mapsUrl = v),
                ),
              ),
              PField(
                label: 'Telefon',
                child: PTextField(
                  value: h.phone ?? '',
                  hint: '+81 ...',
                  keyboardType: TextInputType.phone,
                  onChanged: (v) => widget.onPatch((x) => x.phone = v),
                ),
              ),
              PField(
                label: 'Notlar',
                child: PTextField(
                  value: h.notes ?? '',
                  hint: 'Check-in saati, kat, ek notlar',
                  onChanged: (v) => widget.onPatch((x) => x.notes = v),
                ),
              ),
              const SizedBox(height: 8),
              PButton(
                label: 'Bitti',
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
            Text(value.isEmpty ? 'Tarih seç' : value,
                style: TextStyle(
                    fontSize: 15,
                    color: value.isEmpty ? PT.textTertiary : PT.text)),
          ],
        ),
      ),
    );
  }
}
