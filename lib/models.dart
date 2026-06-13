import 'package:flutter/material.dart';

// Supabase returns timestamps like "2025-04-12T04:48:00+00:00" or
// "2025-04-12T04:48:00" (no Z). We always treat them as UTC by
// ensuring the string ends with Z before parsing.
DateTime _parseAsUtc(String raw) {
  final s = raw.endsWith('Z') || raw.contains('+') ? raw : '${raw}Z';
  return DateTime.parse(s).toUtc();
}

class CrowdingReport {
  final int id;
  final String busRoute;
  final int crowdingLevel;
  final String? boardingStop;
  final String? reporterName;
  final bool justLeft;
  final bool isAc;
  final double? latitude;
  final double? longitude;
  final DateTime timestamp;
  final int helpfulCount;
  final int viewCount;

  CrowdingReport({
    required this.id,
    required this.busRoute,
    required this.crowdingLevel,
    this.boardingStop,
    this.reporterName,
    required this.justLeft,
    required this.isAc,
    this.latitude,
    this.longitude,
    required this.timestamp,
    required this.helpfulCount,
    required this.viewCount,
  });

  factory CrowdingReport.fromJson(Map<String, dynamic> json) {
    final parsedTs = json['timestamp'] != null
        ? _parseAsUtc(json['timestamp'] as String)
        : DateTime.now().toUtc();

    return CrowdingReport(
      id: json['id'] as int,
      busRoute: json['bus_route'] as String,
      crowdingLevel: json['crowding_level'] as int,
      boardingStop: json['boarding_stop'] as String?,
      reporterName: json['reporter_name'] as String?,
      justLeft: json['just_left'] as bool? ?? false,
      isAc: json['is_ac'] as bool? ?? false,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      timestamp: parsedTs,
      helpfulCount: json['helpful_count'] as int? ?? 0,
      viewCount: json['view_count'] as int? ?? 0,
    );
  }

  // IST display time — timestamp is UTC, add 5:30 for IST
  String get istTimeString {
    final ist = timestamp.toUtc().add(const Duration(hours: 5, minutes: 30));
    final h = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
    final m = ist.minute.toString().padLeft(2, '0');
    final period = ist.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  // Time ago — both sides are UTC now so diff is accurate
  String get timeAgo {
    final diff = DateTime.now().toUtc().difference(timestamp);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes == 1) return '1 min ago';
    if (diff.inHours < 1) return '${diff.inMinutes} mins ago';
    if (diff.inHours == 1) return '1 hr ago';
    return '${diff.inHours} hrs ago';
  }

  bool get isStale =>
      DateTime.now().toUtc().difference(timestamp).inMinutes > 15;
}

// ─── Crowding info helper ─────────────────────────────────────────────────
class CrowdingInfo {
  final String emoji;
  final String label;
  final Color color;
  final int percent;

  const CrowdingInfo({
    required this.emoji,
    required this.label,
    required this.color,
    required this.percent,
  });
}

CrowdingInfo getCrowdingInfo(int level) {
  switch (level) {
    case 20:
      return const CrowdingInfo(
        emoji: '🟢',
        label: 'Empty / Few people',
        color: Color(0xFF22c55e),
        percent: 20,
      );
    case 50:
      return const CrowdingInfo(
        emoji: '🟡',
        label: 'Moderate',
        color: Color(0xFFf59e0b),
        percent: 50,
      );
    case 90:
      return const CrowdingInfo(
        emoji: '🔴',
        label: 'Packed',
        color: Color(0xFFef4444),
        percent: 90,
      );
    default:
      return const CrowdingInfo(
        emoji: '🟡',
        label: 'Moderate',
        color: Color(0xFFf59e0b),
        percent: 50,
      );
  }
}