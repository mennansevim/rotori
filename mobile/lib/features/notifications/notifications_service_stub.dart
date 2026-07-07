// Web derlemesi için no-op stub. flutter_local_notifications web'i desteklemiyor.

import 'notifications_service.dart';
import '../../data/reminders_store.dart';

NotificationsService makeNotificationsService() => _NoopService();

class _NoopService implements NotificationsService {
  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermissionIfNeeded() async => true;

  @override
  Future<void> schedule(Reminder reminder) async {}

  @override
  Future<void> cancel(Reminder reminder) async {}

  @override
  Future<void> cancelAll() async {}
}
