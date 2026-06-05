import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/reminder_log.dart';
import '../theme/app_theme.dart';
import '../ui/common.dart';

/// Full history of every reminder SMS the app attempted to send.
class ReminderLogScreen extends StatefulWidget {
  const ReminderLogScreen({super.key});

  @override
  State<ReminderLogScreen> createState() => _ReminderLogScreenState();
}

class _ReminderLogScreenState extends State<ReminderLogScreen> {
  final _db = DatabaseHelper.instance;
  late Future<List<ReminderLog>> _future;
  final _dateFmt = DateFormat('d MMM yyyy · h:mm a');

  @override
  void initState() {
    super.initState();
    _future = _db.getReminderLogs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminder history')),
      body: FutureBuilder<List<ReminderLog>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final logs = snap.data!;
          if (logs.isEmpty) return const _EmptyHistory();
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: logs.length,
            separatorBuilder: (_, i) =>
                const Divider(height: 1, indent: 76, color: AppColors.hairline),
            itemBuilder: (_, i) => _LogTile(log: logs[i], dateFmt: _dateFmt),
          );
        },
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log, required this.dateFmt});
  final ReminderLog log;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Stack(
        children: [
          InitialAvatar(name: log.debtorName, radius: 24),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                  color: AppColors.surface, shape: BoxShape.circle),
              child: Icon(
                log.success ? Icons.check_circle : Icons.cancel,
                size: 16,
                color: log.success ? AppColors.success : AppColors.danger,
              ),
            ),
          ),
        ],
      ),
      title: Text(log.debtorName,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        '${log.success ? 'Sent' : 'Failed'} · ${dateFmt.format(log.sentAt)}',
        style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
      ),
      trailing: Text(money.format(log.amount),
          style: AppTheme.money(size: 16, color: AppColors.brass)),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                  color: AppColors.sage, shape: BoxShape.circle),
              child: const Icon(Icons.mark_chat_read_outlined,
                  size: 40, color: AppColors.pine),
            ),
            const SizedBox(height: 20),
            Text('No reminders sent yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'Reminder SMS sent automatically or manually\nwill appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
