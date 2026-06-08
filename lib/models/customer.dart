/// A person/business the owner extends credit to. One customer can hold many
/// credit accounts (invoices), which is what enables a consolidated balance.
class Customer {
  final int? id;
  final String name;
  final String phone;
  final String note;
  final DateTime createdAt;

  /// Assigned reminder template; null means "use the default template".
  final int? templateId;

  const Customer({
    this.id,
    required this.name,
    required this.phone,
    this.note = '',
    required this.createdAt,
    this.templateId,
  });

  /// [clearTemplate] forces templateId back to null (copyWith can't set null).
  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    String? note,
    DateTime? createdAt,
    int? templateId,
    bool clearTemplate = false,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      templateId: clearTemplate ? null : (templateId ?? this.templateId),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'note': note,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'templateId': templateId,
      };

  factory Customer.fromMap(Map<String, Object?> map) => Customer(
        id: map['id'] as int?,
        name: map['name'] as String,
        phone: map['phone'] as String,
        note: (map['note'] as String?) ?? '',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
        templateId: map['templateId'] as int?,
      );

  String get firstName =>
      name.trim().isEmpty ? name : name.trim().split(' ').first;
}

/// A customer plus aggregated figures across all their credit accounts, used
/// for the consolidated home screen.
class CustomerSummary {
  final Customer customer;
  final double totalOutstanding;
  final double totalGiven;
  final int openAccounts;
  final int dueNow; // accounts with a reminder currently due

  const CustomerSummary({
    required this.customer,
    required this.totalOutstanding,
    required this.totalGiven,
    required this.openAccounts,
    required this.dueNow,
  });

  bool get isSettled => totalOutstanding <= 0;
}
