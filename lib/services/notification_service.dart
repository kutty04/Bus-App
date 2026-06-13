import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  late tz.Location _ist;

  static const int _id6am          = 1;
  static const int _id7am          = 2;
  static const int _id8am          = 3;
  static const int _id10am         = 4;
  static const int _id2pm          = 5;
  static const int _id4pm          = 6;
  static const int _id6pm          = 7;
  static const int _idPostJourney  = 99;
  // FIX: ID for the mid-journey check-in nudge notification
  static const int _idCheckinNudge = 100;

  Future<void> init() async {
    tz_data.initializeTimeZones();
    _ist = tz.getLocation('Asia/Kolkata');
    tz.setLocalLocation(_ist);

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onTap,
    );
  }

  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return false;
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<void> scheduleAllReminders() async {
    await _scheduleDailyAt(
      id: _id6am, hour: 6, minute: 0,
      title: '🚌 Morning commute?',
      body: 'Report how crowded your bus is and help others plan their ride!',
    );
    await _scheduleDailyAt(
      id: _id7am, hour: 7, minute: 0,
      title: '🚌 Peak hour starting!',
      body: 'Buses filling up fast — 10 seconds to report your crowding.',
    );
    await _scheduleDailyAt(
      id: _id8am, hour: 8, minute: 0,
      title: '🚌 Rush hour is here',
      body: 'How packed is your bus right now? Tap to report.',
    );
    await _scheduleDailyAt(
      id: _id10am, hour: 10, minute: 0,
      title: '🚌 Mid-morning check',
      body: 'Still on the move? Let Chennai know how crowded it is.',
    );
    await _scheduleDailyAt(
      id: _id2pm, hour: 14, minute: 0,
      title: '🚌 Afternoon buses',
      body: 'Heading somewhere? Report crowding and help fellow commuters.',
    );
    await _scheduleDailyAt(
      id: _id4pm, hour: 16, minute: 0,
      title: '🚌 Evening rush building',
      body: 'Buses are getting busy. How crowded is yours?',
    );
    await _scheduleDailyAt(
      id: _id6pm, hour: 18, minute: 0,
      title: '🚌 Evening peak!',
      body: 'Peak hour in full swing — tap to report your bus crowding.',
    );
  }

  Future<void> schedulePostJourneyNudge() async {
    await _plugin.cancel(_idPostJourney);
    // Also cancel any pending check-in nudge when journey ends
    await _plugin.cancel(_idCheckinNudge);

    final fireAt = tz.TZDateTime.now(_ist).add(const Duration(minutes: 5));
    await _plugin.zonedSchedule(
      _idPostJourney,
      '🚌 How was your ride?',
      'Your journey just ended. Tap to leave feedback!',
      fireAt,
      _channelDetails(),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'post_journey',
    );
  }

  // FIX: Show an immediate heads-up notification when the 5-min fallback
  // timer fires but JourneyScreen is not open (callback is null).
  // This is the real phone notification that pings the user.
  Future<void> showCheckinNudge({required String routeNo}) async {
    await _plugin.cancel(_idCheckinNudge);
    await _plugin.show(
      _idCheckinNudge,
      '🚌 Quick check-in needed!',
      'Route $routeNo — how crowded is it now? Tap to update.',
      _checkinChannelDetails(),
      payload: 'checkin_nudge',
    );
  }

  Future<void> cancelCheckinNudge() async {
    await _plugin.cancel(_idCheckinNudge);
  }

  Future<void> cancelAllReminders() async {
    for (final id in [
      _id6am, _id7am, _id8am, _id10am, _id2pm, _id4pm, _id6pm
    ]) {
      await _plugin.cancel(id);
    }
  }

  Future<void> _scheduleDailyAt({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    await _plugin.cancel(id);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      _nextInstanceOf(hour, minute),
      _channelDetails(),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(_ist);
    var t = tz.TZDateTime(_ist, now.year, now.month, now.day, hour, minute);
    if (t.isBefore(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  NotificationDetails _channelDetails() {
    const android = AndroidNotificationDetails(
      'chennai_bus_reminders',
      'Bus Crowding Reminders',
      channelDescription: 'Daily reminders to report bus crowding',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    return const NotificationDetails(android: android);
  }

  // FIX: Separate high-priority channel for mid-journey check-ins.
  // Using Importance.max + fullScreenIntent: true makes it appear as a
  // heads-up banner even when the phone screen is on.
  NotificationDetails _checkinChannelDetails() {
    const android = AndroidNotificationDetails(
      'chennai_bus_checkin',
      'Journey Check-ins',
      channelDescription: 'Mid-journey crowding check-in prompts',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      fullScreenIntent: false,
      playSound: true,
      enableVibration: true,
    );
    return const NotificationDetails(android: android);
  }

  void _onTap(NotificationResponse response) {
    if (response.payload == 'post_journey') {
      postJourneyFeedbackNotifier.value = true;
    } else if (response.payload == 'checkin_nudge') {
      // FIX: Open journey screen when user taps the check-in nudge
      checkinNudgeTappedNotifier.value = true;
    } else {
      reportTabNotifier.value = 2;
    }
  }
}

final GlobalKey<NavigatorState> notificationNavigatorKey =
    GlobalKey<NavigatorState>();

final ValueNotifier<int>  reportTabNotifier            = ValueNotifier<int>(-1);
final ValueNotifier<bool> postJourneyFeedbackNotifier  = ValueNotifier<bool>(false);
final ValueNotifier<bool> contributeTabNotifier        = ValueNotifier<bool>(false);
// FIX: Fires when user taps the mid-journey check-in nudge notification
final ValueNotifier<bool> checkinNudgeTappedNotifier   = ValueNotifier<bool>(false);