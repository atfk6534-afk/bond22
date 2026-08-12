import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../students/students_repository.dart';
import 'payments_repository.dart';

class RecordPaymentScreen extends ConsumerStatefulWidget {
  final String? studentId;
  const RecordPaymentScreen({super.key, this.studentId});

  @override
  ConsumerState<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  String? _studentId;
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final Map<String, int> _allocations = {}; // chargeId -> piastres
  final Map<String, TextEditingController> _allocationControllers = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _studentId = widget.studentId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    for (final c in _allocationControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _amountPiastres {
    final t = _amountController.text.trim();
    if (t.isEmpty) return 0;
    return Money.egpToPiastres(num.tryParse(t) ?? 0);
  }

  int get _allocatedTotal => _allocations.values.fold(0, (a, b) => a + b);

  /// Whether the current allocations exactly match the entered amount —
  /// the only state BOND2 accepts (fix #1: no unallocated remainder,
  /// no silent overpayment; there is no credit-balance system).
  bool get _allocationMatches => _amountPiastres > 0 && _allocatedTotal == _amountPiastres;

  TextEditingController _controllerFor(String chargeId) {
    return _allocationControllers.putIfAbsent(chargeId, () => TextEditingController());
  }

  void _setAllocation(String chargeId, int piastres) {
    setState(() {
      if (piastres <= 0) {
        _allocations.remove(chargeId);
      } else {
        _allocations[chargeId] = piastres;
      }
    });
  }

  void _clearAllAllocationFields() {
    for (final c in _allocationControllers.values) {
      c.clear();
    }
    setState(() => _allocations.clear());
  }

  void _autoAllocate(List<OpenCharge> openCharges) {
    // Smart default: fill oldest charges first (rule #1 - avoid manual work).
    var remaining = _amountPiastres;
    final newAllocations = <String, int>{};
    for (final oc in openCharges) {
      if (remaining <= 0) break;
      final take = remaining >= oc.remaining ? oc.remaining : remaining;
      newAllocations[oc.charge.id] = take;
      remaining -= take;
    }
    setState(() {
      _allocations
        ..clear()
        ..addAll(newAllocations);
    });
    for (final oc in openCharges) {
      final value = newAllocations[oc.charge.id];
      _controllerFor(oc.charge.id).text = value == null ? '' : (value / 100).toStringAsFixed(0);
    }
    if (remaining > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'تنبيه: المبلغ المدخل أكبر من إجمالي المستحقات المفتوحة بمقدار ${Money.format(remaining)}. '
          'عدّل المبلغ أو أضف مستحقًا جديدًا قبل الحفظ.',
        ),
      ));
    }
  }

  Future<void> _submit() async {
    if (_studentId == null || _saving) return;
    if (_amountPiastres <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل قيمة صحيحة')));
      return;
    }
    if (!_allocationMatches) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يجب توزيع كامل مبلغ الدفعة على المستحقات قبل الحفظ'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(paymentsRepositoryProvider).recordPayment(
            studentId: _studentId!,
            amountPiastres: _amountPiastres,
            allocations: _allocations,
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل الدفعة بنجاح ✓')));
      context.pop();
    } on OverpaymentException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(activeStudentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل دفعة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          students.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, st) => const Text('تعذر تحميل الطلاب'),
            data: (list) => DropdownButtonFormField<String>(
              value: _studentId,
              decoration: const InputDecoration(labelText: 'الطالب'),
              items: [for (final s in list) DropdownMenuItem(value: s.id, child: Text(s.name))],
              onChanged: (v) {
                _clearAllAllocationFields();
                setState(() => _studentId = v);
              },
            ),
          ),
          const SizedBox(height: 16),
          if (_studentId != null) _StudentBalancePreview(studentId: _studentId!),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            decoration: const InputDecoration(labelText: 'المبلغ المدفوع بالجنيه'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          if (_studentId != null)
            Consumer(builder: (context, ref, _) {
              final openCharges = ref.watch(openChargesProvider(_studentId!));
              return openCharges.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, st) => const Text('تعذر تحميل المستحقات'),
                data: (charges) {
                  if (charges.isEmpty) {
                    return const Text('لا توجد مستحقات مفتوحة لهذا الطالب', style: TextStyle(color: Colors.grey));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('وزّع كامل المبلغ على المستحقات', style: Theme.of(context).textTheme.titleMedium),
                          TextButton(
                            onPressed: _amountPiastres <= 0 ? null : () => _autoAllocate(charges),
                            child: const Text('توزيع تلقائي'),
                          ),
                        ],
                      ),
                      for (final oc in charges)
                        Card(
                          child: ListTile(
                            title: Text(oc.charge.description ?? 'مستحق'),
                            subtitle: Text('المتبقي: ${Money.format(oc.remaining)}'),
                            trailing: SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _controllerFor(oc.charge.id),
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(hintText: '0'),
                                onChanged: (v) {
                                  final egp = num.tryParse(v) ?? 0;
                                  var piastres = Money.egpToPiastres(egp);
                                  // A single allocation may never exceed
                                  // that charge's own remaining balance,
                                  // caught for real by the repository too.
                                  if (piastres > oc.remaining) piastres = oc.remaining;
                                  _setAllocation(oc.charge.id, piastres);
                                },
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _allocationMatches ? Icons.check_circle_rounded : Icons.error_rounded,
                            size: 18,
                            color: _allocationMatches ? AppTheme.success : AppTheme.danger,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'إجمالي الموزّع: ${Money.format(_allocatedTotal)} من ${Money.format(_amountPiastres)}'
                              '${_allocationMatches ? ' ✓ مطابق' : ''}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _allocationMatches ? AppTheme.success : AppTheme.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!_allocationMatches && _amountPiastres > 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'لا يمكن حفظ دفعة بمبلغ غير موزَّع بالكامل — عدّل القيم أعلاه أو اضغط "توزيع تلقائي".',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                    ],
                  );
                },
              );
            }),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_saving || !_allocationMatches) ? null : _submit,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
                : const Text('تسجيل الدفعة'),
          ),
        ],
      ),
    );
  }
}

class _StudentBalancePreview extends ConsumerWidget {
  final String studentId;
  const _StudentBalancePreview({required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(studentBalanceProvider(studentId));
    return balance.when(
      data: (b) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('المستحق حاليًا: ${Money.format(b.outstanding < 0 ? 0 : b.outstanding)}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
