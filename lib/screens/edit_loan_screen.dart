import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/loan.dart';
import '../theme/app_theme.dart';
import '../ui/common.dart';

/// Create or edit a qardan record.
///
/// When adding, [initialName]/[initialPhone] can be supplied from the contact
/// picker so the form opens pre-filled and focused on the amount field.
class EditLoanScreen extends StatefulWidget {
  const EditLoanScreen({
    super.key,
    this.loan,
    this.initialName,
    this.initialPhone,
  });
  final Loan? loan;
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
  late TextEditingController _note;

  late DateTime _dateGiven;
  DateTime? _dueDate;
  late int _reminderDays;

  final _amountFocus = FocusNode();

  /// Reminder cadence presets shown as chips (label -> days).
  static const _cadence = {
    'Off': 0,
    'Daily': 1,
    '3 days': 3,
    'Weekly': 7,
    'Bi-weekly': 15,
    'Monthly': 30,
  };

  bool get _isEditing => widget.loan != null;

  @override
  void initState() {
    super.initState();
    final l = widget.loan;
    _name = TextEditingController(
        text: l?.debtorName ?? widget.initialName ?? '');
    _phone = TextEditingController(
        text: l?.phoneNumber ?? widget.initialPhone ?? '');
    _principal = TextEditingController(
        text: l == null ? '' : l.principal.toStringAsFixed(0));
    _note = TextEditingController(text: l?.note ?? '');
    _dateGiven = l?.dateGiven ?? DateTime.now();
    _dueDate = l?.dueDate;
    _reminderDays = l?.reminderIntervalDays ?? 7;

    if (!_isEditing && (widget.initialName?.isNotEmpty ?? false)) {
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
    _note.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final loan = (widget.loan ??
            Loan(
              debtorName: '',
              phoneNumber: '',
              principal: 0,
              dateGiven: _dateGiven,
            ))
        .copyWith(
      debtorName: _name.text.trim(),
      phoneNumber: _phone.text.trim(),
      principal: double.parse(_principal.text.trim()),
      dateGiven: _dateGiven,
      dueDate: _dueDate,
      note: _note.text.trim(),
      reminderIntervalDays: _reminderDays,
    );

    if (_isEditing) {
      await _db.updateLoan(loan);
    } else {
      await _db.insertLoan(loan);
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
    setState(() => isDue ? _dueDate = picked : _dateGiven = picked);
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit qardan' : 'New qardan')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // Person header — confirms who this qardan is for.
            Row(
              children: [
                InitialAvatar(name: name.isEmpty ? '?' : name, radius: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? 'New person' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall),
                      Text(_phone.text.trim().isEmpty
                          ? 'No number yet'
                          : _phone.text.trim(),
                          style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _label('Amount given'),
            TextFormField(
              controller: _principal,
              focusNode: _amountFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: AppTheme.money(size: 26, color: AppColors.ink),
              decoration: const InputDecoration(
                prefixText: 'Rs  ',
                hintText: '0',
              ),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 20),

            _label('Name'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Debtor’s name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            _label('Phone number'),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  hintText: '+92 300 1234567', prefixIcon: Icon(Icons.phone)),
              validator: (v) => (v == null || v.trim().length < 7)
                  ? 'Enter a valid number'
                  : null,
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
                  onSelected: (_) => setState(() => _reminderDays = e.value),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  selectedColor: AppColors.pine,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(
                      color: selected ? AppColors.pine : AppColors.hairline),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),

            // Progressive disclosure: rarely-changed fields stay folded away.
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
                title: const Text('More details',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: AppColors.pine)),
                children: [
                  _dateRow('Date given', _dateGiven, () => _pickDate(false)),
                  const SizedBox(height: 8),
                  _dateRow('Due date (optional)', _dueDate, () => _pickDate(true)),
                  const SizedBox(height: 16),
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
              label: Text(_isEditing ? 'Save changes' : 'Save qardan'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.muted, fontWeight: FontWeight.w600)),
      );

  Widget _dateRow(String label, DateTime? date, VoidCallback onTap) {
    final df = DateFormat.yMMMd();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 18, color: AppColors.muted),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: AppColors.muted)),
            const Spacer(),
            Text(date == null ? 'Not set' : df.format(date),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
