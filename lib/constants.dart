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

/// Download link for the app, appended to every reminder so debtors can get it
/// too. TODO: replace with the real store/website link when available.
const String kAppDownloadLink = 'https://oweme.app/download';

/// Footer automatically appended to every outgoing reminder SMS.
const String kSmsFooter =
    '\n\nSent via $kAppName. Track & manage your dues — download: '
    '$kAppDownloadLink';

// --- Licensing (Supabase activation keys) ----------------------------------

/// Length of the app-managed free trial, in days.
const int kTrialDays = 30;

/// Shown on the activation screen.
const String kPriceLabel = 'Rs 100 / year';

/// How the user obtains a key from you (shown on the activation screen).
const String kActivationContact = 'WhatsApp/email us to get your key.';

/// Supabase project that stores and validates activation keys.
const String kSupabaseUrl = 'https://vghvhzpvcfbqockayipl.supabase.co';
const String kSupabasePublishableKey = 'sb_publishable_BAOE3hgx8e2CeGwwmgJrKQ_MYy-RVE6';
