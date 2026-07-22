import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../data/airlines.dart';
import '../data/airports.dart';
import '../planner_theme.dart';

/// Havaalanı seçici — dokununca aramalı modal açar.
/// (React AirportPicker'ın işlevsel karşılığı; inline overlay yerine modal.)
class AirportPickerField extends StatelessWidget {
  const AirportPickerField({
    super.key,
    required this.onSelect,
    this.valueLabel,
    this.valueCode,
    this.placeholder,
    this.countryCodes,
  });

  final ValueChanged<Airport> onSelect;
  final String? valueLabel;
  final String? valueCode;
  final String? placeholder;
  final List<String>? countryCodes;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return _PickerButton(
      icon: '✈️',
      label: valueLabel,
      code: valueCode,
      placeholder: placeholder ?? s.s('pickers.airportPlaceholder'),
      onTap: () async {
        final picked = await showModalBottomSheet<Airport>(
          context: context,
          isScrollControlled: true,
          backgroundColor: PT.bgElevated,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _AirportSearchSheet(countryCodes: countryCodes),
        );
        if (picked != null) onSelect(picked);
      },
    );
  }
}

/// Havayolu seçici.
class AirlinePickerField extends StatelessWidget {
  const AirlinePickerField({
    super.key,
    required this.onSelect,
    this.valueLabel,
    this.valueCode,
  });
  final ValueChanged<Airline> onSelect;
  final String? valueLabel;
  final String? valueCode;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return _PickerButton(
      icon: '🛫',
      label: valueLabel,
      code: valueCode,
      placeholder: s.s('pickers.airlinePlaceholder'),
      onTap: () async {
        final picked = await showModalBottomSheet<Airline>(
          context: context,
          isScrollControlled: true,
          backgroundColor: PT.bgElevated,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => const _AirlineSearchSheet(),
        );
        if (picked != null) onSelect(picked);
      },
    );
  }
}

/// styles.css .airport-input-wrap benzeri tıklanabilir alan.
class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.icon,
    required this.placeholder,
    required this.onTap,
    this.label,
    this.code,
  });
  final String icon;
  final String placeholder;
  final VoidCallback onTap;
  final String? label;
  final String? code;

  @override
  Widget build(BuildContext context) {
    final hasValue = label != null && label!.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: PT.bgSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PT.borderStrong),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasValue ? label! : placeholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  color: hasValue ? PT.text : PT.textTertiary,
                ),
              ),
            ),
            if (code != null && code!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: PT.accentSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(code!,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: PT.accent)),
              ),
            const Icon(Icons.expand_more, size: 20, color: PT.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _AirportSearchSheet extends StatefulWidget {
  const _AirportSearchSheet({this.countryCodes});
  final List<String>? countryCodes;
  @override
  State<_AirportSearchSheet> createState() => _AirportSearchSheetState();
}

class _AirportSearchSheetState extends State<_AirportSearchSheet> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final results = searchAirports(_q, limit: 20, countryCodes: widget.countryCodes);
    return _SheetScaffold(
      title: s.s('pickers.pickAirport'),
      hint: s.s('pickers.airportSearchHint'),
      onQuery: (v) => setState(() => _q = v),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final a = results[i];
        return ListTile(
          leading: _CodeChip(a.iata),
          title: Text(a.city, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(a.countryName),
          onTap: () => Navigator.pop(context, a),
        );
      },
    );
  }
}

class _AirlineSearchSheet extends StatefulWidget {
  const _AirlineSearchSheet();
  @override
  State<_AirlineSearchSheet> createState() => _AirlineSearchSheetState();
}

class _AirlineSearchSheetState extends State<_AirlineSearchSheet> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final results = searchAirlines(_q, limit: 20);
    return _SheetScaffold(
      title: s.s('pickers.pickAirline'),
      hint: s.s('pickers.airlineSearchHint'),
      onQuery: (v) => setState(() => _q = v),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final a = results[i];
        return ListTile(
          leading: _CodeChip(a.code),
          title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: a.country != null ? Text(a.country!) : null,
          onTap: () => Navigator.pop(context, a),
        );
      },
    );
  }
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.hint,
    required this.onQuery,
    required this.itemCount,
    required this.itemBuilder,
  });
  final String title;
  final String hint;
  final ValueChanged<String> onQuery;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: PT.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: PT.text)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.s('pickers.close')),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                onChanged: onQuery,
                decoration: InputDecoration(
                  hintText: hint,
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: PT.bgSubtle,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                itemCount: itemCount,
                itemBuilder: itemBuilder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip(this.code);
  final String code;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PT.accentSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(code,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: PT.accent)),
    );
  }
}
