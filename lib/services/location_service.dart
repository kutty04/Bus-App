// lib/services/location_service.dart

import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../data/mtc_data.dart';

// ── Result type ────────────────────────────────────────────────────────────

enum GpsFailReason {
  serviceDisabled,   // Location services turned off in device settings
  permissionDenied,  // User tapped "Don't allow" — can still prompt again
  permissionPermanentlyDenied, // User tapped "Don't allow" + "Don't ask again"
  unknown,
}

class GpsResult {
  final Position? position;
  final GpsFailReason? failReason;

  const GpsResult.success(this.position) : failReason = null;
  const GpsResult.failure(this.failReason) : position = null;

  bool get isSuccess => position != null;
}

// ── Nearest stop result (unchanged) ───────────────────────────────────────

class NearestStopResult {
  final BusStop stop;
  final MtcRoute route;
  final double distanceMeters;

  NearestStopResult({
    required this.stop,
    required this.route,
    required this.distanceMeters,
  });
}

// ── Location service ───────────────────────────────────────────────────────

class LocationService {
  // ── Request permission + get current position ──────────────────────────
  //
  // Returns a GpsResult so callers can distinguish:
  //   • success  → position is set
  //   • failure  → failReason tells you WHY (service off, denied, etc.)
  static Future<GpsResult> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const GpsResult.failure(GpsFailReason.serviceDisabled);
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return const GpsResult.failure(GpsFailReason.permissionDenied);
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return const GpsResult.failure(GpsFailReason.permissionPermanentlyDenied);
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return GpsResult.success(pos);
    } catch (_) {
      return const GpsResult.failure(GpsFailReason.unknown);
    }
  }

  // ── Haversine distance in meters ───────────────────────────────────────
  static double _distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * pi / 180;

  // ── Find nearest stops across ALL routes ──────────────────────────────
  static List<NearestStopResult> findNearestStops(
    double userLat,
    double userLng, {
    int topN = 5,
    double maxDistanceMeters = 800,
  }) {
    final results = <NearestStopResult>[];

    for (final route in kMtcRoutes) {
      for (final stop in route.stops) {
        final dist = _distanceMeters(userLat, userLng, stop.lat, stop.lng);
        if (dist <= maxDistanceMeters) {
          results.add(NearestStopResult(
              stop: stop, route: route, distanceMeters: dist));
        }
      }
    }

    results.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    final seen = <String>{};
    final deduped = <NearestStopResult>[];
    for (final r in results) {
      final key = '${r.route.routeNo}::${r.stop.name}';
      if (!seen.contains(key)) {
        seen.add(key);
        deduped.add(r);
      }
    }

    return deduped.take(topN).toList();
  }

  // ── Search stops by name ───────────────────────────────────────────────
  static List<NearestStopResult> searchByStopName(String query) {
    if (query.trim().length < 2) return [];
    final q = query.trim().toLowerCase();
    final results = <NearestStopResult>[];
    final seen = <String>{};

    for (final route in kMtcRoutes) {
      for (final stop in route.stops) {
        if (stop.name.toLowerCase().contains(q)) {
          final key = '${route.routeNo}::${stop.name}';
          if (!seen.contains(key)) {
            seen.add(key);
            results.add(NearestStopResult(
                stop: stop, route: route, distanceMeters: 0));
          }
        }
      }
    }

    results.sort((a, b) => a.stop.name.compareTo(b.stop.name));
    return results.take(30).toList();
  }

  // ── Format distance ────────────────────────────────────────────────────
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m away';
    return '${(meters / 1000).toStringAsFixed(1)}km away';
  }
}