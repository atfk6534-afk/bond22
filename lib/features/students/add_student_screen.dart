import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/money.dart';
import '../groups/groups_repository.dart';
import '../settings/settings_repository.dart';
import 'students_repository.dart';

class AddStudentScreen extends ConsumerStatefulWidget {
  const AddStudentScreen({super.key});

  @override
  ConsumerState<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends ConsumerState<AddStudentScreen> {
  final _name = TextEditingController();
  final _studentPhone = TextEditingController();
  final _guardianName = TextEditingController();
  final _guardianPhone = TextEditingController();
  final _grade = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();
  String? _groupId;
  String? _academicYearId;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _studentPhone,
      _guardianName,
      _guardianPhone,
      _grade,
      _price,
      _notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اسم الطالب مطلوب')));
      return;
    }
    if (_saving) return; // double-submit protection (rule #65)
    setState(() => _saving = true);

    final id = await ref.read(studentsRepositoryProvider).addStudent(
          name: _name.text.trim(),
          studentPhone: _studentPhone.text.trim().isEmpty ? null : _studentPhone.text.trim(),
          guardianName: _guardianName.text.trim().isEmpty ? null : _guardianName.text.trim(),
          guardianPhone:
              _guardianPhone.text.trim().isEmpty ? null : _guardianPhone.text.trim(),
          academicYearId: _academicYearId,
          grade: _grade.text.trim().isEmpty ? null : _grade.text.trim(),
          groupId: _groupId,
          defaultLessonPricePiastres:
              _price.text.trim().isEmpty ? null : Money.egpToPiastres(num.parse(_price.text.trim())),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );

    if (!mounted) return;
    context.pushReplacement('/students/$id/qr');
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(activeGroupsProvider);
    final years = ref.watch(academicYearsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('إضافة طالب')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'الاسم الكامل *'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _studentPhone,
            decoration: const InputDecoration(labelText: 'هاتف الطالب (اختياري)'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _guardianName,
            decoration: const InputDecoration(labelText: 'اسم ولي الأمر (اختياري)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _guardianPhone,
            decoration: const InputDecoration(labelText: 'هاتف ولي الأمر (اختياري)'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _grade,
            decoration: const InputDecoration(labelText: 'الصف الدراسي (اختياري)'),
          ),
          const SizedBox(height: 12),
          years.when(
            data: (list) => DropdownButtonFormField<String>(
              value: _academicYearId,
              decoration: const InputDecoration(labelText: 'السنة الدراسية (اختياري)'),
              items: [for (final y in list) DropdownMenuItem(value: y.id, child: Text(y.name))],
              onChanged: (v) => setState(() => _academicYearId = v),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          groups.when(
            data: (list) => DropdownButtonFormField<String>(
              value: _groupId,
              decoration: const InputDecoration(labelText: 'المجموعة (اختياري)'),
              items: [for (final g in list) DropdownMenuItem(value: g.id, child: Text(g.name))],
              onChanged: (v) => setState(() => _groupId = v),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            decoration: const InputDecoration(labelText: 'سعر الحصة الافتراضي بالجنيه (اختياري)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
                : const Text('حفظ وإنشاء QR'),
          ),
        ],
      ),
    );
  }
}
