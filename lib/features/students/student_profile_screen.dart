import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/utils/money.dart';
import '../../core/services/contact_service.dart';
import '../payments/payments_repository.dart';
import 'students_repository.dart';

class StudentProfileScreen extends ConsumerWidget {
  final String studentId;
  const StudentProfileScreen({super.key, required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(_studentProvider(studentId));
    final balanceAsync = ref.watch(studentBalanceProvider(studentId));
    final attendanceAsync = ref.watch(studentAttendanceSummaryProvider(studentId));
    final paymentsAsync = ref.watch(_paymentsProvider(studentId));

    return Scaffold(
      appBar: AppBar(
        title: studentAsync.when(
          data: (s) => Text(s?.name ?? ''),
          loading: () => const Text(''),
          error: (_, __) => const Text(''),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            onPressed: () => context.push('/students/$studentId/qr'),
          ),
        ],
      ),
      body: studentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => const Center(child: Text('تعذر تحميل بيانات الطالب')),
        data: (student) {
          if (student == null) return const Center(child: Text('الطالب غير موجود'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoSection(student: student),
              const SizedBox(height: 16),
              _SectionTitle('الملخص المالي'),
              balanceAsync.when(
                data: (b) => _FinancialCard(balance: b, studentId: studentId),
                loading: () => const CircularProgressIndicator(),
                error: (_, __) => const Text('تعذر حساب الرصيد'),
              ),
              const SizedBox(height: 16),
              _SectionTitle('ملخص الحضور'),
              attendanceAsync.when(
                data: (a) => _AttendanceCard(summary: a),
                loading: () => const CircularProgressIndicator(),
                error: (_, __) => const Text('تعذر تحميل الحضور'),
              ),
              const SizedBox(height: 16),
              _SectionTitle('سجل المدفوعات'),
              paymentsAsync.when(
                data: (payments) {
                  if (payments.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('لا توجد مدفوعات مسجلة بعد', style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return Column(
                    children: [
                      for (final p in payments)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.check_circle_outline_rounded),
                            title: Text(Money.format(p.amountPiastres)),
                            subtitle: Text('${p.date.year}/${p.date.month}/${p.date.day}'),
                          ),
                        ),
                    ],
                  );
                },
                loading: () => const CircularProgressIndicator(),
                error: (_, __) => const Text('تعذر تحميل المدفوعات'),
              ),
              const SizedBox(height: 24),
              if (student.guardianPhone != null || student.studentPhone != null)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.call_rounded),
                        label: const Text('اتصال'),
                        onPressed: () => ContactService.call(
                            (student.guardianPhone ?? student.studentPhone)!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.chat_rounded),
                        label: const Text('واتساب'),
                        onPressed: () => ContactService.openWhatsApp(
                          (student.guardianPhone ?? student.studentPhone)!,
                          'مرحبًا بخصوص الطالب ${student.name}',
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: Icon(student.status == StudentStatus.active
                    ? Icons.archive_rounded
                    : Icons.unarchive_rounded),
                label: Text(student.status == StudentStatus.active ? 'أرشفة الطالب' : 'إلغاء الأرشفة'),
                onPressed: () async {
                  await ref.read(studentsRepositoryProvider).setArchived(
                        studentId,
                        student.status == StudentStatus.active,
                      );
                  ref.invalidate(_studentProvider(studentId));
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final Student student;
  const _InfoSection({required this.student});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (student.grade != null) Text('الصف: ${student.grade}'),
            if (student.studentPhone != null) Text('هاتف الطالب: ${student.studentPhone}'),
            if (student.guardianName != null) Text('ولي الأمر: ${student.guardianName}'),
            if (student.guardianPhone != null) Text('هاتف ولي الأمر: ${student.guardianPhone}'),
            if (student.notes != null) Text('ملاحظات: ${student.notes}'),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: Theme.of(context).textTheme.titleMedium));
}

class _FinancialCard extends StatelessWidget {
  final StudentBalance balance;
  final String studentId;
  const _FinancialCard({required this.balance, required this.studentId});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _stat('الإجمالي المستحق', Money.format(balance.totalCharged)),
                _stat('المدفوع', Money.format(balance.totalPaid)),
                _stat('المتبقي', Money.format(balance.outstanding < 0 ? 0 : balance.outstanding)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => context.push('/payments/record?studentId=$studentId'),
                    child: const Text('تسجيل دفعة'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );
}

class _AttendanceCard extends StatelessWidget {
  final AttendanceSummary summary;
  const _AttendanceCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _stat('عدد الحصص', '${summary.total}'),
            _stat('حاضر', '${summary.present}'),
            _stat('غائب', '${summary.absent}'),
            _stat('النسبة', '${summary.percentage.toStringAsFixed(0)}%'),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );
}

final _studentProvider = FutureProvider.family((ref, String id) {
  return ref.watch(studentsRepositoryProvider).byId(id);
});

final _paymentsProvider = StreamProvider.family((ref, String studentId) {
  return ref.watch(paymentsRepositoryProvider).watchForStudent(studentId);
});
