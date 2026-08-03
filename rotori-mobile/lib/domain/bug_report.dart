import 'dart:convert';

import 'types.dart';

enum BugReportCategory { planning, schedule, save, ui, other }

extension BugReportCategoryX on BugReportCategory {
  String get wireName => name;
}

class BugReport {
  const BugReport({
    required this.message,
    required this.category,
    required this.planId,
    required this.context,
    this.contactEmail,
  });

  final String message;
  final BugReportCategory category;
  final String? planId;
  final String? contactEmail;
  final Map<String, Object?> context;

  Map<String, Object?> toJson() => {
        'category': category.wireName,
        'message': message.trim(),
        if (planId != null && planId!.isNotEmpty) 'plan_id': planId,
        if (contactEmail != null && contactEmail!.trim().isNotEmpty)
          'contact_email': contactEmail!.trim(),
        'context': context,
      };

  /// Kullanıcı planının tanı için yeterli, kişisel olmayan özetini üretir.
  static Map<String, Object?> contextForTrip({
    required Trip trip,
    required String planId,
    required String appVersion,
    required String platform,
    required String locale,
    int? activeDay,
  }) {
    final itemCount = trip.days.fold<int>(
      0,
      (sum, day) => sum + day.items.length,
    );
    return {
      'schemaVersion': 1,
      'appVersion': appVersion,
      'platform': platform,
      'locale': locale,
      'planId': planId,
      'dayCount': trip.days.length,
      'activeDay': activeDay,
      'destinations': [
        for (final destination in trip.preferences.destinations)
          {
            'city': destination.city,
            'countryCode': destination.countryCode,
          },
      ],
      'days': [
        for (final day in trip.days)
          {
            'dayNumber': day.dayNumber,
            'date': day.date,
            'itemCount': day.items.length,
            'items': [
              for (final item in day.items)
                {
                  'id': item.id,
                  'time': item.time ?? item.scheduledTime,
                  'durationMin': item.durationMin,
                  'kind': item.kind?.name,
                  'cityId': item.cityId,
                },
            ],
          },
      ],
      'itemCount': itemCount,
    };
  }

  String contextJson() => jsonEncode(context);
}
