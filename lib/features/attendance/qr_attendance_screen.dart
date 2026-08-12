import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/database/database.dart';
import '../../core/services/qr_service.dart';
import '../../core/theme/app_theme.dart';
import '../lessons/lessons_repository.dart';
import 'attendance_repository.dart';

class QrAttendanceScreen extends ConsumerStatefulWidget {
  final String lessonId;
  const QrAttendanceScreen({super.key, required this.lessonId});

  @override
  ConsumerState<QrAttendanceScreen> createState() => _QrAttendanceScreenState();
}

class _QrAttendanceScreenState extends ConsumerState<QrAttendanceScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _processing = false; // debounce - prevent double-processing one frame
  String? _lastMessage;
  Color _lastColor = Colors.black;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    setState(() => _processing = true);

    final repo = ref.read(attendanceRepositoryProvider);
    final result = await repo.handleScan(
      rawQrPayload: raw,
      lessonId: widget.lessonId,
      decode: QrService.decodeStudentId,
    );

    if (!mounted) return;

    switch (result.outcome) {
      case ScanOutcome.recorded:
        _showFeedback('تم تسجيل الحضور ✓\n${result.student?.name ?? ''}', AppTheme.success);
        ref.invalidate(lessonRosterProvider(widget.lessonId));
        break;
      case ScanOutcome.alreadyRecorded:
        _showFeedback('مسجل مسبقًا\n${result.student?.name ?? ''}', AppTheme.warning);
        break;
      case ScanOutcome.invalidQr:
        _showFeedback('كود QR غير صالح', AppTheme.danger);
        break;
      case ScanOutcome.studentNotInLesson:
        _showAddToLessonDialog(result);
        break;
    }

    // Keep the scanner ready for the next student (rule #23).
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _processing = false);
  }

  void _showFeedback(String message, Color color) {
    setState(() {
      _lastMessage = message;
      _lastColor = color;
    });
  }

  void _showAddToLessonDialog(ScanResult result) {
    setState(() => _processing = false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الطالب غير مسجل في هذه الحصة'),
        content: Text(result.student?.name ?? ''),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              await ref.read(attendanceRepositoryProvider).addStudentToLesson(
                    widget.lessonId,
                    result.student!.id,
                    result.student!.defaultLessonPricePiastres ?? 0,
                  );
              await ref.read(attendanceRepositoryProvider).markAttendance(
                    lessonId: widget.lessonId,
                    studentId: result.student!.id,
                    status: AttendanceStatus.present,
                    method: AttendanceMethod.qr,
                  );
              ref.invalidate(lessonRosterProvider(widget.lessonId));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('إضافة للحصة وتسجيل الحضور'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تسجيل الحضور'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt_rounded),
            tooltip: 'الحضور اليدوي',
            onPressed: () => context.push('/lessons/${widget.lessonId}'),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          if (_lastMessage != null)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _lastColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _lastMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
