import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

enum PaymentStatus { paid, partial, unpaid }

PaymentStatus paymentStatusFor({required int charged, required int paid}) {
  if (charged <= 0 || paid >= charged) return PaymentStatus.paid;
  if (paid <= 0) return PaymentStatus.unpaid;
  return PaymentStatus.partial;
}

class StatusBadge extends StatelessWidget {
  final PaymentStatus status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      PaymentStatus.paid => ('مدفوع بالكامل', Icons.check_circle_rounded, AppTheme.success),
      PaymentStatus.partial => ('مدفوع جزئيًا', Icons.timelapse_rounded, AppTheme.warning),
      PaymentStatus.unpaid => ('غير مدفوع', Icons.error_rounded, AppTheme.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}
