// lib/services/bus_lookup_service.dart
//
// Finds MTC routes between origin and destination.
// Supports:
//   • Direct routes  — single bus, no change
//   • Transfer routes — 1 bus change at an intermediate stop
//
// Algorithm (direct):
//   1. Find stops within radiusMeters near origin → collect route IDs
//   2. Same for destination
//   3. Group matches by routeKey (routeNo|direction|source) — unique variant ID
//   4. Intersect origin and destination maps → routes that serve BOTH points
//   5. Check origin index < dest index for correct travel direction
//
// Algorithm (transfer / 1 change):
//   1. Find all routes near origin (originRoutes)
//   2. For each originRoute, walk its stops after boarding point
//   3. At each stop, find all OTHER routes passing within 400m of that stop
//   4. Check if any of those routes also pass near destination
//   → Returns up to 3 transfer options sorted by total stops
//
// FIX LOG:
//   v2 — Removed direction constraint from direct route finder (was silently
//         dropping valid routes when GTFS direction field didn't match).
//        Increased default radius 700m → 1000m.
//        Transfer radius increased 350m → 400m for better interchange detection.
//        Added deduplication by routeNo across directions.
//   v3 — Core routing rewrite: match by routeKey (routeNo|direction|source) not
//         object identity — fixes cases where origin+dest GPS matched different
//         MtcRoute objects for the same bus, causing zero intersection.
//        Added _validRoutes: filter stub routes with ≤3 stops (bad GTFS data
//         that was polluting transfer suggestions with junk routes like "202 R").
//        Added _stopAliases: maps common user search terms like "tambaram",
//         "cmbt", "central" to canonical GTFS stop names for coordinate lookup.
//        Added searchStops() for autocomplete on destination search field.
//   v4 — Expanded _stopAliases to cover all 30 popular destination chip labels.
//        Chips now pass their display name as destName → findRoutesByName(),
//        so alias normalisation fires for curated picks just like typed search.

import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/mtc_data.dart';

// ── Result models ──────────────────────────────────────────────────────────────

class MatchedRoute {
  final String routeNo;
  final String direction;
  final String fullRoute;
  final String boardAt;
  final String alightAt;
  final int stopsApart;
  final int? crowdingPercent;
  final int reportCount;
  final String? crowdingLabel;
  final DateTime? lastReportTime;

  // Transfer-specific — null for direct routes
  final TransferInfo? transfer;

  bool get isDirect => transfer == null;

  const MatchedRoute({
    required this.routeNo,
    required this.direction,
    required this.fullRoute,
    required this.boardAt,
    required this.alightAt,
    required this.stopsApart,
    this.crowdingPercent,
    this.reportCount = 0,
    this.crowdingLabel,
    this.lastReportTime,
    this.transfer,
  });
}

/// Describes the transfer point for a 2-bus journey
class TransferInfo {
  final String transferStop;     // Name of the stop where user changes bus
  final String secondRouteNo;    // Bus to board after transfer
  final String secondRouteFull;  // Full route of second bus
  final String alightAt;         // Final stop on second bus
  final int leg1Stops;           // Stops on first bus
  final int leg2Stops;           // Stops on second bus

  const TransferInfo({
    required this.transferStop,
    required this.secondRouteNo,
    required this.secondRouteFull,
    required this.alightAt,
    required this.leg1Stops,
    required this.leg2Stops,
  });
}

class _StopMatch {
  final MtcRoute route;
  final int stopIndex;
  final BusStop stop;
  final double distanceMeters;

  const _StopMatch({
    required this.route,
    required this.stopIndex,
    required this.stop,
    required this.distanceMeters,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class BusLookupService {
  static const double _defaultRadiusMeters = 1000;
  static const double _transferRadiusMeters = 400;

  static final _client = Supabase.instance.client;

  // ── FIX 1: Filter stub routes (≤3 stops) at class load time ──────────────
  static final List<MtcRoute> _validRoutes = kMtcRoutes
      .where((r) => r.stops.length >= 4)
      .toList();

  // ── FIX 4: Expanded stop name aliases — covers all 30 chip labels ─────────
  //
  // Keys are the chip display text lowercased.
  // Values are canonical GTFS stop names.
  //
  // Rule: if a chip label doesn't match a GTFS stop name exactly, add it here.
  // Chips call findRoutesByName(destName: chipLabel) — alias fires automatically.
  static const Map<String, String> _stopAliases = {
    // ── Chip: Marina Beach ─────────────────────────────────────────────────
    'marina beach': 'Marina Beach',

    // ── Chip: T. Nagar Bus Terminus ────────────────────────────────────────
    't. nagar bus terminus': 'T.Nagar Bus Terminus',
    't nagar bus terminus': 'T.Nagar Bus Terminus',
    't.nagar bus terminus': 'T.Nagar Bus Terminus',
    't nagar': 'T.Nagar Bus Terminus',
    'tnagar': 'T.Nagar Bus Terminus',
    't.nagar': 'T.Nagar Bus Terminus',

    // ── Chip: Chennai Central Station ──────────────────────────────────────
    'chennai central station': 'M.G.R.Central',
    'chennai central': 'M.G.R.Central',
    'central station': 'M.G.R.Central',
    'central': 'M.G.R.Central',
    'mgr central': 'M.G.R.Central',

    // ── Chip: Chennai Egmore Station ───────────────────────────────────────
    'chennai egmore station': 'Egmore',
    'egmore station': 'Egmore',
    'egmore': 'Egmore',

    // ── Chip: Koyambedu Bus Terminus ───────────────────────────────────────
    'koyambedu bus terminus': 'Koyambedu Bus Terminus',
    'koyambedu': 'Koyambedu Bus Terminus',
    'cmbt': 'Koyambedu Bus Terminus',
    'koyambedu bus stand': 'Koyambedu Bus Terminus',
    'koyambedu terminus': 'Koyambedu Bus Terminus',

    // ── Chip: Chennai Airport (MAA) ────────────────────────────────────────
    'chennai airport (maa)': 'Chennai Airport',
    'chennai airport': 'Chennai Airport',
    'airport': 'Chennai Airport',
    'maa': 'Chennai Airport',

    // ── Chip: Anna Nagar Tower ─────────────────────────────────────────────
    // Anna Nagar Tower is a landmark — nearest GTFS stop is the terminus
    'anna nagar tower': 'Anna Nagar Bus Terminus',
    'anna nagar': 'Anna Nagar Bus Terminus',
    'anna nagar terminus': 'Anna Nagar Bus Terminus',

    // ── Chip: Adyar Signal ─────────────────────────────────────────────────
    'adyar signal': 'Adyar',
    'adyar': 'Adyar',
    'adyar depot': 'Adyar Depot',

    // ── Chip: Velachery Bus Terminus ───────────────────────────────────────
    'velachery bus terminus': 'Velachery',
    'velachery': 'Velachery',
    'velachery bus stand': 'Velachery',

    // ── Chip: Tambaram Bus Terminus ────────────────────────────────────────
    'tambaram bus terminus': 'Tambaram West Bus Stand',
    'tambaram': 'Tambaram West Bus Stand',
    'tambaram terminus': 'Tambaram West Bus Stand',
    'tambaram bus stand': 'Tambaram West Bus Stand',
    'tambaram west': 'Tambaram West Bus Stand',

    // ── Chip: Guindy National Park ─────────────────────────────────────────
    // Guindy National Park is inside Guindy — nearest stop
    'guindy national park': 'Guindy',
    'guindy': 'Guindy',
    'guindy bus stand': 'Guindy',

    // ── Chip: Spencer Plaza ────────────────────────────────────────────────
    'spencer plaza': 'Spencer Plaza',

    // ── Chip: Express Avenue Mall ──────────────────────────────────────────
    'express avenue mall': 'Express Avenue',
    'express avenue': 'Express Avenue',

    // ── Chip: Phoenix MarketCity ───────────────────────────────────────────
    // Phoenix MarketCity is in Velachery — nearest bus stop
    'phoenix marketcity': 'Velachery',
    'phoenix market city': 'Velachery',

    // ── Chip: VGP Universal Kingdom ────────────────────────────────────────
    'vgp universal kingdom': 'VGP Universal Kingdom',
    'vgp': 'VGP Universal Kingdom',

    // ── Chip: Kapaleeshwarar Temple ────────────────────────────────────────
    'kapaleeshwarar temple': 'Mylapore',
    'mylapore': 'Mylapore',

    // ── Chip: Santhome Cathedral ───────────────────────────────────────────
    'santhome cathedral': 'Santhome',
    'santhome': 'Santhome',

    // ── Chip: Ripon Building (Corporation) ────────────────────────────────
    'ripon building (corporation)': 'Ripon Building',
    'ripon building': 'Ripon Building',
    'corporation': 'Ripon Building',

    // ── Chip: Government Museum ────────────────────────────────────────────
    'government museum': 'Pantheon Road',
    'pantheon road': 'Pantheon Road',

    // ── Chip: Valluvar Kottam ──────────────────────────────────────────────
    'valluvar kottam': 'Valluvar Kottam',

    // ── Chip: IIT Madras Main Gate ─────────────────────────────────────────
    'iit madras main gate': 'IIT',
    'iit madras': 'IIT',
    'iit': 'IIT',

    // ── Chip: Anna University Main Gate ───────────────────────────────────
    'anna university main gate': 'Anna University',
    'anna university': 'Anna University',

    // ── Chip: Loyola College ───────────────────────────────────────────────
    'loyola college': 'Loyola College',

    // ── Chip: Sholinganallur Signal ────────────────────────────────────────
    'sholinganallur signal': 'Sholinganallur',
    'sholinganallur': 'Sholinganallur',
    'sholi': 'Sholinganallur',

    // ── Chip: Tidel Park ───────────────────────────────────────────────────
    'tidel park': 'Tidel Park',

    // ── Chip: Perungudi Toll ───────────────────────────────────────────────
    'perungudi toll': 'Perungudi',
    'perungudi': 'Perungudi',

    // ── Chip: Thiruvanmiyur Beach ──────────────────────────────────────────
    'thiruvanmiyur beach': 'Thiruvanmiyur',
    'thiruvanmiyur': 'Thiruvanmiyur',

    // ── Chip: Besant Nagar Beach (Elliot's) ───────────────────────────────
    "besant nagar beach (elliot's)": 'Besant Nagar',
    'besant nagar beach': 'Besant Nagar',
    "elliot's beach": 'Besant Nagar',
    'besant nagar': 'Besant Nagar',

    // ── Chip: Porur Signal ─────────────────────────────────────────────────
    'porur signal': 'Porur',
    'porur': 'Porur',

    // ── Chip: Chromepet Bus Stand ──────────────────────────────────────────
    'chromepet bus stand': 'Chromepet',
    'chromepet': 'Chromepet',

    // ── Misc common searches ───────────────────────────────────────────────
    'omr': 'OMR',
    'siruseri': 'Siruseri SIPCOT',
    'perambur': 'Perambur Bus Stand',
    'avadi': 'Avadi Bus Stand',
    'poonamallee': 'Poonamallee Bus Stand',
    'poonamallee bus stand': 'Poonamallee Bus Stand',
  };

  /// Normalises a destination name using the alias map.
  /// Returns the canonical GTFS name if found, or the original input.
  static String _normaliseDestName(String input) {
    final lower = input.trim().toLowerCase();
    return _stopAliases[lower] ?? input.trim();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Main entry point — coordinate-based lookup.
  /// Returns direct routes first, then 1-transfer routes if direct is empty.
  static Future<List<MatchedRoute>> findRoutes({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    double radiusMeters = _defaultRadiusMeters,
    int maxResults = 5,
  }) async {
    final originMatches = _stopsNear(originLat, originLng, radiusMeters);
    final destMatches = _stopsNear(destLat, destLng, radiusMeters);

    // ── Direct routes ──────────────────────────────────────────────────────
    final direct = _findDirectRoutes(originMatches, destMatches, maxResults);

    if (direct.isNotEmpty) {
      final routeNos = direct.map((c) => c.routeNo).toSet().toList();
      final crowding = await _fetchCrowding(routeNos);
      return _assembleResults(direct, crowding);
    }

    // ── Transfer routes (only if no direct found) ──────────────────────────
    final transfers = _findTransferRoutes(
      originLat, originLng,
      destLat, destLng,
      originMatches, destMatches,
      maxResults: 3,
    );

    if (transfers.isEmpty) return [];

    final allRouteNos = transfers
        .expand((t) => [t.leg1Route.routeNo, t.leg2Route.routeNo])
        .toSet()
        .cast<String>();
    final crowding = await _fetchCrowding(allRouteNos.toList());
    return _assembleTransferResults(transfers, crowding);
  }

  /// Destination name lookup — alias-normalised, then coordinate search.
  /// Use this when user types OR TAPS A CHIP for a destination.
  /// Both paths should call this so alias normalisation always fires.
  static Future<List<MatchedRoute>> findRoutesByName({
    required double originLat,
    required double originLng,
    required String destName,
    double radiusMeters = _defaultRadiusMeters,
    int maxResults = 5,
  }) async {
    final canonical = _normaliseDestName(destName);

    // Try exact stop name match first
    BusStop? matchedStop;
    double bestDist = double.infinity;
    for (final route in _validRoutes) {
      for (final stop in route.stops) {
        if (stop.name.toLowerCase() == canonical.toLowerCase()) {
          final d = _haversine(originLat, originLng, stop.lat, stop.lng);
          if (d < bestDist) {
            bestDist = d;
            matchedStop = stop;
          }
        }
      }
    }

    if (matchedStop != null) {
      return findRoutes(
        originLat: originLat,
        originLng: originLng,
        destLat: matchedStop.lat,
        destLng: matchedStop.lng,
        radiusMeters: radiusMeters,
        maxResults: maxResults,
      );
    }

    // Fuzzy partial match fallback
    final lowerCanon = canonical.toLowerCase();
    final fuzzyMatches = <BusStop>[];
    final seenNames = <String>{};
    for (final route in _validRoutes) {
      for (final stop in route.stops) {
        if (stop.name.toLowerCase().contains(lowerCanon) &&
            seenNames.add(stop.name)) {
          fuzzyMatches.add(stop);
        }
      }
    }
    if (fuzzyMatches.isEmpty) return [];

    final first = fuzzyMatches.first;
    return findRoutes(
      originLat: originLat,
      originLng: originLng,
      destLat: first.lat,
      destLng: first.lng,
      radiusMeters: radiusMeters,
      maxResults: maxResults,
    );
  }

  /// Fuzzy stop name search — for destination autocomplete dropdown.
  static List<String> searchStops(String query, {int limit = 8}) {
    if (query.trim().length < 2) return [];
    final lower = query.trim().toLowerCase();
    final seen = <String>{};
    final results = <String>[];
    for (final route in _validRoutes) {
      for (final stop in route.stops) {
        if (stop.name.toLowerCase().contains(lower) && seen.add(stop.name)) {
          results.add(stop.name);
          if (results.length >= limit) return results;
        }
      }
    }
    return results;
  }

  // ── FIX 3: Direct route finder rewrite ───────────────────────────────────
  static List<_RouteCandidate> _findDirectRoutes(
    List<_StopMatch> originMatches,
    List<_StopMatch> destMatches,
    int maxResults,
  ) {
    String routeKey(MtcRoute r) => '${r.routeNo}|${r.direction}|${r.source}';

    final Map<String, _StopMatch> originByKey = {};
    for (final om in originMatches) {
      final key = routeKey(om.route);
      final existing = originByKey[key];
      if (existing == null || om.distanceMeters < existing.distanceMeters) {
        originByKey[key] = om;
      }
    }

    final Map<String, _StopMatch> destByKey = {};
    for (final dm in destMatches) {
      final key = routeKey(dm.route);
      final existing = destByKey[key];
      if (existing == null || dm.distanceMeters < existing.distanceMeters) {
        destByKey[key] = dm;
      }
    }

    final Map<String, _RouteCandidate> bestByRouteNo = {};

    for (final key in originByKey.keys) {
      if (!destByKey.containsKey(key)) continue;

      final om = originByKey[key]!;
      final dm = destByKey[key]!;

      if (om.stopIndex >= dm.stopIndex) continue;

      final stopsApart = dm.stopIndex - om.stopIndex;
      final candidate = _RouteCandidate(
        route: om.route,
        originStop: om.stop,
        destStop: dm.stop,
        originDist: om.distanceMeters,
        stopsApart: stopsApart,
      );

      final routeNo = om.route.routeNo;
      final existing = bestByRouteNo[routeNo];
      if (existing == null || stopsApart < existing.stopsApart) {
        bestByRouteNo[routeNo] = candidate;
      }
    }

    final candidates = bestByRouteNo.values.toList();
    candidates.sort((a, b) => a.stopsApart.compareTo(b.stopsApart));
    return candidates.take(maxResults).toList();
  }

  // ── Transfer route finder ─────────────────────────────────────────────────
  static List<_TransferCandidate> _findTransferRoutes(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
    List<_StopMatch> originMatches,
    List<_StopMatch> destMatches,
    {int maxResults = 3}
  ) {
    final List<_TransferCandidate> found = [];
    final seen = <String>{};

    final originRoutes = <String, _StopMatch>{};
    for (final om in originMatches) {
      final key = om.route.routeNo;
      if (!originRoutes.containsKey(key)) originRoutes[key] = om;
    }
    final topOrigin = originRoutes.values.toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    final leg1Routes = topOrigin.take(15).toList();

    for (final om in leg1Routes) {
      final route1 = om.route;
      final boardIdx = om.stopIndex;

      for (int i = boardIdx + 3; i < route1.stops.length; i++) {
        final transferStop = route1.stops[i];

        final connectingMatches = _stopsNear(
          transferStop.lat, transferStop.lng, _transferRadiusMeters,
        );

        for (final cm in connectingMatches) {
          if (cm.route.routeNo == route1.routeNo) continue;

          final dms = destMatches.where((d) =>
            d.route.routeNo == cm.route.routeNo &&
            d.route == cm.route &&
            d.stopIndex > cm.stopIndex,
          ).toList();

          if (dms.isEmpty) continue;
          dms.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
          final bestDest = dms.first;

          final candidateKey =
              '${route1.routeNo}→${cm.route.routeNo}::${transferStop.name}';
          if (seen.contains(candidateKey)) continue;
          seen.add(candidateKey);

          final leg1Stops = i - boardIdx;
          final leg2Stops = bestDest.stopIndex - cm.stopIndex;

          found.add(_TransferCandidate(
            leg1Route: route1,
            boardAt: om.stop,
            transferStop: transferStop,
            leg1Stops: leg1Stops,
            leg2Route: cm.route,
            alightAt: bestDest.stop,
            leg2Stops: leg2Stops,
          ));

          if (found.length >= maxResults * 5) break;
        }
        if (found.length >= maxResults * 5) break;
      }
      if (found.length >= maxResults * 5) break;
    }

    found.sort((a, b) =>
        (a.leg1Stops + a.leg2Stops).compareTo(b.leg1Stops + b.leg2Stops));

    return found.take(maxResults).toList();
  }

  // ── Assemble results ──────────────────────────────────────────────────────

  static List<MatchedRoute> _assembleResults(
    List<_RouteCandidate> candidates,
    Map<String, _CrowdingStats> crowdingMap,
  ) {
    return (candidates.map((c) {
      final crowding = crowdingMap[c.routeNo];
      return MatchedRoute(
        routeNo: c.routeNo,
        direction: c.route.direction,
        fullRoute: '${c.route.source} → ${c.route.destination}',
        boardAt: c.originStop.name,
        alightAt: c.destStop.name,
        stopsApart: c.stopsApart,
        crowdingPercent: crowding?.avgPercent,
        reportCount: crowding?.count ?? 0,
        crowdingLabel: crowding != null ? _label(crowding.avgPercent) : null,
        lastReportTime: crowding?.lastTime,
      );
    }).toList()
      ..sort((a, b) {
        if (a.reportCount > 0 && b.reportCount == 0) return -1;
        if (b.reportCount > 0 && a.reportCount == 0) return 1;
        return a.stopsApart.compareTo(b.stopsApart);
      }));
  }

  static List<MatchedRoute> _assembleTransferResults(
    List<_TransferCandidate> candidates,
    Map<String, _CrowdingStats> crowdingMap,
  ) {
    return candidates.map((c) {
      final crowding1 = crowdingMap[c.leg1Route.routeNo];
      return MatchedRoute(
        routeNo: c.leg1Route.routeNo,
        direction: c.leg1Route.direction,
        fullRoute: '${c.leg1Route.source} → ${c.leg1Route.destination}',
        boardAt: c.boardAt.name,
        alightAt: c.alightAt.name,
        stopsApart: c.leg1Stops + c.leg2Stops,
        crowdingPercent: crowding1?.avgPercent,
        reportCount: crowding1?.count ?? 0,
        crowdingLabel: crowding1 != null ? _label(crowding1.avgPercent) : null,
        lastReportTime: crowding1?.lastTime,
        transfer: TransferInfo(
          transferStop: c.transferStop.name,
          secondRouteNo: c.leg2Route.routeNo,
          secondRouteFull: '${c.leg2Route.source} → ${c.leg2Route.destination}',
          alightAt: c.alightAt.name,
          leg1Stops: c.leg1Stops,
          leg2Stops: c.leg2Stops,
        ),
      );
    }).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static List<_StopMatch> _stopsNear(double lat, double lng, double radiusMeters) {
    final List<_StopMatch> matches = [];
    for (final route in _validRoutes) {
      for (int i = 0; i < route.stops.length; i++) {
        final stop = route.stops[i];
        final dist = _haversine(lat, lng, stop.lat, stop.lng);
        if (dist <= radiusMeters) {
          matches.add(_StopMatch(
            route: route, stopIndex: i, stop: stop, distanceMeters: dist,
          ));
        }
      }
    }
    return matches;
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;

  static String _label(int percent) {
    if (percent <= 30) return 'Empty';
    if (percent <= 60) return 'Moderate';
    if (percent <= 80) return 'Crowded';
    return 'Full';
  }

  static Future<Map<String, _CrowdingStats>> _fetchCrowding(
      List<String> routeNos) async {
    if (routeNos.isEmpty) return {};
    try {
      final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      final data = await _client
          .from('crowding_reports')
          .select('bus_route, crowding_level, timestamp')
          .inFilter('bus_route', routeNos)
          .gte('timestamp', cutoff.toIso8601String())
          .order('timestamp', ascending: false);

      final Map<String, List<int>> levels = {};
      final Map<String, DateTime> lastTimes = {};

      for (final row in (data as List)) {
        final route = row['bus_route'] as String;
        final level = row['crowding_level'] as int;
        final ts = DateTime.tryParse(row['timestamp'] ?? '');
        levels.putIfAbsent(route, () => []).add(level);
        if (ts != null) {
          if (!lastTimes.containsKey(route) || ts.isAfter(lastTimes[route]!)) {
            lastTimes[route] = ts;
          }
        }
      }

      final Map<String, _CrowdingStats> stats = {};
      for (final entry in levels.entries) {
        final avg = (entry.value.reduce((a, b) => a + b) / entry.value.length).round();
        stats[entry.key] = _CrowdingStats(
          avgPercent: avg, count: entry.value.length, lastTime: lastTimes[entry.key],
        );
      }
      return stats;
    } catch (_) {
      return {};
    }
  }
}

// ── Internal models ───────────────────────────────────────────────────────────

class _RouteCandidate {
  final MtcRoute route;
  final BusStop originStop;
  final BusStop destStop;
  final double originDist;
  final int stopsApart;

  String get routeNo => route.routeNo;
  String get direction => route.direction;

  const _RouteCandidate({
    required this.route,
    required this.originStop,
    required this.destStop,
    required this.originDist,
    required this.stopsApart,
  });
}

class _TransferCandidate {
  final MtcRoute leg1Route;
  final BusStop boardAt;
  final BusStop transferStop;
  final int leg1Stops;
  final MtcRoute leg2Route;
  final BusStop alightAt;
  final int leg2Stops;

  const _TransferCandidate({
    required this.leg1Route,
    required this.boardAt,
    required this.transferStop,
    required this.leg1Stops,
    required this.leg2Route,
    required this.alightAt,
    required this.leg2Stops,
  });
}

class _CrowdingStats {
  final int avgPercent;
  final int count;
  final DateTime? lastTime;

  const _CrowdingStats({
    required this.avgPercent,
    required this.count,
    this.lastTime,
  });
}