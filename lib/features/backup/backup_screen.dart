import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_repository.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  Future<void> _createBackup() async {
    setState(() => _busy = true);
    final result = await ref.read(backupRepositoryProvider).createBackup();
    setState(() => _busy = false);
    if (!mounted) return;

    if (result.success && result.filePath != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء النسخة الاحتياطية ✓')));
      await Share.shareXFiles([XFile(result.filePath!)], text: 'نسخة احتياطية BOND2');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'فشل إنشاء النسخة')));
    }
  }

  Future<void> _restoreBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bond2backup'],
    );
    if (picked == null || picked.files.single.path == null) return;
    final filePath = picked.files.single.path!;

    final manifest = await ref.read(backupRepositoryProvider).validateBackup(filePath);
    if (manifest == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ملف النسخة الاحتياطية غير صالح')));
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: Text(
          'سيتم استبدال البيانات الحالية بالكامل ببيانات هذه النسخة الاحتياطية '
          '(بتاريخ ${manifest['createdAt']}).\n\n'
          'ينصح بعمل نسخة احتياطية من البيانات الحالية أولًا. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('استعادة')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final result = await ref.read(backupRepositoryProvider).restoreBackup(filePath);
    setState(() => _busy = false);
    if (!mounted) return;

    if (result.success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تمت الاستعادة بنجاح ✓ — التطبيق يعرض الآن بيانات النسخة المستعادة'),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'فشلت الاستعادة')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي والاستعادة')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.backup_rounded, size: 56),
            const SizedBox(height: 12),
            const Text(
              'احتفظ بنسخة من بياناتك بانتظام حتى لا تفقدها عند تغيير الهاتف.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _createBackup,
              icon: const Icon(Icons.upload_rounded),
              label: const Text('إنشاء نسخة احتياطية'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restoreBackup,
              icon: const Icon(Icons.download_rounded),
              label: const Text('استعادة من نسخة احتياطية'),
            ),
            if (_busy) const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );
  }
}
