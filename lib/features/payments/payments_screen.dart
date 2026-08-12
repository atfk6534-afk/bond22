import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/utils/money.dart';
import '../../core/services/contact_service.dart';
import '../../shared/widgets/empty_state.dart';
import '../students/students_repository.dart';
import 'payments_repository.dart';

class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todaysPayments = ref.watch(_todaysPaymentsProvider);
    final outstandingStudents = ref.watch(_outstandingStudentsProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المدفوعات'),
          bottom: const TabBar(tabs: [Tab(text: 'اليوم'), Tab(text: 'المستحقات')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/payments/record'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('تسجيل دفعة'),
        ),
        body: TabBarView(
          children: [
            todaysPayments.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => const Center(child: Text('تعذر التحميل')),
              data: (payments) {
                if (payments.isEmpty) {
                  return const EmptyState(icon: Icons.payments_outlined, message: 'لا توجد مدفوعات اليوم');
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  itemCount: payments.length,
                  itemBuilder: (context, i) {
                    final p = payments[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.check_circle_outline_rounded),
                        title: Text(Money.format(p.amountPiastres)),
                        subtitle: Text('${p.date.hour}:${p.date.minute.toString().padLeft(2, '0')}'),
                      ),
                    );
                  },
                );
              },
            ),
            outstandingStudents.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => const Center(child: Text('تعذر التحميل')),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(icon: Icons.verified_rounded, message: 'لا توجد مستحقات — الجميع سدد!');
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final entry = list[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.student.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text('المستحق: ${Money.format(entry.balance.outstanding)}',
                                style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () => context.push('/payments/record?studentId=${entry.student.id}'),
                                    child: const Text('دفع'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (entry.student.guardianPhone != null || entry.student.studentPhone != null)
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => ContactService.openWhatsApp(
                                        (entry.student.guardianPhone ?? entry.student.studentPhone)!,
                                        'مرحبًا، تذكير ودّي بأن المبلغ المستحق للطالب ${entry.student.name} هو ${Money.format(entry.balance.outstanding)}. شكرًا.',
                                      ),
                                      child: const Text('تذكير واتساب'),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

final _todaysPaymentsProvider = StreamProvider((ref) => ref.watch(paymentsRepositoryProvider).watchToday());

class _OutstandingEntry {
  final Student student;
  final StudentBalance balance;
  _OutstandingEntry(this.student, this.balance);
}

final _outstandingStudentsProvider = FutureProvider<List<_OutstandingEntry>>((ref) async {
  final studentsRepo = ref.watch(studentsRepositoryProvider);
  final students = await studentsRepo.watchActive().first;
  final result = <_OutstandingEntry>[];
  for (final s in students) {
    final b = await studentsRepo.balanceFor(s.id);
    if (b.outstanding > 0) result.add(_OutstandingEntry(s, b));
  }
  result.sort((a, b) => b.balance.outstanding.compareTo(a.balance.outstanding));
  return result;
});
