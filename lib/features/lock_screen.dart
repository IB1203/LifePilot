import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../core/local_store.dart';
import '../core/models.dart';
import '../core/secure.dart';
import '../ui/widgets.dart';

/// Tracks whether the app (or the finance area) is unlocked.
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController(this.store) {
    _unlocked = !store.settings.lockEnabled;
    WidgetsBinding.instance.addObserver(this);
  }

  final LifePilotStore store;
  bool _unlocked = true;
  DateTime? _backgroundedAt;

  /// Lock again after the app has been in the background this long.
  static const relockAfter = Duration(seconds: 30);

  bool get enabled => store.settings.lockEnabled;
  bool get unlocked => !enabled || _unlocked;
  bool get appLocked =>
      enabled && !_unlocked && store.settings.lockScope == LockScope.app;
  bool get financeLocked => enabled && !_unlocked;

  void unlock() {
    _unlocked = true;
    notifyListeners();
  }

  void lockNow() {
    if (!enabled) return;
    _unlocked = false;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null && DateTime.now().difference(since) >= relockAfter) {
        lockNow();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class AppLockScope extends InheritedNotifier<AppLockController> {
  const AppLockScope({
    required AppLockController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppLockController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLockScope>()?.notifier;
}

/// Covers [child] with the lock screen while the whole app is locked.
class AppLockGate extends StatelessWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = AppLockScope.maybeOf(context);
    if (controller == null || !controller.appLocked) return child;
    return LockScreen(
      store: controller.store,
      onUnlocked: controller.unlock,
    );
  }
}

/// Asks for the PIN (or biometrics) before opening the finance area when
/// the lock covers finance only. Returns whether access is allowed.
Future<bool> ensureFinanceUnlocked(BuildContext context) async {
  final controller = AppLockScope.maybeOf(context);
  if (controller == null || !controller.financeLocked) return true;
  final unlocked = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (routeContext) => LockScreen(
        store: controller.store,
        reason: 'Unlock to open Finance',
        onUnlocked: () {
          controller.unlock();
          Navigator.pop(routeContext, true);
        },
      ),
    ),
  );
  return unlocked == true;
}

/// Asks for the PIN (or biometrics) again before a sensitive action: a UPI
/// payment, an export, a restore, deleting data or weakening the lock.
/// Returns true straight away when the lock is off, or when the user turned
/// these checks off and [always] is false.
Future<bool> confirmIdentity(
  BuildContext context,
  LifePilotStore store,
  String reason, {
  bool always = false,
}) async {
  final settings = store.settings;
  if (!settings.lockEnabled) return true;
  if (!settings.confirmSensitive && !always) return true;
  final confirmed = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (routeContext) => LockScreen(
        store: store,
        title: 'Confirm it\'s you',
        reason: reason,
        onUnlocked: () => Navigator.pop(routeContext, true),
      ),
    ),
  );
  return confirmed == true;
}

class LockScreen extends StatefulWidget {
  const LockScreen({
    required this.store,
    required this.onUnlocked,
    this.title = 'LifePilot is locked',
    this.reason = 'Enter your PIN to continue',
    super.key,
  });

  final LifePilotStore store;
  final VoidCallback onUnlocked;
  final String title;
  final String reason;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _auth = LocalAuthentication();
  String _pin = '';
  String? _error;
  bool _checking = false;
  DateTime? _blockedUntil;
  Timer? _blockTimer;
  bool _biometricsAvailable = false;

  @override
  void initState() {
    super.initState();
    // A lockout survives closing and reopening the app.
    _block(widget.store.settings.pinLockedUntil);
    if (widget.store.settings.lockUseBiometrics) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
    }
  }

  void _block(DateTime? until) {
    _blockTimer?.cancel();
    if (until == null || !DateTime.now().isBefore(until)) {
      _blockedUntil = null;
      return;
    }
    _blockedUntil = until;
    _error = _blockMessage();
    _blockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_blocked) {
          _error = _blockMessage();
        } else {
          timer.cancel();
          _error = null;
        }
      });
    });
  }

  String _blockMessage() {
    final left = _blockedUntil!.difference(DateTime.now());
    final seconds = left.inSeconds + 1;
    final wait = seconds >= 60 ? '${(seconds / 60).ceil()} min' : '$seconds s';
    return 'Too many attempts. Try again in $wait.';
  }

  Future<void> _unlocked() async {
    await widget.store.clearPinFailures();
    if (mounted) widget.onUnlocked();
  }

  @override
  void dispose() {
    _blockTimer?.cancel();
    super.dispose();
  }

  Future<void> _tryBiometrics() async {
    try {
      final supported =
          await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
      if (!mounted) return;
      setState(() => _biometricsAvailable = supported);
      if (!supported) return;
      final ok = await _auth.authenticate(
        localizedReason: widget.reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (ok && mounted) await _unlocked();
    } on Object {
      // Fall back to the PIN; biometrics can fail for many device reasons.
      if (mounted) setState(() => _biometricsAvailable = false);
    }
  }

  bool get _blocked =>
      _blockedUntil != null && DateTime.now().isBefore(_blockedUntil!);

  Future<void> _press(String digit) async {
    if (_checking || _blocked || _pin.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += digit;
      _error = null;
    });
    final settings = widget.store.settings;
    // PINs are 4–6 digits; try once the length could match.
    if (_pin.length < 4) return;
    setState(() => _checking = true);
    final ok =
        await verifyPin(_pin, settings.pinHash ?? '', settings.pinSalt ?? '');
    if (!mounted) return;
    if (ok) {
      await _unlocked();
      return;
    }
    setState(() => _checking = false);
    if (_pin.length < 6) return;
    _fail();
  }

  Future<void> _fail() async {
    HapticFeedback.heavyImpact();
    setState(() {
      _pin = '';
      _checking = true;
    });
    final until = await widget.store.recordPinFailure();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = 'Incorrect PIN';
      _block(until);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String label, {VoidCallback? onTap, Widget? child}) => SizedBox(
          width: 76,
          height: 76,
          child: TextButton(
            style: TextButton.styleFrom(shape: const CircleBorder()),
            onPressed: onTap ?? () => _press(label),
            child: child ??
                Text(label, style: Theme.of(context).textTheme.headlineMedium),
          ),
        );
    final canCancel = Navigator.of(context).canPop();
    return Scaffold(
      appBar: canCancel
          ? AppBar(
              leading: const CloseButton(),
              backgroundColor: Colors.transparent,
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 40, color: scheme.primary),
                const SizedBox(height: 12),
                Text(widget.title,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(widget.reason, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Semantics(
                  label: '${_pin.length} digits entered',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 6; i++)
                        AnimatedContainer(
                          duration: motion(context, 120),
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _pin.length ? scheme.primary : null,
                            border: Border.all(
                                color: i < 4
                                    ? scheme.primary
                                    : scheme.outlineVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: _error == null
                      ? null
                      : Text(_error!, style: TextStyle(color: scheme.error)),
                ),
                for (final row in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [for (final digit in row) key(digit)],
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    key('bio',
                        onTap: _biometricsAvailable ? _tryBiometrics : () {},
                        child: _biometricsAvailable
                            ? Icon(Icons.fingerprint,
                                size: 32, color: scheme.primary)
                            : const SizedBox.shrink()),
                    key('0'),
                    key('del',
                        onTap: () => setState(() {
                              if (_pin.isNotEmpty) {
                                _pin = _pin.substring(0, _pin.length - 1);
                              }
                            }),
                        child: const Icon(Icons.backspace_outlined)),
                  ],
                ),
                if (_pin.length >= 4 && _pin.length < 6 && !_checking)
                  TextButton(
                    onPressed: _fail,
                    child: const Text('That is my full PIN'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the user choose a new 4–6 digit PIN and stores only its hash.
Future<bool> showSetPinDialog(
    BuildContext context, LifePilotStore store) async {
  final first = TextEditingController();
  final second = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var saving = false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Set an app PIN'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Use 4 to 6 digits. If you forget it, the only way back in is to clear the app data, which deletes your records unless you have a backup.'),
              const SizedBox(height: 12),
              TextFormField(
                controller: first,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'New PIN'),
                validator: (value) => value == null || value.length < 4
                    ? 'Enter at least 4 digits.'
                    : null,
              ),
              TextFormField(
                controller: second,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Confirm PIN'),
                validator: (value) =>
                    value != first.text ? 'The PINs do not match.' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed:
                saving ? null : () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    setDialogState(() => saving = true);
                    final hashed = await hashPin(first.text);
                    await store.updateSettings(store.settings.copyWith(
                      pinHash: hashed.hash,
                      pinSalt: hashed.salt,
                      lockEnabled: true,
                      clearPinLockout: true,
                    ));
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
            child: Text(saving ? 'Saving…' : 'Set PIN'),
          ),
        ],
      ),
    ),
  );
  first.dispose();
  second.dispose();
  return ok == true;
}
