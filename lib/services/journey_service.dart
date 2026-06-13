// lib/services/journey_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/mtc_data.dart';
import 'notification_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class ActiveJourney {
  final String id;
  final String routeNo;
  final String startStop;
  final String deviceId;
  final DateTime startedAt;

  ActiveJourney({
    required this.id,
    required this.routeNo,
    required this.startStop,
    required this.deviceId,
    required this.startedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'route_no': routeNo,
        'start_stop': startStop,
        'device_id': deviceId,
        'started_at': startedAt.toIso8601String(),
      };

  factory ActiveJourney.fromMap(Map<String, dynamic> map) => ActiveJourney(
        id: map['id'],
        routeNo: map['route_no'],
        startStop: map['start_stop'],
        deviceId: map['device_id'],
        startedAt: DateTime.parse(map['started_at']),
      );
}

class JourneyCheckin {
  final String stopName;
  final String crowdingLevel;
  final DateTime timestamp;

  JourneyCheckin({
    required this.stopName,
    required this.crowdingLevel,
    required this.timestamp,
  });
}

typedef CheckinCallback = Future<void> Function({
  required String suggestedStop,
  required bool gpsTriggered,
});

// ─────────────────────────────────────────────────────────────────────────────
// JourneyService
// ─────────────────────────────────────────────────────────────────────────────

class JourneyService extends ChangeNotifier {
  JourneyService();

  ActiveJourney? _activeJourney;
  ActiveJourney? get activeJourney => _activeJourney;
  bool get hasActiveJourney => _activeJourney != null;

  int _journeySeconds = 0;
  int get journeySeconds => _journeySeconds;

  final List<JourneyCheckin> _checkins = [];
  List<JourneyCheckin> get checkins => List.unmodifiable(_checkins);

  bool _checkinPending = false;
  bool get checkinPending => _checkinPending;

  String _currentStopGuess = '';
  String get currentStopGuess => _currentStopGuess;

  Timer? _durationTimer;
  Timer? _fallbackCheckinTimer;
  Timer? _stationaryAutoEndTimer;

  Position? _lastCheckinPosition;
  Position? _lastKnownPosition;
  int _stationarySeconds = 0;

  int _gpsFailStreak = 0;
  static const int _maxGpsFailsBeforeSkipAutoEnd = 3;

  bool _checkinInProgress = false;
  CheckinCallback? _checkinCallback;

  static const double _checkinDistanceMeters = 500.0;
  static const int _fallbackCheckinMinutes = 5;
  static const int _autoEndMinutes = 10;

  final _supabase = Supabase.instance.client;

  void registerCheckinCallback(CheckinCallback cb) {
    _checkinCallback = cb;
    // FIX: If there was a pending check-in waiting for the screen to open,
    // trigger it immediately now that the screen is registered.
    if (_checkinPending && !_checkinInProgress) {
      Future.microtask(() => _triggerCheckin(gpsTriggered: false));
    }
  }

  void unregisterCheckinCallback() => _checkinCallback = null;

  // ─────────────────────────────────────────────────────────────────────────
  // Restore on app launch
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> restoreJourney() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('active_journey');
    if (raw == null) return;

    try {
      final map = _decodePrefs(raw);
      if (map.isEmpty) return;
      _activeJourney = ActiveJourney.fromMap(map);
      _journeySeconds =
          DateTime.now().difference(_activeJourney!.startedAt).inSeconds;
      _startAllTimers();
      notifyListeners();
    } catch (_) {
      await prefs.remove('active_journey');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Start Journey
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> startJourney({
    required String routeNo,
    required String startStop,
    required String deviceId,
  }) async {
    if (_activeJourney != null) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final journey = ActiveJourney(
      id: id,
      routeNo: routeNo,
      startStop: startStop,
      deviceId: deviceId,
      startedAt: DateTime.now(),
    );

    try {
      await _supabase.from('journeys').insert({
        'id': id,
        'route_no': routeNo,
        'start_stop': startStop,
        'device_id': deviceId,
        'started_at': journey.startedAt.toIso8601String(),
        'status': 'active',
      });
    } catch (e) {
      debugPrint('Journey insert error: $e');
    }

    _activeJourney = journey;
    _journeySeconds = 0;
    _stationarySeconds = 0;
    _gpsFailStreak = 0;
    _checkins.clear();
    _currentStopGuess = startStop;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_journey', _encodePrefs(journey.toMap()));

    _captureInitialPosition();
    _startAllTimers();
    notifyListeners();
  }

  Future<void> _captureInitialPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      _lastCheckinPosition = pos;
      _lastKnownPosition = pos;
      _gpsFailStreak = 0;
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // End Journey
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> endJourney({String? endStop}) async {
    if (_activeJourney == null) return;

    final journey = _activeJourney!;
    _cancelAllTimers();

    try {
      await _supabase.from('journeys').update({
        'end_stop': endStop,
        'ended_at': DateTime.now().toIso8601String(),
        'duration_seconds': _journeySeconds,
        'status': 'completed',
      }).eq('id', journey.id);
    } catch (e) {
      debugPrint('Journey end error: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_journey');

    await NotificationService().schedulePostJourneyNudge();

    _activeJourney = null;
    _journeySeconds = 0;
    _stationarySeconds = 0;
    _gpsFailStreak = 0;
    _lastCheckinPosition = null;
    _lastKnownPosition = null;
    _checkins.clear();
    _checkinPending = false;
    _checkinInProgress = false;
    _checkinCallback = null;

    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Submit check-in
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> submitCheckin({
    required String stopName,
    required String crowdingLevel,
  }) async {
    if (_activeJourney == null) return;

    final now = DateTime.now();

    try {
      await _supabase.from('crowding_reports').insert({
        'route_no': _activeJourney!.routeNo,
        'stop_name': stopName,
        'crowding_level': int.tryParse(crowdingLevel) ?? 50,
        'device_id': _activeJourney!.deviceId,
        'created_at': now.toIso8601String(),
        'source': 'journey_checkin',
      });
    } catch (e) {
      debugPrint('Checkin insert error: $e');
    }

    try {
      await _supabase.from('journey_checkins').insert({
        'journey_id': _activeJourney!.id,
        'route_no': _activeJourney!.routeNo,
        'stop_name': stopName,
        'crowding_level': int.tryParse(crowdingLevel) ?? 50,
        'device_id': _activeJourney!.deviceId,
        'created_at': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Journey checkin insert error: $e');
    }

    _currentStopGuess = stopName;
    _checkins.add(JourneyCheckin(
      stopName: stopName,
      crowdingLevel: crowdingLevel,
      timestamp: now,
    ));

    if (_lastKnownPosition != null) {
      _lastCheckinPosition = _lastKnownPosition;
    }

    // FIX: Cancel any pending check-in nudge notification since user just checked in
    await NotificationService().cancelCheckinNudge();

    _resetFallbackTimer();
    _checkinInProgress = false;
    _checkinPending = false;
    notifyListeners();
  }

  void dismissCheckin() {
    _checkinInProgress = false;
    _checkinPending = false;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Timers
  // ─────────────────────────────────────────────────────────────────────────

  void _startAllTimers() {
    _cancelAllTimers();

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _journeySeconds++;
      notifyListeners();
    });

    Timer.periodic(const Duration(seconds: 30), (t) async {
      if (_activeJourney == null) {
        t.cancel();
        return;
      }
      await _checkGpsAndMaybeCheckin();
    });

    _resetFallbackTimer();
  }

  void _resetFallbackTimer() {
    _fallbackCheckinTimer?.cancel();
    _fallbackCheckinTimer = Timer(
      const Duration(minutes: _fallbackCheckinMinutes),
      () async {
        if (_activeJourney == null) return;
        if (!_checkinInProgress) {
          await _triggerCheckin(gpsTriggered: false);
        }
        _resetFallbackTimer();
      },
    );
  }

  void _cancelAllTimers() {
    _durationTimer?.cancel();
    _fallbackCheckinTimer?.cancel();
    _stationaryAutoEndTimer?.cancel();
    _durationTimer = null;
    _fallbackCheckinTimer = null;
    _stationaryAutoEndTimer = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GPS check
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkGpsAndMaybeCheckin() async {
    if (_checkinInProgress) return;

    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 8));
      _gpsFailStreak = 0;
    } catch (_) {
      _gpsFailStreak++;
      debugPrint('GPS fail streak: $_gpsFailStreak');

      if (_gpsFailStreak >= _maxGpsFailsBeforeSkipAutoEnd) {
        debugPrint('GPS unreliable — skipping auto-end check');
        return;
      }

      _stationarySeconds += 30;
      await _checkAutoEnd();
      return;
    }

    _lastKnownPosition = pos;

    if (_lastCheckinPosition != null) {
      final dist = Geolocator.distanceBetween(
        _lastCheckinPosition!.latitude,
        _lastCheckinPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );

      if (dist >= _checkinDistanceMeters) {
        _stationarySeconds = 0;
        await _triggerCheckin(gpsTriggered: true, currentPos: pos);
      } else {
        _stationarySeconds += 30;
        await _checkAutoEnd();
      }
    } else {
      _lastCheckinPosition = pos;
      _stationarySeconds = 0;
    }
  }

  Future<void> _checkAutoEnd() async {
    if (_gpsFailStreak >= _maxGpsFailsBeforeSkipAutoEnd) {
      debugPrint('GPS unreliable — auto-end suppressed');
      return;
    }

    if (_stationarySeconds >= _autoEndMinutes * 60) {
      debugPrint('Auto-ending journey: stationary for $_autoEndMinutes min');
      await endJourney();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Trigger check-in prompt
  // FIX: If JourneyScreen is open → show bottom sheet via callback (old behaviour).
  //      If JourneyScreen is closed → fire a real phone notification instead.
  //      This is what was missing — the crash happened when the callback
  //      tried to use a disposed Navigator context.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _triggerCheckin({
    required bool gpsTriggered,
    Position? currentPos,
  }) async {
    if (_checkinInProgress || _activeJourney == null) return;

    _checkinInProgress = true;
    _checkinPending = true;

    String suggestedStop = _currentStopGuess;
    if (currentPos != null) {
      final nearest = _findNearestStop(currentPos);
      if (nearest != null) suggestedStop = nearest;
    }

    _currentStopGuess = suggestedStop;
    notifyListeners();

    if (_checkinCallback != null) {
      // JourneyScreen is open — show the in-app bottom sheet
      try {
        await _checkinCallback!(
          suggestedStop: suggestedStop,
          gpsTriggered: gpsTriggered,
        );
      } catch (e) {
        debugPrint('Checkin callback error: $e');
        _checkinInProgress = false;
        _checkinPending = false;
      }
    } else {
      // FIX: JourneyScreen is NOT open (or was disposed) — fire a real
      // phone notification so the user gets pinged even from their home screen.
      // When they tap it, checkinNudgeTappedNotifier fires, main.dart opens
      // the journey screen, and registerCheckinCallback() is called, which
      // then immediately shows the sheet (see registerCheckinCallback above).
      _checkinInProgress = false; // allow re-trigger after notification tap
      await NotificationService().showCheckinNudge(
        routeNo: _activeJourney!.routeNo,
      );
    }
  }

  String? _findNearestStop(Position pos) {
    BusStop? nearest;
    double bestDist = double.infinity;

    for (final route in kMtcRoutes) {
      for (final stop in route.stops) {
        final d = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          stop.lat,
          stop.lng,
        );
        if (d < bestDist) {
          bestDist = d;
          nearest = stop;
        }
      }
    }

    return (nearest != null && bestDist < 800) ? nearest.name : null;
  }

  String get formattedDuration {
    final h = _journeySeconds ~/ 3600;
    final m = (_journeySeconds % 3600) ~/ 60;
    final s = _journeySeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Map<String, dynamic> _decodePrefs(String raw) {
    final map = <String, dynamic>{};
    for (final part in raw.split(';;')) {
      final idx = part.indexOf('::');
      if (idx == -1) continue;
      map[part.substring(0, idx)] = part.substring(idx + 2);
    }
    return map;
  }

  String _encodePrefs(Map<String, dynamic> map) =>
      map.entries.map((e) => '${e.key}::${e.value}').join(';;');
}