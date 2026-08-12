import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/money.dart';
import '../groups/groups_repository.dart';
import '../settings/settings_repository.dart';
import 'lessons_repository.dart';

class AddLessonScreen extends ConsumerStatefulWidget {
  const AddLessonScreen({super.key});

  @override
  ConsumerState<AddLessonScreen> createState() => _AddLessonScreenState();
}

class _AddLessonScreenState extends ConsumerState<AddLessonScreen> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  String? _groupId;
  String? _academicYearId;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  bool _recurring = false;
  final Set<int> _weekdays = {};
  DateTime? _recurrenceEnd;
  bool _saving = false;

  static const _weekdayLabels = {1: 'إثنين', 2: 'ثلاثاء', 3: 'أربعاء', 4: 'خميس', 5: 'جمعة', 6: 'سبت', 7: 'أحد'};

  String get _timeString => '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_saving) return;
    final priceValue = _price.text.trim().isEmpty ? 0 : Money.egpToPiastres(num.parse(_price.text.trim()));
    setState(() => _saving = true);

    final repo = ref.read(lessonsRepositoryProvider);
    if (_recurring && _weekdays.isNotEmpty && _recurrenceEnd != null) {
      await repo.createRecurringLessons(
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        academicYearId: _academicYearId,
        groupId: _groupId,
        weekdays: _weekdays.toList(),
        firstDate: _date,
        lastDate: _recurrenceEnd!,
        startTime: _timeString,
        pricePiastres: priceValue,
      );
    } else {
      await repo.createLesson(
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        academicYearId: _academicYearId,
        groupId: _groupId,
        date: _date,
        startTime: _timeString,
        pricePiastres: priceValue,
      );
    }

    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(activeGroupsProvider);
    final years = ref.watch(academicYearsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('حصة جديدة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم الحصة (اختياري)')),
          const SizedBox(height: 12),
          years.when(
            data: (list) => DropdownButtonFormField<String>(
              value: _academicYearId,
              decoration: const InputDecoration(labelText: 'السنة الدراسية'),
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
              decoration: const InputDecoration(labelText: 'المجموعة (سيتم إضافة طلابها تلقائيًا)'),
              items: [for (final g in list) DropdownMenuItem(value: g.id, child: Text(g.name))],
              onChanged: (v) => setState(() => _groupId = v),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('التاريخ'),
            subtitle: Text('${_date.year}/${_date.month}/${_date.day}'),
            trailing: const Icon(Icons.calendar_today_rounded),
            onTap: () async {
              final picked = await showDatePicker(
                context: context, initialDate: _date,
                firstDate: DateTime(2020), lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('الوقت'),
            subtitle: Text(_timeString),
            trailing: const Icon(Icons.access_time_rounded),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: _time);
              if (picked != null) setState(() => _time = picked);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            decoration: const InputDecoration(labelText: 'سعر الحصة بالجنيه'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('حصة متكررة'),
            value: _recurring,
            onChanged: (v) => setState(() => _recurring = v),
          ),
          if (_recurring) ...[
            Wrap(
              spacing: 8,
              children: [
                for (final entry in _weekdayLabels.entries)
                  FilterChip(
                    label: Text(entry.value),
                    selected: _weekdays.contains(entry.key),
                    onSelected: (sel) => setState(() {
                      if (sel) {
                        _weekdays.add(entry.key);
                      } else {
                        _weekdays.remove(entry.key);
                      }
                    }),
                  ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('التكرار حتى تاريخ'),
              subtitle: Text(_recurrenceEnd == null
                  ? 'اختر تاريخ النهاية'
                  : '${_recurrenceEnd!.year}/${_recurrenceEnd!.month}/${_recurrenceEnd!.day}'),
              trailing: const Icon(Icons.event_rounded),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date.add(const Duration(days: 30)),
                  firstDate: _date, lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _recurrenceEnd = picked);
              },
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
                : const Text('حفظ الحصة'),
          ),
        ],
      ),
    );
  }
}
