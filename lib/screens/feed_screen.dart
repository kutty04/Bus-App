// lib/screens/feed_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../models.dart';
import '../services/supabase_service.dart';
import '../services/crowd_prediction_service.dart';
import '../services/prediction_service.dart';
import '../services/notification_service.dart';
import '../services/commute_memory_service.dart';   // ✅ NEW
import '../widgets/report_card.dart';
import '../widgets/time_filter_bar.dart';
import '../widgets/prediction_banner.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<CrowdingReport> _reports = [];
  List<UsualRoute> _usualRoutes = [];          // ✅ NEW
  Map<String, int> _safetyFlags = {};          // ✅ NEW  route → flag count
  bool _loading = true;
  String? _error;
  String _timeFilter = 'all';
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadReports();
    _loadUsualRoutes();                         // ✅ NEW
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────

  Future<void> _loadReports() async {
    setState(() { _loading = true; _error = null; });
    try {
      final reports = await SupabaseService.fetchFeed(
        timeFilter: _timeFilter == 'all' ? null : _timeFilter,
      );
      if (mounted) {
        setState(() { _reports = reports; _loading = false; });
        _loadSafetyFlags(reports);             // ✅ NEW — load flags for visible routes
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ✅ NEW — load commute memory from SharedPreferences
  Future<void> _loadUsualRoutes() async {
    final memories = await CommuteMemoryService.instance.getUsualRoutes();
    if (mounted) {
      setState(() {
        _usualRoutes = memories.map((m) => m.toPublic()).toList();
      });
    }
  }

  // ✅ NEW — load safety flag counts for each route currently on screen
  Future<void> _loadSafetyFlags(List<CrowdingReport> reports) async {
    final routes = reports.map((r) => r.busRoute).toSet();
    final Map<String, int> flags = {};
    for (final route in routes) {
      try {
        final count = await SupabaseService.fetchSafetyFlagCount(route);
        if (count > 0) flags[route] = count;
      } catch (_) {}
    }
    if (mounted) setState(() => _safetyFlags = flags);
  }

  void _subscribeRealtime() {
    _channel = SupabaseService.subscribeToReports(_loadReports);
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('📡 Live Feed',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadReports,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TimeFilterBar(
            selected: _timeFilter,
            onChanged: (v) {
              setState(() => _timeFilter = v);
              _loadReports();
            },
          ),
        ),
      ),
      body: _loading
          ? const _LoadingView()
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _loadReports)
              : _reports.isEmpty
                  ? _EmptyView(timeFilter: _timeFilter)
                  : RefreshIndicator(
                      onRefresh: _loadReports,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          // ✅ NEW — "Your Routes" section (only when user has history)
                          if (_usualRoutes.isNotEmpty)
                            _YourRoutesSection(
                              usualRoutes: _usualRoutes,
                              allReports: _reports,
                              safetyFlags: _safetyFlags,
                            ),

                          // ── All reports ──────────────────────────
                          if (_usualRoutes.isNotEmpty)
                            const Padding(
                              padding:
                                  EdgeInsets.only(top: 4, bottom: 8),
                              child: Row(children: [
                                Icon(Icons.dynamic_feed_outlined,
                                    size: 13,
                                    color: AppTheme.textSecondary),
                                SizedBox(width: 5),
                                Text(
                                  'All live reports',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                              ]),
                            ),

                          for (final report in _reports) ...[
                            // ✅ NEW — safety warning above the first card for that route
                            if (_safetyFlags.containsKey(report.busRoute) &&
                                _reports.indexOf(report) == 
                                    _reports.indexWhere(
                                        (r) => r.busRoute == report.busRoute))
                              _SafetyWarningBadge(
                                route: report.busRoute,
                                count: _safetyFlags[report.busRoute]!,
                              ),
                            ReportCard(report: report),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

// ── Your Routes Section ───────────────────────────────────────────

class _YourRoutesSection extends StatelessWidget {
  final List<UsualRoute> usualRoutes;
  final List<CrowdingReport> allReports;
  final Map<String, int> safetyFlags;

  const _YourRoutesSection({
    required this.usualRoutes,
    required this.allReports,
    required this.safetyFlags,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Text('🧠', style: TextStyle(fontSize: 13)),
            SizedBox(width: 6),
            Text(
              'Your usual routes',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
            SizedBox(width: 6),
            Text(
              '· based on your reports',
              style: TextStyle(color: AppTheme.textDim, fontSize: 11),
            ),
          ]),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: usualRoutes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              final ur = usualRoutes[i];
              // Find the latest live report for this route (if any)
              final liveReport = allReports
                  .where((r) => r.busRoute
                      .toUpperCase()
                      .contains(ur.route.toUpperCase()))
                  .firstOrNull;
              final hasSafety = safetyFlags.containsKey(ur.route);

              return _UsualRouteChip(
                route: ur,
                liveReport: liveReport,
                hasSafetyFlag: hasSafety,
                flagCount: safetyFlags[ur.route] ?? 0,
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _UsualRouteChip extends StatelessWidget {
  final UsualRoute route;
  final CrowdingReport? liveReport;
  final bool hasSafetyFlag;
  final int flagCount;

  const _UsualRouteChip({
    required this.route,
    required this.liveReport,
    required this.hasSafetyFlag,
    required this.flagCount,
  });

  Color get _crowdColor {
    if (liveReport == null) return Colors.white24;
    final level = liveReport!.crowdingLevel; // 20, 50, or 90
    if (level <= 20) return Colors.greenAccent;
    if (level <= 50) return Colors.amber;
    return Colors.redAccent;
  }

  String get _crowdLabel {
    if (liveReport == null) return 'No live data';
    final level = liveReport!.crowdingLevel;
    if (level <= 20) return '$level% · Low';
    if (level <= 50) return '$level% · Moderate';
    return '$level% · Packed';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Route number
          Row(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                route.route,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800),
              ),
            ),
            const Spacer(),
            if (hasSafetyFlag)
              const Tooltip(
                message: 'Safety concern flagged',
                child: Text('⚠️', style: TextStyle(fontSize: 13)),
              ),
          ]),
          const SizedBox(height: 6),

          // Last stop
          Text(
            route.lastStop,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),

          // Live crowding indicator
          Row(children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: _crowdColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                _crowdLabel,
                style: TextStyle(color: _crowdColor, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ── Safety Warning Badge ──────────────────────────────────────────

class _SafetyWarningBadge extends StatelessWidget {
  final String route;
  final int count;

  const _SafetyWarningBadge({required this.route, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        const Text('⚠️', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$count safety concern${count > 1 ? 's' : ''} flagged on Route $route in the last hour.',
            style: TextStyle(
                color: Colors.orange.shade200,
                fontSize: 12,
                height: 1.4),
          ),
        ),
      ]),
    );
  }
}

// ── Loading ───────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 5,
      itemBuilder: (_, __) => const _SkeletonCard(),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _Shimmer(width: 48, height: 48, radius: 24),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Shimmer(width: 120, height: 14, radius: 6),
                  SizedBox(height: 6),
                  _Shimmer(width: 80, height: 11, radius: 4),
                ],
              ),
            ),
            _Shimmer(width: 56, height: 28, radius: 8),
          ]),
          SizedBox(height: 12),
          _Shimmer(width: double.infinity, height: 11, radius: 4),
          SizedBox(height: 6),
          _Shimmer(width: 160, height: 11, radius: 4),
        ],
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const _Shimmer(
      {required this.width, required this.height, required this.radius});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 0.7).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: _anim.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

// ── Error ─────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😵', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Could not load reports. Check your connection.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty ─────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final String timeFilter;
  const _EmptyView({required this.timeFilter});

  static const _routeGroups = [
    _RouteGroup(
      routeNo: '91',
      displayLabel: '91 family',
      variantsNote: '+ 91A, 91K, 91R, 91V',
      corridor: 'Tambaram ↔ Thiruvanmiyur',
    ),
    _RouteGroup(
      routeNo: '102',
      displayLabel: '102 family',
      variantsNote: '+ 102A, 102P, 102X',
      corridor: 'Broadway ↔ Kelambakkam',
    ),
    _RouteGroup(
      routeNo: '19',
      displayLabel: '19 / 19B',
      variantsNote: '19 → Thiruporur  |  19B → Kelambakkam',
      corridor: 'T.Nagar / Saidapet ↔ OMR',
    ),
    _RouteGroup(
      routeNo: '570',
      displayLabel: '570 family',
      variantsNote: '+ 570S, 570X, 570P',
      corridor: 'CMBT ↔ Kelambakkam via OMR',
    ),
    _RouteGroup(
      routeNo: 'MAA2',
      displayLabel: 'MAA2',
      variantsNote: 'Airport Metro ↔ Siruseri IT Park',
      corridor: 'via Sholinganallur, Karapakkam',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final label = timeFilter == 'morning'
        ? 'morning'
        : timeFilter == 'evening'
            ? 'evening'
            : null;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              const Text('🚌', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(
                label == null
                    ? 'No live reports yet'
                    : 'No $label reports yet',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Be the first Chennai commuter to report!\nMeanwhile, here are predictions for your top routes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.5),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => reportTabNotifier.value = 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app_outlined,
                          color: AppTheme.primary, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Tap Report to add one',
                        style: TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(Icons.auto_graph, size: 14, color: AppTheme.primary),
            SizedBox(width: 6),
            Text(
              'Predicted crowding right now',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ]),
        ),

        ..._routeGroups.map((group) {
          CrowdPrediction prediction;
          final mlPrediction = PredictionService.instance.predict(
            route: group.routeNo,
            direction: 'DOWN',
          );
          if (mlPrediction != null) {
            prediction =
                _convertToCrowdPrediction(mlPrediction, group.routeNo);
          } else {
            prediction = CrowdPredictionService.predict(
              routeNo: group.routeNo,
              liveReports: [],
            );
          }
          return _RouteGroupCard(group: group, prediction: prediction);
        }),

        const SizedBox(height: 8),
      ],
    );
  }

  CrowdPrediction _convertToCrowdPrediction(
      CrowdingPrediction pred, String routeNo) {
    int percent = pred.pct;
    String label;
    String emoji;
    String colorKey;
    String contextLine;

    switch (pred.label) {
      case 'low':
        label = 'Low Crowding';
        emoji = '😊';
        colorKey = 'green';
        contextLine = pred.isMLPrediction
            ? 'ML: Seats available • Easy boarding'
            : 'Seats available • Easy boarding';
        break;
      case 'medium':
        label = 'Moderate Crowding';
        emoji = '😐';
        colorKey = 'yellow';
        contextLine = pred.isMLPrediction
            ? 'ML: Some standing • Normal wait'
            : 'Some standing • Normal wait time';
        break;
      case 'high':
        label = 'High Crowding';
        emoji = '😰';
        colorKey = 'red';
        contextLine = pred.isMLPrediction
            ? 'ML: Packed • Consider alternatives'
            : 'Packed • Consider alternate routes';
        break;
      default:
        label = 'Unknown';
        emoji = '❓';
        colorKey = 'yellow';
        contextLine = 'Prediction unavailable';
    }

    return CrowdPrediction(
      predictedPercent: percent,
      label: label,
      emoji: emoji,
      colorKey: colorKey,
      contextLine: contextLine,
      hasLiveData: false,
    );
  }
}

class _RouteGroup {
  final String routeNo;
  final String displayLabel;
  final String variantsNote;
  final String corridor;

  const _RouteGroup({
    required this.routeNo,
    required this.displayLabel,
    required this.variantsNote,
    required this.corridor,
  });
}

class _RouteGroupCard extends StatelessWidget {
  final _RouteGroup group;
  final CrowdPrediction prediction;

  const _RouteGroupCard({required this.group, required this.prediction});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          child: Row(
            children: [
              Text(
                group.displayLabel,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.corridor,
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        PredictionBanner(routeNo: group.routeNo, prediction: prediction),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
          child: Text(
            group.variantsNote,
            style: const TextStyle(
                color: AppTheme.textDim,
                fontSize: 10,
                fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }
}