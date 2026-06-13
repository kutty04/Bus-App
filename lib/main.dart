import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/feed_screen.dart';
import 'screens/route_screen.dart';
import 'screens/report_screen.dart';
import 'screens/contribute_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/journey_screen.dart';

import 'services/journey_service.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'services/prediction_service.dart';

import 'widgets/journey_banner.dart';
import 'widgets/no_internet_screen.dart';
import 'theme.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL',
        defaultValue: 'https://olgrwxyqhfvolscdygln.supabase.co'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY',
        defaultValue: 'sb_publishable_X3m7elPG18T2-IdFDwjmrA_0zU3Y4FJ'),
  );

  await ConnectivityService.instance.init();
  await NotificationService().init();
  await PredictionService.instance.init();

  FlutterNativeSplash.remove();

  runApp(
    ChangeNotifierProvider(
      create: (_) => JourneyService(),
      child: const ChennaisBusApp(),
    ),
  );
}

// ── Root App ──────────────────────────────────────────────────────

class ChennaisBusApp extends StatefulWidget {
  const ChennaisBusApp({super.key});

  @override
  State<ChennaisBusApp> createState() => _ChennaisBusAppState();
}

class _ChennaisBusAppState extends State<ChennaisBusApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JourneyService>().restoreJourney();
      _requestNotificationPermissionsOnce();
    });
  }

  Future<void> _requestNotificationPermissionsOnce() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyAsked = prefs.getBool('notif_permission_asked') ?? false;
    if (alreadyAsked) return;
    await prefs.setBool('notif_permission_asked', true);
    final granted = await NotificationService().requestPermissions();
    if (granted) {
      await NotificationService().scheduleAllReminders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chennai Bus Crowding',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      navigatorKey: notificationNavigatorKey,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const _SplashRouter(),
        '/home': (context) =>
            const ConnectivityGuard(child: MainShell()),
        '/onboarding': (context) => const OnboardingScreen(),
      },
    );
  }
}

// ── Splash Router ─────────────────────────────────────────────────

class _SplashRouter extends StatefulWidget {
  const _SplashRouter();

  @override
  State<_SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<_SplashRouter> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_done') ?? false;
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacementNamed(done ? '/home' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(backgroundColor: Color(0xFF121212));
}

// ── Main Shell ────────────────────────────────────────────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  // 4 screens: Feed, By Route, Report, Contribute
  final _screens = const [
    FeedScreen(),
    RouteScreen(),
    ReportScreen(),
    ContributeScreen(),
  ];

  void _tabListener() {
    if (reportTabNotifier.value == 2) {
      setState(() => _currentIndex = 2);
      reportTabNotifier.value = -1;
    }
  }

  void _feedbackListener() {
    if (postJourneyFeedbackNotifier.value) {
      postJourneyFeedbackNotifier.value = false;
      _showPostJourneyFeedback();
    }
  }

  void _contributeListener() {
    if (contributeTabNotifier.value) {
      contributeTabNotifier.value = false;
      setState(() => _currentIndex = 3); // Contribute is now index 3
    }
  }

  void _checkinNudgeListener() {
    if (checkinNudgeTappedNotifier.value) {
      checkinNudgeTappedNotifier.value = false;
      _openJourneyScreen();
    }
  }

  void _openJourneyScreen() {
    if (!mounted) return;
    NotificationService().cancelCheckinNudge();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const JourneyScreen()),
    );
  }

  @override
  void initState() {
    super.initState();
    reportTabNotifier.addListener(_tabListener);
    postJourneyFeedbackNotifier.addListener(_feedbackListener);
    contributeTabNotifier.addListener(_contributeListener);
    checkinNudgeTappedNotifier.addListener(_checkinNudgeListener);
  }

  @override
  void dispose() {
    reportTabNotifier.removeListener(_tabListener);
    postJourneyFeedbackNotifier.removeListener(_feedbackListener);
    contributeTabNotifier.removeListener(_contributeListener);
    checkinNudgeTappedNotifier.removeListener(_checkinNudgeListener);
    super.dispose();
  }

  Future<void> _showPostJourneyFeedback() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _FeedbackSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const JourneyBanner(),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) =>
            setState(() => _currentIndex = i),
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.primary.withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dynamic_feed_outlined),
            selectedIcon: Icon(Icons.dynamic_feed),
            label: 'Live Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'By Route',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note),
            selectedIcon: Icon(Icons.edit_note),
            label: 'Contribute',
          ),
        ],
      ),
    );
  }
}

// ── Feedback Sheet ────────────────────────────────────────────────

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  int _rating = 0;
  String _comment = '';
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 36),
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
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text('How was your ride? 🚌',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text('Your feedback helps improve the app',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          const SizedBox(height: 20),

          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _rating = star),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      _rating >= star ? Icons.star : Icons.star_border,
                      color:
                          _rating >= star ? Colors.amber : Colors.white38,
                      size: 36,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            style: const TextStyle(color: Colors.white),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Any comments? (optional)',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
            onChanged: (v) => _comment = v,
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_rating == 0 || _submitting)
                  ? null
                  : () async {
                      setState(() => _submitting = true);
                      await Future.delayed(
                          const Duration(milliseconds: 300));
                      if (context.mounted) Navigator.pop(context);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)
                  : const Text('Submit Feedback',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Center(
                child: Text('Skip',
                    style: TextStyle(color: Colors.white38))),
          ),
        ],
      ),
    );
  }
}