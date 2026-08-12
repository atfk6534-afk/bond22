import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/utils/money.dart';
import '../../core/services/contact_service.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/status_badge.dart';
import 'students_repository.dart';

class StudentsListScreen extends ConsumerStatefulWidget {
  const StudentsListScreen({super.key});

  @override
  ConsumerState<StudentsListScreen> createState() => _StudentsListScreenState();
}

class _StudentsListScreenState extends ConsumerState<StudentsListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = _query.isEmpty
        ? ref.watch(activeStudentsProvider)
        : ref.watch(_searchProvider(_query));

    return Scaffold(
      appBar: AppBar(title: const Text('الطلاب')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/students/add'),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('إضافة طالب'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'بحث بالاسم أو رقم الهاتف...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: studentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => const Center(child: Text('تعذر تحميل الطلاب')),
              data: (students) {
                if (students.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline_rounded,
                    message: _query.isEmpty ? 'لا يوجد طلاب بعد' : 'لا توجد نتائج',
                    actionLabel: _query.isEmpty ? '+ إضافة طالب' : null,
                    onAction: _query.isEmpty ? () => context.push('/students/add') : null,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  itemCount: students.length,
                  itemBuilder: (context, i) => _StudentCard(student: students[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

final _searchProvider = StreamProvider.family<List<Student>, String>((ref, q) {
  return ref.watch(studentsRepositoryProvider).search(q);
});

class _StudentCard extends ConsumerWidget {
  final Student student;
  const _StudentCard({required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(studentBalanceProvider(student.id));

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/students/${student.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(student.name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  balanceAsync.when(
                    data: (b) => StatusBadge(
                        status: paymentStatusFor(charged: b.totalCharged, paid: b.totalPaid)),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (student.grade != null) student.grade!,
                ].join(' - '),
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 8),
              balanceAsync.when(
                data: (b) => Text(
                  'المتبقي: ${Money.format(b.outstanding < 0 ? 0 : b.outstanding)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _MiniAction(
                    icon: Icons.qr_code_rounded,
                    label: 'QR',
                    onTap: () => context.push('/students/${student.id}/qr'),
                  ),
                  _MiniAction(
                    icon: Icons.payments_rounded,
                    label: 'دفعة',
                    onTap: () => context.push('/payments/record?studentId=${student.id}'),
                  ),
                  if (student.guardianPhone != null || student.studentPhone != null) ...[
                    _MiniAction(
                      icon: Icons.call_rounded,
                      label: 'اتصال',
                      onTap: () => ContactService.call(
                          (student.guardianPhone ?? student.studentPhone)!),
                    ),
                    _MiniAction(
                      icon: Icons.chat_rounded,
                      label: 'واتساب',
                      onTap: () => ContactService.openWhatsApp(
                        (student.guardianPhone ?? student.studentPhone)!,
                        'مرحبًا بخصوص الطالب ${student.name}',
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MiniAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
