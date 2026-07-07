// iOS/Android yerel bildirim servisi.
// Bileti satışa açılacağı sabah 09:00'da kanal/badge ile hatırlatır.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'notifications_service.dart';
import '../../data/reminders_store.dart';

NotificationsService makeNotificationsService() => _IoService();

class _IoService implements NotificationsService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  @override
  Future<void> init() async {
    if (_inited) return;
    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(const InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    ));
    _inited = true;
  }

  @override
  Future<bool> requestPermissionIfNeeded() async {
    await init();
    try {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final ok = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        if (ok == true) return true;
      }
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final ok = await android.requestNotificationsPermission();
        return ok ?? true;
      }
      return true;
    } catch (e) {
      debugPrint('notifications permission error: $e');
      return false;
    }
  }

  @override
  Future<void> schedule(Reminder r) async {
    await init();

    final when = tz.TZDateTime.from(r.fireAt, tz.local);
    // Geçmişteki tarihler için schedule yapma.
    if (when.isBefore(tz.TZDateTime.now(tz.local))) return;

    const androidDetails = AndroidNotificationDetails(
      'ticket_windows',
      'Bilet açılış hatırlatmaları',
      channelDescription: 'USJ / Disney / Shinkansen bilet açılış tarihleri.',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.zonedSchedule(
      r.notificationId,
      '${r.icon} ${r.title}',
      r.subtitle.isEmpty ? r.tip : r.subtitle,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  @override
  Future<void> cancel(Reminder r) async {
    await init();
    await _plugin.cancel(r.notificationId);
  }

  @override
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
