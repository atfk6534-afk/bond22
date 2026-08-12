import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/services/report_export_service.dart';
import '../../core/utils/money.dart';
import '../groups/groups_repository.dart';
import '../settings/settings_repository.dart';
import 'reports_repository.dart';

/// Unified Reports screen (rule #50, fix #6): attendance/absence,
/// payments, outstanding balances, material sales, and per-student
/// financial summaries — all behind shared date/academic-year/group
/// filters, each section exportable to real CSV/PDF (fix #7).
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportFilters _filters = const ReportFilters();

  List<StudentAttendanceRow>? _attendance;
  List<Payment>? _payments;
  List<StudentOutstandingRow>? _outstanding;
  List<MaterialSalesRow>? _materialSales;
  List<StudentFinancialRow>? _studentSummaries;
  FinancialSummary? _financial;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final repo = ref.read(reportsRepositoryProvider);
    final results = await Future.wait([
      repo.attendanceReport(_filters),
      repo.paymentsReport(_filters),
      repo.outstandingBalancesReport(_filters),
      repo.materialSalesReport(),
      repo.studentFinancialSummaries(_filters),
      repo.financialSummary(_filters),
    ]);
    if (!mounted) return;
    setState(() {
      _attendance = results[0] as List<StudentAttendanceRow>;
      _payments = results[1] as List<Payment>;
      _outstanding = results[2] as List<StudentOutstandingRow>;
      _materialSales = results[3] as List<MaterialSalesRow>;
      _studentSummaries = results[4] as List<StudentFinancialRow>;
      _financial = results[5] as FinancialSummary;
      _loading = false;
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _filters.from : _filters.to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _filters = isFrom ? _filters.copyWith(from: picked) : _filters.copyWith(to: picked);
    });
    _reload();
  }

  void _setQuickRange(int days) {
    final now = DateTime.now();
    setState(() {
      _filters = _filters.copyWith(
        from: DateTime(now.year, now.month, now.day).subtract(Duration(days: days)),
        to: now.add(const Duration(days: 1)),
      );
    });
    _reload();
  }

  void _clearDates() {
    setState(() => _filters = _filters.copyWith(clearFrom: true, clearTo: true));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final years = ref.watch(academicYearsProvider);
    final groups = ref.watch(activeGroupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FiltersCard(
              filters: _filters,
              years: years,
              groups: groups,
              onPickFrom: () => _pickDate(isFrom: true),
              onPickTo: () => _pickDate(isFrom: false),
              onClearDates: _clearDates,
              onQuickRange: _setQuickRange,
              onYearChanged: (v) {
                setState(() => _filters = _filters.copyWith(academicYearId: v, clearYear: v == null));
                _reload();
              },
              onGroupChanged: (v) {
                setState(() => _filters = _filters.copyWith(groupId: v, clearGroup: v == null));
                _reload();
              },
            ),
            const SizedBox(height: 16),
            if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (!_loading) ...[
              _FinancialSummarySection(summary: _financial!),
              const SizedBox(height: 16),
              _AttendanceSection(rows: _attendance!),
              const SizedBox(height: 16),
              _PaymentsSection(payments: _payments!),
              const SizedBox(height: 16),
              _OutstandingSection(rows: _outstanding!),
              const SizedBox(height: 16),
              _MaterialSalesSection(rows: _materialSales!),
              const SizedBox(height: 16),
              _StudentSummariesSection(rows: _studentSummaries!),
            ],
          ],
        ),
      ),
    );
  }
}

class _FiltersCard extends StatelessWidget {
  final ReportFilters filters;
  final AsyncValue<List<AcademicYear>> years;
  final AsyncValue<List<Group>> groups;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onClearDates;
  final void Function(int days) onQuickRange;
  final void Function(String?) onYearChanged;
  final void Function(String?) onGroupChanged;

  const _FiltersCard({
    required this.filters,
    required this.years,
    required this.groups,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onClearDates,
    required this.onQuickRange,
    required this.onYearChanged,
    required this.onGroupChanged,
  });

  String _fmt(DateTime? d) => d == null ? '—' : '${d.year}/${d.month}/${d.day}';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الفلاتر', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(label: const Text('اليوم'), onPressed: () => onQuickRange(0)),
                ActionChip(label: const Text('هذا الأسبوع'), onPressed: () => onQuickRange(7)),
                ActionChip(label: const Text('هذا الشهر'), onPressed: () => onQuickRange(30)),
                ActionChip(label: const Text('الكل'), onPressed: onClearDates),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onPickFrom,
                    child: Text('من: ${_fmt(filters.from)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onPickTo,
                    child: Text('إلى: ${_fmt(filters.to)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            years.when(
              data: (list) => DropdownButtonFormField<String>(
                value: filters.academicYearId,
                decoration: const InputDecoration(labelText: 'السنة الدراسية (الكل)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('كل السنوات')),
                  for (final y in list) DropdownMenuItem(value: y.id, child: Text(y.name)),
                ],
                onChanged: onYearChanged,
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 10),
            groups.when(
              data: (list) => DropdownButtonFormField<String>(
                value: filters.groupId,
                decoration: const InputDecoration(labelText: 'المجموعة (الكل)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('كل المجموعات')),
                  for (final g in list) DropdownMenuItem(value: g.id, child: Text(g.name)),
                ],
                onChanged: onGroupChanged,
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportSectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onExportCsv;
  final VoidCallback? onExportPdf;

  const _ReportSectionCard({
    required this.title,
    required this.child,
    this.onExportCsv,
    this.onExportPdf,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                if (onExportCsv != null)
                  IconButton(icon: const Icon(Icons.grid_on_rounded), tooltip: 'تصدير CSV', onPressed: onExportCsv),
                if (onExportPdf != null)
                  IconButton(icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: 'تصدير PDF', onPressed: onExportPdf),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _FinancialSummarySection extends StatelessWidget {
  final FinancialSummary summary;
  const _FinancialSummarySection({required this.summary});

  @override
  Widget build(BuildContext context) {
    return _ReportSectionCard(
      title: 'الملخص المالي',
      onExportCsv: () => ReportExportService.exportCsv(
        fileNameWithoutExtension: 'financial_summary',
        headers: const ['البند', 'المبلغ'],
        rows: [
          ['إجمالي المستحق خلال الفترة', Money.format(summary.chargedInRange)],
          ['  - رسوم حصص', Money.format(summary.lessonCharges)],
          ['  - رسوم مواد/كتب', Money.format(summary.materialCharges)],
          ['  - أخرى', Money.format(summary.otherCharges)],
          ['المُحصَّل خلال الفترة', Money.format(summary.collectedInRange)],
          ['إجمالي المستحقات المفتوحة (كل الفترات)', Money.format(summary.outstandingAllTime)],
        ],
      ),
      onExportPdf: () => ReportExportService.exportPdfTable(
        title: 'الملخص المالي — BOND2',
        headers: const ['البند', 'المبلغ'],
        rows: [
          ['إجمالي المستحق خلال الفترة', Money.format(summary.chargedInRange)],
          ['رسوم حصص', Money.format(summary.lessonCharges)],
          ['رسوم مواد/كتب', Money.format(summary.materialCharges)],
          ['أخرى', Money.format(summary.otherCharges)],
          ['المُحصَّل خلال الفترة', Money.format(summary.collectedInRange)],
          ['إجمالي المستحقات المفتوحة', Money.format(summary.outstandingAllTime)],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إجمالي المستحق خلال الفترة: ${Money.format(summary.chargedInRange)}'),
          Text('  حصص: ${Money.format(summary.lessonCharges)}  •  مواد: ${Money.format(summary.materialCharges)}',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 6),
          Text('المُحصَّل خلال الفترة: ${Money.format(summary.collectedInRange)}'),
          const SizedBox(height: 6),
          Text('إجمالي المستحقات المفتوحة حاليًا: ${Money.format(summary.outstandingAllTime)}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _AttendanceSection extends StatelessWidget {
  final List<StudentAttendanceRow> rows;
  const _AttendanceSection({required this.rows});

  @override
  Widget build(BuildContext context) {
    final totalPresent = rows.fold<int>(0, (a, r) => a + r.present);
    final totalAbsent = rows.fold<int>(0, (a, r) => a + r.absent);

    return _ReportSectionCard(
      title: 'الحضور والغياب',
      onExportCsv: () => ReportExportService.exportCsv(
        fileNameWithoutExtension: 'attendance_report',
        headers: const ['الطالب', 'عدد الحصص', 'حاضر', 'غائب', 'النسبة %'],
        rows: [
          for (final r in rows)
            [r.student.name, r.total, r.present, r.absent, r.percentage.toStringAsFixed(0)],
        ],
      ),
      onExportPdf: () => ReportExportService.exportPdfTable(
        title: 'تقرير الحضور والغياب — BOND2',
        headers: const ['الطالب', 'حصص', 'حاضر', 'غائب', '%'],
        rows: [
          for (final r in rows)
            [r.student.name, '${r.total}', '${r.present}', '${r.absent}', r.percentage.toStringAsFixed(0)],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إجمالي: $totalPresent حاضر • $totalAbsent غائب', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Text('لا توجد بيانات حضور في هذه الفترة', style: TextStyle(color: Colors.grey))
          else
            ...rows.take(8).map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(r.student.name)),
                      Text('${r.present}/${r.total} (${r.percentage.toStringAsFixed(0)}%)',
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )),
          if (rows.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('و ${rows.length - 8} طالبًا آخر — صدّر CSV/PDF لعرض الكل',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _PaymentsSection extends StatelessWidget {
  final List<Payment> payments;
  const _PaymentsSection({required this.payments});

  @override
  Widget build(BuildContext context) {
    final total = payments.fold<int>(0, (a, p) => a + p.amountPiastres);
    return _ReportSectionCard(
      title: 'المدفوعات',
      onExportCsv: () => ReportExportService.exportCsv(
        fileNameWithoutExtension: 'payments_report',
        headers: const ['التاريخ', 'المبلغ', 'ملاحظات'],
        rows: [
          for (final p in payments)
            ['${p.date.year}/${p.date.month}/${p.date.day}', Money.format(p.amountPiastres), p.notes ?? ''],
        ],
      ),
      onExportPdf: () => ReportExportService.exportPdfTable(
        title: 'تقرير المدفوعات — BOND2',
        headers: const ['التاريخ', 'المبلغ', 'ملاحظات'],
        rows: [
          for (final p in payments)
            ['${p.date.year}/${p.date.month}/${p.date.day}', Money.format(p.amountPiastres), p.notes ?? ''],
        ],
      ),
      child: Text('عدد الدفعات: ${payments.length} — الإجمالي: ${Money.format(total)}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _OutstandingSection extends StatelessWidget {
  final List<StudentOutstandingRow> rows;
  const _OutstandingSection({required this.rows});

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<int>(0, (a, r) => a + r.outstanding);
    return _ReportSectionCard(
      title: 'المستحقات (Outstanding)',
      onExportCsv: () => ReportExportService.exportCsv(
        fileNameWithoutExtension: 'outstanding_balances',
        headers: const ['الطالب', 'المستحق'],
        rows: [for (final r in rows) [r.student.name, Money.format(r.outstanding)]],
      ),
      onExportPdf: () => ReportExportService.exportPdfTable(
        title: 'تقرير المستحقات — BOND2',
        headers: const ['الطالب', 'المستحق'],
        rows: [for (final r in rows) [r.student.name, Money.format(r.outstanding)]],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('عدد الطلاب: ${rows.length} — الإجمالي: ${Money.format(total)}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...rows.take(8).map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(r.student.name)),
                    Text(Money.format(r.outstanding), style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _MaterialSalesSection extends StatelessWidget {
  final List<MaterialSalesRow> rows;
  const _MaterialSalesSection({required this.rows});

  @override
  Widget build(BuildContext context) {
    return _ReportSectionCard(
      title: 'مبيعات المواد والكتب',
      onExportCsv: () => ReportExportService.exportCsv(
        fileNameWithoutExtension: 'material_sales',
        headers: const ['المادة', 'عدد المبيعات', 'القيمة', 'المُحصَّل', 'المتبقي'],
        rows: [
          for (final r in rows)
            [
              r.material.name,
              r.report.count,
              Money.format(r.report.totalValue),
              Money.format(r.report.totalCollected),
              Money.format(r.report.totalOutstanding),
            ],
        ],
      ),
      onExportPdf: () => ReportExportService.exportPdfTable(
        title: 'تقرير مبيعات المواد — BOND2',
        headers: const ['المادة', 'مبيعات', 'القيمة', 'المُحصَّل', 'المتبقي'],
        rows: [
          for (final r in rows)
            [
              r.material.name,
              '${r.report.count}',
              Money.format(r.report.totalValue),
              Money.format(r.report.totalCollected),
              Money.format(r.report.totalOutstanding),
            ],
        ],
      ),
      child: rows.isEmpty
          ? const Text('لا توجد مبيعات مواد بعد', style: TextStyle(color: Colors.grey))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(child: Text(r.material.name)),
                        Text('${r.report.count} × — ${Money.format(r.report.totalCollected)}/${Money.format(r.report.totalValue)}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _StudentSummariesSection extends StatelessWidget {
  final List<StudentFinancialRow> rows;
  const _StudentSummariesSection({required this.rows});

  @override
  Widget build(BuildContext context) {
    return _ReportSectionCard(
      title: 'الملخص المالي لكل طالب',
      onExportCsv: () => ReportExportService.exportCsv(
        fileNameWithoutExtension: 'student_financial_summary',
        headers: const ['الطالب', 'إجمالي المستحق', 'المدفوع', 'المتبقي'],
        rows: [
          for (final r in rows)
            [
              r.student.name,
              Money.format(r.balance.totalCharged),
              Money.format(r.balance.totalPaid),
              Money.format(r.balance.outstanding < 0 ? 0 : r.balance.outstanding),
            ],
        ],
      ),
      onExportPdf: () => ReportExportService.exportPdfTable(
        title: 'الملخص المالي للطلاب — BOND2',
        headers: const ['الطالب', 'إجمالي المستحق', 'المدفوع', 'المتبقي'],
        rows: [
          for (final r in rows)
            [
              r.student.name,
              Money.format(r.balance.totalCharged),
              Money.format(r.balance.totalPaid),
              Money.format(r.balance.outstanding < 0 ? 0 : r.balance.outstanding),
            ],
        ],
      ),
      child: Text('عدد الطلاب: ${rows.length} — استخدم التصدير لعرض التفاصيل الكاملة',
          style: const TextStyle(color: Colors.grey, fontSize: 12)),
    );
  }
}
