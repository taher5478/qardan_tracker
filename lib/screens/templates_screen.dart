import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/loan.dart';
import '../models/sms_template.dart';
import '../services/sms_service.dart';
import '../theme/app_theme.dart';

/// Sample loan used for live previews across the template editor.
Loan _sampleLoan() => Loan(
      customerId: 0,
      customerName: 'Ali Khan',
      customerPhone: '+920000000000',
      reference: 'INV-102',
      principal: 5000,
      amountPaid: 2000,
      dateGiven: DateTime.now().subtract(const Duration(days: 40)),
      dueDate: DateTime.now().subtract(const Duration(days: 5)),
    );

/// Library of reminder templates: view, add, edit, delete, set default.
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  final _db = DatabaseHelper.instance;
  late Future<List<SmsTemplate>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _future = _db.getTemplates());

  Future<void> _edit([SmsTemplate? t]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TemplateEditScreen(template: t)),
    );
    if (saved == true) _reload();
  }

  Future<void> _setDefault(SmsTemplate t) async {
    await _db.setDefaultTemplate(t.id!);
    _reload();
  }

  Future<void> _delete(SmsTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${t.name}"?'),
        content: const Text(
            'Customers using this template will fall back to the default.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _db.deleteTemplate(t.id!);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Message templates')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: AppColors.pine,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New template',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<List<SmsTemplate>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: list.length,
            itemBuilder: (_, i) => _templateCard(list[i]),
          );
        },
      ),
    );
  }

  Widget _templateCard(SmsTemplate t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Row(
              children: [
                Flexible(
                  child: Text(t.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (t.isDefault) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.sage,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Default',
                        style: TextStyle(
                            color: AppColors.pineDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'default') _setDefault(t);
                if (v == 'edit') _edit(t);
                if (v == 'delete') _delete(t);
              },
              itemBuilder: (_) => [
                if (!t.isDefault)
                  const PopupMenuItem(
                      value: 'default', child: Text('Set as default')),
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (!t.isDefault)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
            onTap: () => _edit(t),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              SmsService.render(_sampleLoan(), template: t.body),
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Create or edit a single template, with a live preview.
class TemplateEditScreen extends StatefulWidget {
  const TemplateEditScreen({super.key, this.template});
  final SmsTemplate? template;

  @override
  State<TemplateEditScreen> createState() => _TemplateEditScreenState();
}

class _TemplateEditScreenState extends State<TemplateEditScreen> {
  final _db = DatabaseHelper.instance;
  late final TextEditingController _name =
      TextEditingController(text: widget.template?.name ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.template?.body ?? '');

  bool get _isEditing => widget.template != null;

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final body = _body.text.trim();
    if (name.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name and message are required')));
      return;
    }
    if (_isEditing) {
      await _db.updateTemplate(
          widget.template!.copyWith(name: name, body: body));
    } else {
      await _db.insertTemplate(SmsTemplate(name: name, body: body));
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_isEditing ? 'Edit template' : 'New template')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _label('Template name'),
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: 'e.g. Friendly'),
          ),
          const SizedBox(height: 16),
          _label('Message'),
          TextField(
            controller: _body,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                hintText: 'Use placeholders like {amount}, {name}…'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Placeholders: {name} {fullname} {amount} {business} {reference} '
            '{due} {daysoverdue}',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.sage.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Preview',
                    style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  _body.text.trim().isEmpty
                      ? 'Your message preview appears here.'
                      : SmsService.render(_sampleLoan(), template: _body.text),
                  style: const TextStyle(height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(_isEditing ? 'Save changes' : 'Create template'),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                color: AppColors.muted, fontWeight: FontWeight.w600)),
      );
}
