import 'package:go_router/go_router.dart';

import '../../features/dashboard/dashboard_screen.dart';
import '../../features/students/students_list_screen.dart';
import '../../features/students/add_student_screen.dart';
import '../../features/students/student_profile_screen.dart';
import '../../features/students/student_qr_screen.dart';
import '../../features/groups/groups_list_screen.dart';
import '../../features/lessons/lessons_list_screen.dart';
import '../../features/lessons/add_lesson_screen.dart';
import '../../features/lessons/lesson_details_screen.dart';
import '../../features/attendance/qr_attendance_screen.dart';
import '../../features/payments/payments_screen.dart';
import '../../features/payments/record_payment_screen.dart';
import '../../features/materials/materials_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/backup/backup_screen.dart';
import '../../shared/widgets/root_shell.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => RootShell(location: state.uri.toString(), child: child),
      routes: [
        GoRoute(path: '/', builder: (c, s) => const DashboardScreen()),
        GoRoute(path: '/students', builder: (c, s) => const StudentsListScreen()),
        GoRoute(path: '/lessons', builder: (c, s) => const LessonsListScreen()),
        GoRoute(path: '/payments', builder: (c, s) => const PaymentsScreen()),
        GoRoute(path: '/materials', builder: (c, s) => const MaterialsScreen()),
      ],
    ),
    GoRoute(
        path: '/students/add',
        builder: (c, s) => const AddStudentScreen()),
    GoRoute(
      path: '/students/:id',
      builder: (c, s) => StudentProfileScreen(studentId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/students/:id/qr',
      builder: (c, s) => StudentQrScreen(studentId: s.pathParameters['id']!),
    ),
    GoRoute(path: '/groups', builder: (c, s) => const GroupsListScreen()),
    GoRoute(path: '/lessons/add', builder: (c, s) => const AddLessonScreen()),
    GoRoute(
      path: '/lessons/:id',
      builder: (c, s) => LessonDetailsScreen(lessonId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/lessons/:id/attendance',
      builder: (c, s) => QrAttendanceScreen(lessonId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/payments/record',
      builder: (c, s) => RecordPaymentScreen(
        studentId: s.uri.queryParameters['studentId'],
      ),
    ),
    GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
    GoRoute(path: '/reports', builder: (c, s) => const ReportsScreen()),
    GoRoute(path: '/backup', builder: (c, s) => const BackupScreen()),
  ],
);
