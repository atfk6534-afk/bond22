import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/settings_repository.dart';
import 'features/onboarding/welcome_screen.dart';
import 'features/settings/app_lock_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: Bond2App()));
}

class Bond2App extends ConsumerWidget {
  const Bond2App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final themeMode = settingsAsync.maybeWhen(
      data: (s) => switch (s.themeMode) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      },
      orElse: () => ThemeMode.system,
    );

    return MaterialApp.router(
      title: 'BOND2',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: appRouter,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: _StartupGate(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

/// Decides what the user sees first: first-launch Welcome screen
/// (rule #8), the PIN lock gate (rule #56), or the app itself.
class _StartupGate extends ConsumerWidget {
  final Widget child;
  const _StartupGate({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(teacherProfileProvider);

    return profileAsync.when(
      loading: () => const _SplashScreen(),
      error: (e, st) => const Scaffold(
        body: Center(child: Text('حدث خطأ غير متوقع أثناء بدء التطبيق')),
      ),
      data: (profile) {
        if (profile == null) return const WelcomeScreen();
        return AppLockGate(child: child);
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'BOND2',
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
