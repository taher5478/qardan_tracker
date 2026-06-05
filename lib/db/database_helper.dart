import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/loan.dart';
import '../models/reminder_log.dart';

/// Singleton wrapper around the SQLite database.
///
/// IMPORTANT: this is also opened from the WorkManager background isolate,
/// so it must not depend on any Flutter UI state.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _dbName = 'qardan_tracker.db';
  static const _dbVersion = 2;
  static const table = 'loans';
  static const logTable = 'reminder_log';

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        debtorName TEXT NOT NULL,
        phoneNumber TEXT NOT NULL,
        principal REAL NOT NULL,
        amountPaid REAL NOT NULL DEFAULT 0,
        dateGiven INTEGER NOT NULL,
        dueDate INTEGER,
        note TEXT NOT NULL DEFAULT '',
        reminderIntervalDays INTEGER NOT NULL DEFAULT 7,
        lastReminderAt INTEGER,
        isActive INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await _createLogTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createLogTable(db);
    }
  }

  Future<void> _createLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE $logTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loanId INTEGER NOT NULL,
        debtorName TEXT NOT NULL,
        phoneNumber TEXT NOT NULL,
        amount REAL NOT NULL,
        sentAt INTEGER NOT NULL,
        success INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  Future<int> insertLoan(Loan loan) async {
    final db = await database;
    return db.insert(table, loan.toMap()..remove('id'));
  }

  Future<int> updateLoan(Loan loan) async {
    final db = await database;
    return db.update(
      table,
      loan.toMap(),
      where: 'id = ?',
      whereArgs: [loan.id],
    );
  }

  Future<int> deleteLoan(int id) async {
    final db = await database;
    return db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Loan>> getAllLoans() async {
    final db = await database;
    final rows = await db.query(table, orderBy: 'isActive DESC, dateGiven DESC');
    return rows.map(Loan.fromMap).toList();
  }

  Future<Loan?> getLoan(int id) async {
    final db = await database;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Loan.fromMap(rows.first);
  }

  /// Active loans with money still outstanding and a reminder interval set.
  Future<List<Loan>> getLoansNeedingReminders() async {
    final db = await database;
    final rows = await db.query(
      table,
      where:
          'isActive = 1 AND reminderIntervalDays > 0 AND (principal - amountPaid) > 0',
    );
    return rows.map(Loan.fromMap).toList();
  }

  /// Record that a reminder was just sent for [id].
  Future<void> markReminderSent(int id, int whenEpochMillis) async {
    final db = await database;
    await db.update(
      table,
      {'lastReminderAt': whenEpochMillis},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Reminder log ---------------------------------------------------------

  Future<int> insertReminderLog(ReminderLog log) async {
    final db = await database;
    return db.insert(logTable, log.toMap()..remove('id'));
  }

  Future<List<ReminderLog>> getReminderLogs() async {
    final db = await database;
    final rows = await db.query(logTable, orderBy: 'sentAt DESC');
    return rows.map(ReminderLog.fromMap).toList();
  }

  /// Total reminder SMS successfully sent.
  Future<int> countSentReminders() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM $logTable WHERE success = 1');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
