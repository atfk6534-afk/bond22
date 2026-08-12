import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/empty_state.dart';
import '../settings/settings_repository.dart';
import 'groups_repository.dart';

class GroupsListScreen extends ConsumerWidget {
  const GroupsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(activeGroupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('المجموعات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddGroupSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('مجموعة جديدة'),
      ),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => const Center(child: Text('تعذر تحميل المجموعات')),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.groups_2_rounded,
              message: 'لا توجد مجموعات بعد',
              actionLabel: '+ مجموعة جديدة',
              onAction: () => _showAddGroupSheet(context, ref),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final g = list[i];
              return Card(
                child: ListTile(
                  title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([if (g.grade != null) g.grade!, if (g.schedule != null) g.schedule!].join(' • ')),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddGroupSheet(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final gradeController = TextEditingController();
    final scheduleController = TextEditingController();
    String? yearId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final years = ref.watch(academicYearsProvider);
        return Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('مجموعة جديدة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'اسم المجموعة')),
              const SizedBox(height: 12),
              TextField(controller: gradeController, decoration: const InputDecoration(labelText: 'الصف (اختياري)')),
              const SizedBox(height: 12),
              TextField(controller: scheduleController, decoration: const InputDecoration(labelText: 'الموعد (اختياري)')),
              const SizedBox(height: 12),
              years.when(
                data: (list) => DropdownButtonFormField<String>(
                  value: yearId,
                  decoration: const InputDecoration(labelText: 'السنة الدراسية'),
                  items: [for (final y in list) DropdownMenuItem(value: y.id, child: Text(y.name))],
                  onChanged: (v) => yearId = v,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty || yearId == null) return;
                  await ref.read(groupsRepositoryProvider).addGroup(
                        name: nameController.text.trim(),
                        academicYearId: yearId!,
                        grade: gradeController.text.trim().isEmpty ? null : gradeController.text.trim(),
                        schedule: scheduleController.text.trim().isEmpty ? null : scheduleController.text.trim(),
                      );
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      }),
    );
  }
}
