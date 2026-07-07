import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/rules.dart';
import '../../../domain/types.dart';
import '../planner_theme.dart';
import '../steps.dart';

/// apps/planner/src/components/steps/PublishStep.tsx portu.
/// Uyarı paneli (collectTripWarnings) + paylaşım URL + JSON dışa/içe aktarma.
class PublishStep extends StatelessWidget {
  const PublishStep({
    super.key,
    required this.trip,
    required this.onChange,
    this.onGoToStep,
  });
  final Trip trip;
  final void Function(void Function(Trip)) onChange;

  /// Uyarıdaki "adıma dön" için — rules.dart step string'i ('hotels', 'plan'...).
  final void Function(StepId step)? onGoToStep;

  static const Map<String, String> _stepLabels = {
    'journey': 'Rota',
    'explore': 'Keşfet',
    'title': 'Başlık',
    'hotels': 'Konaklama',
    'food': 'Yemek',
    'plan': 'Plan',
    'calendar': 'Takvim',
  };

  static const Map<String, StepId> _stepIds = {
    'journey': StepId.journey,
    'explore': StepId.explore,
    'title': StepId.title,
    'hotels': StepId.hotels,
    'food': StepId.food,
    'plan': StepId.plan,
  };

  String get _shareUrl => '/viewer/?u=${trip.slug}';

  Color _severityColor(TripWarningSeverity s) => switch (s) {
        TripWarningSeverity.info => const Color(0xFF0369A1),
        TripWarningSeverity.warn => const Color(0xFFB45309),
        TripWarningSeverity.urgent => PT.danger,
      };

  Color _severityBg(TripWarningSeverity s) => switch (s) {
        TripWarningSeverity.info => const Color(0x140369A1),
        TripWarningSeverity.warn => const Color(0x14B45309),
        TripWarningSeverity.urgent => const Color(0x14BF4800),
      };

  void _copyShare(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _shareUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✓ Bağlantı kopyalandı')),
    );
  }

  void _exportJson(BuildContext context) {
    final json = const JsonEncoder.withIndent('  ').convert(trip.toJson());
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('JSON dışa aktar'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(json,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('✓ JSON kopyalandı')),
              );
            },
            child: const Text('Kopyala'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat')),
        ],
      ),
    );
  }

  void _importJson(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('JSON içe aktar'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            maxLines: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Buraya Trip JSON yapıştır…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          TextButton(
            onPressed: () {
              try {
                final map = jsonDecode(ctrl.text) as Map<String, dynamic>;
                final imported = Trip.fromJson(map);
                // Mevcut trip'in id/slug'ını korur, alanları içe aktarır.
                onChange((t) {
                  t.title = imported.title;
                  t.subtitle = imported.subtitle;
                  t.timezone = imported.timezone;
                  t.tripStart = imported.tripStart;
                  t.tripEnd = imported.tripEnd;
                  t.flights = imported.flights;
                  t.hotels = imported.hotels;
                  t.tickets = imported.tickets;
                  t.preferences = imported.preferences;
                  t.days = imported.days;
                  t.deadlines = imported.deadlines;
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✓ Plan içe aktarıldı')),
                );
              } catch (e) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Geçersiz JSON: $e')),
                );
              }
            },
            child: const Text('İçe aktar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final warnings = collectTripWarnings(trip);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        const PageHeadline('Yayına hazır'),
        PageSub(
            'Planınız "${trip.slug}" kullanıcısı altında kaydedildi. Aşağıdaki '
            'bağlantıyı paylaşarak başka cihazdan rehbere ulaşılabilir.'),

        // Uyarı panelleri
        for (final w in warnings)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _severityBg(w.severity),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _severityColor(w.severity).withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.message,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: _severityColor(w.severity))),
                if (w.step != null &&
                    _stepIds[w.step] != null &&
                    onGoToStep != null) ...[
                  const SizedBox(height: 10),
                  PButton(
                    label: '${_stepLabels[w.step] ?? w.step} adımına dön →',
                    primary: false,
                    onPressed: () => onGoToStep!(_stepIds[w.step]!),
                  ),
                ],
              ],
            ),
          ),

        // Paylaşım kartı
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PCardTitle('Paylaşılabilir bağlantı'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: PT.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: PT.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(_shareUrl,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: PT.text)),
                    ),
                    const SizedBox(width: 8),
                    PButton(
                      label: 'Kopyala',
                      primary: false,
                      onPressed: () => _copyShare(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: PButton(
                      label: 'Dışa aktar',
                      primary: false,
                      onPressed: () => _exportJson(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PButton(
                      label: 'İçe aktar',
                      primary: false,
                      onPressed: () => _importJson(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Yayın kilidi: plan boşsa yayın adımı kilitli kalır — '
                  'viewer boş ekran açmasın diye. En az bir aktivite ekle.',
                  style: TextStyle(
                      fontSize: 13, color: PT.textTertiary, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
