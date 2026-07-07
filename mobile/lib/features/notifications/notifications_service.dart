// Bilet hatırlatmaları için yerel bildirim servisi.
// Mobilde flutter_local_notifications + timezone kullanır; web'de no-op.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications_service_stub.dart'
    if (dart.library.io) 'notifications_service_io.dart';

import '../../data/reminders_store.dart';

abstract class NotificationsService {
  Future<void> init();
  Future<bool> requestPermissionIfNeeded();
  Future<void> schedule(Reminder reminder);
  Future<void> cancel(Reminder reminder);
  Future<void> cancelAll();
}

/// Platforma özel implementasyon — conditional import ile seçilir.
NotificationsService createNotificationsService() => makeNotificationsService();

final notificationsServiceProvider = Provider<NotificationsService>((ref) {
  final svc = createNotificationsService();
  // Tetiklendiğinde bir kez init olsun; permission ilk kullanımda istenir.
  svc.init();
  return svc;
});
