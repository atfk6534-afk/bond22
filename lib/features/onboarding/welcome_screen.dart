import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_repository.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _nameController = TextEditingController();
  final _subjectController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.saveProfile(
          name: _nameController.text.trim(),
          subject: _subjectController.text.trim().isEmpty
              ? null
              : _subjectController.text.trim(),
        );
    // Smart default: create the current academic year automatically so
    // the teacher is never blocked waiting to set one up (rule #1).
    final now = DateTime.now();
    final startYear = now.month >= 8 ? now.year : now.year - 1;
    await settingsRepo.addAcademicYear('$startYear/${startYear + 1}');
    ref.invalidate(teacherProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.school_rounded, size: 72),
              const SizedBox(height: 12),
              const Text(
                'أهلًا بك في BOND2',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'خطوة واحدة سريعة ثم نبدأ',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'اسم المدرّس'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subjectController,
                decoration:
                    const InputDecoration(labelText: 'المادة الأساسية (اختياري)'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _start,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator())
                    : const Text('ابدأ استخدام BOND2'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
