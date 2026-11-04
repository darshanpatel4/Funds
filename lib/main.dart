import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/lock_screen.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'theme.dart';

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
  runApp(ChangeNotifierProvider.value(value: state, child: const FundsApp()));
}

class FundsApp extends StatefulWidget {
  const FundsApp({super.key});

  @override
  State<FundsApp> createState() => _FundsAppState();
}

class _FundsAppState extends State<FundsApp> with WidgetsBindingObserver {
  late bool _locked;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    _locked = context.read<AppState>().appLock;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final s = context.read<AppState>();
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Funds',
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
