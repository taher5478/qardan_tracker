import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/loan.dart';

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

  bool get _isEditing => widget.loan != null;

  @override
  void initState() {
    super.initState();
    final l = widget.loan;
    _name = TextEditingController(
        text: l?.debtorName ?? widget.initialName ?? '');
    _phone = TextEditingController(
        text: l?.phoneNumber ?? widget.initialPhone ?? '');
    _principal =
        TextEditingController(text: l == null ? '' : l.principal.toStringAsFixed(0));
    _note = TextEditingController(text: l?.note ?? '');
    _dateGiven = l?.dateGiven ?? DateTime.now();
    _dueDate = l?.dueDate;
    _reminderDays = l?.reminderIntervalDays ?? 7;

    // Came from the contact picker with a name already set -> jump to amount.
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
    setState(() {
      if (isDue) {
        _dueDate = picked;
      } else {
        _dateGiven = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMd();
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Qardan' : 'Add Qardan')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Debtor name', border: OutlineInputBorder()),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Phone number (with country code)',
                  hintText: '+92300...',
                  border: OutlineInputBorder()),
              validator: (v) =>
                  (v == null || v.trim().length < 7) ? 'Enter a valid number' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _principal,
              focusNode: _amountFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Amount given', border: OutlineInputBorder()),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date given'),
              subtitle: Text(df.format(_dateGiven)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _pickDate(false),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Due date (optional)'),
              subtitle: Text(_dueDate == null ? 'Not set' : df.format(_dueDate!)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _pickDate(true),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _reminderDays,
              decoration: const InputDecoration(
                  labelText: 'Reminder SMS frequency',
                  border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Never')),
                DropdownMenuItem(value: 1, child: Text('Every day')),
                DropdownMenuItem(value: 3, child: Text('Every 3 days')),
                DropdownMenuItem(value: 7, child: Text('Every week')),
                DropdownMenuItem(value: 15, child: Text('Every 15 days')),
                DropdownMenuItem(value: 30, child: Text('Every month')),
              ],
              onChanged: (v) => setState(() => _reminderDays = v ?? 0),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Note (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
