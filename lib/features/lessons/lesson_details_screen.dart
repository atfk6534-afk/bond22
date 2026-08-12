import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/status_badge.dart';
import '../attendance/attendance_repository.dart';
import 'lessons_repository.dart';

class LessonDetailsScreen extends ConsumerWidget {
  final String lessonId;
  const LessonDetailsScreen({super.key, required this.lessonId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosterAsync = ref.watch(lessonRosterProvider(lessonId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الحصة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => context.push('/lessons/$lessonId/attendance'),
          ),
        ],
      ),
      body: rosterAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => const Center(child: Text('تعذر تحميل بيانات الحصة')),
        data: (roster) {
          if (roster.isEmpty) {
            return const Center(child: Text('لا يوجد طلاب في هذه الحصة بعد'));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: roster.length,
            itemBuilder: (context, i) => _RosterTile(entry: roster[i], lessonId: lessonId),
          );
        },
      ),
    );
  }
}

class _RosterTile extends ConsumerWidget {
  final LessonRosterEntry entry;
  final String lessonId;
  const _RosterTile({required this.entry, required this.lessonId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceRepo = ref.read(attendanceRepositoryProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(entry.student.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                StatusBadge(
                  status: paymentStatusFor(charged: entry.chargeAmount, paid: entry.paidForCharge),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('المتبقي: ${Money.format(entry.remaining < 0 ? 0 : entry.remaining)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.check_circle_rounded,
                        color: entry.attendanceStatus == AttendanceStatus.present ? Colors.green : null),
                    label: const Text('حاضر'),
                    onPressed: () async {
                      await attendanceRepo.markAttendance(
                        lessonId: lessonId,
                        studentId: entry.student.id,
                        status: AttendanceStatus.present,
                        method: AttendanceMethod.manual,
                      );
                      ref.invalidate(lessonRosterProvider(lessonId));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.cancel_rounded,
                        color: entry.attendanceStatus == AttendanceStatus.absent ? Colors.red : null),
                    label: const Text('غائب'),
                    onPressed: () async {
                      await attendanceRepo.markAttendance(
                        lessonId: lessonId,
                        studentId: entry.student.id,
                        status: AttendanceStatus.absent,
                        method: AttendanceMethod.manual,
                      );
                      ref.invalidate(lessonRosterProvider(lessonId));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.payments_rounded),
                  onPressed: () => context.push('/payments/record?studentId=${entry.student.id}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
