import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../db/database_helper.dart';
import '../models/loan.dart';
import '../models/reminder_log.dart';
import '../models/sms_template.dart';
import '../services/settings_service.dart';
import '../services/sms_service.dart';
import '../theme/app_theme.dart';
import '../ui/common.dart';

/// Create a new credit account, or edit the *terms* of an existing one.
///
/// On create: amount + customer name/phone are collected; the customer is found
/// (by phone) or created, so repeat customers consolidate automatically.
/// On edit: the principal is LOCKED (shown read-only) — only reference, due
/// date, reminder cadence and note can change, protecting the ledger math.
class EditLoanScreen extends StatefulWidget {
  const EditLoanScreen({
    super.key,
    this.loan,
    this.customerId,
    this.initialName,
    this.initialPhone,
  });

  /// Non-null => editing terms of this account.
  final Loan? loan;

  /// When adding for an existing customer, skip name/phone capture.
  final int? customerId;
  final String? initialName;
  final String? initialPhone;

  @override
  State<EditLoanScreen> createState() => _EditLoanScreenState();
}

class _EditLoanScreenState extends State<EditLoanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  late TextEditingController _name;
  late TextEditingController _phone;
  late TextEditingController _principal;
  late TextEditingController _reference;
  late TextEditingController _note;

  late DateTime _dateGiven;
  DateTime? _dueDate;
  bool _dueDateError = false;
  late int _reminderDays;

  // Message-preview state: the customer's assigned template (null = default)
  // and whether the user picked a different one in this screen.
  List<SmsTemplate> _templates = const [];
  int? _templateId;
  bool _templateTouched = false;

  // Open credits this customer already has — shown so the owner knows the
  // reminder SMS combines all of them into one message.
  int _otherOpenCredits = 0;

  final _amountFocus = FocusNode();

  static const _cadence = {
    'Off': 0,
    'Daily': 1,
    '3 days': 3,
    'Weekly': 7,
    'Bi-weekly': 15,
    'Monthly': 30,
  };

  bool get _isEditing => widget.loan != null;
  bool get _captureCustomer => !_isEditing && widget.customerId == null;

  @override
  void initState() {
    super.initState();
    final l = widget.loan;
    _name = TextEditingController(
        text: l?.customerName ?? widget.initialName ?? '');
    _phone = TextEditingController(
        text: l?.customerPhone ?? widget.initialPhone ?? '');
    _principal = TextEditingController(
        text: l == null ? '' : l.principal.toStringAsFixed(0));
    _reference = TextEditingController(text: l?.reference ?? '');
    _note = TextEditingController(text: l?.note ?? '');
    _dateGiven = l?.dateGiven ?? DateTime.now();
    _dueDate = l?.dueDate;
    _reminderDays = l?.reminderIntervalDays ?? 7;

    _templateId = l?.templateId;
    _loadContext();

    if (!_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _amountFocus.requestFocus();
      });
    }
  }

  /// Load templates (for the preview) and the customer's existing template /
  /// open-credit count, so the screen can explain exactly what will happen.
  Future<void> _loadContext() async {
    final templates = await _db.getTemplates();
    final customerId = widget.loan?.customerId ?? widget.customerId;
    int? assigned = _templateId;
    var others = 0;
    if (customerId != null) {
      assigned ??= (await _db.getCustomer(customerId))?.templateId;
      others = (await _db.getLoansForCustomer(customerId))
          .where((l) =>
              l.isActive && !l.isSettled && l.id != widget.loan?.id)
          .length;
    }
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _templateId ??= assigned;
      _otherOpenCredits = others;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _principal.dispose();
    _reference.dispose();
    _note.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    // Due date is mandatory: reminders anchor to it (first reminder lands ON
    // the due date, never before).
    setState(() => _dueDateError = _dueDate == null);
    if (!formOk || _dueDate == null) return;

    if (_isEditing) {
      final base = widget.loan!;
      // Build explicitly (not copyWith) to update only the editable terms;
      // principal and the original dateGiven stay locked.
      await _db.updateLoanTerms(Loan(
        id: base.id,
        customerId: base.customerId,
        reference: _reference.text.trim(),
        principal: base.principal,
        dateGiven: base.dateGiven,
        dueDate: _dueDate,
        note: _note.text.trim(),
        reminderIntervalDays: _reminderDays,
        lastReminderAt: base.lastReminderAt,
        isActive: base.isActive,
      ));
      await _applyTemplateChoice(base.customerId);
    } else {
      final customerId = widget.customerId ??
          await _db.findOrCreateCustomer(
              _name.text.trim(), _phone.text.trim());
      // First credit ever? Offer a test send after saving, so the owner sees
      // exactly what their customer receives.
      final isFirstRecord = (await _db.getAllLoans()).isEmpty;
      final loanId = await _db.insertLoan(Loan(
        customerId: customerId,
        reference: _reference.text.trim(),
        principal: double.parse(_principal.text.trim()),
        dateGiven: _dateGiven,
        dueDate: _dueDate,
        note: _note.text.trim(),
        reminderIntervalDays: _reminderDays,
      ));
      await _applyTemplateChoice(customerId);
      if (isFirstRecord && mounted) await _offerFirstSend(loanId);
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// Persist a template picked in the preview — it's a per-customer setting.
  Future<void> _applyTemplateChoice(int customerId) async {
    if (!_templateTouched) return;
    final c = await _db.getCustomer(customerId);
    if (c == null) return;
    await _db.updateCustomer(_templateId == null
        ? c.copyWith(clearTemplate: true)
        : c.copyWith(templateId: _templateId));
  }

  /// One-time onboarding moment: after the very first credit is saved, offer
  /// to send the reminder right away so the owner sees how reminders work.
  Future<void> _offerFirstSend(int loanId) async {
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your first credit is saved 🎉'),
        content: const Text(
            'Want to send the reminder SMS now? You’ll see exactly what your '
            'customer receives — after this, reminders go out automatically '
            'on schedule.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.sms_outlined, size: 18),
              label: const Text('Send now')),
        ],
      ),
    );
    if (send != true || !mounted) return;

    final sms = SmsService();
    if (!await sms.hasPermission() && !await sms.requestPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('SMS permission needed — reminder not sent.')));
      }
      return;
    }

    final loan = await _db.getLoan(loanId);
    if (loan == null) return;
    final now = DateTime.now();
    final ok = await sms.sendReminder(loan);
    await _db.insertReminderLog(ReminderLog(
      loanId: loanId,
      debtorName: loan.debtorName,
      phoneNumber: loan.phoneNumber,
      amount: loan.outstanding,
      sentAt: now,
      success: ok,
    ));
    if (ok) await _db.markReminderSent(loanId, now.millisecondsSinceEpoch);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      content: Text(ok
          ? 'Sent from your SIM — check your Messages app to see it.'
          : 'Couldn’t send. You can try from the account screen any time.'),
    ));
  }

  // --- Reminder transparency helpers ---------------------------------------

  String get _templateName {
    final match = _templates.where((t) => t.id == _templateId);
    if (match.isNotEmpty) return match.first.name;
    final def = _templates.where((t) => t.isDefault);
    return def.isEmpty ? 'Default' : def.first.name;
  }

  String get _templateBody {
    final match = _templates.where((t) => t.id == _templateId);
    if (match.isNotEmpty) return match.first.body;
    final def = _templates.where((t) => t.isDefault);
    return def.isEmpty ? kDefaultSmsTemplate : def.first.body;
  }

  /// The exact SMS the customer would receive, rendered from live form values.
  String get _previewMessage {
    final name = _name.text.trim().isEmpty
        ? (widget.loan?.customerName ?? widget.initialName ?? 'Customer')
        : _name.text.trim();
    final principal = double.tryParse(_principal.text.trim()) ??
        widget.loan?.principal ??
        0;
    return SmsService.render(
      Loan(
        customerId: 0,
        reference: _reference.text.trim(),
        principal: principal,
        amountPaid: widget.loan?.amountPaid ?? 0,
        dateGiven: _dateGiven,
        dueDate: _dueDate,
        customerName: name.isEmpty ? 'Customer' : name,
      ),
      template: _templateBody,
    );
  }

  /// Plain-words answer to "when will messages actually go out?".
  String _scheduleHint() {
    if (_reminderDays == 0) {
      return 'No automatic reminders — you can still send one manually any time.';
    }
    final every =
        _reminderDays == 1 ? 'every day' : 'every $_reminderDays days';
    final base = _dueDate == null
        ? 'First SMS goes out on the due date, then $every until paid.'
        : 'First SMS on ${DateFormat.yMMMd().format(_dueDate!)} (the due date), '
            'then $every until paid.';
    if (_otherOpenCredits > 0) {
      final n = _otherOpenCredits;
      return '$base This customer’s $n other open credit'
          '${n == 1 ? '' : 's'} will be combined into the same SMS.';
    }
    return base;
  }

  Future<void> _pickTemplate() async {
    final chosen = await showModalBottomSheet<Object?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Reminder template for this customer',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final t in _templates)
              ListTile(
                leading: Icon(
                    t.isDefault ? Icons.star_outline : Icons.sms_outlined),
                title: Text(t.name + (t.isDefault ? ' (default)' : '')),
                subtitle: Text(t.body,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: _templateId == null ? t.isDefault : t.id == _templateId,
                onTap: () => Navigator.pop(ctx, t.id),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    setState(() {
      _templateId = chosen as int;
      _templateTouched = true;
    });
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _dueDate = picked;
      _dueDateError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _captureCustomer
        ? _name.text.trim()
        : (widget.loan?.customerName ?? widget.initialName ?? '');
    return Scaffold(
      appBar: AppBar(
          title: Text(_isEditing ? 'Edit terms' : 'New credit account')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Row(
              children: [
                InitialAvatar(
                    name: displayName.isEmpty ? '?' : displayName, radius: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(displayName.isEmpty ? 'New customer' : displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _label('Amount given'),
            if (_isEditing)
              _lockedPrincipal()
            else
              TextFormField(
                controller: _principal,
                focusNode: _amountFocus,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: AppTheme.money(size: 26, color: AppColors.ink),
                onChanged: (_) => setState(() {}), // refresh message preview
                decoration: InputDecoration(
                    prefixText: '${AppSettings.instance.currencySymbol}  ',
                    hintText: '0'),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
            const SizedBox(height: 20),

            if (_captureCustomer) ...[
              _label('Customer name'),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Full name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              _label('Phone number'),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    hintText: '+92 300 1234567', prefixIcon: Icon(Icons.phone)),
                validator: (v) => (v == null || v.trim().length < 7)
                    ? 'Enter a valid number'
                    : null,
              ),
              const SizedBox(height: 20),
            ],

            _label('Due date'),
            _dateRow(
                _dueDate == null ? 'Select due date' : 'Due date',
                _dueDate,
                _pickDueDate,
                error: _dueDateError),
            if (_dueDateError)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Please select a due date',
                    style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
              ),
            const SizedBox(height: 20),

            _label('Invoice / reference (optional)'),
            TextFormField(
              controller: _reference,
              onChanged: (_) => setState(() {}), // refresh message preview
              decoration: const InputDecoration(hintText: 'e.g. INV-102'),
            ),
            const SizedBox(height: 24),

            _label('Remind automatically'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _cadence.entries.map((e) {
                final selected = _reminderDays == e.value;
                return ChoiceChip(
                  label: Text(e.key),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _reminderDays = e.value),
                  labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.ink,
                      fontWeight: FontWeight.w600),
                  selectedColor: AppColors.pine,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(
                      color: selected ? AppColors.pine : AppColors.hairline),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // Plain-words schedule: exactly when SMS will go out.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 15, color: AppColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_scheduleHint(),
                      style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12.5,
                          height: 1.35)),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_reminderDays > 0) ...[
              Row(
                children: [
                  _label('Message preview'),
                  const SizedBox(width: 4),
                  Tooltip(
                    message:
                        'Templates can be edited in\nSettings → Manage Message templates',
                    triggerMode: TooltipTriggerMode.tap,
                    child: Icon(Icons.info_outline,
                        size: 15, color: AppColors.muted),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _templates.isEmpty ? null : _pickTemplate,
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: Text(_templateName,
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.sage.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Text(_previewMessage,
                    style: const TextStyle(fontSize: 12.5, height: 1.45)),
              ),
              const SizedBox(height: 12),
            ],

            _label('Note (optional)'),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration:
                  const InputDecoration(hintText: 'e.g. for shop renovation'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(_isEditing ? 'Save changes' : 'Save credit'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lockedPrincipal() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.sage.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Text(money.format(widget.loan!.principal),
              style: AppTheme.money(size: 24)),
          const Spacer(),
          const Icon(Icons.lock_outline, size: 18, color: AppColors.muted),
          const SizedBox(width: 6),
          const Text('Locked', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.muted, fontWeight: FontWeight.w600)),
      );

  Widget _dateRow(String label, DateTime? date, VoidCallback onTap,
      {bool error = false}) {
    final df = DateFormat.yMMMd();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(
              color: error ? AppColors.danger : AppColors.hairline,
              width: error ? 1.4 : 1),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                size: 18, color: error ? AppColors.danger : AppColors.muted),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: error ? AppColors.danger : AppColors.muted)),
            const Spacer(),
            Text(date == null ? 'Not set' : df.format(date),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
