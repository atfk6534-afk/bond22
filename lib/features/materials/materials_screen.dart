import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/database/database.dart' as db;
import '../../core/utils/money.dart';
import 'package:open_filex/open_filex.dart';
import '../../shared/widgets/empty_state.dart';
import '../settings/settings_repository.dart';
import '../students/students_repository.dart';
import 'materials_repository.dart';

class MaterialsScreen extends ConsumerWidget {
  const MaterialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materials = ref.watch(allMaterialsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('المواد والكتب')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMaterialSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة مادة'),
      ),
      body: materials.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => const Center(child: Text('تعذر التحميل')),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.menu_book_rounded,
              message: 'لا توجد مواد بعد',
              actionLabel: '+ إضافة مادة',
              onAction: () => _showAddMaterialSheet(context, ref),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final m = list[i];
              return Card(
                child: ListTile(
                  leading: Icon(m.type == db.MaterialType.book ? Icons.menu_book_rounded : Icons.description_rounded),
                  title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    [
                      Money.format(m.pricePiastres),
                      if (m.grade != null) m.grade!,
                    ].join(' • '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _showPurchaseSheet(context, ref, m.id, m.name),
                        child: const Text('بيع لطالب'),
                      ),
                      if (m.filePath != null)
                        IconButton(
                          icon: const Icon(Icons.open_in_new_rounded),
                          tooltip: 'فتح الملف',
                          onPressed: () => _openMaterialFile(context, m.filePath!),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _confirmDelete(context, ref, m),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openMaterialFile(BuildContext context, String path) async {
    final file = File(path);
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الملف غير موجود — ربما حُذف أو لم يُنسخ بشكل صحيح.'),
        ));
      }
      return;
    }
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'تعذر فتح الملف: ${result.message}',
        ),
      ));
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, db.MaterialItem material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المادة؟'),
        content: Text('سيتم حذف "${material.name}" وملفها المرفق نهائيًا.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(materialsRepositoryProvider).deleteMaterial(material.id);
    } catch (_) {
      // Deleting a material that already has student purchases is
      // blocked at the database level to protect financial history
      // (rule #35/#67) - never show a raw technical error (rule #63).
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا يمكن حذف هذه المادة لأن طلابًا اشتروها بالفعل — أرشفها بدلًا من ذلك أو اترك سجلها كما هو.'),
        ));
      }
    }
  }

  void _showAddMaterialSheet(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final gradeController = TextEditingController();
    final descriptionController = TextEditingController();
    db.MaterialType type = db.MaterialType.note;
    String? pickedFilePath;
    String? pickedFileName;
    String? academicYearId;
    String? subjectId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final years = ref.watch(academicYearsProvider);
        final subjects = ref.watch(subjectsProvider);

        return StatefulBuilder(builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('إضافة مادة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'الاسم')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<db.MaterialType>(
                    value: type,
                    decoration: const InputDecoration(labelText: 'النوع'),
                    items: const [
                      DropdownMenuItem(value: db.MaterialType.note, child: Text('مذكرة')),
                      DropdownMenuItem(value: db.MaterialType.book, child: Text('كتاب')),
                      DropdownMenuItem(value: db.MaterialType.other, child: Text('أخرى')),
                    ],
                    onChanged: (v) => setState(() => type = v ?? db.MaterialType.note),
                  ),
                  const SizedBox(height: 12),
                  years.when(
                    data: (list) => DropdownButtonFormField<String>(
                      value: academicYearId,
                      decoration: const InputDecoration(labelText: 'السنة الدراسية (اختياري)'),
                      items: [for (final y in list) DropdownMenuItem(value: y.id, child: Text(y.name))],
                      onChanged: (v) => setState(() => academicYearId = v),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: gradeController,
                    decoration: const InputDecoration(labelText: 'الصف الدراسي (اختياري)'),
                  ),
                  const SizedBox(height: 12),
                  subjects.when(
                    data: (list) => DropdownButtonFormField<String>(
                      value: subjectId,
                      decoration: const InputDecoration(labelText: 'المادة الدراسية (اختياري)'),
                      items: [for (final s in list) DropdownMenuItem(value: s.id, child: Text(s.name))],
                      onChanged: (v) => setState(() => subjectId = v),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    decoration: const InputDecoration(labelText: 'السعر بالجنيه'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'وصف (اختياري)'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.attach_file_rounded),
                    label: Text(pickedFileName == null ? 'إرفاق ملف (اختياري)' : 'تم اختيار: $pickedFileName'),
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(type: FileType.any);
                      if (result != null && result.files.single.path != null) {
                        setState(() {
                          pickedFilePath = result.files.single.path;
                          pickedFileName = result.files.single.name;
                        });
                      }
                    },
                  ),
                  if (pickedFilePath != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'سيتم نسخ الملف داخل تخزين BOND2 الخاص، فلن تتأثر النسخة الأصلية.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty) return;
                      final price = priceController.text.trim().isEmpty
                          ? 0
                          : Money.egpToPiastres(num.parse(priceController.text.trim()));
                      await ref.read(materialsRepositoryProvider).addMaterial(
                            name: nameController.text.trim(),
                            type: type,
                            academicYearId: academicYearId,
                            grade: gradeController.text.trim().isEmpty ? null : gradeController.text.trim(),
                            subjectId: subjectId,
                            pricePiastres: price,
                            description: descriptionController.text.trim().isEmpty
                                ? null
                                : descriptionController.text.trim(),
                            sourceFilePath: pickedFilePath,
                          );
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            ),
          );
        });
      }),
    );
  }

  void _showPurchaseSheet(BuildContext context, WidgetRef ref, String materialId, String materialName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final students = ref.watch(activeStudentsProvider);
        return Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
          child: SizedBox(
            height: 400,
            child: Column(
              children: [
                Text('بيع "$materialName" لطالب', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Expanded(
                  child: students.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, st) => const Text('تعذر التحميل'),
                    data: (list) => ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final s = list[i];
                        return ListTile(
                          title: Text(s.name),
                          onTap: () async {
                            await ref.read(materialsRepositoryProvider).purchaseMaterial(
                                  studentId: s.id,
                                  materialId: materialId,
                                );
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('تم تسجيل عملية البيع ✓')));
                            }
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
