import 'package:flutter/material.dart';
import '../theme.dart';
import '../models.dart';
import '../services/supabase_service.dart';
import '../services/location_service.dart';
import '../services/user_route_service.dart';
import '../services/prediction_service.dart';        // ✅ Your existing service
import '../services/crowd_prediction_service.dart';  // ✅ Fallback service
import '../data/mtc_data.dart';
import '../widgets/report_card.dart';
import '../widgets/time_filter_bar.dart';
import '../widgets/prediction_banner.dart';          // ✅ Show prediction
import '../services/notification_service.dart';

class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key});
  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  String _searchQuery = '';
  String _selectedRoute = '';
  String _timeFilter = 'all';
  List<CrowdingReport> _reports = [];
  bool _loading = false;
  String? _fetchError;
  String _searchMode = 'stop';

  List<MtcRoute> _routeResults = [];
  List<UserRoute> _userRouteResults = [];
  List<NearestStopResult> _stopResults = [];
  bool _noRouteFound = false;

  bool _gpsLoading = false;
  List<NearestStopResult> _nearbyStops = [];

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNearbyStops();
  }

  Future<void> _loadNearbyStops() async {
    setState(() => _gpsLoading = true);
    final result = await LocationService.getCurrentPosition();
    if (result.isSuccess && mounted) {
      final pos = result.position!;
      setState(() => _nearbyStops =
          LocationService.findNearestStops(pos.latitude, pos.longitude));
    }
    if (mounted) setState(() => _gpsLoading = false);
  }

  Future<void> _onSearchChanged(String q) async {
    setState(() {
      _searchQuery = q;
      _noRouteFound = false;
    });
    if (_searchMode == 'route') {
      final lower = q.toLowerCase();
      final mtc = q.isEmpty
          ? <MtcRoute>[]
          : kMtcRoutes
              .where((r) => r.routeNo.toLowerCase().contains(lower))
              .take(10)
              .toList();
      final user =
          q.isEmpty ? <UserRoute>[] : await UserRouteService.searchByRouteNo(q);
      setState(() {
        _routeResults = mtc;
        _userRouteResults = user;
        _noRouteFound = mtc.isEmpty && user.isEmpty && q.length >= 2;
      });
    } else {
      setState(() => _stopResults = LocationService.searchByStopName(q));
    }
  }

  Future<void> _selectRoute(String routeNo) async {
    setState(() {
      _selectedRoute = routeNo;
      _loading = true;
      _fetchError = null;
      _routeResults = [];
      _userRouteResults = [];
      _stopResults = [];
      _noRouteFound = false;
    });
    _searchController.clear();
    try {
      final reports = await SupabaseService.fetchByRoute(routeNo,
          timeFilter: _timeFilter == 'all' ? null : _timeFilter);
      if (mounted) setState(() { _reports = reports; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchError = 'Could not load reports. Check your connection.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectStop(NearestStopResult result) async {
    setState(() {
      _selectedRoute = result.route.routeNo;
      _loading = true;
      _fetchError = null;
      _routeResults = [];
      _userRouteResults = [];
      _stopResults = [];
      _noRouteFound = false;
    });
    _searchController.clear();
    try {
      final reports = await SupabaseService.fetchNearStop(result.stop.name,
          timeFilter: _timeFilter == 'all' ? null : _timeFilter);
      if (mounted) setState(() { _reports = reports; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchError = 'Could not load reports. Check your connection.';
          _loading = false;
        });
      }
    }
  }

  void _retry() {
    if (_selectedRoute.isNotEmpty) _selectRoute(_selectedRoute);
  }

  Future<void> _openAddRoute() async {
    if (!mounted) return;
    contributeTabNotifier.value = true;
  }

  // ✅ NEW: Get prediction using your PredictionService
  CrowdPrediction _getPredictionForRoute(String routeNo) {
    // Try ML prediction first
    final mlPrediction = PredictionService.instance.predict(
      route: routeNo,
      direction: 'DOWN', // Default direction
    );
    
    if (mlPrediction != null) {
      // Convert your CrowdingPrediction to CrowdPrediction format
      return _convertToCrowdPrediction(mlPrediction, routeNo);
    }
    
    // Fallback to rule-based prediction
    return CrowdPredictionService.predict(
      routeNo: routeNo,
      liveReports: _reports,
    );
  }

  // ✅ NEW: Convert your PredictionService's format to PredictionBanner's format
  CrowdPrediction _convertToCrowdPrediction(CrowdingPrediction pred, String routeNo) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('🗺 By Route',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TimeFilterBar(
            selected: _timeFilter,
            onChanged: (v) {
              setState(() => _timeFilter = v);
              if (_selectedRoute.isNotEmpty) _selectRoute(_selectedRoute);
            },
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Mode toggle ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(children: [
              _ModeChip(
                label: '📍 By Stop',
                selected: _searchMode == 'stop',
                onTap: () {
                  setState(() {
                    _searchMode = 'stop';
                    _searchQuery = '';
                    _noRouteFound = false;
                  });
                  _searchController.clear();
                },
              ),
              const SizedBox(width: 8),
              _ModeChip(
                label: '🚌 By Route',
                selected: _searchMode == 'route',
                onTap: () {
                  setState(() {
                    _searchMode = 'route';
                    _searchQuery = '';
                    _noRouteFound = false;
                  });
                  _searchController.clear();
                },
              ),
            ]),
          ),
          const SizedBox(height: 10),

          // ── Search bar ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _searchMode == 'stop'
                    ? 'Search stop name (e.g. Adyar, Guindy)'
                    : 'Search route number (e.g. 19B, 101)',
                hintStyle:
                    const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        })
                    : null,
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // ── Search results ───────────────────────────────────────
          if (_routeResults.isNotEmpty ||
              _userRouteResults.isNotEmpty ||
              _stopResults.isNotEmpty)
            _SearchResults(
              routeResults: _routeResults,
              userRouteResults: _userRouteResults,
              stopResults: _stopResults,
              searchMode: _searchMode,
              onSelectRoute: _selectRoute,
              onSelectStop: _selectStop,
            ),

          // ── "Not found" prompt ───────────────────────────────────
          if (_noRouteFound)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: GestureDetector(
                onTap: _openAddRoute,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.4)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.add_circle_outline, color: AppTheme.primary),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Route not found — Add it!',
                                style: TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            SizedBox(height: 2),
                            Text(
                                'Contribute this route to help other commuters',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12)),
                          ]),
                    ),
                    Icon(Icons.chevron_right, color: AppTheme.primary),
                  ]),
                ),
              ),
            ),

          // ── GPS nearby chips ─────────────────────────────────────
          if (_searchQuery.isEmpty && _nearbyStops.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Row(children: [
                Icon(Icons.my_location, size: 14, color: AppTheme.primary),
                SizedBox(width: 6),
                Text('Nearest stops to you',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            SizedBox(
              height: 52,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _nearbyStops.length,
                itemBuilder: (ctx, i) {
                  final r = _nearbyStops[i];
                  return GestureDetector(
                    onTap: () => _selectStop(r),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(r.stop.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500)),
                            Text(
                                'Route ${r.route.routeNo} · ${LocationService.formatDistance(r.distanceMeters)}',
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 10)),
                          ]),
                    ),
                  );
                },
              ),
            ),
          ],

          if (_searchQuery.isEmpty && _gpsLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Detecting location...',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ]),
            ),

          // ✅ NEW: Show prediction banner when route is selected
          if (_selectedRoute.isNotEmpty && !_loading && _fetchError == null)
            PredictionBanner(
              routeNo: _selectedRoute,
              prediction: _getPredictionForRoute(_selectedRoute),
            ),

          const Divider(height: 1),

          // ── Reports area ─────────────────────────────────────────
          Expanded(
            child: _selectedRoute.isEmpty
                ? _RoutePromptEmpty(searchMode: _searchMode)
                : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _fetchError != null
                        ? _FetchErrorView(
                            error: _fetchError!,
                            onRetry: _retry,
                          )
                        : _reports.isEmpty
                            ? _RouteReportsEmpty(routeNo: _selectedRoute)
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _reports.length,
                                itemBuilder: (ctx, i) =>
                                    ReportCard(report: _reports[i]),
                              ),
          ),
        ],
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────

class _FetchErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _FetchErrorView({required this.error, required this.onRetry});

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
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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

// ── Empty: no route selected yet ─────────────────────────────────

class _RoutePromptEmpty extends StatelessWidget {
  final String searchMode;
  const _RoutePromptEmpty({required this.searchMode});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(searchMode == 'stop' ? '📍' : '🚌',
                style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              searchMode == 'stop' ? 'Search for a stop' : 'Search for a route',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              searchMode == 'stop'
                  ? 'Type a stop name above to see\ncrowding reports near it'
                  : 'Type a route number above to see\nrecent crowding reports',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty: route selected but no reports ─────────────────────────

class _RouteReportsEmpty extends StatelessWidget {
  final String routeNo;
  const _RouteReportsEmpty({required this.routeNo});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔍', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              'No reports for Route $routeNo',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'No one has reported crowding\non this route recently.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline,
                      color: AppTheme.primary, size: 18),
                  SizedBox(width: 8),
                  Text('Be the first to report!',
                      style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search Results dropdown ───────────────────────────────────────

class _SearchResults extends StatelessWidget {
  final List<MtcRoute> routeResults;
  final List<UserRoute> userRouteResults;
  final List<NearestStopResult> stopResults;
  final String searchMode;
  final void Function(String) onSelectRoute;
  final void Function(NearestStopResult) onSelectStop;

  const _SearchResults({
    required this.routeResults,
    required this.userRouteResults,
    required this.stopResults,
    required this.searchMode,
    required this.onSelectRoute,
    required this.onSelectStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      decoration: BoxDecoration(
          color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
      constraints: const BoxConstraints(maxHeight: 260),
      child: ListView(shrinkWrap: true, children: [
        if (searchMode == 'route') ...[
          if (routeResults.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Text('MTC Routes',
                  style: TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
            ...routeResults.map((r) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.directions_bus,
                      color: AppTheme.primary, size: 18),
                  title: Text(r.routeNo,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                  subtitle: Text('${r.source} → ${r.destination}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                  onTap: () => onSelectRoute(r.routeNo),
                )),
          ],
          if (userRouteResults.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Text('Community Routes',
                  style: TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
            ...userRouteResults.map((r) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.people_outline,
                      color: AppTheme.yellow, size: 18),
                  title: Text(r.routeNo,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                  subtitle: Text('${r.startStop} → ${r.endStop}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.yellow.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('community',
                        style: TextStyle(
                            color: AppTheme.yellow, fontSize: 10)),
                  ),
                  onTap: () => onSelectRoute(r.routeNo),
                )),
          ],
        ],
        if (searchMode == 'stop')
          ...stopResults.map((r) => ListTile(
                dense: true,
                leading: const Icon(Icons.place, color: AppTheme.primary, size: 18),
                title: Text(r.stop.name,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13)),
                subtitle: Text('Route ${r.route.routeNo}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11)),
                onTap: () => onSelectStop(r),
              )),
      ]),
    );
  }
}

// ── Mode chip ────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.2)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? AppTheme.primary : Colors.transparent),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
      );
}