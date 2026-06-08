import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/customer.dart';
import '../models/loan.dart';
import '../models/payment.dart';
import '../models/reminder_log.dart';

/// Single SQLite gateway. Also opened from the WorkManager background isolate,
/// so it must not depend on any Flutter UI state.
///
/// Schema v3 introduces a proper relational ledger:
///   customers 1───* loans 1───* payments
/// The outstanding balance is always DERIVED from payments (never overwritten),
/// and a loan's principal is locked after creation.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _dbName = 'qardan_tracker.db';
  static const _dbVersion = 3;

  static const customers = 'customers';
  static const loans = 'loans';
  static const payments = 'payments';
  static const logTable = 'reminder_log';

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, _dbName),
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  // --- Schema ---------------------------------------------------------------

  Future<void> _onCreate(Database db, int version) async {
    await _createCustomers(db);
    await _createLoans(db);
    await _createPayments(db);
    await _createLog(db);
  }

  Future<void> _createCustomers(DatabaseExecutor db) => db.execute('''
        CREATE TABLE $customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT NOT NULL,
          note TEXT NOT NULL DEFAULT '',
          createdAt INTEGER NOT NULL
        )''');

  Future<void> _createLoans(DatabaseExecutor db) => db.execute('''
        CREATE TABLE $loans (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerId INTEGER NOT NULL,
          reference TEXT NOT NULL DEFAULT '',
          principal REAL NOT NULL,
          dateGiven INTEGER NOT NULL,
          dueDate INTEGER,
          note TEXT NOT NULL DEFAULT '',
          reminderIntervalDays INTEGER NOT NULL DEFAULT 7,
          lastReminderAt INTEGER,
          isActive INTEGER NOT NULL DEFAULT 1,
          FOREIGN KEY (customerId) REFERENCES $customers(id) ON DELETE CASCADE
        )''');

  Future<void> _createPayments(DatabaseExecutor db) => db.execute('''
        CREATE TABLE $payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          loanId INTEGER NOT NULL,
          amount REAL NOT NULL,
          paidAt INTEGER NOT NULL,
          note TEXT NOT NULL DEFAULT '',
          FOREIGN KEY (loanId) REFERENCES $loans(id) ON DELETE CASCADE
        )''');

  Future<void> _createLog(DatabaseExecutor db) => db.execute('''
        CREATE TABLE $logTable (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          loanId INTEGER NOT NULL,
          debtorName TEXT NOT NULL,
          phoneNumber TEXT NOT NULL,
          amount REAL NOT NULL,
          sentAt INTEGER NOT NULL,
          success INTEGER NOT NULL DEFAULT 1
        )''');

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createLog(db);
    }
    if (oldVersion < 3) {
      await _migrateToRelational(db);
    }
  }

  /// Convert the flat v1/v2 `loans` table (debtorName/phone/amountPaid baked in)
  /// into the customers/loans/payments model without losing data.
  Future<void> _migrateToRelational(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('ALTER TABLE $loans RENAME TO loans_old');
      await _createCustomers(txn);
      await _createLoans(txn);
      await _createPayments(txn);

      final oldRows = await txn.query('loans_old');
      final customerIdByKey = <String, int>{}; // "name|phone" -> customerId

      for (final row in oldRows) {
        final name = (row['debtorName'] as String?)?.trim() ?? '';
        final phone = (row['phoneNumber'] as String?)?.trim() ?? '';
        final key = '$name|$phone';

        final customerId = customerIdByKey[key] ??= await txn.insert(customers, {
          'name': name,
          'phone': phone,
          'note': '',
          'createdAt': row['dateGiven'] ?? DateTime.now().millisecondsSinceEpoch,
        });

        final loanId = await txn.insert(loans, {
          'customerId': customerId,
          'reference': '',
          'principal': row['principal'],
          'dateGiven': row['dateGiven'],
          'dueDate': row['dueDate'],
          'note': row['note'] ?? '',
          'reminderIntervalDays': row['reminderIntervalDays'] ?? 7,
          'lastReminderAt': row['lastReminderAt'],
          'isActive': row['isActive'] ?? 1,
        });

        final paid = (row['amountPaid'] as num?)?.toDouble() ?? 0;
        if (paid > 0) {
          await txn.insert(payments, {
            'loanId': loanId,
            'amount': paid,
            'paidAt': row['dateGiven'] ?? DateTime.now().millisecondsSinceEpoch,
            'note': 'Imported balance',
          });
        }
      }

      await txn.execute('DROP TABLE loans_old');
    });
  }

  // --- Customers ------------------------------------------------------------

  Future<int> insertCustomer(Customer c) async {
    final db = await database;
    return db.insert(customers, c.toMap()..remove('id'));
  }

  Future<void> updateCustomer(Customer c) async {
    final db = await database;
    await db.update(customers, c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  Future<Customer?> getCustomer(int id) async {
    final db = await database;
    final rows = await db.query(customers, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<Customer?> findCustomerByPhone(String phone) async {
    final db = await database;
    final rows = await db
        .query(customers, where: 'phone = ?', whereArgs: [phone.trim()]);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  /// Find an existing customer by phone (or name if phone is blank), else create
  /// one. This is what powers consolidation: re-using a debtor merges accounts.
  Future<int> findOrCreateCustomer(String name, String phone) async {
    final trimmedPhone = phone.trim();
    if (trimmedPhone.isNotEmpty) {
      final existing = await findCustomerByPhone(trimmedPhone);
      if (existing != null) return existing.id!;
    }
    return insertCustomer(Customer(
      name: name.trim(),
      phone: trimmedPhone,
      createdAt: DateTime.now(),
    ));
  }

  /// All customers with aggregated balances, ready for the home screen.
  Future<List<CustomerSummary>> getCustomerSummaries() async {
    final all = await getAllLoans();
    final now = DateTime.now();
    final byCustomer = <int, List<Loan>>{};
    for (final l in all) {
      byCustomer.putIfAbsent(l.customerId, () => []).add(l);
    }

    final db = await database;
    final customerRows = await db.query(customers, orderBy: 'name COLLATE NOCASE');

    final result = <CustomerSummary>[];
    for (final row in customerRows) {
      final customer = Customer.fromMap(row);
      final list = byCustomer[customer.id] ?? const [];
      final outstanding =
          list.fold<double>(0, (s, l) => s + (l.isActive ? l.outstanding : 0));
      final given = list.fold<double>(0, (s, l) => s + l.principal);
      final open = list.where((l) => l.isActive && !l.isSettled).length;
      final due = list.where((l) => l.isReminderDue(now)).length;
      result.add(CustomerSummary(
        customer: customer,
        totalOutstanding: outstanding,
        totalGiven: given,
        openAccounts: open,
        dueNow: due,
      ));
    }
    return result;
  }

  // --- Loans (credit accounts) ---------------------------------------------

  /// Selects all loan columns plus the derived paid sum and the customer's
  /// name/phone. Used everywhere a loan is read for display.
  static const _loanSelect = '''
      SELECT l.*, c.name AS customerName, c.phone AS customerPhone,
        IFNULL((SELECT SUM(p.amount) FROM payments p WHERE p.loanId = l.id), 0)
          AS amountPaid
      FROM loans l JOIN customers c ON c.id = l.customerId''';

  Future<List<Loan>> getAllLoans() async {
    final db = await database;
    final rows = await db.rawQuery(
        '$_loanSelect ORDER BY l.isActive DESC, l.dateGiven DESC');
    return rows.map(Loan.fromMap).toList();
  }

  Future<List<Loan>> getLoansForCustomer(int customerId) async {
    final db = await database;
    final rows = await db.rawQuery(
        '$_loanSelect WHERE l.customerId = ? ORDER BY l.dateGiven DESC',
        [customerId]);
    return rows.map(Loan.fromMap).toList();
  }

  Future<Loan?> getLoan(int id) async {
    final db = await database;
    final rows = await db.rawQuery('$_loanSelect WHERE l.id = ?', [id]);
    return rows.isEmpty ? null : Loan.fromMap(rows.first);
  }

  Future<int> insertLoan(Loan loan) async {
    final db = await database;
    return db.insert(loans, loan.toMap()..remove('id'));
  }

  /// Updates only mutable terms — NEVER the principal, so the original invoice
  /// amount stays locked and the ledger math is protected.
  Future<void> updateLoanTerms(Loan loan) async {
    final db = await database;
    await db.update(
      loans,
      {
        'reference': loan.reference,
        'dueDate': loan.dueDate?.millisecondsSinceEpoch,
        'note': loan.note,
        'reminderIntervalDays': loan.reminderIntervalDays,
        'isActive': loan.isActive ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [loan.id],
    );
  }

  Future<void> deleteLoan(int id) async {
    final db = await database;
    await db.delete(loans, where: 'id = ?', whereArgs: [id]);
  }

  /// Active, unsettled loans whose reminder interval is set. The actual
  /// "is it due right now" decision uses [Loan.isReminderDue].
  Future<List<Loan>> getLoansNeedingReminders() async {
    final db = await database;
    final rows = await db.rawQuery('$_loanSelect '
        'WHERE l.isActive = 1 AND l.reminderIntervalDays > 0 '
        'AND (l.principal - amountPaid) > 0');
    return rows.map(Loan.fromMap).toList();
  }

  Future<void> markReminderSent(int loanId, int whenEpochMillis) async {
    final db = await database;
    await db.update(loans, {'lastReminderAt': whenEpochMillis},
        where: 'id = ?', whereArgs: [loanId]);
  }

  // --- Payments (audit trail) ----------------------------------------------

  Future<int> insertPayment(Payment p) async {
    final db = await database;
    return db.insert(payments, p.toMap()..remove('id'));
  }

  Future<void> deletePayment(int id) async {
    final db = await database;
    await db.delete(payments, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Payment>> getPaymentsForLoan(int loanId) async {
    final db = await database;
    final rows = await db.query(payments,
        where: 'loanId = ?', whereArgs: [loanId], orderBy: 'paidAt DESC');
    return rows.map(Payment.fromMap).toList();
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

  Future<int> countSentReminders() async {
    final db = await database;
    final result = await db
        .rawQuery('SELECT COUNT(*) AS c FROM $logTable WHERE success = 1');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // --- Backup / restore -----------------------------------------------------

  /// Raw dump of every table, for JSON backup.
  Future<Map<String, List<Map<String, Object?>>>> dumpAll() async {
    final db = await database;
    return {
      customers: await db.query(customers),
      loans: await db.query(loans),
      payments: await db.query(payments),
      logTable: await db.query(logTable),
    };
  }

  /// Replace all data with a previously dumped backup. Ids are preserved so the
  /// customer/loan/payment relationships stay intact.
  Future<void> restoreAll(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      // Delete children first to satisfy foreign keys.
      await txn.delete(logTable);
      await txn.delete(payments);
      await txn.delete(loans);
      await txn.delete(customers);

      Future<void> insertAll(String table) async {
        for (final row in (data[table] as List? ?? const [])) {
          await txn.insert(table, Map<String, Object?>.from(row as Map));
        }
      }

      await insertAll(customers);
      await insertAll(loans);
      await insertAll(payments);
      await insertAll(logTable);
    });
  }
}
