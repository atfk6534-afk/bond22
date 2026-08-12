import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bond2/core/database/database.dart';
import 'package:bond2/core/utils/id_generator.dart';
import 'package:bond2/features/payments/payments_repository.dart';
import 'package:bond2/features/students/students_repository.dart';

void main() {
  late AppDatabase db;
  late StudentsRepository studentsRepo;
  late PaymentsRepository paymentsRepo;

  setUp(() {
    db = openTestDatabase();
    studentsRepo = StudentsRepository(db);
    paymentsRepo = PaymentsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> addStudentWithCharge(int chargePiastres) async {
    final studentId = await studentsRepo.addStudent(name: 'طالب اختبار');
    await db.into(db.charges).insert(ChargesCompanion.insert(
          id: IdGenerator.newId(),
          studentId: studentId,
          sourceType: ChargeSourceType.lesson,
          description: const Value('حصة تجريبية'),
          amountPiastres: chargePiastres,
        ));
    return studentId;
  }

  group('Payment calculations (rule #30)', () {
    test('full payment brings outstanding balance to zero', () async {
      final studentId = await addStudentWithCharge(10000); // 100 EGP
      final charges = await paymentsRepo.openChargesFor(studentId);
      expect(charges.length, 1);

      await paymentsRepo.recordPayment(
        studentId: studentId,
        amountPiastres: 10000,
        allocations: {charges.first.charge.id: 10000},
      );

      final balance = await studentsRepo.balanceFor(studentId);
      expect(balance.totalCharged, 10000);
      expect(balance.totalPaid, 10000);
      expect(balance.outstanding, 0);
    });

    test('partial payment leaves correct remaining amount', () async {
      final studentId = await addStudentWithCharge(10000);
      final charges = await paymentsRepo.openChargesFor(studentId);

      await paymentsRepo.recordPayment(
        studentId: studentId,
        amountPiastres: 5000,
        allocations: {charges.first.charge.id: 5000},
      );

      var balance = await studentsRepo.balanceFor(studentId);
      expect(balance.outstanding, 5000);

      // Second partial payment on the same charge.
      final stillOpen = await paymentsRepo.openChargesFor(studentId);
      expect(stillOpen.first.remaining, 5000);
      await paymentsRepo.recordPayment(
        studentId: studentId,
        amountPiastres: 5000,
        allocations: {stillOpen.first.charge.id: 5000},
      );

      balance = await studentsRepo.balanceFor(studentId);
      expect(balance.outstanding, 0);
    });

    test('payment allocated across two charges (rule #33 example)', () async {
      final studentId = await studentsRepo.addStudent(name: 'طالب متعدد المستحقات');
      final lessonChargeId = IdGenerator.newId();
      final bookChargeId = IdGenerator.newId();
      await db.into(db.charges).insert(ChargesCompanion.insert(
            id: lessonChargeId, studentId: studentId,
            sourceType: ChargeSourceType.lesson, amountPiastres: 10000,
          ));
      await db.into(db.charges).insert(ChargesCompanion.insert(
            id: bookChargeId, studentId: studentId,
            sourceType: ChargeSourceType.material, amountPiastres: 5000,
          ));

      // Student pays 120 EGP: 100 to the lesson, 20 to the book.
      await paymentsRepo.recordPayment(
        studentId: studentId,
        amountPiastres: 12000,
        allocations: {lessonChargeId: 10000, bookChargeId: 2000},
      );

      final open = await paymentsRepo.openChargesFor(studentId);
      expect(open.length, 1);
      expect(open.first.charge.id, bookChargeId);
      expect(open.first.remaining, 3000); // 50 - 20 = 30 EGP remaining
    });

    test('overpayment on a single charge is rejected (rule #69)', () async {
      final studentId = await addStudentWithCharge(10000);
      final charges = await paymentsRepo.openChargesFor(studentId);

      expect(
        () => paymentsRepo.recordPayment(
          studentId: studentId,
          amountPiastres: 15000,
          allocations: {charges.first.charge.id: 15000},
        ),
        throwsA(isA<OverpaymentException>()),
      );
    });

    test('allocations exceeding payment amount are rejected', () async {
      final studentId = await addStudentWithCharge(10000);
      final charges = await paymentsRepo.openChargesFor(studentId);

      expect(
        () => paymentsRepo.recordPayment(
          studentId: studentId,
          amountPiastres: 5000,
          allocations: {charges.first.charge.id: 8000},
        ),
        throwsA(isA<OverpaymentException>()),
      );
    });

    test('zero or negative payment amount is rejected', () async {
      final studentId = await addStudentWithCharge(10000);
      expect(
        () => paymentsRepo.recordPayment(studentId: studentId, amountPiastres: 0, allocations: {}),
        throwsA(isA<OverpaymentException>()),
      );
    });

    test('FIX #1: underallocated payment (money left unallocated) is rejected', () async {
      final studentId = await addStudentWithCharge(10000); // 100 EGP charge
      final charges = await paymentsRepo.openChargesFor(studentId);

      // Student pays 100 EGP but only 60 EGP gets allocated to the charge -
      // this must be rejected outright, never silently accepted, because
      // student balances are always computed by summing allocations only.
      expect(
        () => paymentsRepo.recordPayment(
          studentId: studentId,
          amountPiastres: 10000,
          allocations: {charges.first.charge.id: 6000},
        ),
        throwsA(isA<OverpaymentException>()),
      );

      // Confirm nothing was persisted at all (atomic rejection).
      final balance = await studentsRepo.balanceFor(studentId);
      expect(balance.totalPaid, 0);
      expect(balance.outstanding, 10000);
    });

    test('FIX #1: empty allocations map is rejected even with a positive amount', () async {
      final studentId = await addStudentWithCharge(10000);
      expect(
        () => paymentsRepo.recordPayment(studentId: studentId, amountPiastres: 5000, allocations: {}),
        throwsA(isA<OverpaymentException>()),
      );
    });

    test('FIX #1: zero-value allocation entries are rejected', () async {
      final studentId = await addStudentWithCharge(10000);
      final charges = await paymentsRepo.openChargesFor(studentId);
      expect(
        () => paymentsRepo.recordPayment(
          studentId: studentId,
          amountPiastres: 5000,
          allocations: {charges.first.charge.id: 0},
        ),
        throwsA(isA<OverpaymentException>()),
      );
    });

    test('FIX #1: exact allocation across multiple charges succeeds and sums correctly', () async {
      final studentId = await studentsRepo.addStudent(name: 'طالب توزيع دقيق');
      final c1 = IdGenerator.newId();
      final c2 = IdGenerator.newId();
      await db.into(db.charges).insert(ChargesCompanion.insert(
            id: c1, studentId: studentId, sourceType: ChargeSourceType.lesson, amountPiastres: 4000,
          ));
      await db.into(db.charges).insert(ChargesCompanion.insert(
            id: c2, studentId: studentId, sourceType: ChargeSourceType.lesson, amountPiastres: 6000,
          ));

      // 100 EGP paid, split exactly 40/60 - must succeed.
      await paymentsRepo.recordPayment(
        studentId: studentId,
        amountPiastres: 10000,
        allocations: {c1: 4000, c2: 6000},
      );

      final balance = await studentsRepo.balanceFor(studentId);
      expect(balance.totalPaid, 10000);
      expect(balance.outstanding, 0);
    });
  });
}
