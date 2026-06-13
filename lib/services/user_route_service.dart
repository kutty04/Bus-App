// lib/services/user_route_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class UserRoute {
  final String id;
  final String routeNo;
  final String startStop;
  final String endStop;
  final List<String>? additionalStops;
  final DateTime createdAt;

  UserRoute({
    required this.id,
    required this.routeNo,
    required this.startStop,
    required this.endStop,
    this.additionalStops,
    required this.createdAt,
  });

  factory UserRoute.fromJson(Map<String, dynamic> json) {
    return UserRoute(
      id: json['id'].toString(),
      routeNo: json['route_no'] as String,
      startStop: json['start_stop'] as String,
      endStop: json['end_stop'] as String,
      additionalStops: json['additional_stops'] != null
          ? List<String>.from(json['additional_stops'])
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class UserRouteService {
  static final _db = Supabase.instance.client;

  /// Add a full community route (basic or detailed)
  static Future<UserRoute> addRoute({
    required String routeNo,
    required String startStop,
    required String endStop,
    List<String>? additionalStops,
  }) async {
    final response = await _db
        .from('user_routes')
        .insert({
          'route_no': routeNo.toUpperCase(),
          'start_stop': startStop,
          'end_stop': endStop,
          'additional_stops': additionalStops,
          'entry_type': 'full_route',
        })
        .select()
        .single();

    return UserRoute.fromJson(response);
  }

  /// Report a missing stop on an existing route
  static Future<void> addMissingStop({
    required String routeNo,
    required String missingStop,
    String? afterStop,
  }) async {
    await _db.from('user_routes').insert({
      'route_no': routeNo.toUpperCase(),
      'start_stop': missingStop,
      'end_stop': missingStop,
      'entry_type': 'missing_stop',
      'after_stop': afterStop,
    });
  }

  /// Search community routes by route number
  static Future<List<UserRoute>> searchByRouteNo(String query) async {
    final response = await _db
        .from('user_routes')
        .select()
        .ilike('route_no', '%$query%')
        .eq('entry_type', 'full_route')
        .limit(10);

    return (response as List)
        .map((json) => UserRoute.fromJson(json))
        .toList();
  }

  /// Get all community routes
  static Future<List<UserRoute>> getAllRoutes() async {
    final response = await _db
        .from('user_routes')
        .select()
        .eq('entry_type', 'full_route')
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => UserRoute.fromJson(json))
        .toList();
  }

  /// Search community routes whose stop names match the query.
  /// Checks start_stop, end_stop, and additional_stops.
  static Future<List<({String routeNo, String stopName})>> searchByStopName(
      String query) async {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();

    final response = await _db
        .from('user_routes')
        .select()
        .eq('entry_type', 'full_route');

    final results = <({String routeNo, String stopName})>[];
    final seen = <String>{};

    for (final row in (response as List)) {
      final routeNo = row['route_no'] as String;
      final allStops = <String>[
        row['start_stop'] as String,
        row['end_stop'] as String,
        if (row['additional_stops'] != null)
          ...List<String>.from(row['additional_stops']),
      ];
      for (final stop in allStops) {
        if (stop.toLowerCase().contains(q)) {
          final key = '$routeNo|$stop';
          if (seen.add(key)) {
            results.add((routeNo: routeNo, stopName: stop));
          }
        }
      }
    }
    return results;
  }

  /// Search community routes by partial route number — merges with MTC suggestions.
  static Future<List<String>> searchRouteNumbers(String query) async {
    if (query.trim().isEmpty) return [];
    final response = await _db
        .from('user_routes')
        .select('route_no')
        .ilike('route_no', '%${query.trim()}%')
        .eq('entry_type', 'full_route')
        .limit(10);

    final seen = <String>{};
    return (response as List)
        .map((r) => r['route_no'] as String)
        .where(seen.add)
        .toList();
  }
}