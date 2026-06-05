/// One record of a reminder SMS we attempted to send.
class ReminderLog {
  final int? id;
  final int loanId;
  final String debtorName;
  final String phoneNumber;
  final double amount; // outstanding amount at the time of sending
  final DateTime sentAt;
  final bool success;

  const ReminderLog({
    this.id,
    required this.loanId,
    required this.debtorName,
    required this.phoneNumber,
    required this.amount,
    required this.sentAt,
    required this.success,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'loanId': loanId,
      'debtorName': debtorName,
      'phoneNumber': phoneNumber,
      'amount': amount,
      'sentAt': sentAt.millisecondsSinceEpoch,
      'success': success ? 1 : 0,
    };
  }

  factory ReminderLog.fromMap(Map<String, Object?> map) {
    return ReminderLog(
      id: map['id'] as int?,
      loanId: map['loanId'] as int,
      debtorName: map['debtorName'] as String,
      phoneNumber: map['phoneNumber'] as String,
      amount: (map['amount'] as num).toDouble(),
      sentAt: DateTime.fromMillisecondsSinceEpoch(map['sentAt'] as int),
      success: (map['success'] as int? ?? 0) == 1,
    );
  }
}
