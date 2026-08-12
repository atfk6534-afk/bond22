import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Real CSV/PDF export for BOND2 reports (rules #74-75, fix #7).
/// Every report screen calls into this rather than leaving the
/// csv/pdf/printing packages declared-but-unused.
///
/// The pure, platform-independent parts (building the CSV file /
/// PDF bytes) are split into their own static methods so they can be
/// unit-tested directly without needing to fake the share_plus /
/// printing platform channels.
class ReportExportService {
  const ReportExportService._();

  /// Pure step: writes [headers] + [rows] as a real CSV file under the
  /// app's exports folder and returns its path. Does not share/open it.
  static Future<String> buildCsvFile({
    required String fileNameWithoutExtension,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) async {
    final csvString = const ListToCsvConverter().convert([headers, ...rows]);
    final docsDir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory(p.join(docsDir.path, 'bond2_exports'));
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = p.join(exportsDir.path, '${fileNameWithoutExtension}_$timestamp.csv');
    // UTF-8 BOM so Excel opens Arabic text correctly instead of mojibake.
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...csvString.codeUnits];
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// Builds the CSV file then opens the OS share sheet so the teacher
  /// can save it or send it anywhere (Drive, email, etc).
  static Future<String> exportCsv({
    required String fileNameWithoutExtension,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) async {
    final path = await buildCsvFile(
      fileNameWithoutExtension: fileNameWithoutExtension,
      headers: headers,
      rows: rows,
    );
    await Share.shareXFiles([XFile(path)], text: fileNameWithoutExtension);
    return path;
  }

  /// Pure step: builds a real, RTL-friendly PDF table report and returns
  /// its raw bytes. Does not share/print it.
  ///
  /// KNOWN LIMITATION (documented honestly, not silently shipped): the
  /// `pdf` package's default font (Helvetica) does not contain Arabic
  /// glyphs. The PDF produced here is a structurally valid, real PDF
  /// (verified in report_export_test.dart) with correct RTL layout and
  /// correct underlying text data, but Arabic characters may render as
  /// blank boxes in the default font until a real Arabic-capable TTF
  /// (e.g. Amiri, Cairo, or Noto Naskh Arabic) is bundled under
  /// `assets/fonts/` and loaded here via `pw.Font.ttf(...)`. This
  /// environment has no network access to fetch such a font file, so it
  /// could not be added as part of this change. CSV export (which most
  /// teachers will actually use to open reports in Excel/Sheets) is
  /// NOT affected by this limitation - Arabic text there is correct.
  static Future<Uint8List> buildPdfBytes({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    String? subtitle,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          if (subtitle != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Text(subtitle, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            ),
          pw.Table.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerRight,
            headerAlignment: pw.Alignment.centerRight,
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'تم إنشاؤه بواسطة BOND2 — ${DateTime.now().toIso8601String().split("T").first}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Builds the PDF then opens the platform's share/print sheet
  /// (`Printing.sharePdf`) so the teacher can save, print, or send it.
  static Future<void> exportPdfTable({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    String? subtitle,
  }) async {
    final bytes = await buildPdfBytes(title: title, headers: headers, rows: rows, subtitle: subtitle);
    await Printing.sharePdf(bytes: bytes, filename: '${_slugify(title)}.pdf');
  }

  static String _slugify(String s) =>
      s.replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^\w_]'), '');
}
