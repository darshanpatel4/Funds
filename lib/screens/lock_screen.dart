import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/logo.dart';

final _auth = LocalAuthentication();

const _noScreenLock =
    'Set a screen lock (PIN, pattern or fingerprint) on this phone first.';

/// Asks the phone for fingerprint / face / PIN. Returns null on success or a
/// message to show the user.
Future<String?> authenticate(String reason) async {
  try {
    if (!await _auth.isDeviceSupported()) return _noScreenLock;
    final ok = await _auth.authenticate(
      localizedReason: reason,
      biometricOnly: false,
      persistAcrossBackgrounding: true,
    );
    return ok ? null : 'Not unlocked. Try again.';
  } on LocalAuthException catch (e) {
    switch (e.code) {
      case LocalAuthExceptionCode.noCredentialsSet:
        return _noScreenLock;
      case LocalAuthExceptionCode.temporaryLockout:
      case LocalAuthExceptionCode.biometricLockout:
        return 'Too many attempts. Use your phone PIN or try again later.';
      case LocalAuthExceptionCode.userCanceled:
      case LocalAuthExceptionCode.systemCanceled:
      case LocalAuthExceptionCode.authInProgress:
        return 'Not unlocked. Try again.';
      default:
        return e.description ?? 'Could not unlock. Try again.';
    }
  } catch (_) {
    return 'Could not unlock. Try again.';
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final error = await authenticate('Unlock Funds');
    if (!mounted) return;
    if (error == null) {
      widget.onUnlocked();
    } else if (error == _noScreenLock) {
      // The phone has no screen lock (for example a backup with app lock
      // was restored on a new phone). Don't lock the owner out: open the
      // app and turn app lock off until they set a screen lock.
      await context.read<AppState>().setFlag('app_lock', false);
      widget.onUnlocked();
    } else {
      setState(() {
        _busy = false;
        _message = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FundsLogo(size: 72),
                    const SizedBox(height: 20),
                    Text('Funds is locked',
                        style: ts(28, weight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 8),
                    Text(
                      'Unlock with your fingerprint or the PIN you use for this phone.',
                      textAlign: TextAlign.center,
                      style: ts(15, color: C.muted, height: 1.5),
                    ),
                    const SizedBox(height: 56),
                    Semantics(
                      button: true,
                      label: 'Unlock with fingerprint',
                      child: Material(
                        color: C.surface,
                        shape: const CircleBorder(side: BorderSide(color: C.border)),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _unlock,
                          child: const SizedBox(
                            width: 96,
                            height: 96,
                            child: Icon(Icons.fingerprint_rounded, color: C.accent, size: 52),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(_message ?? 'Touch the sensor',
                        textAlign: TextAlign.center,
                        style: ts(13,
                            weight: FontWeight.w600,
                            color: _message == null ? C.muted : C.expense)),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: _unlock,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: C.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('Use phone PIN instead',
                      style: ts(15, weight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 14, color: C.muted),
                  const SizedBox(width: 6),
                  Text('Your data never leaves this phone',
                      style: ts(12, weight: FontWeight.w600, color: C.muted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
