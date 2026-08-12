import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:bond2/core/services/report_export_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory dir;
  _FakePathProviderPlatform(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bond2_export_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('ReportExportService (fix #7 — CSV/PDF actually implemented)', () {
    test('buildCsvFile writes a real CSV file with a UTF-8 BOM and correct rows', () async {
      final path = await ReportExportService.buildCsvFile(
        fileNameWithoutExtension: 'test_report',
        headers: const ['الاسم', 'المبلغ'],
        rows: const [
          ['أحمد', '100'],
          ['سارة', '50'],
        ],
      );

      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(path, contains('bond2_exports'));
      expect(path.endsWith('.csv'), isTrue);

      final bytes = await file.readAsBytes();
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);

      final content = utf8.decode(bytes.sublist(3));
      expect(content, contains('الاسم'));
      expect(content, contains('أحمد'));
      expect(content, contains('100'));
      expect(content, contains('سارة'));
    });

    test('buildPdfBytes produces a non-empty, real PDF byte stream', () async {
      final bytes = await ReportExportService.buildPdfBytes(
        title: 'تقرير تجريبي',
        headers: const ['الاسم', 'القيمة'],
        rows: const [
          ['بند 1', '10'],
          ['بند 2', '20'],
        ],
      );

      expect(bytes.isNotEmpty, isTrue);
      final header = String.fromCharCodes(bytes.sublist(0, 4));
      expect(header, '%PDF');
    });

    test('buildCsvFile handles an empty dataset without crashing', () async {
      final path = await ReportExportService.buildCsvFile(
        fileNameWithoutExtension: 'empty_report',
        headers: const ['A', 'B'],
        rows: const [],
      );
      expect(await File(path).exists(), isTrue);
    });
  });
}
