import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/reminder_log.dart';

/// Full history of every reminder SMS the app attempted to send.
class ReminderLogScreen extends StatefulWidget {
  const ReminderLogScreen({super.key});

  @override
  State<ReminderLogScreen> createState() => _ReminderLogScreenState();
}

class _ReminderLogScreenState extends State<ReminderLogScreen> {
  final _db = DatabaseHelper.instance;
  late Future<List<ReminderLog>> _future;
  final _money = NumberFormat.currency(symbol: 'Rs ', decimalDigits: 0);
  final _dateFmt = DateFormat('d MMM yyyy, h:mm a');

  @override
  void initState() {
    super.initState();
    _future = _db.getReminderLogs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminder History')),
      body: FutureBuilder<List<ReminderLog>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final logs = snap.data!;
          if (logs.isEmpty) {
            return const Center(child: Text('No reminders sent yet.'));
          }
          return ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (_, i) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final log = logs[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      log.success ? Colors.green.shade100 : Colors.red.shade100,
                  child: Icon(
                    log.success ? Icons.check : Icons.error_outline,
                    color: log.success ? Colors.green : Colors.red,
                  ),
                ),
                title: Text(log.debtorName),
                subtitle: Text(
                    '${_dateFmt.format(log.sentAt)}\n${log.phoneNumber}'),
                isThreeLine: true,
                trailing: Text(
                  _money.format(log.amount),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
