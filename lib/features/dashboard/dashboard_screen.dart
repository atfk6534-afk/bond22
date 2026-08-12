import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/utils/money.dart';
import '../lessons/lessons_repository.dart';
import '../payments/payments_repository.dart';
import '../students/students_repository.dart';
import '../../shared/widgets/empty_state.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todaysLessons = ref.watch(todaysLessonsProvider);
    final todaysPayments = ref.watch(_todaysPaymentsTotalProvider);
    final outstandingCount = ref.watch(_studentsWithBalanceCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BOND2', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(todaysLessonsProvider);
          ref.invalidate(_todaysPaymentsTotalProvider);
          ref.invalidate(_studentsWithBalanceCountProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _QuickActionsGrid(),
            const SizedBox(height: 20),
            _FinancialSummaryRow(todaysPayments: todaysPayments, outstandingCount: outstandingCount),
            const SizedBox(height: 20),
            Text('حصص اليوم', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            todaysLessons.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => const Text('تعذر تحميل الحصص'),
              data: (lessons) {
                if (lessons.isEmpty) {
                  return EmptyState(
                    icon: Icons.event_busy_rounded,
                    message: 'لا توجد حصص اليوم',
                    actionLabel: '+ إضافة حصة',
                    onAction: () => context.push('/lessons/add'),
                  );
                }
                return Column(children: [for (final l in lessons) _LessonCard(lesson: l)]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = [
      ('+ إضافة طالب', Icons.person_add_alt_1_rounded, () => context.push('/students/add')),
      ('بدء الحضور', Icons.qr_code_scanner_rounded, () => context.push('/lessons')),
      ('+ إضافة حصة', Icons.add_box_rounded, () => context.push('/lessons/add')),
      ('تسجيل دفعة', Icons.payments_rounded, () => context.push('/payments/record')),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.4,
      children: [
        for (final a in actions)
          _ActionCard(label: a.$1, icon: a.$2, onTap: a.$3),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionCard({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinancialSummaryRow extends StatelessWidget {
  final AsyncValue<int> todaysPayments;
  final AsyncValue<int> outstandingCount;
  const _FinancialSummaryRow({required this.todaysPayments, required this.outstandingCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'تم تحصيله اليوم',
            value: todaysPayments.when(
              data: (v) => Money.format(v),
              loading: () => '...',
              error: (_, __) => '-',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'طلاب عليهم مستحقات',
            value: outstandingCount.when(
              data: (v) => v.toString(),
              loading: () => '...',
              error: (_, __) => '-',
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final Lesson lesson;
  const _LessonCard({required this.lesson});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(lesson.name ?? 'حصة', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(lesson.startTime),
        trailing: FilledButton(
          onPressed: () => context.push('/lessons/${lesson.id}/attendance'),
          child: const Text('بدء الحضور'),
        ),
        onTap: () => context.push('/lessons/${lesson.id}'),
      ),
    );
  }
}

final _todaysPaymentsTotalProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(paymentsRepositoryProvider);
  final payments = await repo.watchToday().first;
  return payments.fold<int>(0, (sum, p) => sum + p.amountPiastres);
});

final _studentsWithBalanceCountProvider = FutureProvider<int>((ref) async {
  final studentsRepo = ref.watch(studentsRepositoryProvider);
  final students = await studentsRepo.watchActive().first;
  var count = 0;
  for (final s in students) {
    final balance = await studentsRepo.balanceFor(s.id);
    if (balance.outstanding > 0) count++;
  }
  return count;
});
