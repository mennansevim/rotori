import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/types.dart';
import 'plan_providers.dart';

/// Plan görüntüleyici — okuma modu. Countdown + rota özeti + günler.
class PlanViewerScreen extends ConsumerWidget {
  const PlanViewerScreen({super.key, required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planByIdProvider(planId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/plans'),
        ),
        title: const Text('Plan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Düzenle',
            onPressed: () => context.go('/plans/$planId/edit'),
          ),
        ],
      ),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Yüklenemedi: $err'),
          ),
        ),
        data: (trip) => _Body(trip: trip),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(trip.tripStart) ?? DateTime.now();
    final now = DateTime.now();
    final daysUntil = start.difference(now).inDays;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          trip.title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        if (trip.subtitle != null && trip.subtitle!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            trip.subtitle!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 24),

        // Countdown
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  daysUntil > 0
                      ? '$daysUntil gün kaldı'
                      : daysUntil == 0
                          ? 'Bugün başladı 🎉'
                          : '${-daysUntil} gündür başladı',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${trip.tripStart.substring(0, 10)} → '
                  '${trip.tripEnd.substring(0, 10)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Uçuşlar
        if (trip.flights.outbound.isNotEmpty ||
            trip.flights.returnLegs.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '✈️ Uçuşlar',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final leg in trip.flights.outbound)
                    _LegRow(leg: leg, direction: '→'),
                  for (final leg in trip.flights.returnLegs)
                    _LegRow(leg: leg, direction: '←'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),

        // Oteller
        if (trip.hotels.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🏨 Konaklama',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final h in trip.hotels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${h.name} · ${h.city}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (h.address.isNotEmpty) Text(h.address),
                          Text(
                            '${h.checkIn} → ${h.checkOut}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),

        // Günler
        Text(
          '📅 Günler (${trip.days.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (trip.days.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Bu plana henüz gün eklenmedi. Düzenle → gün ekle.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          for (final day in trip.days) _DayCard(day: day),
      ],
    );
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({required this.leg, required this.direction});
  final FlightLeg leg;
  final String direction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$direction '),
          Text(
            '${leg.city}${leg.airport.isNotEmpty ? ' (${leg.airport})' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            leg.dateTime.length >= 16
                ? leg.dateTime.substring(0, 16).replaceAll('T', ' ')
                : leg.dateTime,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});
  final DayPlan day;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text('Gün ${day.dayNumber} · ${day.date}'),
        subtitle: Text(day.theme),
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          if (day.items.isEmpty)
            const Text('(Bu güne aktivite eklenmedi.)')
          else
            for (final it in day.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(
                        it.time ?? it.scheduledTime ?? '--:--',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.title),
                          if (it.description != null &&
                              it.description!.isNotEmpty)
                            Text(
                              it.description!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
