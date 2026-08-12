import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bond2/core/database/database.dart';
import 'package:bond2/features/materials/materials_repository.dart';
import 'package:bond2/features/payments/payments_repository.dart';
import 'package:bond2/features/students/students_repository.dart';

void main() {
  late AppDatabase db;
  late StudentsRepository studentsRepo;
  late MaterialsRepository materialsRepo;
  late PaymentsRepository paymentsRepo;

  setUp(() {
    db = openTestDatabase();
    studentsRepo = StudentsRepository(db);
    materialsRepo = MaterialsRepository(db);
    paymentsRepo = PaymentsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Material purchases (rules #39-41, #67)', () {
    test('purchasing a material creates a charge for its current price', () async {
      final studentId = await studentsRepo.addStudent(name: 'طالب الكتاب');
      final materialId = await materialsRepo.addMaterial(
        name: 'كتاب الفيزياء', type: MaterialType.book, pricePiastres: 8000,
      );

      await materialsRepo.purchaseMaterial(studentId: studentId, materialId: materialId);

      final balance = await studentsRepo.balanceFor(studentId);
      expect(balance.totalCharged, 8000);
      expect(balance.outstanding, 8000);
    });

    test('later price changes do not alter historical purchases', () async {
      final studentId = await studentsRepo.addStudent(name: 'طالب قديم');
      final materialId = await materialsRepo.addMaterial(
        name: 'مذكرة كيمياء', type: MaterialType.note, pricePiastres: 5000,
      );

      await materialsRepo.purchaseMaterial(studentId: studentId, materialId: materialId);

      // Price increases after the purchase was made.
      await (db.update(db.materials)..where((t) => t.id.equals(materialId)))
          .write(const MaterialsCompanion(pricePiastres: Value(10000)));

      final purchases = await (db.select(db.materialPurchases)
            ..where((t) => t.studentId.equals(studentId)))
          .get();
      expect(purchases.single.pricePiastresAtPurchase, 5000); // unchanged snapshot

      final balance = await studentsRepo.balanceFor(studentId);
      expect(balance.totalCharged, 5000); // charge also unaffected
    });

    test('partial payment on a material purchase (rule #40)', () async {
      final studentId = await studentsRepo.addStudent(name: 'طالب دفع جزئي');
      final materialId = await materialsRepo.addMaterial(
        name: 'كتاب أحياء', type: MaterialType.book, pricePiastres: 10000,
      );
      await materialsRepo.purchaseMaterial(studentId: studentId, materialId: materialId);

      final open = await paymentsRepo.openChargesFor(studentId);
      await paymentsRepo.recordPayment(
        studentId: studentId,
        amountPiastres: 4000,
        allocations: {open.first.charge.id: 4000},
      );

      final balance = await studentsRepo.balanceFor(studentId);
      expect(balance.totalPaid, 4000);
      expect(balance.outstanding, 6000);
    });

    test('material sales report aggregates across all purchases', () async {
      final materialId = await materialsRepo.addMaterial(
        name: 'مذكرة رياضيات', type: MaterialType.note, pricePiastres: 2000,
      );
      final s1 = await studentsRepo.addStudent(name: 'طالب 1');
      final s2 = await studentsRepo.addStudent(name: 'طالب 2');
      await materialsRepo.purchaseMaterial(studentId: s1, materialId: materialId);
      await materialsRepo.purchaseMaterial(studentId: s2, materialId: materialId);

      final open1 = await paymentsRepo.openChargesFor(s1);
      await paymentsRepo.recordPayment(
          studentId: s1, amountPiastres: 2000, allocations: {open1.first.charge.id: 2000});

      final report = await materialsRepo.salesReportFor(materialId);
      expect(report.count, 2);
      expect(report.totalValue, 4000);
      expect(report.totalCollected, 2000);
      expect(report.totalOutstanding, 2000);
    });
  });
}
