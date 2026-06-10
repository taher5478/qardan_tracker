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
/// too.
const String kAppDownloadLink = 'https://oweme-ten.vercel.app';

/// Always appended to reminders: makes clear the message is automated (not
/// personally sent). No marketing/URL here, so it stays spam-filter-friendly.
const String kSmsAutoNote =
    '\n\nThis is an automated reminder sent by the $kAppName app.';

/// Optional app-link line. Only appended when the owner turns it on in Settings
/// AND is a paid subscriber (keeps the link off most messages by default).
const String kSmsDownloadSuffix = ' Get $kAppName: $kAppDownloadLink';

// --- Licensing (Supabase activation keys) ----------------------------------

/// Length of the app-managed free trial, in days.
const int kTrialDays = 30;

/// Anti-spam pacing for outbound SMS: a randomized gap between each message so
/// carriers don't flag a rapid programmatic burst. Actual gap = base + jitter.
const int kSmsGapBaseSeconds = 6;
const int kSmsGapJitterSeconds = 5; // 0..5 added randomly -> 6–11s apart

/// Shown on the activation/subscription screen.
const String kPriceLabel = 'Rs 499 / year';

/// How the user obtains a key from you (shown on the activation screen).
const String kActivationContact = 'WhatsApp/email us to get your key.';

/// Supabase project that stores and validates activation keys.
const String kSupabaseUrl = 'https://vghvhzpvcfbqockayipl.supabase.co';
const String kSupabasePublishableKey = 'sb_publishable_BAOE3hgx8e2CeGwwmgJrKQ_MYy-RVE6';

/// Web OAuth client ID (from Google Cloud → Credentials → "Web application").
/// Needed so Google sign-in returns an ID token Supabase Auth can verify.
const String kGoogleServerClientId =
    '368260346508-0of9k277sec9vcmpmh7j6f708emhevij.apps.googleusercontent.com';
