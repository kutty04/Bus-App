import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../models.dart';
import '../services/supabase_service.dart';
import '../services/location_service.dart';
import '../services/journey_service.dart';
import '../data/mtc_data.dart';
import '../services/user_route_service.dart';
import '../services/commute_memory_service.dart'; // ✅ NEW

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _reporterName = '';
  String _selectedRoute = '';
  String _selectedStop = '';
  int _crowdingLevel = 50;
  bool _justLeft = false;
  bool _isAc = false;

  // ── Ladies bus & safety ───────────────────────────────────────────
  bool? _isLadiesBus;
  String? _safetyFlag;

  bool _gpsLoading = false;
  String _gpsStatus = '';
  GpsFailReason? _gpsFailReason;
  List<NearestStopResult> _nearbyStops = [];
  NearestStopResult? _selectedNearby;
  double? _userLat;
  double? _userLng;

  bool _showStopSearch = false;
  // ignore: unused_field
  List<NearestStopResult> _stopSearchResults = [];
  List<String> _uniqueStopNames = [];

  List<_RouteSuggestion> _routeSuggestions = [];
  bool _showRouteSuggestions = false;
  String _selectedDirection = '';

  final _stopSearchController = TextEditingController();
  final _manualRouteController = TextEditingController();
  final _manualStopController = TextEditingController();
  late final TextEditingController _nameController;
  final _routeController = TextEditingController();
  final _routeInputController = TextEditingController();

  bool _submitting = false;
  String _deviceId = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _loadReporterName();
    _loadDeviceId();
    _autoDetectLocation();
  }

  @override
  void dispose() {
    _stopSearchController.dispose();
    _manualRouteController.dispose();
    _manualStopController.dispose();
    _routeController.dispose();
    _routeInputController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadReporterName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('reporterName') ?? '';
    setState(() => _reporterName = name);
    _nameController.text = name;
  }

  Future<void> _loadDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String id = prefs.getString('device_id') ?? '';
    if (id.isEmpty) {
      id = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setString('device_id', id);
    }
    setState(() => _deviceId = id);
  }

  Future<void> _saveReporterName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reporterName', name);
  }

  Future<void> _autoDetectLocation() async {
    setState(() {
      _gpsLoading = true;
      _gpsStatus = 'Detecting your location...';
      _gpsFailReason = null;
      _nearbyStops = [];
      _selectedNearby = null;
    });

    final result = await LocationService.getCurrentPosition();

    if (!result.isSuccess) {
      final reason = result.failReason!;
      setState(() {
        _gpsLoading = false;
        _gpsFailReason = reason;
        _gpsStatus = _statusMessageFor(reason);
        _showStopSearch = reason != GpsFailReason.permissionPermanentlyDenied &&
            reason != GpsFailReason.serviceDisabled;
      });
      return;
    }

    final pos = result.position!;
    _userLat = pos.latitude;
    _userLng = pos.longitude;

    final nearby = LocationService.findNearestStops(pos.latitude, pos.longitude);

    if (nearby.isEmpty) {
      setState(() {
        _gpsLoading = false;
        _gpsStatus = 'No stops within 800m — search manually below';
        _showStopSearch = true;
      });
      return;
    }

    setState(() {
      _gpsLoading = false;
      _gpsFailReason = null;
      _nearbyStops = nearby;
      _gpsStatus = 'Found ${nearby.length} nearby stops';
      _selectNearbyStop(nearby.first);
    });
  }

  String _statusMessageFor(GpsFailReason reason) {
    switch (reason) {
      case GpsFailReason.serviceDisabled:
        return 'Location services are off';
      case GpsFailReason.permissionDenied:
        return 'Location permission denied';
      case GpsFailReason.permissionPermanentlyDenied:
        return 'Location permission blocked';
      case GpsFailReason.unknown:
        return 'Location unavailable — search manually below';
    }
  }

  void _selectNearbyStop(NearestStopResult result) {
    setState(() {
      _selectedNearby = result;
      _selectedStop = result.stop.name;
      _selectedRoute = '';
      _selectedDirection = '';
      _routeController.clear();
      _manualRouteController.clear();
      _manualStopController.clear();
    });
  }

  void _onStopQueryChanged(String q) {
    if (q.isEmpty) {
      setState(() {
        _stopSearchResults = [];
        _uniqueStopNames = [];
      });
      return;
    }
    final results = LocationService.searchByStopName(q);
    final seen = <String>{};
    final unique = <String>[];
    for (final r in results) {
      if (seen.add(r.stop.name)) unique.add(r.stop.name);
    }
    setState(() {
      _stopSearchResults = results;
      _uniqueStopNames = unique;
    });

    UserRouteService.searchByStopName(q).then((communityResults) {
      if (!mounted) return;
      for (final cr in communityResults) {
        if (seen.add(cr.stopName)) unique.add(cr.stopName);
      }
      setState(() => _uniqueStopNames = List.from(unique));
    });
  }

  void _onStopNameTapped(String stopName) {
    _stopSearchController.clear();
    setState(() {
      _selectedStop = stopName;
      _selectedRoute = '';
      _selectedDirection = '';
      _selectedNearby = null;
      _stopSearchResults = [];
      _uniqueStopNames = [];
      _showStopSearch = false;
      _routeInputController.clear();
      _routeSuggestions = [];
      _showRouteSuggestions = false;
    });
  }

  // ignore: unused_element
  void _confirmStopAndRoute(NearestStopResult result) {
    _stopSearchController.clear();
    setState(() {
      _selectedStop = result.stop.name;
      _selectedRoute = '';
      _selectedDirection = '';
      _selectedNearby = result;
      _stopSearchResults = [];
      _uniqueStopNames = [];
      _showStopSearch = false;
      _manualRouteController.clear();
      _manualStopController.clear();
      _routeInputController.clear();
      _routeSuggestions = [];
      _showRouteSuggestions = false;
    });
  }

  /// Extracts the base route number that passengers actually see on the bus.
  /// GTFS internally stores variants like "119 CT1", "102 CT19", "91 CT2".
  /// These CT/R/P suffixes are MTC depot codes — not real bus numbers.
  /// This strips them so the dropdown shows "119", "102", "91" as expected.
  String _baseRouteNo(String rawRouteNo) {
    // Remove everything after the first space that looks like a depot code
    // Examples: "119 CT1" → "119", "102 CT19" → "102", "91 CT" → "91"
    // Keep routes that are naturally alphanumeric like "1C", "M70", "12D"
    final parts = rawRouteNo.trim().split(' ');
    if (parts.length == 1) return parts[0]; // already clean e.g. "19", "1C"
    // Second part is a depot code if it starts with CT, R, P, or is all digits
    final suffix = parts[1].toUpperCase();
    if (suffix.startsWith('CT') ||
        suffix.startsWith('R') ||
        suffix.startsWith('P') ||
        RegExp(r'^\d+$').hasMatch(suffix)) {
      return parts[0]; // strip depot suffix
    }
    return rawRouteNo; // keep as-is for anything else
  }

  void _onRouteQueryChanged(String q) {
    if (q.trim().isEmpty) {
      setState(() {
        _routeSuggestions = [];
        _showRouteSuggestions = false;
        _selectedRoute = '';
        _selectedDirection = '';
      });
      return;
    }
    final query = q.trim().toUpperCase();
    final seen = <String>{};
    final suggestions = <_RouteSuggestion>[];

    for (final route in kMtcRoutes) {
      final baseNo = _baseRouteNo(route.routeNo);
      // Match against the base number (what user types) not the internal GTFS ID
      if (baseNo.toUpperCase().startsWith(query) ||
          baseNo.toUpperCase().contains(query)) {
        // Deduplicate by base route number — one entry per real bus number
        if (seen.add(baseNo)) {
          // Find the best representative route for this base number:
          // prefer the one whose routeNo exactly equals the base (no suffix)
          final representative = kMtcRoutes.firstWhere(
            (r) => _baseRouteNo(r.routeNo) == baseNo && r.routeNo == baseNo,
            orElse: () => kMtcRoutes.firstWhere(
              (r) => _baseRouteNo(r.routeNo) == baseNo,
            ),
          );
          suggestions.add(_RouteSuggestion(
            routeNo: baseNo,
            direction: '${representative.source} → ${representative.destination}',
          ));
        }
      }
    }
    suggestions.sort((a, b) => a.routeNo.compareTo(b.routeNo));
    setState(() {
      _routeSuggestions = suggestions.take(10).toList();
      _showRouteSuggestions = suggestions.isNotEmpty;
      _selectedRoute = q.trim();
      _selectedDirection = '';
    });

    UserRouteService.searchRouteNumbers(q.trim()).then((communityRoutes) {
      if (!mounted) return;
      for (final r in communityRoutes) {
        final key = '${r}____';
        if (seen.add(key)) {
          suggestions.add(_RouteSuggestion(routeNo: r, direction: ''));
        }
      }
      if (suggestions.isEmpty) return;
      setState(() {
        _routeSuggestions = suggestions.take(12).toList();
        _showRouteSuggestions = true;
      });
    });
  }

  // ignore: unused_element
  String _getRouteDirection(String routeNo) {
    try {
      final route = kMtcRoutes.firstWhere(
        (r) => r.routeNo == routeNo,
        orElse: () => kMtcRoutes.firstWhere(
          (r) => _baseRouteNo(r.routeNo) == routeNo,
        ),
      );
      return '${route.source} → ${route.destination}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _submit() async {
    final route = _selectedRoute.isNotEmpty
        ? _selectedRoute
        : _routeInputController.text.trim();
    final stop = _selectedStop.isNotEmpty
        ? _selectedStop
        : _manualStopController.text.trim();

    if (route.isEmpty || stop.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter both a route number and stop name')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // ── Submit crowding report ────────────────────────────────────
      await SupabaseService.submitReport(
        busRoute: route,
        crowdingLevel: _crowdingLevel,
        boardingStop: stop,
        reporterName: _reporterName.isEmpty ? 'Anonymous' : _reporterName,
        justLeft: _justLeft,
        isAc: _isAc,
        isLadiesBus: _isLadiesBus,
        latitude: _userLat,
        longitude: _userLng,
      );

      // ── Submit safety flag separately if user flagged one ─────────
      if (_safetyFlag != null) {
        await SupabaseService.submitSafetyReport(
          busRoute: route,
          boardingStop: stop,
          concernType: _safetyFlag!,
        );
      }

      // ✅ NEW — record this route to commute memory (local, private)
      await CommuteMemoryService.instance.recordReport(route, stop);

      await _saveReporterName(_reporterName);

      if (!mounted) return;

      final journeyService = context.read<JourneyService>();

      if (!journeyService.hasActiveJourney) {
        await _showStartJourneySheet(journeyService, route, stop);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Report submitted! Check-in added to your journey.'),
            backgroundColor: Color(0xFF22c55e),
          ),
        );
      }

      // ── Reset form ────────────────────────────────────────────────
      setState(() {
        _crowdingLevel = 50;
        _justLeft = false;
        _isLadiesBus = null;
        _safetyFlag = null;
        _selectedNearby = null;
        _selectedRoute = '';
        _selectedDirection = '';
        _manualRouteController.clear();
        _manualStopController.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not submit. Check your connection.'),
            backgroundColor: Colors.red.shade700,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _submit,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showStartJourneySheet(
      JourneyService journeyService, String route, String stop) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            const Text('Report saved! 🎉',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Are you boarding this bus now?',
                style: TextStyle(color: Colors.white60, fontSize: 14)),
            const SizedBox(height: 8),
            Text('Route $route · $stop',
                style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await journeyService.startJourney(
                    routeNo: route,
                    startStop: stop,
                    deviceId: _deviceId,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Journey started! Tap the green bar anytime 🚌'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Start Journey 🚌',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('✅ Report submitted! Thanks for helping commuters.'),
                    backgroundColor: Color(0xFF22c55e),
                  ),
                );
              },
              child: const Text('Not right now',
                  style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Report Crowding',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Re-detect location',
            onPressed: _gpsLoading ? null : _autoDetectLocation,
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── GPS Status / Permission card ──────────────────────────
          _GpsStatusCard(
            loading: _gpsLoading,
            status: _gpsStatus,
            failReason: _gpsFailReason,
            nearbyStops: _nearbyStops,
            selected: _selectedNearby,
            onSelect: _selectNearbyStop,
            onOpenSettings: () async {
              await Geolocator.openAppSettings();
            },
            onOpenLocationSettings: () async {
              await Geolocator.openLocationSettings();
            },
          ),
          const SizedBox(height: 16),

          // ── Manual Search Toggle ──────────────────────────────────
          if (_showStopSearch || _nearbyStops.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Or search manually',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
                TextButton(
                  onPressed: () =>
                      setState(() => _showStopSearch = !_showStopSearch),
                  child: Text(_showStopSearch ? 'Hide' : 'Search manually'),
                ),
              ],
            ),
          ],

          if (_showStopSearch) ...[
            TextField(
              controller: _stopSearchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search stop name (e.g. Adyar, Guindy)',
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _stopSearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _stopSearchController.clear();
                          _onStopQueryChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onChanged: _onStopQueryChanged,
            ),

            if (_uniqueStopNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
                      child: Text('Tap stop → choose your bus route',
                          style: TextStyle(
                              color: AppTheme.textDim,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                    ..._uniqueStopNames.take(8).map((stopName) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.place,
                            color: AppTheme.primary, size: 18),
                        title: Text(stopName,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        onTap: () => _onStopNameTapped(stopName),
                      );
                    }),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
          ],

          // ── Selected Stop display + bus number entry ───────────────
          if (_selectedStop.isNotEmpty) ...[
            _InfoChip(
                label: 'Stop', value: _selectedStop, icon: Icons.place),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedStop = '';
                  _selectedRoute = '';
                  _selectedNearby = null;
                  _showStopSearch = true;
                });
              },
              icon: const Icon(Icons.swap_horiz, size: 16, color: AppTheme.primary),
              label: const Text('Change stop',
                  style: TextStyle(color: AppTheme.primary, fontSize: 12)),
            ),
            const SizedBox(height: 8),
            const _SectionLabel('Bus number'),
            const SizedBox(height: 6),
            if (_selectedRoute.isNotEmpty && _selectedDirection.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppTheme.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz, size: 14, color: AppTheme.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedDirection,
                        style: const TextStyle(
                            color: AppTheme.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            TextField(
              controller: _routeInputController,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'e.g. 19B, M70, 21D',
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                prefixIcon: const Icon(Icons.directions_bus_outlined),
                suffixIcon: _routeInputController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _routeInputController.clear();
                          setState(() {
                            _selectedRoute = '';
                            _selectedDirection = '';
                            _routeSuggestions = [];
                            _showRouteSuggestions = false;
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onChanged: _onRouteQueryChanged,
            ),
            if (_showRouteSuggestions) ...[
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: _routeSuggestions.map((suggestion) {
                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: AppTheme.blue,
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(suggestion.routeNo,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                      title: suggestion.direction.isNotEmpty
                          ? Text(
                              suggestion.direction,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12),
                            )
                          : const Text('Community route',
                              style: TextStyle(
                                  color: AppTheme.textDim, fontSize: 11)),
                      onTap: () {
                        setState(() {
                          _selectedRoute = suggestion.routeNo;
                          _selectedDirection = suggestion.direction;
                          _routeInputController.text = suggestion.routeNo;
                          _routeSuggestions = [];
                          _showRouteSuggestions = false;
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],

          // ── Crowding Level ────────────────────────────────────────
          const _SectionLabel('How crowded is the bus?'),
          const SizedBox(height: 8),
          Row(
            children: [
              _CrowdingButton(
                  level: 20,
                  selected: _crowdingLevel == 20,
                  onTap: () => setState(() => _crowdingLevel = 20)),
              const SizedBox(width: 8),
              _CrowdingButton(
                  level: 50,
                  selected: _crowdingLevel == 50,
                  onTap: () => setState(() => _crowdingLevel = 50)),
              const SizedBox(width: 8),
              _CrowdingButton(
                  level: 90,
                  selected: _crowdingLevel == 90,
                  onTap: () => setState(() => _crowdingLevel = 90)),
            ],
          ),
          const SizedBox(height: 16),

          // ── Toggles ───────────────────────────────────────────────
          _ToggleTile(
            label: '🚌 Bus Just Left?',
            subtitle: 'The bus departed from this stop',
            value: _justLeft,
            onChanged: (v) => setState(() => _justLeft = v),
          ),
          _ToggleTile(
            label: '❄️ AC Bus?',
            subtitle: 'Air-conditioned bus',
            value: _isAc,
            onChanged: (v) => setState(() => _isAc = v),
          ),
          const SizedBox(height: 16),

          // ── Ladies Bus Selector ───────────────────────────────────
          const _SectionLabel('🚺 Free Ladies Bus?'),
          const SizedBox(height: 8),
          _LadiesBusSelector(
            value: _isLadiesBus,
            onChanged: (v) => setState(() => _isLadiesBus = v),
          ),
          const SizedBox(height: 16),

          // ── Safety Flag (optional, anonymous) ─────────────────────
          _SafetyFlagSection(
            selectedFlag: _safetyFlag,
            onFlagChanged: (flag) => setState(() => _safetyFlag = flag),
          ),
          const SizedBox(height: 16),

          // ── Reporter Name ─────────────────────────────────────────
          const _SectionLabel('Your name (optional)'),
          const SizedBox(height: 8),
          TextField(
            style: const TextStyle(color: Colors.white),
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'Anonymous',
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              prefixIcon: const Icon(Icons.person_outline),
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
            onChanged: (v) => _reporterName = v,
          ),
          const SizedBox(height: 24),

          // ── Submit ────────────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _submitting
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)
                  : const Text('Submit Report',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Ladies Bus Selector ───────────────────────────────────────────────────────

class _LadiesBusSelector extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?> onChanged;

  const _LadiesBusSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tamil Nadu free bus exclusively for women',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _LadiesOption(
                label: '✅ Yes',
                selected: value == true,
                color: const Color(0xFF22c55e),
                onTap: () => onChanged(value == true ? null : true),
              ),
              const SizedBox(width: 8),
              _LadiesOption(
                label: '❌ No',
                selected: value == false,
                color: Colors.red.shade400,
                onTap: () => onChanged(value == false ? null : false),
              ),
              const SizedBox(width: 8),
              _LadiesOption(
                label: '🤷 Not Sure',
                selected: value == null,
                color: Colors.orange,
                onTap: () => onChanged(null),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LadiesOption extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _LadiesOption({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : AppTheme.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : Colors.white12,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? color : AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Safety Flag Section ───────────────────────────────────────────────────────

class _SafetyFlagSection extends StatelessWidget {
  final String? selectedFlag;
  final ValueChanged<String?> onFlagChanged;

  const _SafetyFlagSection({
    required this.selectedFlag,
    required this.onFlagChanged,
  });

  static const _concerns = [
    ('overcrowded', '😰 Overcrowded beyond comfort'),
    ('poor_lighting', '🌑 Poor lighting / dark route'),
    ('feeling_unsafe', '⚠️ Feeling unsafe'),
    ('disruptive', '🍺 Drunk / disruptive passengers'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selectedFlag != null
              ? Colors.orange.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🔴 ', style: TextStyle(fontSize: 14)),
              Text(
                'Flag a safety concern? (optional)',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Completely anonymous — never linked to your name',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 12),
          ..._concerns.map((c) {
            final (key, label) = c;
            final isSelected = selectedFlag == key;
            return GestureDetector(
              onTap: () => onFlagChanged(isSelected ? null : key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.orange.withValues(alpha: 0.12)
                      : AppTheme.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? Colors.orange : Colors.white12,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color:
                              isSelected ? Colors.orange : Colors.white70,
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle,
                          color: Colors.orange, size: 18),
                  ],
                ),
              ),
            );
          }),
          if (selectedFlag != null) ...[
            const SizedBox(height: 4),
            const Text(
              'Tap again to remove flag',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

// ── GPS Status Card ───────────────────────────────────────────────────────────

class _GpsStatusCard extends StatelessWidget {
  final bool loading;
  final String status;
  final GpsFailReason? failReason;
  final List<NearestStopResult> nearbyStops;
  final NearestStopResult? selected;
  final void Function(NearestStopResult) onSelect;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenLocationSettings;

  const _GpsStatusCard({
    required this.loading,
    required this.status,
    required this.failReason,
    required this.nearbyStops,
    required this.selected,
    required this.onSelect,
    required this.onOpenSettings,
    required this.onOpenLocationSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_statusIcon, color: _borderColor, size: 18),
              const SizedBox(width: 8),
              if (loading)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Expanded(
                  child: Text(status,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                ),
            ],
          ),
          if (!loading && failReason != null) ...[
            const SizedBox(height: 12),
            _PermissionDeniedHint(
              reason: failReason!,
              onOpenSettings: onOpenSettings,
              onOpenLocationSettings: onOpenLocationSettings,
            ),
          ],
          if (nearbyStops.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...nearbyStops.take(4).map((r) => GestureDetector(
                  onTap: () => onSelect(r),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected == r
                          ? AppTheme.primary.withValues(alpha: 0.2)
                          : AppTheme.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected == r
                            ? AppTheme.primary
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_bus,
                            size: 14, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.stop.name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                              Text(
                                  'Route ${r.route.routeNo} · ${LocationService.formatDistance(r.distanceMeters)}',
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                        if (selected == r)
                          const Icon(Icons.check_circle,
                              color: AppTheme.primary, size: 16),
                      ],
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Color get _borderColor {
    if (loading) return AppTheme.primary;
    if (failReason == GpsFailReason.permissionPermanentlyDenied ||
        failReason == GpsFailReason.serviceDisabled) {
      return Colors.orange;
    }
    if (failReason != null) return Colors.white38;
    return AppTheme.primary;
  }

  IconData get _statusIcon {
    if (loading) return Icons.my_location;
    if (failReason == GpsFailReason.permissionPermanentlyDenied ||
        failReason == GpsFailReason.serviceDisabled) {
      return Icons.location_off;
    }
    if (failReason != null) return Icons.location_disabled;
    return Icons.my_location;
  }
}

// ── Permission denied hint ────────────────────────────────────────────────────

class _PermissionDeniedHint extends StatelessWidget {
  final GpsFailReason reason;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenLocationSettings;

  const _PermissionDeniedHint({
    required this.reason,
    required this.onOpenSettings,
    required this.onOpenLocationSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isPermanent = reason == GpsFailReason.permissionPermanentlyDenied;
    final isServiceOff = reason == GpsFailReason.serviceDisabled;

    if (!isPermanent && !isServiceOff) {
      return const Text(
        'Search for your stop manually below.',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isServiceOff
                ? 'Location services are turned off on your device. Enable them to auto-detect nearby stops.'
                : 'Location access was permanently blocked. Open Settings to allow it for Chennai Bus.',
            style: const TextStyle(
                color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  isServiceOff ? onOpenLocationSettings : onOpenSettings,
              icon: const Icon(Icons.settings_outlined,
                  size: 15, color: Colors.orange),
              label: Text(
                isServiceOff
                    ? 'Open Location Settings'
                    : 'Open App Settings',
                style: const TextStyle(color: Colors.orange, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orange, width: 1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text('Or search your stop manually below',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

// ── Route suggestion model ────────────────────────────────────────────────────

class _RouteSuggestion {
  final String routeNo;
  final String direction;
  const _RouteSuggestion({required this.routeNo, required this.direction});
}

// ── Subwidgets ────────────────────────────────────────────────────────────────

class _CrowdingButton extends StatelessWidget {
  final int level;
  final bool selected;
  final VoidCallback onTap;

  const _CrowdingButton(
      {required this.level, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final info = getCrowdingInfo(level);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? info.color.withValues(alpha: 0.2) : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? info.color : Colors.transparent, width: 2),
          ),
          child: Column(
            children: [
              Text(info.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(info.label,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile(
      {required this.label,
      required this.subtitle,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        title: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(subtitle,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppTheme.primary,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600),
      );
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoChip(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: AppTheme.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 10),
          Text('$label: ',
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}