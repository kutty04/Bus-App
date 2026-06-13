// lib/services/crowd_prediction_service.dart
//
// Predicts crowding for a route at a given time.
// Uses hardcoded historical patterns (domain knowledge) as the base,
// then blends in live Supabase reports when they exist.
//
// Route families covered (your top 5):
//   • 91 family  — 91, 91A, 91K, 91R, 91V  (Tambaram ↔ Thiruvanmiyur corridor)
//   • 102 family — 102, 102A, 102P, 102X   (Broadway ↔ Kelambakkam via OMR)
//   • 19 family  — 19, 19B                 (T.Nagar/Saidapet ↔ Thiruporur/Kelambakkam)
//   • 570 family — 570, 570S, 570X, 570P   (CMBT ↔ Kelambakkam via OMR/IT corridor)
//   • MAA2       — MAA2 / MAA-2            (Chennai Airport Metro ↔ Siruseri IT Park)
//
// Data sources: spiritofchennai.com, moovitapp.com, chennaicitybus.in,
//   Wikipedia MTC article, chennaicentral.in (Aug 2025).
// Peak hours confirmed: 7–10 AM and 5–8 PM on weekdays (MTC official).
// OMR IT corridor routes (570, 19B, 102, MAA2) have especially heavy IT-worker
//   peaks. 91 family serves Tambaram suburban commuters.
//
// No ML, no server calls — works fully offline.

import '../models.dart';

// ─── Public result type ───────────────────────────────────────────────────────

class CrowdPrediction {
  /// 0–100
  final int predictedPercent;

  /// 'Quiet' | 'Moderate' | 'Packed'
  final String label;

  /// Emoji for the label
  final String emoji;

  /// Color key: 'green' | 'yellow' | 'red'
  final String colorKey;

  /// True when at least one live report contributed to this prediction
  final bool hasLiveData;

  /// Human-readable context string shown under the prediction
  final String contextLine;

  const CrowdPrediction({
    required this.predictedPercent,
    required this.label,
    required this.emoji,
    required this.colorKey,
    required this.hasLiveData,
    required this.contextLine,
  });
}

// ─── Historical pattern data ──────────────────────────────────────────────────
//
// Structure: routeNo → list of _Pattern
// Each pattern covers a time slot (startHour..endHour, IST, 24h) and
// whether it applies on weekdays, weekends, or both.
//
// crowding: 0–100 based on commuter domain knowledge + route data.
//
// OMR corridor context (570, 19B, 102, MAA2):
//   Morning peak 7–10 AM: IT professionals heading to work (Sholinganallur,
//   Perungudi, Karapakkam, Siruseri). Buses fill at CMBT/T.Nagar/Saidapet.
//   Evening peak 5:30–8 PM: IT return rush from Kelambakkam / Sholinganallur.
//   570 runs every 13–14 min; combined with 570S gives ~5–7 min frequency.
//   19B allocated 40 buses, runs every 8 min — still nearly always packed at peak.
//   102 family: Broadway ↔ Kelambakkam, 44 stops, first bus 4:50 AM.
//   MAA2: Airport Metro ↔ Siruseri IT Park, 36 stops, ~58 min trip.
//   Weekend peaks softer — IT offices closed, tourist/leisure traffic instead.
//
// 91 family context:
//   Tambaram ↔ Thiruvanmiyur suburban corridor.
//   91V extends to Vandalur Zoo (24 trips/day, first 5:50 AM).
//   91A: Hasthinapuram ↔ Thiruvanmiyur via Chromepet (peak demand confirmed
//   by commuter complaints — insufficient frequency).
//   91K/91R: shorter curtailment variants, lighter overall.
//   Peak profile: classic suburban commuter — sharp morning/evening spikes,
//   quiet midday.

class _Pattern {
  final int startHour; // inclusive, IST 24h
  final int endHour;   // exclusive, IST 24h
  final bool weekday;
  final bool weekend;
  final int crowding;  // 0-100

  const _Pattern({
    required this.startHour,
    required this.endHour,
    this.weekday = true,
    this.weekend = true,
    required this.crowding,
  });

  bool matches(int hour, bool isWeekday) {
    final dayOk = isWeekday ? weekday : weekend;
    return dayOk && hour >= startHour && hour < endHour;
  }
}

const _defaultPattern = _Pattern(startHour: 0, endHour: 24, crowding: 40);

const Map<String, List<_Pattern>> _routePatterns = {

  // ════════════════════════════════════════════════════════════════════════════
  // 91 FAMILY — Tambaram ↔ Thiruvanmiyur suburban corridor
  // Heavy suburban commuters. Peak hours sharp. Weekend lighter but not quiet.
  // ════════════════════════════════════════════════════════════════════════════

  '91': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 90),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 52),
    _Pattern(startHour: 10, endHour: 16, crowding: 44),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 87),
    _Pattern(startHour: 16, endHour: 20, weekday: false, weekend: true,  crowding: 50),
    _Pattern(startHour: 20, endHour: 23, crowding: 28),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 12),
  ],

  // 91A: Hasthinapuram ↔ Thiruvanmiyur — commuter complaints about insufficient
  // buses. When a bus does come it is overloaded during peak.
  '91A': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 93),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 55),
    _Pattern(startHour: 10, endHour: 16, crowding: 46),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 90),
    _Pattern(startHour: 16, endHour: 20, weekday: false, weekend: true,  crowding: 52),
    _Pattern(startHour: 20, endHour: 23, crowding: 30),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 12),
  ],

  // 91K: shorter curtailment, fewer stops, slightly lower absolute crowding
  '91K': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 82),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 45),
    _Pattern(startHour: 10, endHour: 16, crowding: 38),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 78),
    _Pattern(startHour: 16, endHour: 20, weekday: false, weekend: true,  crowding: 42),
    _Pattern(startHour: 20, endHour: 23, crowding: 22),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 10),
  ],

  // 91R: another curtailment variant, similar to 91K
  '91R': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 80),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 42),
    _Pattern(startHour: 10, endHour: 16, crowding: 36),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 76),
    _Pattern(startHour: 16, endHour: 20, weekday: false, weekend: true,  crowding: 40),
    _Pattern(startHour: 20, endHour: 23, crowding: 20),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 9),
  ],

  // 91V: Thiruvanmiyur ↔ Vandalur Zoo. 24 trips/day, first bus 5:50 AM.
  // Zoo proximity boosts weekend ridership noticeably.
  '91V': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 86),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 62),
    _Pattern(startHour: 10, endHour: 16, weekday: true,  weekend: false, crowding: 42),
    _Pattern(startHour: 10, endHour: 16, weekday: false, weekend: true,  crowding: 58), // Zoo visitors
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 82),
    _Pattern(startHour: 16, endHour: 20, weekday: false, weekend: true,  crowding: 65), // Zoo return
    _Pattern(startHour: 20, endHour: 23, crowding: 24),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 10),
  ],

  // ════════════════════════════════════════════════════════════════════════════
  // 102 FAMILY — Broadway ↔ Kelambakkam (via Velachery, OMR)
  // 44 stops, first bus 4:50 AM. Long trunk route serving both city centre
  // workers and IT corridor. Heavy IT peak + city commuters.
  // Variants: 102A (Thiruvanmiyur↔Pudupakkam, 41 stops), 102P, 102X (express).
  // ════════════════════════════════════════════════════════════════════════════

  '102': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 91),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 50),
    _Pattern(startHour: 10, endHour: 16, crowding: 48),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 89),
    _Pattern(startHour: 16, endHour: 20, weekday: false, weekend: true,  crowding: 52),
    _Pattern(startHour: 20, endHour: 23, crowding: 32),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 14),
  ],

  // 102A: Thiruvanmiyur ↔ Pudupakkam. 41 stops, ~63 min trip.
  // Serves deeper OMR — Navalur, Pudupakkam. Slightly lighter than trunk 102.
  '102A': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 86),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 45),
    _Pattern(startHour: 10, endHour: 16, crowding: 42),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 83),
    _Pattern(startHour: 16, endHour: 20, weekday: false, weekend: true,  crowding: 46),
    _Pattern(startHour: 20, endHour: 23, crowding: 26),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 10),
  ],

  // 102P: partial / curtailment variant
  '102P': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 82),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 42),
    _Pattern(startHour: 10, endHour: 16, crowding: 38),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 79),
    _Pattern(startHour: 16, endHour: 20, weekday: false, weekend: true,  crowding: 42),
    _Pattern(startHour: 20, endHour: 23, crowding: 22),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 9),
  ],

  // 102X: express, fewer stops → slightly less crowded per stop but fills fast
  '102X': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 88),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 48),
    _Pattern(startHour: 10, endHour: 16, crowding: 40),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 85),
    _Pattern(startHour: 16, endHour: 20, weekday: false, weekend: true,  crowding: 48),
    _Pattern(startHour: 20, endHour: 23, crowding: 26),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 10),
  ],

  // ════════════════════════════════════════════════════════════════════════════
  // 19 FAMILY — T.Nagar/Saidapet ↔ Thiruporur/Kelambakkam via OMR
  // 19: T.Nagar ↔ Thiruporur, 46 stops, ~88 min full trip (5 AM–9:30 PM).
  // 19B: Saidapet ↔ Kelambakkam, 33 stops, 40 buses allocated, runs every 8 min.
  //   Average peak speed only 18 km/h on OMR (Metro Phase 2 construction).
  //   One of the busiest OMR routes — IT professionals, students, residents.
  // ════════════════════════════════════════════════════════════════════════════

  '19': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 90),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 50),
    _Pattern(startHour: 10, endHour: 16, crowding: 42),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 85),
    _Pattern(startHour: 16, endHour: 20, weekday: false, weekend: true,  crowding: 48),
    _Pattern(startHour: 20, endHour: 23, crowding: 28),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 12),
  ],

  // 19B: even busier than 19 at peak (Saidapet origin fills early, OMR stretch packed)
  '19B': [
    _Pattern(startHour: 5,  endHour: 7,  weekday: true,  weekend: false, crowding: 72), // early IT shift
    _Pattern(startHour: 5,  endHour: 7,  weekday: false, weekend: true,  crowding: 30),
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 95), // absolute peak — 40 buses still packed
    _Pattern(startHour: 7,  endHour: 10, weekday: false, weekend: true,  crowding: 52),
    _Pattern(startHour: 10, endHour: 16, crowding: 44),
    _Pattern(startHour: 16, endHour: 18, weekday: true,  weekend: false, crowding: 78),
    _Pattern(startHour: 18, endHour: 20, weekday: true,  weekend: false, crowding: 92), // IT return rush peak
    _Pattern(startHour: 18, endHour: 20, weekday: false, weekend: true,  crowding: 52),
    _Pattern(startHour: 20, endHour: 22, crowding: 34),
    _Pattern(startHour: 22, endHour: 24, crowding: 18),
    _Pattern(startHour: 0,  endHour: 5,  crowding: 10),
  ],

  // ════════════════════════════════════════════════════════════════════════════
  // 570 FAMILY — CMBT ↔ Kelambakkam (main OMR spine)
  // 570: 54 stops, every 13–14 min (68 daily trips).
  // 570S: via Velachery/Thoraipakkam/Siruseri, 24 stops, every 29–30 min.
  //   Combined 570+570S: effective ~1 bus every 5–7 min at shared stops.
  // 570X: express variant, fewer stops, faster.
  // 570P: partial variant.
  // Morning: buses fill at CMBT and Vadapalani (8–10 AM heavy IT peak).
  // Evening: 5:30–8 PM from Kelambakkam/Sholinganallur — IT return very crowded.
  // Midday 11 AM–2 PM: much lighter.
  // ════════════════════════════════════════════════════════════════════════════

  '570': [
    _Pattern(startHour: 5,  endHour: 7,  weekday: true,  weekend: false, crowding: 30), // early comfortable
    _Pattern(startHour: 5,  endHour: 7,  weekday: false, weekend: true,  crowding: 20),
    _Pattern(startHour: 7,  endHour: 8,  weekday: true,  weekend: false, crowding: 72),
    _Pattern(startHour: 8,  endHour: 10, weekday: true,  weekend: false, crowding: 94), // heavy IT peak; fills at CMBT+Vadapalani
    _Pattern(startHour: 8,  endHour: 10, weekday: false, weekend: true,  crowding: 48),
    _Pattern(startHour: 10, endHour: 11, weekday: true,  weekend: false, crowding: 55),
    _Pattern(startHour: 11, endHour: 14, crowding: 32), // midday much lighter
    _Pattern(startHour: 14, endHour: 16, crowding: 42),
    _Pattern(startHour: 16, endHour: 18, weekday: true,  weekend: false, crowding: 70),
    _Pattern(startHour: 18, endHour: 20, weekday: true,  weekend: false, crowding: 95), // IT return from Kelambakkam/Sholinganallur
    _Pattern(startHour: 18, endHour: 20, weekday: false, weekend: true,  crowding: 50),
    _Pattern(startHour: 20, endHour: 22, crowding: 36),
    _Pattern(startHour: 22, endHour: 24, crowding: 20),
    _Pattern(startHour: 0,  endHour: 5,  crowding: 10),
  ],

  // 570S: via different OMR path (Kandanchavadi, Thoraipakkam → Siruseri IT Park)
  // Less frequent (29–30 min), dedicated IT park users, similar peak profile
  '570S': [
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 90),
    _Pattern(startHour: 7,  endHour: 10, weekday: false, weekend: true,  crowding: 44),
    _Pattern(startHour: 10, endHour: 11, crowding: 50),
    _Pattern(startHour: 11, endHour: 14, crowding: 30),
    _Pattern(startHour: 14, endHour: 16, crowding: 40),
    _Pattern(startHour: 16, endHour: 18, weekday: true,  weekend: false, crowding: 68),
    _Pattern(startHour: 18, endHour: 20, weekday: true,  weekend: false, crowding: 92),
    _Pattern(startHour: 20, endHour: 22, crowding: 34),
    _Pattern(startHour: 0,  endHour: 7,  crowding: 12),
  ],

  // 570X: express, fewer intermediate stops → slightly faster but equally packed
  '570X': [
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 92),
    _Pattern(startHour: 7,  endHour: 10, weekday: false, weekend: true,  crowding: 46),
    _Pattern(startHour: 10, endHour: 14, crowding: 36),
    _Pattern(startHour: 14, endHour: 17, crowding: 44),
    _Pattern(startHour: 17, endHour: 20, weekday: true,  weekend: false, crowding: 91),
    _Pattern(startHour: 17, endHour: 20, weekday: false, weekend: true,  crowding: 48),
    _Pattern(startHour: 20, endHour: 22, crowding: 30),
    _Pattern(startHour: 0,  endHour: 7,  crowding: 12),
  ],

  // 570P: partial curtailment variant
  '570P': [
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 84),
    _Pattern(startHour: 7,  endHour: 10, weekday: false, weekend: true,  crowding: 40),
    _Pattern(startHour: 10, endHour: 16, crowding: 36),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 80),
    _Pattern(startHour: 16, endHour: 20, weekday: false, weekend: true,  crowding: 42),
    _Pattern(startHour: 20, endHour: 22, crowding: 24),
    _Pattern(startHour: 0,  endHour: 7,  crowding: 10),
  ],

  // ════════════════════════════════════════════════════════════════════════════
  // MAA2 / MAA-2 — Chennai Airport Metro Station ↔ Siruseri IT Park
  // 36 stops, ~58 min trip. Launched by MTC Chennai (confirmed April 2025).
  // Covers: Pallavaram, 200ft Radial Road, Thoraipakkam, Karapakkam,
  //   Sholinganallur, ECR Junction, Akkarai (Moovit/MTC tweet).
  // Serves airport→OMR corridor + IT professionals.
  // Airport link means some off-peak demand (flights), but weekday IT peak dominates.
  // ════════════════════════════════════════════════════════════════════════════

  'MAA2': [
    _Pattern(startHour: 5,  endHour: 7,  weekday: true,  weekend: false, crowding: 38), // early airport travellers
    _Pattern(startHour: 5,  endHour: 7,  weekday: false, weekend: true,  crowding: 35),
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 88), // IT + airport combined peak
    _Pattern(startHour: 7,  endHour: 10, weekday: false, weekend: true,  crowding: 55), // weekend airport traffic
    _Pattern(startHour: 10, endHour: 14, weekday: true,  weekend: false, crowding: 46),
    _Pattern(startHour: 10, endHour: 14, weekday: false, weekend: true,  crowding: 52), // weekend leisure/airport higher midday
    _Pattern(startHour: 14, endHour: 17, crowding: 44),
    _Pattern(startHour: 17, endHour: 20, weekday: true,  weekend: false, crowding: 86), // IT return + evening flights
    _Pattern(startHour: 17, endHour: 20, weekday: false, weekend: true,  crowding: 58),
    _Pattern(startHour: 20, endHour: 23, crowding: 32), // late flights
    _Pattern(startHour: 0,  endHour: 5,  crowding: 15), // night flights / airport workers
  ],

  // alias for 'MAA-2' in case it's stored with hyphen
  'MAA-2': [
    _Pattern(startHour: 5,  endHour: 7,  crowding: 36),
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 88),
    _Pattern(startHour: 7,  endHour: 10, weekday: false, weekend: true,  crowding: 55),
    _Pattern(startHour: 10, endHour: 14, crowding: 46),
    _Pattern(startHour: 14, endHour: 17, crowding: 44),
    _Pattern(startHour: 17, endHour: 20, weekday: true,  weekend: false, crowding: 86),
    _Pattern(startHour: 17, endHour: 20, weekday: false, weekend: true,  crowding: 58),
    _Pattern(startHour: 20, endHour: 23, crowding: 32),
    _Pattern(startHour: 0,  endHour: 5,  crowding: 15),
  ],

  // ════════════════════════════════════════════════════════════════════════════
  // LEGACY routes kept from original file (city-wide trunk routes)
  // ════════════════════════════════════════════════════════════════════════════

  '19C': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 92),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 55),
    _Pattern(startHour: 10, endHour: 16, crowding: 45),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 88),
    _Pattern(startHour: 16, endHour: 20, weekday: false, weekend: true,  crowding: 50),
    _Pattern(startHour: 20, endHour: 23, crowding: 30),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 15),
  ],
  '21C': [
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 88),
    _Pattern(startHour: 7,  endHour: 10, weekday: false, weekend: true,  crowding: 48),
    _Pattern(startHour: 10, endHour: 16, crowding: 40),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 84),
    _Pattern(startHour: 20, endHour: 23, crowding: 25),
    _Pattern(startHour: 0,  endHour: 7,  crowding: 10),
  ],
  'M70': [
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 85),
    _Pattern(startHour: 7,  endHour: 10, weekday: false, weekend: true,  crowding: 40),
    _Pattern(startHour: 10, endHour: 16, crowding: 38),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 80),
    _Pattern(startHour: 20, endHour: 23, crowding: 22),
    _Pattern(startHour: 0,  endHour: 7,  crowding: 10),
  ],
  '5': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 88),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 45),
    _Pattern(startHour: 10, endHour: 16, crowding: 44),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 86),
    _Pattern(startHour: 20, endHour: 23, crowding: 28),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 12),
  ],
  '5C': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 86),
    _Pattern(startHour: 10, endHour: 16, crowding: 42),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 83),
    _Pattern(startHour: 20, endHour: 23, crowding: 26),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 10),
  ],
  '47': [
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 82),
    _Pattern(startHour: 10, endHour: 16, crowding: 38),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 78),
    _Pattern(startHour: 20, endHour: 23, crowding: 22),
    _Pattern(startHour: 0,  endHour: 7,  crowding: 8),
  ],
  '47A': [
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 80),
    _Pattern(startHour: 10, endHour: 16, crowding: 36),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 76),
    _Pattern(startHour: 20, endHour: 23, crowding: 20),
    _Pattern(startHour: 0,  endHour: 7,  crowding: 8),
  ],
  '70': [
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 84),
    _Pattern(startHour: 10, endHour: 16, crowding: 40),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 80),
    _Pattern(startHour: 20, endHour: 23, crowding: 24),
    _Pattern(startHour: 0,  endHour: 7,  crowding: 10),
  ],
  '23C': [
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 86),
    _Pattern(startHour: 10, endHour: 16, crowding: 42),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 82),
    _Pattern(startHour: 20, endHour: 23, crowding: 26),
    _Pattern(startHour: 0,  endHour: 7,  crowding: 10),
  ],
  '29C': [
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 78),
    _Pattern(startHour: 10, endHour: 16, crowding: 36),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 74),
    _Pattern(startHour: 20, endHour: 23, crowding: 20),
    _Pattern(startHour: 0,  endHour: 7,  crowding: 8),
  ],
  '101': [
    _Pattern(startHour: 6,  endHour: 10, weekday: true,  weekend: false, crowding: 90),
    _Pattern(startHour: 6,  endHour: 10, weekday: false, weekend: true,  crowding: 52),
    _Pattern(startHour: 10, endHour: 16, crowding: 46),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 88),
    _Pattern(startHour: 20, endHour: 23, crowding: 30),
    _Pattern(startHour: 0,  endHour: 6,  crowding: 12),
  ],
  '109': [
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 82),
    _Pattern(startHour: 10, endHour: 16, crowding: 38),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 78),
    _Pattern(startHour: 20, endHour: 23, crowding: 22),
    _Pattern(startHour: 0,  endHour: 7,  crowding: 8),
  ],
  'M77': [
    _Pattern(startHour: 7,  endHour: 10, weekday: true,  weekend: false, crowding: 80),
    _Pattern(startHour: 10, endHour: 16, crowding: 36),
    _Pattern(startHour: 16, endHour: 20, weekday: true,  weekend: false, crowding: 76),
    _Pattern(startHour: 20, endHour: 23, crowding: 20),
    _Pattern(startHour: 0,  endHour: 7,  crowding: 8),
  ],
};

// ─── Service ──────────────────────────────────────────────────────────────────

class CrowdPredictionService {
  /// Normalise a route number for lookup.
  /// Handles: '570s' → '570S', 'maa-2' → 'MAA-2', 'maa2' → 'MAA2', etc.
  static String _normalise(String routeNo) {
    final upper = routeNo.toUpperCase().trim();
    // Treat 'MAA2' and 'MAA-2' as separate keys both present in the map.
    return upper;
  }

  /// Get the historical base crowding % for a route at a specific IST hour.
  static int getHistoricalBase(String routeNo, int istHour, bool isWeekday) {
    final key = _normalise(routeNo);
    final patterns = _routePatterns[key];
    if (patterns == null) {
      return _genericCrowding(istHour, isWeekday);
    }
    for (final p in patterns) {
      if (p.matches(istHour, isWeekday)) return p.crowding;
    }
    return _defaultPattern.crowding;
  }

  /// Blend historical base with live reports and return a full prediction.
  ///
  /// [liveReports] — recent reports for this route (last 30–60 mins).
  ///                 Pass an empty list when there are no live reports.
  static CrowdPrediction predict({
    required String routeNo,
    required List<CrowdingReport> liveReports,
    DateTime? atTime, // defaults to now (IST)
  }) {
    final now = atTime ?? DateTime.now().toUtc();
    final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    final isWeekday = ist.weekday <= 5; // Mon=1 … Fri=5

    final base = getHistoricalBase(routeNo, ist.hour, isWeekday);

    int finalScore;
    bool hasLive = false;

    if (liveReports.isEmpty) {
      finalScore = base;
    } else {
      final avg = liveReports
              .map((r) => r.crowdingLevel)
              .reduce((a, b) => a + b) /
          liveReports.length;
      // Blend: live reports carry 60% weight, history 40%
      finalScore = ((avg * 0.6) + (base * 0.4)).round().clamp(0, 100);
      hasLive = true;
    }

    return _buildResult(finalScore, hasLive, liveReports.length, routeNo, ist.hour);
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  static int _genericCrowding(int hour, bool isWeekday) {
    if (!isWeekday) {
      if (hour >= 8 && hour < 12) return 55;
      if (hour >= 16 && hour < 20) return 50;
      return 30;
    }
    if (hour >= 6 && hour < 10) return 80;
    if (hour >= 10 && hour < 16) return 40;
    if (hour >= 16 && hour < 20) return 78;
    if (hour >= 20 && hour < 23) return 25;
    return 15;
  }

  static CrowdPrediction _buildResult(
    int score,
    bool hasLive,
    int reportCount,
    String routeNo,
    int istHour,
  ) {
    final String label;
    final String emoji;
    final String colorKey;

    if (score <= 35) {
      label = 'Quiet';
      emoji = '🟢';
      colorKey = 'green';
    } else if (score <= 65) {
      label = 'Moderate';
      emoji = '🟡';
      colorKey = 'yellow';
    } else {
      label = 'Packed';
      emoji = '🔴';
      colorKey = 'red';
    }

    final String contextLine;
    if (hasLive) {
      final noun = reportCount == 1 ? 'report' : 'reports';
      contextLine = 'Based on $reportCount live $noun + historical pattern';
    } else {
      contextLine = _historicalContextLine(routeNo, istHour);
    }

    return CrowdPrediction(
      predictedPercent: score,
      label: label,
      emoji: emoji,
      colorKey: colorKey,
      hasLiveData: hasLive,
      contextLine: contextLine,
    );
  }

  static String _historicalContextLine(String routeNo, int hour) {
    // Route-specific context hints
    final upper = _normalise(routeNo);
    if ((upper == '570' || upper == '570S' || upper == '570X') &&
        hour >= 8 && hour < 10) {
      return 'IT peak — buses fill at CMBT & Vadapalani';
    }
    if ((upper == '570' || upper == '570S') && hour >= 18 && hour < 20) {
      return 'IT return rush from Kelambakkam';
    }
    if (upper == '19B' && hour >= 7 && hour < 10) {
      return 'OMR IT peak — heavy even with 8-min frequency';
    }
    if ((upper == 'MAA2' || upper == 'MAA-2') && hour >= 7 && hour < 10) {
      return 'Airport + IT corridor combined peak';
    }
    if (upper == '91A' && hour >= 6 && hour < 10) {
      return 'Infrequent route — very crowded when it comes';
    }

    // Generic time-based fallback
    if (hour >= 6 && hour < 10) return 'Typical morning peak pattern';
    if (hour >= 10 && hour < 16) return 'Typical mid-day pattern';
    if (hour >= 16 && hour < 20) return 'Typical evening peak pattern';
    if (hour >= 20 && hour < 23) return 'Typical late evening pattern';
    return 'Typical off-peak pattern';
  }
}