import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The on-phone SQLite database. Nothing here talks to the network.
class FundsDb {
  FundsDb._(this.db);

  final Database db;

  static const tables = [
    'accounts', 'entries', 'plans', 'goals', 'budgets', 'settings', 'people', 'loans', 'fds',
  ];

  static const _fdsTable = '''
    CREATE TABLE fds (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      principal INTEGER NOT NULL,
      rate REAL NOT NULL,
      compounding TEXT NOT NULL DEFAULT 'quarterly',
      start_date TEXT NOT NULL,
      maturity_date TEXT NOT NULL,
      account_id INTEGER,
      closed INTEGER NOT NULL DEFAULT 0,
      closed_date TEXT,
      closed_amount INTEGER,
      closed_how TEXT,
      renewed_from INTEGER,
      renewed_to INTEGER,
      created_at INTEGER NOT NULL
    )''';

  static const _peopleTable = '''
    CREATE TABLE people (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )''';

  static const _loansTable = '''
    CREATE TABLE loans (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      person_id INTEGER NOT NULL,
      direction TEXT NOT NULL,
      rate REAL NOT NULL DEFAULT 0,
      rate_period TEXT NOT NULL DEFAULT 'month',
      due_date TEXT,
      note TEXT NOT NULL DEFAULT '',
      settled INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''';

  static Future<FundsDb> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'funds.db'),
      version: 4,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // v2: accounts can be left out of the total balance.
          await db.execute(
              'ALTER TABLE accounts ADD COLUMN counted INTEGER NOT NULL DEFAULT 1');
        }
        if (oldVersion < 3) {
          // v3: lend & borrow.
          await db.execute(_peopleTable);
          await db.execute(_loansTable);
          await db.execute('ALTER TABLE entries ADD COLUMN loan_id INTEGER');
        }
        if (oldVersion < 4) {
          // v4: fixed deposits.
          await db.execute(_fdsTable);
          await db.execute('ALTER TABLE entries ADD COLUMN fd_id INTEGER');
        }
      },
      onCreate: (db, version) async {
        final b = db.batch();
        b.execute('''
          CREATE TABLE accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            opening INTEGER NOT NULL DEFAULT 0,
            credit_limit INTEGER,
            due_day INTEGER,
            sort INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            counted INTEGER NOT NULL DEFAULT 1
          )''');
        b.execute('''
          CREATE TABLE entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            amount INTEGER NOT NULL,
            account_id INTEGER NOT NULL,
            to_account_id INTEGER,
            category TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            date TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            plan_id INTEGER,
            loan_id INTEGER,
            fd_id INTEGER
          )''');
        b.execute(_peopleTable);
        b.execute(_loansTable);
        b.execute(_fdsTable);
        b.execute('CREATE INDEX entries_date ON entries(date)');
        b.execute('CREATE INDEX entries_account ON entries(account_id)');
        b.execute('''
          CREATE TABLE plans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            name TEXT NOT NULL,
            amount INTEGER NOT NULL,
            day INTEGER NOT NULL,
            account_id INTEGER NOT NULL,
            start_month TEXT NOT NULL,
            last_posted TEXT,
            tenure INTEGER,
            active INTEGER NOT NULL DEFAULT 1,
            category TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )''');
        b.execute('''
          CREATE TABLE goals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            target INTEGER NOT NULL,
            saved INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )''');
        b.execute('''
          CREATE TABLE budgets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL UNIQUE,
            amount INTEGER NOT NULL
          )''');
        b.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )''');
        await b.commit(noResult: true);
      },
    );
    return FundsDb._(db);
  }

  /// Every table's rows, for backups.
  Future<Map<String, List<Map<String, Object?>>>> dump() async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in tables) {
      out[t] = await db.query(t);
    }
    return out;
  }

  /// Replaces all data with [data] in one transaction (all or nothing).
  Future<void> restore(Map<String, List<Map<String, Object?>>> data) async {
    await db.transaction((txn) async {
      for (final t in tables) {
        await txn.delete(t);
      }
      final b = txn.batch();
      for (final t in tables) {
        for (final row in data[t] ?? const <Map<String, Object?>>[]) {
          b.insert(t, row);
        }
      }
      await b.commit(noResult: true);
    });
  }
}
