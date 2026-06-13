// lib/screens/journey_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/journey_service.dart';
import '../theme.dart';

class JourneyScreen extends StatefulWidget {
  final bool endingJourney;
  final ValueNotifier<int>? reportTabNotifier;
  const JourneyScreen({
    super.key,
    this.endingJourney = false,
    this.reportTabNotifier,
  });

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  bool _showFeedback = false;
  final _endStopController = TextEditingController();
  String? _feedbackCrowding;
  bool _isEnding = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (widget.endingJourney) {
        setState(() => _showFeedback = true);
      }

      // FIX: Read the service once here, before registering the callback.
      // Do NOT capture `context` inside the callback — it may be disposed
      // by the time the Timer fires. Instead capture `svc` directly.
      final svc = context.read<JourneyService>();

      svc.registerCheckinCallback(({
        required String suggestedStop,
        required bool gpsTriggered,
      }) async {
        // FIX: Always guard with `mounted` before any Navigator/context usage.
        // This is what was causing the `_dependents.isEmpty: is not true` crash —
        // the callback was running after the widget was disposed.
        if (!mounted) return;
        await _showCheckinSheet(
          suggestedStop: suggestedStop,
          gpsTriggered: gpsTriggered,
        );
      });
    });
  }

  @override
  void dispose() {
    _endStopController.dispose();
    // FIX: Only unregister if the journey is still active, so the service
    // doesn't lose its callback reference when the screen is briefly rebuilt.
    // Use a try-catch because context.read can fail during dispose in edge cases.
    try {
      final svc = context.read<JourneyService>();
      if (svc.hasActiveJourney) svc.unregisterCheckinCallback();
    } catch (_) {}
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<JourneyService>(
      builder: (context, svc, _) {
        // ── No active journey — show empty state instead of popping ──
        if (!svc.hasActiveJourney && !_showFeedback) {
          return Scaffold(
            backgroundColor: AppTheme.darkTheme.scaffoldBackgroundColor,
            appBar: AppBar(
              backgroundColor: const Color(0xFF121212),
              title: const Text('Journey',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: _NoJourneyEmpty(
              reportTabNotifier:
                  widget.reportTabNotifier ?? ValueNotifier<int>(0),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppTheme.darkTheme.scaffoldBackgroundColor,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            title: Text(
              _showFeedback ? 'Journey Complete' : 'Active Journey',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _showFeedback
              ? _buildFeedbackView(context, svc)
              : _buildActiveView(context, svc),
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────
  // Active journey view
  // ───────────────────────────────────────────────────────────────

  Widget _buildActiveView(BuildContext context, JourneyService svc) {
    final journey = svc.activeJourney!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status card
          _StatusCard(journey: journey, svc: svc),

          const SizedBox(height: 24),

          // Check-in history
          if (svc.checkins.isNotEmpty) ...[
            const Text(
              'Check-ins',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...svc.checkins.reversed.map((c) => _CheckinTile(checkin: c)),
            const SizedBox(height: 24),
          ],

          if (svc.checkins.isEmpty) ...[
            const _NoCheckinsYet(),
            const SizedBox(height: 24),
          ],

          // Manual check-in button
          OutlinedButton.icon(
            onPressed: svc.checkinPending
                ? null
                : () => _showCheckinSheet(
                      suggestedStop: svc.currentStopGuess,
                      gpsTriggered: false,
                    ),
            icon: const Icon(Icons.location_on_outlined,
                color: Colors.white70, size: 18),
            label: const Text(
              'Update crowding now',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),

          const SizedBox(height: 32),

          // End journey button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _showFeedback = true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'End Journey',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Auto-ends after 10 min stationary',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────
  // Mid-journey check-in bottom sheet
  // FIX: Capture `svc` BEFORE the await so we never touch `context`
  //      after the widget might have been disposed.
  // ───────────────────────────────────────────────────────────────

  Future<void> _showCheckinSheet({
    required String suggestedStop,
    required bool gpsTriggered,
  }) async {
    // FIX: Guard mounted BEFORE any async/Navigator usage
    if (!mounted) return;

    // FIX: Capture svc reference here, not inside sheet builder.
    // This avoids stale context issues inside StatefulBuilder callbacks.
    final svc = context.read<JourneyService>();

    String stopName = suggestedStop;
    String? selectedCrowding;
    final stopController = TextEditingController(text: suggestedStop);

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: gpsTriggered
                          ? Colors.blue.withValues(alpha: 0.15)
                          : Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      gpsTriggered ? '📍 GPS Update' : '⏱ 5-min Update',
                      style: TextStyle(
                        color: gpsTriggered
                            ? Colors.blueAccent
                            : Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              const Text(
                'Quick check-in',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Route ${svc.activeJourney?.routeNo ?? ''}',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 13),
              ),

              const SizedBox(height: 24),

              // Q1: Still crowded?
              const Text(
                'Is it still crowded?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _CrowdingChip(
                    label: 'Low',
                    emoji: '🟢',
                    value: '20',
                    selected: selectedCrowding == '20',
                    onTap: () =>
                        setSheetState(() => selectedCrowding = '20'),
                  ),
                  const SizedBox(width: 10),
                  _CrowdingChip(
                    label: 'Medium',
                    emoji: '🟡',
                    value: '50',
                    selected: selectedCrowding == '50',
                    onTap: () =>
                        setSheetState(() => selectedCrowding = '50'),
                  ),
                  const SizedBox(width: 10),
                  _CrowdingChip(
                    label: 'High',
                    emoji: '🔴',
                    value: '90',
                    selected: selectedCrowding == '90',
                    onTap: () =>
                        setSheetState(() => selectedCrowding = '90'),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Q2: Which stop?
              const Text(
                'Which stop are you at?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: stopController,
                style: const TextStyle(color: Colors.white),
                onChanged: (v) => stopName = v,
                decoration: InputDecoration(
                  hintText: 'Stop name',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.location_on,
                      color: Colors.white38, size: 18),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),

              const SizedBox(height: 24),

              // Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: selectedCrowding == null
                      ? null
                      : () async {
                          final stop =
                              stopController.text.trim().isNotEmpty
                                  ? stopController.text.trim()
                                  : suggestedStop;
                          // FIX: Pop using ctx (sheet's own context), not outer context
                          Navigator.pop(ctx);
                          await svc.submitCheckin(
                            stopName: stop,
                            crowdingLevel: selectedCrowding!,
                          );
                          // FIX: Guard with mounted before using outer context
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Check-in saved! 🙌'),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    disabledBackgroundColor:
                        Colors.green.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Submit check-in',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  // FIX: Use ctx (sheet's own context) for Navigator.pop
                  onPressed: () {
                    Navigator.pop(ctx);
                    svc.dismissCheckin();
                  },
                  child: const Text(
                    'Skip this time',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // If sheet was dismissed without submitting (back gesture)
    if (svc.checkinPending) svc.dismissCheckin();
    stopController.dispose();
  }

  // ───────────────────────────────────────────────────────────────
  // End-journey feedback view
  // ───────────────────────────────────────────────────────────────

  Widget _buildFeedbackView(BuildContext context, JourneyService svc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          if (svc.hasActiveJourney) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Journey Summary',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  _infoRow('Route', svc.activeJourney!.routeNo),
                  const SizedBox(height: 6),
                  _infoRow('From', svc.activeJourney!.startStop),
                  const SizedBox(height: 6),
                  _infoRow('Duration', svc.formattedDuration),
                  const SizedBox(height: 6),
                  _infoRow(
                      'Check-ins', '${svc.checkins.length} during ride'),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // End stop
          const Text(
            'Where did you get off?',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _endStopController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter stop name (optional)',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
            ),
          ),

          const SizedBox(height: 24),

          // Overall crowding
          const Text(
            'How crowded was your bus overall?',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _CrowdingChip(
                label: 'Low',
                emoji: '🟢',
                value: '20',
                selected: _feedbackCrowding == '20',
                onTap: () => setState(() => _feedbackCrowding = '20'),
              ),
              const SizedBox(width: 10),
              _CrowdingChip(
                label: 'Medium',
                emoji: '🟡',
                value: '50',
                selected: _feedbackCrowding == '50',
                onTap: () => setState(() => _feedbackCrowding = '50'),
              ),
              const SizedBox(width: 10),
              _CrowdingChip(
                label: 'High',
                emoji: '🔴',
                value: '90',
                selected: _feedbackCrowding == '90',
                onTap: () => setState(() => _feedbackCrowding = '90'),
              ),
            ],
          ),

          const SizedBox(height: 36),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isEnding ? null : () => _submitFeedback(svc),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isEnding
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Save & Finish',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed:
                  _isEnding ? null : () => _submitFeedback(svc, skip: true),
              child: const Text(
                'Skip feedback',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitFeedback(JourneyService svc,
      {bool skip = false}) async {
    setState(() => _isEnding = true);
    final endStop =
        skip ? null : _endStopController.text.trim().nullIfEmpty();
    await svc.endJourney(endStop: endStop);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Journey saved! Thanks for contributing 🙌'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 13)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ── Empty: no active journey ──────────────────────────────────────

class _NoJourneyEmpty extends StatelessWidget {
  final ValueNotifier<int> reportTabNotifier;
  const _NoJourneyEmpty({required this.reportTabNotifier});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🗺️', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 20),
            const Text(
              'No active journey',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start a journey from the Report tab\nafter submitting a crowding report.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white54, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                reportTabNotifier.value = 2;
              },
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Go to Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty: journey active but no check-ins yet ────────────────────

class _NoCheckinsYet extends StatelessWidget {
  const _NoCheckinsYet();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: const Row(
        children: [
          Text('📍', style: TextStyle(fontSize: 28)),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No check-ins yet',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                SizedBox(height: 3),
                Text(
                  'Check-ins will appear here as you move.\nYou can also tap "Update crowding now" below.',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared crowding chip ──────────────────────────────────────────

class _CrowdingChip extends StatelessWidget {
  final String label;
  final String emoji;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _CrowdingChip({
    required this.label,
    required this.emoji,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color:
                selected ? Colors.white12 : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.white54 : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Check-in history tile ─────────────────────────────────────────

class _CheckinTile extends StatelessWidget {
  final JourneyCheckin checkin;

  const _CheckinTile({required this.checkin});

  @override
  Widget build(BuildContext context) {
    final emoji = checkin.crowdingLevel == '20'
        ? '🟢'
        : checkin.crowdingLevel == '50'
            ? '🟡'
            : '🔴';
    final label = checkin.crowdingLevel == '20'
        ? 'Low'
        : checkin.crowdingLevel == '50'
            ? 'Medium'
            : 'High';
    final ist = checkin.timestamp
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30));
    final h = ist.hour > 12
        ? ist.hour - 12
        : (ist.hour == 0 ? 12 : ist.hour);
    final m = ist.minute.toString().padLeft(2, '0');
    final ampm = ist.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$h:$m $ampm';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              checkin.stopName,
              style:
                  const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: checkin.crowdingLevel == '20'
                  ? Colors.green
                  : checkin.crowdingLevel == '50'
                      ? Colors.amber
                      : Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            timeStr,
            style:
                const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Status card ───────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final ActiveJourney journey;
  final JourneyService svc;

  const _StatusCard({required this.journey, required this.svc});

  @override
  Widget build(BuildContext context) {
    final ist = journey.startedAt
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30));
    final h = ist.hour > 12
        ? ist.hour - 12
        : (ist.hour == 0 ? 12 : ist.hour);
    final m = ist.minute.toString().padLeft(2, '0');
    final ampm = ist.hour >= 12 ? 'PM' : 'AM';
    final startTime = '$h:$m $ampm';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF69F0AE),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Color(0xFF69F0AE),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (svc.checkins.isNotEmpty)
                Text(
                  '${svc.checkins.length} check-in${svc.checkins.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _row('Route', journey.routeNo),
          const SizedBox(height: 8),
          _row('From', journey.startStop),
          const SizedBox(height: 8),
          _row(
              'Now at',
              svc.currentStopGuess.isNotEmpty
                  ? svc.currentStopGuess
                  : '—'),
          const SizedBox(height: 8),
          _row('Duration', svc.formattedDuration),
          const SizedBox(height: 8),
          _row('Started', startTime),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 13)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

extension on String {
  String? nullIfEmpty() => isEmpty ? null : this;
}