import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Crowding prediction result from the ML model
class CrowdingPrediction {
  final String label;    // 'low' | 'medium' | 'high'
  final int pct;         // 20 | 50 | 90
  final double confidence; // 0.0 – 1.0
  final bool isMLPrediction; // false = fallback to historical pattern

  const CrowdingPrediction({
    required this.label,
    required this.pct,
    required this.confidence,
    required this.isMLPrediction,
  });

  /// Human-readable string shown in the UI
  String get displayText {
    final timeLabel = _timeLabel();
    switch (label) {
      case 'high':
        return 'Usually packed $timeLabel';
      case 'medium':
        return 'Usually moderate $timeLabel';
      default:
        return 'Usually light $timeLabel';
    }
  }

  String _timeLabel() {
    final h = DateTime.now().hour;
    if (h >= 7 && h <= 9) return 'during morning peak';
    if (h >= 17 && h <= 19) return 'during evening peak';
    if (h >= 10 && h <= 16) return 'during midday';
    return 'at this hour';
  }

  /// Crowding color for UI (same as your existing crowding card)
  String get colorHex {
    switch (label) {
      case 'high':   return '#FF4444';
      case 'medium': return '#FFA500';
      default:       return '#4CAF50';
    }
  }
}

/// Service that loads model_rules.json and predicts crowding
/// Place model_rules.json in assets/data/model_rules.json
class PredictionService {
  static PredictionService? _instance;
  Map<String, dynamic>? _rules;
  bool _loaded = false;

  PredictionService._();

  static PredictionService get instance {
    _instance ??= PredictionService._();
    return _instance!;
  }

  /// Call once at app start (in main.dart after Supabase init)
  Future<void> init() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('lib/data/model_rules.json');
      _rules = json.decode(raw) as Map<String, dynamic>;
      _loaded = true;
      debugPrint('[PredictionService] Loaded ${_rules!.length} routes');
    } catch (e) {
      debugPrint('[PredictionService] Failed to load model_rules.json: $e');
    }
  }

  /// Predict crowding for a route at a given time
  /// [route]     — e.g. '19', '102', 'MAA2'
  /// [direction] — 'DOWN' or 'UP'
  /// [at]        — DateTime (defaults to now)
  CrowdingPrediction? predict({
    required String route,
    String direction = 'DOWN',
    DateTime? at,
  }) {
    if (!_loaded || _rules == null) return null;

    final now = at ?? DateTime.now();
    final hour = now.hour;
    final day = now.weekday - 1; // Dart: 1=Mon → 0=Mon

    // Normalize route name
    final routeKey = route.trim().toUpperCase();

    try {
      final routeData = _rules![routeKey] as Map<String, dynamic>?;
      if (routeData == null) return _fallback(routeKey, hour, day);

      final dirData = routeData[direction] as Map<String, dynamic>?
          ?? routeData['DOWN'] as Map<String, dynamic>?;
      if (dirData == null) return _fallback(routeKey, hour, day);

      final hourData = dirData[hour.toString()] as Map<String, dynamic>?;
      if (hourData == null) return _fallback(routeKey, hour, day);

      final dayData = hourData[day.toString()] as Map<String, dynamic>?;
      if (dayData == null) return _fallback(routeKey, hour, day);

      return CrowdingPrediction(
        label: dayData['label'] as String,
        pct: (dayData['pct'] as num).toInt(),
        confidence: (dayData['confidence'] as num).toDouble(),
        isMLPrediction: true,
      );
    } catch (e) {
      debugPrint('[PredictionService] Error predicting for $routeKey: $e');
      return _fallback(routeKey, hour, day);
    }
  }

  /// Fallback: rule-based prediction when ML lookup fails
  CrowdingPrediction _fallback(String route, int hour, int day) {
    final isWeekend = day >= 5;
    final isPeakAm = hour >= 7 && hour <= 9;
    final isPeakPm = hour >= 17 && hour <= 19;

    if (isWeekend) {
      return const CrowdingPrediction(
        label: 'low', pct: 20, confidence: 0.6, isMLPrediction: false,
      );
    }

    if (isPeakAm || isPeakPm) {
      // IT corridor routes are always packed
      final isItRoute = ['19', '19A', '570', '570S', '95', '102',
                         '102C', '519T', '99'].contains(route);
      return CrowdingPrediction(
        label: 'high',
        pct: 90,
        confidence: isItRoute ? 0.85 : 0.70,
        isMLPrediction: false,
      );
    }

    return const CrowdingPrediction(
      label: 'low', pct: 20, confidence: 0.65, isMLPrediction: false,
    );
  }

  /// Check if a route has ML data
  bool hasRoute(String route) {
    return _loaded && _rules != null &&
        _rules!.containsKey(route.trim().toUpperCase());
  }
}
