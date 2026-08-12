import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/qr_service.dart';
import 'students_repository.dart';

class StudentQrScreen extends ConsumerStatefulWidget {
  final String studentId;
  const StudentQrScreen({super.key, required this.studentId});

  @override
  ConsumerState<StudentQrScreen> createState() => _StudentQrScreenState();
}

class _StudentQrScreenState extends ConsumerState<StudentQrScreen> {
  final GlobalKey _qrBoundaryKey = GlobalKey();
  bool _busy = false;

  Future<File?> _renderQrToFile(String studentName) async {
    try {
      final boundary =
          _qrBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/bond2_qr_$studentName.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      return file;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentAsync = ref.watch(_studentProvider(widget.studentId));

    return Scaffold(
      appBar: AppBar(title: const Text('QR الطالب')),
      body: studentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => const Center(child: Text('تعذر تحميل بيانات الطالب')),
        data: (student) {
          if (student == null) return const Center(child: Text('الطالب غير موجود'));
          final payload = QrService.encodeStudent(student.id);

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(student.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 20),
                RepaintBoundary(
                  key: _qrBoundaryKey,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    color: Colors.white,
                    child: QrImageView(data: payload, size: 260),
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText('معرّف الطالب: ${student.id}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('مشاركة صورة QR'),
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          final file = await _renderQrToFile(student.name);
                          setState(() => _busy = false);
                          if (file != null) {
                            await Share.shareXFiles(
                              [XFile(file.path)],
                              text: 'كود حضور ${student.name} — BOND2',
                            );
                          }
                        },
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.chat_rounded),
                  // FIX #5: BOND2 cannot guarantee a true direct-to-WhatsApp
                  // send with an attached image — WhatsApp's public
                  // wa.me/URL API only supports pre-filled TEXT, not an
                  // image attachment together with a specific contact.
                  // The honest, reliable behavior is to open the normal
                  // share sheet with the QR image pre-attached, and let
                  // the teacher pick WhatsApp from it themselves - the
                  // label says exactly that instead of overclaiming.
                  label: const Text('مشاركة QR واختيار واتساب من القائمة'),
                  onPressed: (student.guardianPhone ?? student.studentPhone) == null || _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          final file = await _renderQrToFile(student.name);
                          setState(() => _busy = false);
                          final message =
                              'مرحبًا، هذا كود حضور BOND2 الخاص بالطالب ${student.name}. برجاء الاحتفاظ به لاستخدامه في الحضور.';
                          if (!mounted) return;
                          if (file != null) {
                            // Opens the OS share sheet with the QR image
                            // attached; the teacher chooses WhatsApp (or
                            // any other app) from it themselves.
                            await Share.shareXFiles([XFile(file.path)], text: message);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('تعذّر تجهيز صورة QR للمشاركة. حاول مرة أخرى.'),
                            ));
                          }
                        },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

final _studentProvider = FutureProvider.family((ref, String id) {
  return ref.watch(studentsRepositoryProvider).byId(id);
});
