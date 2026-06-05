/// A single qardan (interest-free loan) given to a debtor.
class Loan {
  final int? id;
  final String debtorName;
  final String phoneNumber;
  final double principal; // original amount given
  final double amountPaid; // total repaid so far
  final DateTime dateGiven;
  final DateTime? dueDate;
  final String note;

  /// How often (in days) a reminder SMS should be sent. 0 = never.
  final int reminderIntervalDays;

  /// Epoch millis of the last reminder we actually sent. Null = none yet.
  final int? lastReminderAt;

  /// When false the loan is settled / archived and no reminders are sent.
  final bool isActive;

  const Loan({
    this.id,
    required this.debtorName,
    required this.phoneNumber,
    required this.principal,
    this.amountPaid = 0,
    required this.dateGiven,
    this.dueDate,
    this.note = '',
    this.reminderIntervalDays = 7,
    this.lastReminderAt,
    this.isActive = true,
  });

  double get outstanding => (principal - amountPaid).clamp(0, double.infinity);

  bool get isSettled => outstanding <= 0;

  Loan copyWith({
    int? id,
    String? debtorName,
    String? phoneNumber,
    double? principal,
    double? amountPaid,
    DateTime? dateGiven,
    DateTime? dueDate,
    String? note,
    int? reminderIntervalDays,
    int? lastReminderAt,
    bool? isActive,
  }) {
    return Loan(
      id: id ?? this.id,
      debtorName: debtorName ?? this.debtorName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      principal: principal ?? this.principal,
      amountPaid: amountPaid ?? this.amountPaid,
      dateGiven: dateGiven ?? this.dateGiven,
      dueDate: dueDate ?? this.dueDate,
      note: note ?? this.note,
      reminderIntervalDays: reminderIntervalDays ?? this.reminderIntervalDays,
      lastReminderAt: lastReminderAt ?? this.lastReminderAt,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'debtorName': debtorName,
      'phoneNumber': phoneNumber,
      'principal': principal,
      'amountPaid': amountPaid,
      'dateGiven': dateGiven.millisecondsSinceEpoch,
      'dueDate': dueDate?.millisecondsSinceEpoch,
      'note': note,
      'reminderIntervalDays': reminderIntervalDays,
      'lastReminderAt': lastReminderAt,
      'isActive': isActive ? 1 : 0,
    };
  }

  factory Loan.fromMap(Map<String, Object?> map) {
    return Loan(
      id: map['id'] as int?,
      debtorName: map['debtorName'] as String,
      phoneNumber: map['phoneNumber'] as String,
      principal: (map['principal'] as num).toDouble(),
      amountPaid: (map['amountPaid'] as num).toDouble(),
      dateGiven:
          DateTime.fromMillisecondsSinceEpoch(map['dateGiven'] as int),
      dueDate: map['dueDate'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['dueDate'] as int),
      note: (map['note'] as String?) ?? '',
      reminderIntervalDays: (map['reminderIntervalDays'] as int?) ?? 7,
      lastReminderAt: map['lastReminderAt'] as int?,
      isActive: (map['isActive'] as int? ?? 1) == 1,
    );
  }
}
