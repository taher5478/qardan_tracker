import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/loan.dart';
import '../models/sms_template.dart';
import '../theme/app_theme.dart';
import '../ui/common.dart';
import 'edit_loan_screen.dart';
import 'loan_detail_screen.dart';
import 'activation_screen.dart';

/// Shows a customer's consolidated account: every credit they hold, the total
/// balance, and entry points to add credit or open an individual invoice.
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final int customerId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  final _db = DatabaseHelper.instance;
  final _df = DateFormat.yMMMd();

  Customer? _customer;
  List<Loan> _loans = const [];
  List<SmsTemplate> _templates = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final customer = await _db.getCustomer(widget.customerId);
    final loans = await _db.getLoansForCustomer(widget.customerId);
    final templates = await _db.getTemplates();
    if (!mounted) return;
    setState(() {
      _customer = customer;
      _loans = loans;
      _templates = templates;
      _loading = false;
    });
  }

  String get _currentTemplateName {
    final id = _customer?.templateId;
    if (id == null) return 'Default template';
    final match = _templates.where((t) => t.id == id);
    return match.isEmpty ? 'Default template' : match.first.name;
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
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Use default template'),
              selected: _customer?.templateId == null,
              onTap: () => Navigator.pop(ctx, 'default'),
            ),
            const Divider(height: 1),
            for (final t in _templates)
              ListTile(
                leading: const Icon(Icons.sms_outlined),
                title: Text(t.name),
                selected: _customer?.templateId == t.id,
                onTap: () => Navigator.pop(ctx, t.id),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    final c = _customer!;
    await _db.updateCustomer(chosen == 'default'
        ? c.copyWith(clearTemplate: true)
        : c.copyWith(templateId: chosen as int));
    _load();
  }

  // Archived accounts still owe money (archiving only stops reminders), so
  // their balance stays in the customer's total — matching the home screen.
  double get _totalOutstanding =>
      _loans.fold(0.0, (s, l) => s + l.outstanding);

  Future<void> _addCredit() async {
    if (!await requireActive(context)) return;
    if (!mounted) return;
    final c = _customer!;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditLoanScreen(
          customerId: c.id,
          initialName: c.name,
          initialPhone: c.phone,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openLoan(Loan loan) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: loan.id!)),
    );
    _load();
  }

  Future<void> _editCustomer() async {
    final c = _customer!;
    final nameCtrl = TextEditingController(text: c.name);
    final phoneCtrl = TextEditingController(text: c.phone);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final name = nameCtrl.text.trim();
          final phone = phoneCtrl.text.trim();
          final nameInvalid = name.isEmpty;
          // Reminders are sent by SMS, so a customer needs a usable number.
          final phoneInvalid = phone.length < 7;
          return AlertDialog(
            title: const Text('Edit customer'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 12),
                TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(
                        labelText: 'Phone',
                        errorText: phone.isNotEmpty && phoneInvalid
                            ? 'Enter a valid phone number'
                            : null)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: (nameInvalid || phoneInvalid)
                      ? null
                      : () => Navigator.pop(ctx, true),
                  child: const Text('Save')),
            ],
          );
        },
      ),
    );
    if (saved != true) return;
    await _db.updateCustomer(c.copyWith(
      name: nameCtrl.text.trim(),
      phone: phoneCtrl.text.trim(),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = _customer;
    return Scaffold(
      appBar: AppBar(
        title: Text(c?.name ?? 'Customer'),
        actions: [
          if (c != null)
            IconButton(
                onPressed: _editCustomer,
                icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      floatingActionButton: c == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addCredit,
              backgroundColor: AppColors.pine,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add credit',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : c == null
              ? const Center(child: Text('Customer not found'))
              : _content(c),
    );
  }

  Widget _content(Customer c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      children: [
        Column(
          children: [
            InitialAvatar(name: c.name, radius: 36),
            const SizedBox(height: 12),
            Text(c.name, style: Theme.of(context).textTheme.headlineSmall),
            Text(c.phone, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 18),
            Text('Total outstanding',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: AppColors.muted)),
            Text(money.format(_totalOutstanding),
                style: AppTheme.money(
                    size: 40,
                    color: _totalOutstanding <= 0
                        ? AppColors.success
                        : AppColors.brass)),
          ],
        ),
        const SizedBox(height: 20),
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            onTap: _pickTemplate,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sms_outlined, color: AppColors.pine),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Reminder template',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 12)),
                        Text(_currentTemplateName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.muted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Credit accounts',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_loans.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No credit accounts yet.',
                style: TextStyle(color: AppColors.muted)),
          )
        else
          ..._loans.map(_accountCard),
      ],
    );
  }

  Widget _accountCard(Loan loan) {
    final progress = loan.principal <= 0
        ? 0.0
        : (loan.amountPaid / loan.principal).clamp(0.0, 1.0);
    final settled = loan.isSettled || !loan.isActive;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: () => _openLoan(loan),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Opacity(
            opacity: settled ? 0.6 : 1,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loan.reference.trim().isEmpty
                                  ? 'Credit · ${_df.format(loan.dateGiven)}'
                                  : loan.reference.trim(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              settled
                                  ? 'Settled'
                                  : 'Outstanding ${money.format(loan.outstanding)}',
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Text(money.format(loan.principal),
                          style: AppTheme.money(size: 17)),
                    ],
                  ),
                  if (!settled && loan.amountPaid > 0) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: AppColors.sage,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.pine),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
