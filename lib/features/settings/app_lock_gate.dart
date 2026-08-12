import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_repository.dart';

/// Wraps the whole app; if a PIN is enabled, shows a lock screen first
/// until the correct PIN is entered for this app session.
class AppLockGate extends ConsumerStatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  bool _unlockedThisSession = false;
  final _pinController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _tryUnlock() async {
    final ok = await ref
        .read(settingsRepositoryProvider)
        .verifyPin(_pinController.text.trim());
    if (ok) {
      setState(() => _unlockedThisSession = true);
    } else {
      setState(() => _error = 'رمز الدخول غير صحيح');
      _pinController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => widget.child,
      data: (settings) {
        if (!settings.pinEnabled || _unlockedThisSession) return widget.child;

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, size: 56),
                    const SizedBox(height: 16),
                    const Text('BOND2 مقفل', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: 'أدخل الرمز',
                        errorText: _error,
                      ),
                      onSubmitted: (_) => _tryUnlock(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _tryUnlock, child: const Text('دخول')),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
