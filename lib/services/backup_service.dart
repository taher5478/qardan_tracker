import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/loan.dart';

/// Local data-portability: CSV export and JSON backup/restore. No cloud, no
/// account — the owner shares the file wherever they like (Drive, email, etc.).
class BackupService {
  final _db = DatabaseHelper.instance;

  static const _backupVersion = 1;

  /// Build a human-readable ledger CSV (one row per credit account) and open
  /// the system share sheet so the owner can save/send it.
  Future<void> exportLedgerCsv() async {
    final loans = await _db.getAllLoans();
    final df = DateFormat('yyyy-MM-dd');

    final rows = <List<dynamic>>[
      [
        'Customer',
        'Phone',
        'Reference',
        'Principal',
        'Paid',
        'Outstanding',
        'Date given',
        'Due date',
        'Status',
      ],
      ...loans.map((l) => [
            l.customerName,
            l.customerPhone,
            l.reference,
            l.principal.toStringAsFixed(2),
            l.amountPaid.toStringAsFixed(2),
            l.outstanding.toStringAsFixed(2),
            df.format(l.dateGiven),
            l.dueDate == null ? '' : df.format(l.dueDate!),
            _status(l),
          ]),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final path = await _writeTemp('ledger_${_stamp()}.csv', csv);
    await Share.shareXFiles([XFile(path)], text: 'Qarzan ledger export');
  }

  /// Build the full backup as a JSON string (shared by file export and the
  /// Google Drive uploader).
  Future<String> buildBackupJson() async {
    final dump = await _db.dumpAll();
    final payload = {
      'app': 'qarzan_tracker',
      'backupVersion': _backupVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'tables': dump,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Suggested backup file name with a timestamp.
  String backupFileName() => 'oweme_backup_${_stamp()}.json';

  /// Write a full JSON backup of all tables and share it.
  Future<void> backupToJson() async {
    final json = await buildBackupJson();
    final path = await _writeTemp(backupFileName(), json);
    await Share.shareXFiles([XFile(path)], text: 'OweMe full backup');
  }

  /// Let the owner pick a previously made backup and restore it. Returns a
  /// human-readable result message; throws nothing the UI must catch.
  Future<String> restoreFromJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return 'Restore cancelled';

    final file = result.files.first;
    final content = file.bytes != null
        ? utf8.decode(file.bytes!)
        : await File(file.path!).readAsString();

    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return 'That file is not a valid backup';
    }
    if (payload['app'] != 'qarzan_tracker' || payload['tables'] == null) {
      return 'That file is not a Qarzan backup';
    }

    await _db.restoreAll(payload['tables'] as Map<String, dynamic>);
    return 'Backup restored successfully';
  }

  // --- helpers --------------------------------------------------------------

  String _status(Loan l) {
    if (!l.isActive) return 'Archived';
    if (l.isSettled) return 'Settled';
    return 'Open';
  }

  String _stamp() => DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  Future<String> _writeTemp(String name, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(content);
    return file.path;
  }
}
