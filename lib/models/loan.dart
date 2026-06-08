/// A single credit account / invoice extended to a customer.
///
/// The [principal] is the locked original amount — it is set once at creation
/// and never edited afterwards, so the ledger math can't be corrupted. The
/// amount repaid is NOT stored here; it is derived from the payments table and
/// supplied via [amountPaid] when the row is loaded through a joined query.
class Loan {
  final int? id;
  final int customerId;
  final String reference; // invoice / order number (optional)
  final double principal; // locked at creation
  final DateTime dateGiven;
  final DateTime? dueDate;
  final String note;
  final int reminderIntervalDays;
  final int? lastReminderAt;
  final bool isActive;

  // --- Transient (not persisted) — populated by joined reads -------------
  final double amountPaid;
  final String customerName;
  final String customerPhone;

  const Loan({
    this.id,
    required this.customerId,
    this.reference = '',
    required this.principal,
    required this.dateGiven,
    this.dueDate,
    this.note = '',
    this.reminderIntervalDays = 7,
    this.lastReminderAt,
    this.isActive = true,
    this.amountPaid = 0,
    this.customerName = '',
    this.customerPhone = '',
  });

  double get outstanding =>
      (principal - amountPaid).clamp(0, double.infinity);

  bool get isSettled => outstanding <= 0;

  // Back-compat accessors used by the SMS/reminder layer.
  String get debtorName => customerName;
  String get phoneNumber => customerPhone;

  /// Whole days the account is past its due date (0 if not overdue / no due).
  int daysOverdue(DateTime now) {
    final due = dueDate;
    if (due == null || now.isBefore(due)) return 0;
    return now.difference(due).inDays;
  }

  /// Whether an automatic reminder should be sent right now.
  ///
  /// Fixes two prior bugs:
  ///  - Never treats a missing [lastReminderAt] as epoch 0 (which caused an
  ///    instant reminder on the first background sweep).
  ///  - Honours [dueDate]: with a due date set, the first reminder lands ON the
  ///    due date and recurs every interval after; with no due date, the first
  ///    reminder lands one interval after [dateGiven] — never the same day.
  bool isReminderDue(DateTime now) {
    if (!isActive || reminderIntervalDays <= 0 || isSettled) return false;

    final intervalMs = reminderIntervalDays * 24 * 60 * 60 * 1000;
    final hasDueDate = dueDate != null;
    final anchorMs = (dueDate ?? dateGiven).millisecondsSinceEpoch;

    // Baseline = the synthetic "last reminder" used before any real one is sent.
    final baselineMs = hasDueDate ? anchorMs - intervalMs : anchorMs;
    final lastMs = lastReminderAt ?? baselineMs;

    return now.millisecondsSinceEpoch - lastMs >= intervalMs;
  }

  Loan copyWith({
    int? id,
    int? customerId,
    String? reference,
    double? principal,
    DateTime? dateGiven,
    DateTime? dueDate,
    String? note,
    int? reminderIntervalDays,
    int? lastReminderAt,
    bool? isActive,
    double? amountPaid,
    String? customerName,
    String? customerPhone,
  }) {
    return Loan(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      reference: reference ?? this.reference,
      principal: principal ?? this.principal,
      dateGiven: dateGiven ?? this.dateGiven,
      dueDate: dueDate ?? this.dueDate,
      note: note ?? this.note,
      reminderIntervalDays: reminderIntervalDays ?? this.reminderIntervalDays,
      lastReminderAt: lastReminderAt ?? this.lastReminderAt,
      isActive: isActive ?? this.isActive,
      amountPaid: amountPaid ?? this.amountPaid,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
    );
  }

  /// Only the persisted columns (transient display fields excluded).
  Map<String, Object?> toMap() => {
        'id': id,
        'customerId': customerId,
        'reference': reference,
        'principal': principal,
        'dateGiven': dateGiven.millisecondsSinceEpoch,
        'dueDate': dueDate?.millisecondsSinceEpoch,
        'note': note,
        'reminderIntervalDays': reminderIntervalDays,
        'lastReminderAt': lastReminderAt,
        'isActive': isActive ? 1 : 0,
      };

  factory Loan.fromMap(Map<String, Object?> map) => Loan(
        id: map['id'] as int?,
        customerId: map['customerId'] as int,
        reference: (map['reference'] as String?) ?? '',
        principal: (map['principal'] as num).toDouble(),
        dateGiven:
            DateTime.fromMillisecondsSinceEpoch(map['dateGiven'] as int),
        dueDate: map['dueDate'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['dueDate'] as int),
        note: (map['note'] as String?) ?? '',
        reminderIntervalDays: (map['reminderIntervalDays'] as int?) ?? 7,
        lastReminderAt: map['lastReminderAt'] as int?,
        isActive: (map['isActive'] as int? ?? 1) == 1,
        // Aggregates supplied by joined queries (default to 0/'').
        amountPaid: (map['amountPaid'] as num?)?.toDouble() ?? 0,
        customerName: (map['customerName'] as String?) ?? '',
        customerPhone: (map['customerPhone'] as String?) ?? '',
      );
}
