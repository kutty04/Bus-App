// lib/widgets/journey_banner.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/journey_service.dart';
import '../screens/journey_screen.dart';

// The banner does two jobs:
//  1. Shows the persistent green "Journey Active" strip across all tabs
//  2. Registers the check-in callback so the dialog fires even when
//     JourneyScreen is not open (user is on Feed/Route tabs)

class JourneyBanner extends StatefulWidget {
  const JourneyBanner({super.key});

  @override
  State<JourneyBanner> createState() => _JourneyBannerState();
}

class _JourneyBannerState extends State<JourneyBanner> {
  bool _checkinSheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerCallback();
    });
  }

  void _registerCallback() {
    if (!mounted) return;
    final svc = context.read<JourneyService>();
    svc.registerCheckinCallback(({
      required String suggestedStop,
      required bool gpsTriggered,
    }) async {
      if (!mounted || _checkinSheetOpen) return;
      _checkinSheetOpen = true;
      await _showCheckinSheet(
        suggestedStop: suggestedStop,
        gpsTriggered: gpsTriggered,
      );
      _checkinSheetOpen = false;
    });
  }

  Future<void> _showCheckinSheet({
    required String suggestedStop,
    required bool gpsTriggered,
  }) async {
    final svc = context.read<JourneyService>();
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
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 24),
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
                  _chip('Low', '🟢', '20', selectedCrowding,
                      () => setSheetState(() => selectedCrowding = '20')),
                  const SizedBox(width: 10),
                  _chip('Medium', '🟡', '50', selectedCrowding,
                      () => setSheetState(() => selectedCrowding = '50')),
                  const SizedBox(width: 10),
                  _chip('High', '🔴', '90', selectedCrowding,
                      () => setSheetState(() => selectedCrowding = '90')),
                ],
              ),
              const SizedBox(height: 24),
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
                          Navigator.pop(ctx);
                          await svc.submitCheckin(
                            stopName: stop,
                            crowdingLevel: selectedCrowding!,
                          );
                          if (context.mounted) {
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
                  onPressed: () {
                    Navigator.pop(ctx);
                    svc.dismissCheckin();
                  },
                  child: const Text(
                    'Skip this time',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (svc.checkinPending) svc.dismissCheckin();
    stopController.dispose();
  }

  Widget _chip(String label, String emoji, String value,
      String? selected, VoidCallback onTap) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white12 : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.white54 : Colors.transparent,
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
                  color: isSelected ? Colors.white : Colors.white54,
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

  @override
  Widget build(BuildContext context) {
    return Consumer<JourneyService>(
      builder: (context, svc, _) {
        if (!svc.hasActiveJourney) return const SizedBox.shrink();

        final journey = svc.activeJourney!;
        final checkinCount = svc.checkins.length;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const JourneyScreen()),
          ).then((_) => _registerCallback()),
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
              ),
            ),
            child: Row(
              children: [
                _PulsingDot(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Journey Active — Route ${journey.routeNo}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'From ${journey.startStop} · ${svc.formattedDuration}'
                        '${checkinCount > 0 ? ' · $checkinCount check-in${checkinCount == 1 ? '' : 's'}' : ''}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _confirmEndJourney(context, svc),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text(
                    'End',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmEndJourney(
      BuildContext context, JourneyService svc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('End Journey?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will save your journey and prompt you for feedback.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('End Journey'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => const JourneyScreen(endingJourney: true)),
      ).then((_) => _registerCallback());
    }
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFF69F0AE),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
