// lib/services/commute_memory_service.dart
//
// Silently learns from the user's reporting behaviour.
// Every time a report is submitted, call recordReport(route, stop).
// The service counts how many times each route was used and exposes
// the top-3 as "usual routes" — all stored locally, never on Supabase.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CommuteMemoryService {
  CommuteMemoryService._();
  static final instance = CommuteMemoryService._();

  static const _kKey = 'commute_memory_v1';

  // ── Public API ────────────────────────────────────────────────────

  /// Call this every time the user successfully submits a crowding report.
  Future<void> recordReport(String route, String stop) async {
    final data = await _load();
    final key = route.trim().toUpperCase();
    final entry = data[key] ?? _RouteMemory(route: route, stop: stop);
    entry.count += 1;
    entry.lastStop = stop;
    entry.lastSeen = DateTime.now();
    data[key] = entry;
    await _save(data);
  }

  /// Returns up to 3 routes the user reports most often, sorted by count desc.
  Future<List<_RouteMemory>> getUsualRoutes() async {
    final data = await _load();
    final sorted = data.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return sorted.take(3).toList();
  }

  /// Clears all stored memory (useful for a settings reset).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }

  // ── Internal helpers ──────────────────────────────────────────────

  Future<Map<String, _RouteMemory>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(k, _RouteMemory.fromJson(v as Map<String, dynamic>)),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, _RouteMemory> data) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      data.map((k, v) => MapEntry(k, v.toJson())),
    );
    await prefs.setString(_kKey, encoded);
  }
}

// ── Model (internal only) ─────────────────────────────────────────

class _RouteMemory {
  final String route;
  String lastStop;
  int count = 0;
  DateTime lastSeen;

  _RouteMemory({
    required this.route,
    required String stop,
  })  : lastStop = stop,
        lastSeen = DateTime.now();

  factory _RouteMemory.fromJson(Map<String, dynamic> j) => _RouteMemory(
        route: j['route'] as String,
        stop: j['lastStop'] as String? ?? '',
      )
        ..count = (j['count'] as int? ?? 0)
        ..lastSeen = DateTime.tryParse(j['lastSeen'] as String? ?? '') ??
            DateTime.now();

  Map<String, dynamic> toJson() => {
        'route': route,
        'lastStop': lastStop,
        'count': count,
        'lastSeen': lastSeen.toIso8601String(),
      };
}

// ── Public model for UI ───────────────────────────────────────────

class UsualRoute {
  final String route;
  final String lastStop;
  final int reportCount;

  const UsualRoute({
    required this.route,
    required this.lastStop,
    required this.reportCount,
  });
}

extension UsualRouteMapper on _RouteMemory {
  UsualRoute toPublic() => UsualRoute(
        route: route,
        lastStop: lastStop,
        reportCount: count,
      );
}