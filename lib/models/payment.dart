/// A single repayment recorded against a credit account. Payments are append
/// only — they form the audit trail, and the outstanding balance is always
/// derived from them rather than overwritten.
class Payment {
  final int? id;
  final int loanId;
  final double amount;
  final DateTime paidAt;
  final String note;

  const Payment({
    this.id,
    required this.loanId,
    required this.amount,
    required this.paidAt,
    this.note = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'loanId': loanId,
        'amount': amount,
        'paidAt': paidAt.millisecondsSinceEpoch,
        'note': note,
      };

  factory Payment.fromMap(Map<String, Object?> map) => Payment(
        id: map['id'] as int?,
        loanId: map['loanId'] as int,
        amount: (map['amount'] as num).toDouble(),
        paidAt: DateTime.fromMillisecondsSinceEpoch(map['paidAt'] as int),
        note: (map['note'] as String?) ?? '',
      );
}
