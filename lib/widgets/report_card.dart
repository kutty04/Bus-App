import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../theme.dart';
import '../services/supabase_service.dart';

class ReportCard extends StatelessWidget {
  final CrowdingReport report;

  const ReportCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    if (report.justLeft) {
      return _JustLeftCard(report: report);
    }
    return _CrowdingCard(report: report);
  }
}

// ─── Crowding Report Card ──────────────────────────────────────────────────
class _CrowdingCard extends StatelessWidget {
  final CrowdingReport report;
  const _CrowdingCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final info = getCrowdingInfo(report.crowdingLevel);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: info.color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: route badge + crowding + AC badge ─────────────────
          Row(
            children: [
              _RouteBadge(route: report.busRoute),
              const SizedBox(width: 8),
              Text(
                '${info.emoji} ${info.label}',
                style: TextStyle(color: info.color, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const Spacer(),
              _ACBadge(isAC: report.isAc),
            ],
          ),
          const SizedBox(height: 8),

          // ── Middle: stop + reporter ────────────────────────────────────
          Text(
            '📍 ${report.boardingStop ?? '—'}  ·  👤 ${report.reporterName ?? 'Anonymous'}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),

          if (report.isStale) ...[
            const SizedBox(height: 6),
            const Text('⚠️ Data may be stale (>15 min)', style: TextStyle(color: AppTheme.yellow, fontSize: 11)),
          ],

          const SizedBox(height: 10),

          // ── Bottom row: crowding bar + time + helpful ──────────────────
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: report.crowdingLevel / 100,
                    backgroundColor: AppTheme.surfaceAlt,
                    color: info.color,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(report.istTimeString, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              const SizedBox(width: 10),
              _HelpfulButton(report: report),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Just Left Card ────────────────────────────────────────────────────────
class _JustLeftCard extends StatelessWidget {
  final CrowdingReport report;
  const _JustLeftCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: const Border(left: BorderSide(color: AppTheme.indigo, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RouteBadge(route: report.busRoute),
              const SizedBox(width: 8),
              const Text(
                '🚌 Bus Just Left',
                style: TextStyle(color: AppTheme.indigo, fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const Spacer(),
              _ACBadge(isAC: report.isAc),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '📍 ${report.boardingStop ?? '—'}  ·  👤 ${report.reporterName ?? 'Anonymous'}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(report.istTimeString, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              _HelpfulButton(report: report),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Route Badge ──────────────────────────────────────────────────────────
class _RouteBadge extends StatelessWidget {
  final String route;
  const _RouteBadge({required this.route});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.blue,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        route,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

// ─── AC Badge ─────────────────────────────────────────────────────────────
class _ACBadge extends StatelessWidget {
  final bool isAC;
  const _ACBadge({required this.isAC});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isAC ? AppTheme.acBg : AppTheme.nonAcBg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        isAC ? '❄️ AC' : 'Non-AC',
        style: TextStyle(
          color: isAC ? AppTheme.acBlue : AppTheme.nonAcText,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Helpful Button ────────────────────────────────────────────────────────
class _HelpfulButton extends StatefulWidget {
  final CrowdingReport report;
  const _HelpfulButton({required this.report});

  @override
  State<_HelpfulButton> createState() => _HelpfulButtonState();
}

class _HelpfulButtonState extends State<_HelpfulButton> {
  bool _helped = false;
  late int _count;

  @override
  void initState() {
    super.initState();
    _count = widget.report.helpfulCount;
    _checkIfHelped();
  }

  Future<void> _checkIfHelped() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'helpful_${widget.report.id}';
    if (mounted) setState(() => _helped = prefs.getBool(key) ?? false);
  }

  Future<void> _tap() async {
    if (_helped) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('helpful_${widget.report.id}', true);
    try {
      await SupabaseService.markHelpful(widget.report.id);
    } catch (_) {}
    if (mounted) setState(() { _helped = true; _count++; });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _helped ? AppTheme.blueDark : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _helped ? Icons.thumb_up : Icons.thumb_up_outlined,
              size: 12,
              color: _helped ? AppTheme.blueLight : AppTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              '$_count',
              style: TextStyle(
                color: _helped ? AppTheme.blueLight : AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}