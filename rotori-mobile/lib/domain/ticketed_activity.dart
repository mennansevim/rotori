/// Biletli etkinliklerin planlama sırasında kullanacağı güvenli varsayılanlar.
///
/// Başlık eşleştirmesi yalnızca kullanıcıya başlangıç değeri sunar. Asıl
/// sabitlik, TimelineItem üzerindeki açık ticketedEvent kilidinden gelir.
class TicketedActivityDefaults {
  const TicketedActivityDefaults({
    required this.durationMinutes,
    required this.arrivalBufferMinutes,
    this.fullDay = false,
  });

  final int durationMinutes;
  final int arrivalBufferMinutes;
  final bool fullDay;
}

const TicketedActivityDefaults kDefaultTicketedActivity =
    TicketedActivityDefaults(
  durationMinutes: 120,
  arrivalBufferMinutes: 30,
);

TicketedActivityDefaults ticketedActivityDefaultsForTitle(String title) {
  final normalized = title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  if (normalized.contains('universal studios') ||
      RegExp(r'(^|\W)usj($|\W)').hasMatch(normalized) ||
      normalized.contains('disneyland') ||
      normalized.contains('disneysea') ||
      normalized.contains('disney sea')) {
    return const TicketedActivityDefaults(
      durationMinutes: 12 * 60,
      arrivalBufferMinutes: 60,
      fullDay: true,
    );
  }

  if (normalized.contains('teamlab borderless') ||
      normalized.contains('team lab borderless')) {
    return const TicketedActivityDefaults(
      durationMinutes: 4 * 60,
      arrivalBufferMinutes: 30,
    );
  }

  if (normalized.contains('teamlab planets') ||
      normalized.contains('team lab planets')) {
    return const TicketedActivityDefaults(
      durationMinutes: 3 * 60,
      arrivalBufferMinutes: 30,
    );
  }

  if ((normalized.contains('teamlab') || normalized.contains('team lab')) &&
      normalized.contains('botanical')) {
    return const TicketedActivityDefaults(
      durationMinutes: 2 * 60,
      arrivalBufferMinutes: 30,
    );
  }

  return kDefaultTicketedActivity;
}
