import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/accounts_screen.dart';
import 'screens/entry_form_screen.dart';
import 'screens/fd_screen.dart';
import 'screens/lend_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/report_screen.dart';
import 'screens/shell.dart';
import 'services/backup_service.dart';
import 'services/reminders.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'utils/format.dart';

/// Lets reminders open pages from outside the widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.black,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final state = await AppState.create();
  try {
    await Reminders.init();
  } catch (e) {
    debugPrint('Reminders unavailable: $e');
  }
  runApp(ChangeNotifierProvider.value(value: state, child: const FundsApp()));
}

class FundsApp extends StatefulWidget {
  const FundsApp({super.key});

  @override
  State<FundsApp> createState() => _FundsAppState();
}

class _FundsAppState extends State<FundsApp> with WidgetsBindingObserver {
  late bool _locked;
  late final AppState _state;
  DateTime? _leftAt;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _locked = _state.appLock;
    WidgetsBinding.instance.addObserver(this);
    _state.addListener(_onDataChanged);
    Reminders.onOpen = _openFromReminder;
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterStart());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _state.removeListener(_onDataChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _afterStart() async {
    final s = _state;
    // Ask once for permission to show reminders.
    if (s.remindersOn && s.setting('notif_asked') != '1') {
      await s.setSetting('notif_asked', '1');
      await Reminders.requestPermission();
    }
    await Reminders.reschedule(s);
    await Reminders.checkBudget(s);
    unawaited(BackupService.autoBackupIfDue(s));
    final payload = await Reminders.launchPayload();
    if (payload != null) _openFromReminder(payload);
  }

  /// Reschedules reminders shortly after the data changes.
  void _onDataChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      await Reminders.reschedule(_state);
      await Reminders.checkBudget(_state);
    });
  }

  void _openFromReminder(String payload) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    final context = nav.context;
    final parts = payload.split(':');
    final id = parts.length > 1 ? int.tryParse(parts[1]) : null;
    switch (parts.first) {
      case 'add':
        currentTab.value = Tabs.home;
        openEntryForm(context);
      case 'plans':
        currentTab.value = Tabs.plans;
      case 'accounts':
        openAccounts(context);
      case 'person':
        if (id != null) openPerson(context, id);
      case 'fd':
        if (id != null) openFd(context, id);
      case 'report':
        currentTab.value = Tabs.home;
        if (parts.length > 1) openReport(context, parseMonth(parts[1]));
      default:
        currentTab.value = Tabs.home;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final s = _state;
    if (lifecycle == AppLifecycleState.paused) {
      // Leaving for the share sheet / file picker does not count.
      _leftAt = s.externalActivity ? null : DateTime.now();
    } else if (lifecycle == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (s.appLock &&
          !_locked &&
          left != null &&
          DateTime.now().difference(left).inSeconds >= s.lockAfterSeconds) {
        setState(() => _locked = true);
      }
      // A new day may have started while the app was in the background.
      s.postDuePlans();
      unawaited(BackupService.autoBackupIfDue(s));
      _onDataChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Funds',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: const Shell(),
      builder: (context, child) {
        return Stack(
          children: [
            ExcludeSemantics(
              excluding: _locked,
              child: TickerMode(enabled: !_locked, child: child!),
            ),
            if (_locked)
              Positioned.fill(
                child: LockScreen(onUnlocked: () => setState(() => _locked = false)),
              ),
          ],
        );
      },
    );
  }
}
