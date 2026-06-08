/// A reusable reminder message template. One template can be marked the default
/// (used when a customer has no specific template assigned).
class SmsTemplate {
  final int? id;
  final String name;
  final String body;
  final bool isDefault;

  const SmsTemplate({
    this.id,
    required this.name,
    required this.body,
    this.isDefault = false,
  });

  SmsTemplate copyWith({int? id, String? name, String? body, bool? isDefault}) =>
      SmsTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        body: body ?? this.body,
        isDefault: isDefault ?? this.isDefault,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'body': body,
        'isDefault': isDefault ? 1 : 0,
      };

  factory SmsTemplate.fromMap(Map<String, Object?> map) => SmsTemplate(
        id: map['id'] as int?,
        name: map['name'] as String,
        body: map['body'] as String,
        isDefault: (map['isDefault'] as int? ?? 0) == 1,
      );
}

/// Starter templates seeded on first run. The first one is the default.
const List<Map<String, String>> kSeedTemplates = [
  {
    'name': 'Professional',
    'body':
        'Reminder: an amount of {amount} is pending{reference}. Kindly clear '
            'it at your earliest convenience. Thank you.{business}',
  },
  {
    'name': 'Friendly',
    'body':
        'Hi {name}! 😊 Just a friendly reminder that {amount} is still pending. '
            'Whenever it’s convenient, no rush at all. Thanks a lot!{business}',
  },
  {
    'name': 'Polite formal',
    'body':
        'Dear {fullname}, this is a gentle reminder that {amount} remains '
            'outstanding{reference}. Kindly arrange the payment. Thank you.{business}',
  },
  {
    'name': 'Firm / overdue',
    'body':
        'Dear {fullname}, your payment of {amount} is now {daysoverdue} days '
            'overdue{reference}. Please settle it promptly to avoid further '
            'follow-up.{business}',
  },
  {
    'name': 'Short',
    'body': 'Reminder: {amount} pending{reference}. Please pay soon. '
        'Thank you.{business}',
  },
];
