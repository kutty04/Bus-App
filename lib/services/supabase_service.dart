import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;
  static const _table = 'crowding_reports';
  static const _safetyTable = 'safety_reports'; // ← NEW

  // ─── Fetch live feed (last 30 mins) ───────────────────────────────────────
  static Future<List<CrowdingReport>> fetchFeed({String? timeFilter}) async {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 30));

    final data = await _client
        .from(_table)
        .select()
        .gte('timestamp', cutoff.toIso8601String())
        .order('timestamp', ascending: false)
        .limit(100);

    final reports = (data as List).map((e) => CrowdingReport.fromJson(e)).toList();
    return _applyTimeFilter(reports, timeFilter);
  }

  // ─── Fetch by route (last 30 mins) ────────────────────────────────────────
  static Future<List<CrowdingReport>> fetchByRoute(String busRoute, {String? timeFilter}) async {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 30));

    final data = await _client
        .from(_table)
        .select()
        .eq('bus_route', busRoute)
        .gte('timestamp', cutoff.toIso8601String())
        .order('timestamp', ascending: false);

    final reports = (data as List).map((e) => CrowdingReport.fromJson(e)).toList();
    return _applyTimeFilter(reports, timeFilter);
  }

  // ─── Fetch near a stop ────────────────────────────────────────────────────
  static Future<List<CrowdingReport>> fetchNearStop(String stopName, {String? timeFilter}) async {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 30));

    final data = await _client
        .from(_table)
        .select()
        .ilike('boarding_stop', '%$stopName%')
        .gte('timestamp', cutoff.toIso8601String())
        .order('timestamp', ascending: false);

    final reports = (data as List).map((e) => CrowdingReport.fromJson(e)).toList();
    return _applyTimeFilter(reports, timeFilter);
  }

  // ─── Submit a crowding report ─────────────────────────────────────────────
  static Future<void> submitReport({
    required String busRoute,
    required int crowdingLevel,
    required String boardingStop,
    required String reporterName,
    required bool justLeft,
    required bool isAc,
    bool? isLadiesBus,   // ← NEW: nullable — null means user didn't answer
    double? latitude,
    double? longitude,
  }) async {
    await _client.from(_table).insert({
      'bus_route': busRoute,
      'crowding_level': crowdingLevel,
      'boarding_stop': boardingStop,
      'reporter_name': reporterName,
      'just_left': justLeft,
      'is_ac': isAc,
      'is_ladies_bus': isLadiesBus,  // ← NEW: null is fine, Supabase stores as NULL
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'helpful_count': 0,
      'view_count': 0,
    });
  }

  // ─── NEW: Submit a safety report (always anonymous) ───────────────────────
  static Future<void> submitSafetyReport({
    required String busRoute,
    required String boardingStop,
    required String concernType,
  }) async {
    await _client.from(_safetyTable).insert({
      'bus_route': busRoute,
      'boarding_stop': boardingStop,
      'concern_type': concernType,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      // No reporter_name — anonymous by design
    });
  }

  // ─── NEW: Fetch safety warnings for a route (last 1 hour) ─────────────────
  // Use this on the feed screen to show "⚠️ 2 concerns flagged on Route 19C"
  static Future<int> fetchSafetyFlagCount(String busRoute) async {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 1));

    final data = await _client
        .from(_safetyTable)
        .select()
        .eq('bus_route', busRoute)
        .gte('timestamp', cutoff.toIso8601String());

    return (data as List).length;
  }

  // ─── Mark helpful ─────────────────────────────────────────────────────────
  static Future<void> markHelpful(int reportId) async {
    await _client.rpc('increment_helpful', params: {'report_id': reportId});
  }

  // ─── Realtime subscription ────────────────────────────────────────────────
  static RealtimeChannel subscribeToReports(void Function() onUpdate) {
    return _client
        .channel('crowding-feed')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _table,
          callback: (_) => onUpdate(),
        )
        .subscribe();
  }

  // ─── IST time filter helper ───────────────────────────────────────────────
  static List<CrowdingReport> _applyTimeFilter(
      List<CrowdingReport> reports, String? filter) {
    if (filter == null) return reports;
    return reports.where((r) {
      final ist = r.timestamp.toUtc().add(const Duration(hours: 5, minutes: 30));
      final isMorning = ist.hour < 12;
      return filter == 'morning' ? isMorning : !isMorning;
    }).toList();
  }
}