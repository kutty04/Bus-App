// lib/screens/contribute_screen.dart
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/user_route_service.dart';

class ContributeScreen extends StatelessWidget {
  const ContributeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Contribute Data',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.2),
                  AppTheme.primary.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('🚌', style: TextStyle(fontSize: 28)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Help us grow the dataset',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Our data has gaps. You can fill them.',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                _StatRow(
                  items: [
                    ('161', 'routes'),
                    ('4463', 'stops'),
                    ('?', 'missing'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const _SectionHeader('What would you like to add?'),
          const SizedBox(height: 12),

          // ── Option 1: Add a route ─────────────────────────────────────────
          _ContributeCard(
            icon: '🗺',
            title: 'Add a bus route',
            subtitle:
                'Route number not in our dataset? Add start, end, and optionally all stops.',
            badge: 'Most needed',
            badgeColor: Colors.green,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AddRouteContributePage()),
            ),
          ),

          const SizedBox(height: 12),

          // ── Option 2: Add missing stop ────────────────────────────────────
          _ContributeCard(
            icon: '📍',
            title: 'Add a missing stop to existing route',
            subtitle:
                'Route exists but a stop is missing? Add just the stop to the right route.',
            badge: 'Common issue',
            badgeColor: Colors.orange,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AddMissingStopPage()),
            ),
          ),

          const SizedBox(height: 24),

          // ── Known gaps section ────────────────────────────────────────────
          const _SectionHeader('Known gaps in our dataset'),
          const SizedBox(height: 10),
          _GapCard(
            routes: const [
              '19', '19A', '95X', '99', '47D', 'MAA2', '519', '523'
            ],
            corridor: 'OMR / 200 Feet Road',
            description:
                'Many buses on the Pallavaram–Thuraipakkam–Sholinganallur–Kelambakkam corridor are missing or have incomplete stop data.',
            onContribute: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AddRouteContributePage()),
            ),
          ),

          const SizedBox(height: 32),

          const Center(
            child: Text(
              'All contributions are reviewed and added to\nthe live dataset within 24 hours. 🙏',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Route Page — basic + optional detailed
// ─────────────────────────────────────────────────────────────────────────────

class AddRouteContributePage extends StatefulWidget {
  final String? prefillRoute;
  const AddRouteContributePage({super.key, this.prefillRoute});

  @override
  State<AddRouteContributePage> createState() =>
      _AddRouteContributePageState();
}

class _AddRouteContributePageState extends State<AddRouteContributePage> {
  final _routeController = TextEditingController();
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  final _stopsController = TextEditingController();

  bool _showDetailedStops = false;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefillRoute != null) {
      _routeController.text = widget.prefillRoute!;
    }
  }

  @override
  void dispose() {
    _routeController.dispose();
    _startController.dispose();
    _endController.dispose();
    _stopsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final route = _routeController.text.trim();
    final start = _startController.text.trim();
    final end = _endController.text.trim();

    if (route.isEmpty || start.isEmpty || end.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill in route number, start and end stop')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final stopsRaw = _stopsController.text.trim();
      final allStops = stopsRaw.isEmpty
          ? null
          : stopsRaw
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

      await UserRouteService.addRoute(
        routeNo: route.toUpperCase(),
        startStop: start,
        endStop: end,
        additionalStops: allStops,
      );

      setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Add a Bus Route',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _submitted ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text(
              'Contribution saved!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Route ${_routeController.text.toUpperCase()} is now visible to all users with a community badge.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Done',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() {
                  _submitted = false;
                  _routeController.clear();
                  _startController.clear();
                  _endController.clear();
                  _stopsController.clear();
                  _showDetailedStops = false;
                });
              },
              child: const Text('Add another route',
                  style: TextStyle(color: AppTheme.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Info box ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Basic info is enough — just route number, start and end stop. Detailed stops are optional but very helpful.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const _Label('Bus route number *'),
        const SizedBox(height: 6),
        _Field(
          controller: _routeController,
          hint: 'e.g. 19B, 102X, MAA2',
          icon: Icons.directions_bus,
          caps: TextCapitalization.characters,
        ),

        const SizedBox(height: 16),
        const _Label('Starting stop *'),
        const SizedBox(height: 6),
        _Field(
          controller: _startController,
          hint: 'e.g. Kelambakkam Bus Stand',
          icon: Icons.trip_origin,
        ),

        const SizedBox(height: 16),
        const _Label('Ending stop *'),
        const SizedBox(height: 6),
        _Field(
          controller: _endController,
          hint: 'e.g. Broadway Terminus',
          icon: Icons.place,
        ),

        // ── Detailed stops toggle ────────────────────────────────────────
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () =>
              setState(() => _showDetailedStops = !_showDetailedStops),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _showDetailedStops
                    ? AppTheme.primary.withValues(alpha: 0.5)
                    : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _showDetailedStops
                      ? Icons.expand_less
                      : Icons.expand_more,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _showDetailedStops
                            ? 'Hide detailed stops'
                            : 'Add all stops (optional)',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        'Enter every stop in order — very helpful for other commuters',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_showDetailedStops) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.list, color: AppTheme.primary, size: 16),
                    SizedBox(width: 8),
                    _Label('All stops in order'),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Enter one stop per line, in order from start to end',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _stopsController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 12,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText:
                        'Kelambakkam Bus Stand\nKazhipattur\nSholinganallur\nOkkiyam Thuraipakkam\nThuraipakkam\nPerungudi\n...\nBroadway',
                    hintStyle: const TextStyle(
                        color: AppTheme.textDim,
                        fontSize: 12,
                        height: 1.6),
                    filled: true,
                    fillColor: AppTheme.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 32),

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
                : const Text('Submit contribution',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Missing Stop Page
// ─────────────────────────────────────────────────────────────────────────────

class AddMissingStopPage extends StatefulWidget {
  const AddMissingStopPage({super.key});

  @override
  State<AddMissingStopPage> createState() => _AddMissingStopPageState();
}

class _AddMissingStopPageState extends State<AddMissingStopPage> {
  final _routeController = TextEditingController();
  final _stopController = TextEditingController();
  final _afterStopController = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _routeController.dispose();
    _stopController.dispose();
    _afterStopController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final route = _routeController.text.trim();
    final stop = _stopController.text.trim();

    if (route.isEmpty || stop.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill in route number and missing stop')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      // Save as a "stop addition" community route entry
      await UserRouteService.addMissingStop(
        routeNo: route.toUpperCase(),
        missingStop: stop,
        afterStop: _afterStopController.text.trim().nullIfEmpty(),
      );
      setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Add Missing Stop',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _submitted
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('📍', style: TextStyle(fontSize: 56)),
                    const SizedBox(height: 16),
                    const Text('Stop reported!',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      'We\'ll add "${_stopController.text}" to route ${_routeController.text.toUpperCase()} in the next update.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Done',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber,
                          color: Colors.orange, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Use this if a bus route already exists in the app but a stop you use is missing from its list.',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                const _Label('Route number *'),
                const SizedBox(height: 6),
                _Field(
                  controller: _routeController,
                  hint: 'e.g. 102X, 19B',
                  icon: Icons.directions_bus,
                  caps: TextCapitalization.characters,
                ),

                const SizedBox(height: 16),
                const _Label('Missing stop name *'),
                const SizedBox(height: 6),
                _Field(
                  controller: _stopController,
                  hint: 'e.g. Thuraipakkam',
                  icon: Icons.place,
                ),

                const SizedBox(height: 16),
                const _Label('Stop comes after (optional)'),
                const SizedBox(height: 6),
                _Field(
                  controller: _afterStopController,
                  hint: 'e.g. Okkiyam Thuraipakkam',
                  icon: Icons.arrow_downward,
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    'Helps us place the stop in the correct order',
                    style: TextStyle(
                        color: AppTheme.textDim, fontSize: 11),
                  ),
                ),

                const SizedBox(height: 32),
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
                        : const Text('Report missing stop',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600),
      );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextCapitalization caps;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.caps = TextCapitalization.words,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      textCapitalization: caps,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textSecondary),
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700),
      );
}

class _ContributeCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final VoidCallback onTap;

  const _ContributeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(badge,
                            style: TextStyle(
                                color: badgeColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppTheme.textDim),
          ],
        ),
      ),
    );
  }
}

class _GapCard extends StatelessWidget {
  final List<String> routes;
  final String corridor;
  final String description;
  final VoidCallback onContribute;

  const _GapCard({
    required this.routes,
    required this.corridor,
    required this.description,
    required this.onContribute,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
              const SizedBox(width: 6),
              Text(corridor,
                  style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(description,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: routes
                .map((r) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: Text(r,
                          style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onContribute,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: const Text('Contribute these routes',
                  style:
                      TextStyle(color: AppTheme.primary, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final List<(String, String)> items;
  const _StatRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items
          .map((item) => Expanded(
                child: Column(
                  children: [
                    Text(item.$1,
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    Text(item.$2,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

extension on String {
  String? nullIfEmpty() => isEmpty ? null : this;
}
