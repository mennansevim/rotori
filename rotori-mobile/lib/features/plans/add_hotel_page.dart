import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
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

  Future<void> _save(Trip trip) async {
    setState(() => _submitted = true);
    if (!_valid || _saving) return;
    final repo = ref.read(plansRepositoryProvider);
    if (repo == null) return;
    setState(() => _saving = true);
    // Mevcut trip üzerine oteli ekleyip kaydet. Trip mutable olduğundan
    // doğrudan listeye ekliyoruz; repository yerel + Supabase senkronunu yapar.
    trip.hotels.add(_draft);
    try {
      await repo.save(trip);
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PField(
                  label: s.s('hotels.city'),
                  child: PTextField(
                    value: _draft.city,
                    hint: 'Tokyo',
                    invalid: _submitted && _draft.city.trim().isEmpty,
                    onChanged: (v) => setState(() => _draft.city = v),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: PField(
                  label: s.s('hotels.hotelName'),
                  child: PTextField(
                    value: _draft.name,
                    hint: 'Hotel Grand City',
                    invalid: _submitted && _draft.name.trim().isEmpty,
                    onChanged: (v) => setState(() => _draft.name = v),
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
              const SizedBox(width: 14),
              Expanded(
                child: PField(
                  label: s.s('hotels.checkOut'),
                  child: _DateBox(
                    value: _draft.checkOut,
                    invalid: _submitted && _draft.checkOut.isEmpty,
                    onTap: () => _pickDate(
                      current: _draft.checkOut,
                      minDate:
                          _draft.checkIn.isNotEmpty ? _draft.checkIn : tripStart,
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
            hint: _draft.address.trim().isEmpty
                ? Text(s.s('hotels.addressRequired'),
                    style: const TextStyle(fontSize: 12, color: PT.danger))
                : null,
            child: PTextField(
              value: _draft.address,
              hint: '2-37-6 Ikebukuro, Toshima-ku, Tokyo 171-0014',
              invalid: _submitted && _draft.address.trim().isEmpty,
              onChanged: (v) => setState(() => _draft.address = v),
            ),
          ),
          PField(
            label: s.s('hotels.addressLocal'),
            hint: Text(s.s('hotels.addressLocalHint'),
                style: const TextStyle(fontSize: 12, color: PT.textTertiary)),
            child: PTextField(
              value: _draft.addressLocal ?? '',
              hint: 'ホテルグランドシティ池袋 東京都豊島区...',
              onChanged: (v) => _draft.addressLocal = v,
            ),
          ),
          PField(
            label: s.s('hotels.mapsUrl'),
            child: PTextField(
              value: _draft.mapsUrl ?? '',
              hint: 'https://maps.google.com/...',
              onChanged: (v) => _draft.mapsUrl = v,
            ),
          ),
          PField(
            label: s.s('hotels.phone'),
            child: PTextField(
              value: _draft.phone ?? '',
              hint: '+81 ...',
              keyboardType: TextInputType.phone,
              onChanged: (v) => _draft.phone = v,
            ),
          ),
          PField(
            label: s.s('hotels.notes'),
            child: PTextField(
              value: _draft.notes ?? '',
              hint: s.s('hotels.notesPlaceholder'),
              onChanged: (v) => _draft.notes = v,
            ),
          ),
          const SizedBox(height: 8),
          PButton(
            label: _saving ? s.s('hotels.saving') : s.s('hotels.saveHotel'),
            block: true,
            onPressed: _saving ? null : () => _save(trip),
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
          border: Border.all(
              color: invalid ? PT.danger : PT.borderStrong),
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
