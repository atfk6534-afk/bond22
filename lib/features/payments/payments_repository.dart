import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/utils/id_generator.dart';

/// A charge together with how much of it is still outstanding.
class OpenCharge {
  final Charge charge;
  final int paidSoFar;
  int get remaining => charge.amountPiastres - paidSoFar;
  const OpenCharge({required this.charge, required this.paidSoFar});
}

class OverpaymentException implements Exception {
  final String message;
  OverpaymentException(this.message);
  @override
  String toString() => message;
}

class PaymentsRepository {
  final AppDatabase db;
  PaymentsRepository(this.db);

  /// All charges for a student that still have a remaining balance,
  /// oldest first — used to build the "Record Payment" allocation UI
  /// (rule #33).
  Future<List<OpenCharge>> openChargesFor(String studentId) async {
    final charges = await (db.select(db.charges)
          ..where((t) => t.studentId.equals(studentId))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();

    final result = <OpenCharge>[];
    for (final c in charges) {
      final paid = await _allocatedFor(c.id);
      if (c.amountPiastres - paid > 0) {
        result.add(OpenCharge(charge: c, paidSoFar: paid));
      }
    }
    return result;
  }

  Future<int> _allocatedFor(String chargeId) async {
    final sum = db.paymentAllocations.amountPiastres.sum();
    final query = db.selectOnly(db.paymentAllocations)
      ..addColumns([sum])
      ..where(db.paymentAllocations.chargeId.equals(chargeId));
    final row = await query.getSingle();
    return row.read(sum) ?? 0;
  }

  /// Sum of remaining balances across all open charges for a student —
  /// the maximum amount that can ever be fully allocated in one payment
  /// (since BOND2 has no credit-balance system). Used by the UI to warn
  /// before the teacher types an amount that could never be allocated.
  Future<int> totalOpenChargesFor(String studentId) async {
    final open = await openChargesFor(studentId);
    return open.fold<int>(0, (sum, oc) => sum + oc.remaining);
  }

  /// Records a payment atomically: creates the Payment row, then one
  /// PaymentAllocation row per entry in [allocations] (chargeId -> amount).
  /// Everything commits together or nothing does (rule #6).
  ///
  /// STRICT INTEGRITY RULE: every piastre of [amountPiastres] MUST be
  /// allocated to a charge. Partial allocation (allocatedTotal <
  /// amountPiastres) is rejected just as strictly as overpayment
  /// (allocatedTotal > amountPiastres) — student balances are always
  /// computed by summing PaymentAllocations (rule #35), so any
  /// unallocated remainder would silently vanish from every balance and
  /// report in the app while still being counted as "collected" money.
  /// BOND2 does not implement a credit-balance/wallet system, so there
  /// is currently no safe place to park unallocated funds.
  ///
  /// Throws [OverpaymentException] if:
  /// - amountPiastres <= 0
  /// - any single allocation exceeds that charge's remaining balance
  /// - the allocations do not sum to EXACTLY amountPiastres (rule #69)
  Future<String> recordPayment({
    required String studentId,
    required int amountPiastres,
    required Map<String, int> allocations, // chargeId -> piastres
    String? notes,
  }) async {
    if (amountPiastres <= 0) {
      throw OverpaymentException('قيمة الدفعة يجب أن تكون أكبر من صفر');
    }
    if (allocations.isEmpty) {
      throw OverpaymentException('يجب توزيع الدفعة على مستحق واحد على الأقل');
    }
    if (allocations.values.any((v) => v <= 0)) {
      throw OverpaymentException('لا يمكن توزيع مبلغ صفر أو سالب على أي مستحق');
    }
    final allocatedTotal = allocations.values.fold<int>(0, (a, b) => a + b);
    if (allocatedTotal > amountPiastres) {
      throw OverpaymentException('إجمالي التوزيع أكبر من قيمة الدفعة');
    }
    if (allocatedTotal < amountPiastres) {
      throw OverpaymentException(
        'يجب توزيع كامل مبلغ الدفعة على المستحقات. '
        'المُوزَّع: ${allocatedTotal / 100} من ${amountPiastres / 100} جنيه. '
        'استخدم "توزيع تلقائي" أو عدّل القيم يدويًا حتى يتطابق الإجمالي.',
      );
    }

    return db.transaction<String>(() async {
      for (final entry in allocations.entries) {
        final charge = await (db.select(db.charges)
              ..where((t) => t.id.equals(entry.key)))
            .getSingle();
        final paidSoFar = await _allocatedFor(entry.key);
        final remaining = charge.amountPiastres - paidSoFar;
        if (entry.value > remaining) {
          throw OverpaymentException(
            'المبلغ الموزّع على "${charge.description ?? ''}" أكبر من المتبقي عليه',
          );
        }
      }

      final paymentId = IdGenerator.newId();
      await db.into(db.payments).insert(PaymentsCompanion.insert(
            id: paymentId,
            studentId: studentId,
            amountPiastres: amountPiastres,
            notes: Value(notes),
          ));

      for (final entry in allocations.entries) {
        await db.into(db.paymentAllocations).insert(
              PaymentAllocationsCompanion.insert(
                id: IdGenerator.newId(),
                paymentId: paymentId,
                chargeId: entry.key,
                amountPiastres: entry.value,
              ),
            );
      }

      return paymentId;
    });
  }

  Stream<List<Payment>> watchForStudent(String studentId) {
    return (db.select(db.payments)
          ..where((t) => t.studentId.equals(studentId))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .watch();
  }

  Stream<List<Payment>> watchToday() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return (db.select(db.payments)
          ..where((t) => t.date.isBetweenValues(start, end)))
        .watch();
  }
}

final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  return PaymentsRepository(ref.watch(databaseProvider));
});

final openChargesProvider =
    FutureProvider.family<List<OpenCharge>, String>((ref, studentId) {
  return ref.watch(paymentsRepositoryProvider).openChargesFor(studentId);
});
