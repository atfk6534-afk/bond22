import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'settings_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(teacherProfileProvider);
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          profile.when(
            data: (p) => ListTile(
              leading: const Icon(Icons.person_rounded),
              title: Text(p?.name ?? ''),
              subtitle: Text(p?.mainSubject ?? 'المدرّس'),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const Divider(),
          const _SectionHeader('التطبيق'),
          settings.when(
            data: (s) => ListTile(
              leading: const Icon(Icons.dark_mode_rounded),
              title: const Text('المظهر'),
              trailing: DropdownButton<String>(
                value: s.themeMode,
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('تلقائي')),
                  DropdownMenuItem(value: 'light', child: Text('فاتح')),
                  DropdownMenuItem(value: 'dark', child: Text('داكن')),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  await ref.read(settingsRepositoryProvider).setThemeMode(v);
                  ref.invalidate(appSettingsProvider);
                },
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const Divider(),
          const _SectionHeader('الأمان'),
          settings.when(
            data: (s) => SwitchListTile(
              secondary: const Icon(Icons.lock_rounded),
              title: const Text('قفل التطبيق برمز PIN'),
              value: s.pinEnabled,
              onChanged: (enable) async {
                if (enable) {
                  final pin = await _promptForPin(context);
                  if (pin != null && pin.length >= 4) {
                    await ref.read(settingsRepositoryProvider).enablePin(pin);
                  }
                } else {
                  await ref.read(settingsRepositoryProvider).disablePin();
                }
                ref.invalidate(appSettingsProvider);
              },
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const Divider(),
          const _SectionHeader('البيانات'),
          ListTile(
            leading: const Icon(Icons.bar_chart_rounded),
            title: const Text('التقارير'),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => context.push('/reports'),
          ),
          ListTile(
            leading: const Icon(Icons.backup_rounded),
            title: const Text('النسخ الاحتياطي والاستعادة'),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => context.push('/backup'),
          ),
          ListTile(
            leading: const Icon(Icons.groups_2_rounded),
            title: const Text('إدارة المجموعات'),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => context.push('/groups'),
          ),
          const Divider(),
          const _SectionHeader('حول'),
          const ListTile(
            leading: Icon(Icons.info_rounded),
            title: Text('BOND2'),
            subtitle: Text('الإصدار 1.0.0'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForPin(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنشاء رمز PIN'),
        content: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'أدخل رمزًا من 4 أرقام على الأقل'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('تفعيل'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.grey)),
      );
}
