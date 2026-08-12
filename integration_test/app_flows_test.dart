// Integration test for BOND2's core end-to-end flows (rule #80).
//
// NOTE: this requires a connected Android device or emulator to run:
//   flutter test integration_test/app_flows_test.dart
// It is NOT executed by the current GitHub Actions workflow, which only
// builds the release APK on a plain Linux runner with no Android
// emulator available. Running these flows is a manual/local QA step
// (or can be added to CI later with an emulator runner) - being explicit
// about this here rather than silently pretending they run in CI.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bond2/main.dart';
import 'package:bond2/features/settings/settings_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Flow 1: welcome setup -> add student -> QR screen shown',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: Bond2App()));
    await tester.pumpAndSettle();

    // First launch shows the Welcome/setup screen (rule #8).
    expect(find.text('أهلًا بك في BOND2'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'أ. محمد إبراهيم');
    await tester.tap(find.text('ابدأ استخدام BOND2'));
    await tester.pumpAndSettle();

    // Dashboard should now be visible.
    expect(find.text('BOND2'), findsWidgets);

    // Navigate to Students tab and add a student.
    await tester.tap(find.text('الطلاب'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة طالب').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'الاسم الكامل *'), 'طالب تجريبي');
    await tester.tap(find.text('حفظ وإنشاء QR'));
    await tester.pumpAndSettle();

    // Should land on the Student QR screen showing the new student's name.
    expect(find.text('طالب تجريبي'), findsWidgets);
    expect(find.text('QR الطالب'), findsOneWidget);
  });
}
