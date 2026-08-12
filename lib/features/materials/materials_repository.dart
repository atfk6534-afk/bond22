import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/services/file_storage_service.dart';
import '../../core/utils/id_generator.dart';

class MaterialSalesReport {
  final int count;
  final int totalValue;
  final int totalCollected;
  int get totalOutstanding => totalValue - totalCollected;
  const MaterialSalesReport({required this.count, required this.totalValue, required this.totalCollected});
}

class MaterialsRepository {
  final AppDatabase db;
  MaterialsRepository(this.db);

  Stream<List<MaterialItem>> watchAll() {
    return (db.select(db.materials)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();
  }

  /// Creates a material. If [sourceFilePath] is given (e.g. a path the
  /// teacher picked from Downloads via file_picker), the file is COPIED
  /// into BOND2's own persistent app storage under a name derived from
  /// the new material's id — never the original external path and never
  /// the material's (possibly Arabic) name (fix #3). The persistent path
  /// is what gets stored in the database, so the app never depends on
  /// the original external file staying in place, and the file is
  /// automatically included in backups (rules #38, #53).
  Future<String> addMaterial({
    required String name,
    required MaterialType type,
    String? academicYearId,
    String? grade,
    String? subjectId,
    required int pricePiastres,
    String? sourceFilePath,
    String? description,
  }) async {
    final id = IdGenerator.newId();

    String? persistentFilePath;
    if (sourceFilePath != null && sourceFilePath.trim().isNotEmpty) {
      persistentFilePath = await FileStorageService.storeMaterialFile(
        materialId: id,
        sourcePath: sourceFilePath,
      );
    }

    await db.into(db.materials).insert(MaterialsCompanion.insert(
          id: id,
          name: name,
          type: type,
          academicYearId: Value(academicYearId),
          grade: Value(grade),
          subjectId: Value(subjectId),
          pricePiastres: Value(pricePiastres),
          filePath: Value(persistentFilePath),
          description: Value(description),
        ));
    return id;
  }

  /// Deletes a material and its stored file, if any (rule #38 - "Delete
  /// with appropriate confirmation" is enforced by the calling UI).
  Future<void> deleteMaterial(String materialId) async {
    await (db.delete(db.materials)..where((t) => t.id.equals(materialId))).go();
    await FileStorageService.deleteMaterialFile(materialId);
  }

  /// Records a student purchasing a material. The CURRENT material price
  /// is snapshotted onto the purchase and its Charge so later price
  /// changes never alter this historical record (rule #39, #67).
  Future<String> purchaseMaterial({
    required String studentId,
    required String materialId,
  }) async {
    return db.transaction<String>(() async {
      final material = await (db.select(db.materials)..where((t) => t.id.equals(materialId))).getSingle();
      final purchaseId = IdGenerator.newId();
      await db.into(db.materialPurchases).insert(MaterialPurchasesCompanion.insert(
            id: purchaseId,
            studentId: studentId,
            materialId: materialId,
            pricePiastresAtPurchase: material.pricePiastres,
          ));
      if (material.pricePiastres > 0) {
        await db.into(db.charges).insert(ChargesCompanion.insert(
              id: IdGenerator.newId(),
              studentId: studentId,
              sourceType: ChargeSourceType.material,
              sourceId: Value(purchaseId),
              description: Value(material.name),
              amountPiastres: material.pricePiastres,
            ));
      }
      return purchaseId;
    });
  }

  Future<MaterialSalesReport> salesReportFor(String materialId) async {
    final purchases =
        await (db.select(db.materialPurchases)..where((t) => t.materialId.equals(materialId))).get();
    var totalValue = 0;
    var totalCollected = 0;
    for (final purchase in purchases) {
      totalValue += purchase.pricePiastresAtPurchase;
      final charge = await (db.select(db.charges)..where((t) => t.sourceId.equals(purchase.id))).getSingleOrNull();
      if (charge != null) {
        final sum = db.paymentAllocations.amountPiastres.sum();
        final q = db.selectOnly(db.paymentAllocations)
          ..addColumns([sum])
          ..where(db.paymentAllocations.chargeId.equals(charge.id));
        totalCollected += (await q.getSingle()).read(sum) ?? 0;
      }
    }
    return MaterialSalesReport(count: purchases.length, totalValue: totalValue, totalCollected: totalCollected);
  }
}

final materialsRepositoryProvider = Provider<MaterialsRepository>((ref) {
  return MaterialsRepository(ref.watch(databaseProvider));
});

final allMaterialsProvider = StreamProvider<List<MaterialItem>>((ref) {
  return ref.watch(materialsRepositoryProvider).watchAll();
});
