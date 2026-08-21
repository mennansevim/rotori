import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../data/google_maps_launcher.dart';
import '../../data/plans_repository.dart';
import '../../domain/trip_factory.dart';
import '../../domain/types.dart';
import '../planner/planner_theme.dart';
import 'plan_providers.dart';

/// Viewer panelindeki "Otel ekle" kartından açılan **tam sayfa** otel ekleme
/// akışı. Planlayıcıya (8 adımlı stepper) geri dönmez; yalnızca otel bilgisi
/// alır, "Kaydet" ile plana ekler ve viewer'a döner. Plan realtime dinlendiği
/// için viewer paneli otomatik güncellenir.
class AddHotelPage extends ConsumerStatefulWidget {
  const AddHotelPage({super.key, required this.planId});
  final String planId;

  @override
  ConsumerState<AddHotelPage> createState() => _AddHotelPageState();
}

class _AddHotelPageState extends ConsumerState<AddHotelPage> {
  late final HotelStay _draft = HotelStay(
    id: newHotelId(),
    city: '',
    name: '',
    checkIn: '',
    checkOut: '',
    address: '',
  );
  bool _saving = false;
  bool _submitted = false;

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

  bool get _valid =>
      _draft.city.trim().isNotEmpty &&
      _draft.name.trim().isNotEmpty &&
      _draft.address.trim().isNotEmpty &&
      _draft.checkIn.isNotEmpty &&
      _draft.checkOut.isNotEmpty;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _findOnGoogleMaps(LanguageScope s) async {
    final query = [_draft.name.trim(), _draft.city.trim()]
        .where((part) => part.isNotEmpty)
        .join(' ');
    final opened = await openGoogleMapsSearch(
      query.isEmpty ? s.s('hotels.mapSearchDefault') : query,
    );
    if (!opened) _toast(s.s('hotels.mapOpenFailed'));
  }

  Future<void> _save(Trip trip) async {
    setState(() => _submitted = true);
    if (!_valid || _saving) return;

    final s = LanguageScope.of(context);

    setState(() => _saving = true);

    // Oturum YOKSA da kaydet.
    //
    // **Why:** Burada `repo == null` iken "oturum açman gerekiyor" deyip
    // çıkılıyordu, oysa oturumsuz akış uygulamanın desteklediği bir yol:
    // `planByIdProvider` repo yokken planı `draftTripProvider`'dan okuyor ve
    // uçuş ekranı (flight_details_page) tam olarak bunu yapıyor —
    // `repo?.save()` no-op olur, taslak yine güncellenir. İki ekranın farklı
    // davranması yüzünden aynı planda uçuş eklenebiliyor ama otel
    // eklenemiyordu.
    //
    // Kopya üzerinde çalışılır: yerinde mutasyon aynı nesneyi geri yazdığı
    // için stream yeni bir değer yayınlamıyordu (uçuş ekranındaki desen).
    final saved = Trip.fromJson(trip.toJson());
    saved.hotels.add(_draft);

    // Yalnız KAYIT try içinde. Eskiden `context.pop()` de içindeydi:
    // navigasyon hatası "Otel kaydedilemedi" diye raporlanıyordu, oysa otel
    // kaydedilmişti — kullanıcı yanlış bilgiyle ikinci kez kaydetmeye
    // çalışırdı.
    try {
      await ref.read(plansRepositoryProvider)?.save(saved);
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
        _toast(s.s('hotels.saveFailed'));
      }
      return;
    }

    ref.read(draftTripProvider.notifier).state = saved;
    if (!mounted) return;
    setState(() => _saving = false);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final planAsync = ref.watch(planByIdProvider(widget.planId));
    return Theme(
      data: PT.theme(),
      child: Scaffold(
        backgroundColor: PT.bg,
        appBar: AppBar(
          backgroundColor: PT.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            s.s('drawer.hotels.add'),
            style: const TextStyle(
              color: PT.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          iconTheme: const IconThemeData(color: PT.text),
        ),
        body: planAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Text(s.s('hotels.saveError'),
                style: const TextStyle(color: PT.danger)),
          ),
          data: (trip) => _form(context, s, trip),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, LanguageScope s, Trip trip) {
    final tripStart = trip.preferences.travelDates.start;
    final tripEnd = trip.preferences.travelDates.end;
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: PT.bgElevated,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: PT.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: PT.accentSoft,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.hotel_rounded,
                                color: PT.accent,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                s.s('hotels.formIntro'),
                                style: const TextStyle(
                                  color: PT.textSecondary,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        PButton(
                          key: const ValueKey('hotel-find-on-google-maps'),
                          label: s.s('hotels.findOnMap'),
                          primary: false,
                          block: true,
                          leading: const Icon(
                            Icons.map_outlined,
                            color: PT.accent,
                            size: 19,
                          ),
                          onPressed: () => _findOnGoogleMaps(s),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s.s('hotels.mapPickerHelp'),
                          style: const TextStyle(
                            color: PT.textTertiary,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PField(
                    label: s.s('hotels.city'),
                    child: PTextField(
                      key: const ValueKey('hotel-city-field'),
                      value: _draft.city,
                      invalid: _submitted && _draft.city.trim().isEmpty,
                      onChanged: (v) => setState(() => _draft.city = v),
                    ),
                  ),
                  PField(
                    label: s.s('hotels.hotelName'),
                    child: PTextField(
                      key: const ValueKey('hotel-name-field'),
                      value: _draft.name,
                      invalid: _submitted && _draft.name.trim().isEmpty,
                      onChanged: (v) => setState(() => _draft.name = v),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: PField(
                          label: s.s('hotels.checkIn'),
                          child: _DateBox(
                            value: _draft.checkIn,
                            invalid: _submitted && _draft.checkIn.isEmpty,
                            onTap: () => _pickDate(
                              current: _draft.checkIn,
                              minDate: tripStart,
                              maxDate: tripEnd,
                              onPick: (v) => _draft.checkIn = v,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PField(
                          label: s.s('hotels.checkOut'),
                          child: _DateBox(
                            value: _draft.checkOut,
                            invalid: _submitted && _draft.checkOut.isEmpty,
                            onTap: () => _pickDate(
                              current: _draft.checkOut,
                              minDate: _draft.checkIn.isNotEmpty
                                  ? _draft.checkIn
                                  : tripStart,
                              maxDate: tripEnd,
                              onPick: (v) => _draft.checkOut = v,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  PField(
                    label: s.s('hotels.address'),
                    hint: _submitted && _draft.address.trim().isEmpty
                        ? Text(
                            s.s('hotels.addressRequired'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: PT.danger,
                            ),
                          )
                        : null,
                    child: PTextField(
                      key: const ValueKey('hotel-address-field'),
                      value: _draft.address,
                      invalid: _submitted && _draft.address.trim().isEmpty,
                      onChanged: (v) => setState(() => _draft.address = v),
                    ),
                  ),
                  PField(
                    label: s.s('hotels.addressLocal'),
                    hint: Text(
                      s.s('hotels.addressLocalHint'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: PT.textTertiary,
                      ),
                    ),
                    child: PTextField(
                      key: const ValueKey('hotel-local-address-field'),
                      value: _draft.addressLocal ?? '',
                      onChanged: (v) => _draft.addressLocal = v,
                    ),
                  ),
                  PField(
                    label: s.s('hotels.mapsUrl'),
                    child: PTextField(
                      key: const ValueKey('hotel-maps-url-field'),
                      value: _draft.mapsUrl ?? '',
                      keyboardType: TextInputType.url,
                      onChanged: (v) => _draft.mapsUrl = v,
                    ),
                  ),
                  PField(
                    label: s.s('hotels.phone'),
                    child: PTextField(
                      key: const ValueKey('hotel-phone-field'),
                      value: _draft.phone ?? '',
                      keyboardType: TextInputType.phone,
                      onChanged: (v) => _draft.phone = v,
                    ),
                  ),
                  PField(
                    label: s.s('hotels.notes'),
                    child: PTextField(
                      key: const ValueKey('hotel-notes-field'),
                      value: _draft.notes ?? '',
                      onChanged: (v) => _draft.notes = v,
                    ),
                  ),
                  const SizedBox(height: 4),
                  PButton(
                    label: _saving
                        ? s.s('hotels.saving')
                        : s.s('hotels.saveHotel'),
                    block: true,
                    onPressed: _saving ? null : () => _save(trip),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({
    required this.value,
    required this.onTap,
    this.invalid = false,
  });
  final String value;
  final VoidCallback onTap;
  final bool invalid;

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
          border: Border.all(color: invalid ? PT.danger : PT.borderStrong),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 16, color: PT.textTertiary),
            const SizedBox(width: 10),
            Text(
              value.isEmpty ? s.s('hotels.pickDate') : value,
              style: TextStyle(
                fontSize: 15,
                color: value.isEmpty ? PT.textTertiary : PT.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
