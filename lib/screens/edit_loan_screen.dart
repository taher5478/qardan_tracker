import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../db/database_helper.dart';
import '../models/loan.dart';
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

    if (!_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _amountFocus.requestFocus();
      });
    }
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
      // Build explicitly (not copyWith) so a null due date actually clears it.
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
    } else {
      final customerId = widget.customerId ??
          await _db.findOrCreateCustomer(
              _name.text.trim(), _phone.text.trim());
      await _db.insertLoan(Loan(
        customerId: customerId,
        reference: _reference.text.trim(),
        principal: double.parse(_principal.text.trim()),
        dateGiven: _dateGiven,
        dueDate: _dueDate,
        note: _note.text.trim(),
        reminderIntervalDays: _reminderDays,
      ));
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _pickDate(bool isDue) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isDue ? _dueDate : _dateGiven) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isDue) {
        _dueDate = picked;
        _dueDateError = false;
      } else {
        _dateGiven = picked;
      }
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
                decoration: const InputDecoration(prefixText: '$kCurrencySymbol  ', hintText: '0'),
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
                () => _pickDate(true),
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
            const SizedBox(height: 8),

            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
                title: const Text('More details',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: AppColors.pine)),
                children: [
                  if (!_isEditing)
                    _dateRow('Date given', _dateGiven, () => _pickDate(false)),
                  if (!_isEditing) const SizedBox(height: 16),
                  TextFormField(
                    controller: _note,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(hintText: 'Note (optional)'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
