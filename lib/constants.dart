/// App-wide constants. Change the display name in one place.
const String kAppName = 'OweMe';

/// Default currency symbol. The live value is read from settings so a business
/// can change it; this is only the fallback / first-run default.
const String kCurrencySymbol = 'Rs';

/// Default business name used in SMS templates until the owner sets their own.
const String kDefaultBusinessName = '';

/// Placeholders a business owner can use inside an SMS template. The engine in
/// [SmsService] substitutes these at send time.
///   {name}        - customer's first name
///   {fullname}    - customer's full name
///   {amount}      - outstanding amount, formatted with the currency symbol
///   {business}    - business name (blank if unset)
///   {reference}   - invoice / order reference (blank if unset)
///   {due}         - due date (blank if none)
///   {daysoverdue} - whole days past the due date (0 if not overdue / no due)
const String kDefaultSmsTemplate =
    'Reminder: an amount of {amount} is pending{reference}. '
    'Kindly clear it at your earliest convenience. Thank you.{business}';
