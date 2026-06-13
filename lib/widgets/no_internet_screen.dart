// lib/widgets/no_internet_screen.dart

import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../theme.dart';

/// Wraps any child widget. When the device goes offline it replaces
/// the child with a full-screen "No Connection" screen.
/// When connectivity is restored it automatically returns to the child.
class ConnectivityGuard extends StatefulWidget {
  final Widget child;
  const ConnectivityGuard({super.key, required this.child});

  @override
  State<ConnectivityGuard> createState() => _ConnectivityGuardState();
}

class _ConnectivityGuardState extends State<ConnectivityGuard> {
  late bool _online;

  @override
  void initState() {
    super.initState();
    _online = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onStatusChange.listen((online) {
      if (mounted) setState(() => _online = online);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_online) return widget.child;
    return const _NoInternetScreen();
  }
}

// ── Full-screen no-internet UI ────────────────────────────────────

class _NoInternetScreen extends StatelessWidget {
  const _NoInternetScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.white38,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 28),

                // Title
                const Text(
                  'No Internet Connection',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),

                // Subtitle
                const Text(
                  'Chennai Bus Crowding needs an internet connection to load live reports.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

                // Tips
                const _Tip(
                  icon: Icons.signal_cellular_alt,
                  text: 'Check your mobile data is turned on',
                ),
                const SizedBox(height: 10),
                const _Tip(
                  icon: Icons.wifi,
                  text: 'Or connect to a Wi-Fi network',
                ),
                const SizedBox(height: 40),

                // Waiting indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Waiting for connection…',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Tip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white24, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}