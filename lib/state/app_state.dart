import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../data/db.dart';
import '../data/deposits.dart';
import '../data/lending.dart';
import '../data/models.dart';
import '../data/recurring.dart';
import '../utils/format.dart';

/// Upcoming money movement shown under "Coming up".
class Upcoming {
  final String title;
  final String subtitle;
  final DateTime date;
  final int amount; // signed: + comes in, − goes out
  final PlanKind? kind;
  final bool isCardDue;

  const Upcoming({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.amount,
    this.kind,
    this.isCardDue = false,
  });
}

/// One piece of net worth, e.g. "Bank accounts ₹2,48,600". Negative
/// amounts are owed.
class WorthPart {
  /// bank, cash, wallet, card, fd, lent or borrowed.
  final String kind;
  final String label;
  final String subtitle;
  final int amount;

  const WorthPart(this.kind, this.label, this.subtitle, this.amount);
}

/// Holds all data in memory (a personal ledger is small) and writes every
/// change straight to the on-phone database.
class AppState extends ChangeNotifier {
  AppState(this._db);

  final FundsDb _db;

  List<Account> accounts = [];
  List<Entry> entries = []; // newest first
  List<Plan> plans = [];
  List<Goal> goals = [];
  List<Budget> budgets = [];
  List<Person> people = [];
  List<Loan> loans = [];
  List<Fd> fds = [];
  List<Tag> tags = [];
  List<MutualFund> funds = [];
  Map<int, List<Entry>> _fundEntries = {};
  Map<int, Set<int>> _entryTags = {};
  Map<int, List<Entry>> _tagEntries = {};
  Map<int, List<Entry>> _loanEntries = {};
  Map<String, String> _settings = {};
  Map<int, int> _balances = {};

  /// Amounts hidden on screen for this session (eye button).
  bool amountsHidden = false;

  /// True while the share sheet / file picker is open, so leaving the app
  /// for them does not trigger the app lock.
  bool externalActivity = false;

  static Future<AppState> create() async {
    final s = AppState(await FundsDb.open());
    await s._load();
    await s._convertOldSips();
    s.amountsHidden = s.hideAmountsByDefault;
    await s.postDuePlans();
    return s;
  }

  // ------------------------------------------------------------- loading

  Future<void> _load() async {
    final db = _db.db;
    accounts = (await db.query('accounts', orderBy: 'sort, id'))
        .map(Account.fromMap)
        .toList();
    entries = (await db.query('entries', orderBy: 'date DESC, created_at DESC, id DESC'))
        .map(Entry.fromMap)
        .toList();
    plans = (await db.query('plans', orderBy: 'day, id')).map(Plan.fromMap).toList();
    goals = (await db.query('goals', orderBy: 'id')).map(Goal.fromMap).toList();
    budgets = (await db.query('budgets', orderBy: 'id')).map(Budget.fromMap).toList();
    people = (await db.query('people', orderBy: 'name COLLATE NOCASE'))
        .map(Person.fromMap)
        .toList();
    loans = (await db.query('loans', orderBy: 'id')).map(Loan.fromMap).toList();
    fds = (await db.query('fds', orderBy: 'maturity_date, id')).map(Fd.fromMap).toList();
    funds = (await db.query('funds', orderBy: 'id')).map(MutualFund.fromMap).toList();
    // Links to entries that were deleted (with their account, person...).
    await db.execute(
        'DELETE FROM entry_tags WHERE entry_id NOT IN (SELECT id FROM entries) '
        'OR tag_id NOT IN (SELECT id FROM tags)');
    tags = (await db.query('tags', orderBy: 'id DESC')).map(Tag.fromMap).toList();
    final links = <int, Set<int>>{};
    for (final r in await db.query('entry_tags')) {
      links.putIfAbsent(r['entry_id'] as int, () => {}).add(r['tag_id'] as int);
    }
    _entryTags = links;
    _settings = {
      for (final r in await db.query('settings')) r['key'] as String: r['value'] as String,
    };
    _recompute();
  }

  void _recompute() {
    final b = <int, int>{for (final a in accounts) a.id!: a.opening};
    for (final e in entries) {
      if (b.containsKey(e.accountId)) {
        b[e.accountId] = b[e.accountId]! + e.effectOn(e.accountId);
      }
      final to = e.toAccountId;
      if (to != null && b.containsKey(to)) {
        b[to] = b[to]! + e.effectOn(to);
      }
    }
    _balances = b;

    final byLoan = <int, List<Entry>>{};
    for (final e in entries) {
      final id = e.loanId;
      if (id != null) byLoan.putIfAbsent(id, () => []).add(e);
    }
    _loanEntries = byLoan;

    final byTag = <int, List<Entry>>{};
    for (final e in entries) {
      for (final t in _entryTags[e.id] ?? const <int>{}) {
        byTag.putIfAbsent(t, () => []).add(e);
      }
    }
    _tagEntries = byTag;

    final byFund = <int, List<Entry>>{};
    for (final e in entries) {
      final id = e.fundId;
      if (id != null) byFund.putIfAbsent(id, () => []).add(e);
    }
    _fundEntries = byFund;
  }

  Future<void> _reload() async {
    await _load();
    notifyListeners();
  }

  // ------------------------------------------------------------ settings

  String? setting(String key) => _settings[key];

  bool _flag(String key, bool fallback) {
    final v = _settings[key];
    return v == null ? fallback : v == '1';
  }

  bool feature(String key) => _flag(key, true);

  bool get appLock => _flag('app_lock', false);
  bool get hideAmountsByDefault => _flag('hide_amounts', false);
  int get lockAfterSeconds => int.tryParse(_settings['lock_after'] ?? '') ?? 60;
  int? get lastAccountId => int.tryParse(_settings['last_account'] ?? '');

  DateTime? get lastBackup {
    final v = int.tryParse(_settings['last_backup'] ?? '');
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  // ------------------------------------------------- automatic backup

  bool get autoBackup => _flag('auto_backup', true);

  /// 'daily', 'weekly' or 'monthly'.
  String get autoBackupFrequency => _settings['auto_backup_freq'] ?? 'weekly';

  int get autoBackupDays => switch (autoBackupFrequency) {
        'daily' => 1,
        'monthly' => 30,
        _ => 7,
      };

  /// Password for protected backups, or null. Stays on this phone only.
  String? get backupPassword {
    final v = _settings['backup_password'];
    return v == null || v.isEmpty ? null : v;
  }

  DateTime? get lastAutoBackup {
    final v = int.tryParse(_settings['last_auto_backup'] ?? '');
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  String? get autoBackupError {
    final v = _settings['auto_backup_error'];
    return v == null || v.isEmpty ? null : v;
  }

  bool get autoBackupDue {
    final last = lastAutoBackup;
    if (last == null) return true;
    return today().difference(dateOnly(last)).inDays >= autoBackupDays;
  }

  Future<void> setBackupPassword(String? password) =>
      setSetting('backup_password', password ?? '');

  // -------------------------------------------------------- reminders

  bool get remindersOn => _flag('reminders_on', true);

  /// One kind of reminder: bills, salary, card, lend, fd, budget, daily.
  bool reminderOn(String kind) => _flag('rem_$kind', true);

  /// Minutes after midnight for date reminders (default 9:00 AM).
  int get reminderTime => int.tryParse(_settings['rem_time'] ?? '') ?? 9 * 60;

  /// Minutes after midnight for the evening reminder (default 9:00 PM).
  int get dailyReminderTime => int.tryParse(_settings['rem_daily_time'] ?? '') ?? 21 * 60;

  bool get reminderAmounts => _flag('rem_amounts', false);

  Future<void> setSetting(String key, String value) async {
    await _db.db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: _replace);
    _settings[key] = value;
    notifyListeners();
  }

  Future<void> setFlag(String key, bool value) => setSetting(key, value ? '1' : '0');

  Future<void> setFeature(String key, bool on) async {
    await setFlag(key, on);
    // Plans that were hidden may have dates to catch up on.
    if (on) await postDuePlans();
  }

  void toggleHidden() {
    amountsHidden = !amountsHidden;
    notifyListeners();
  }

  // ------------------------------------------------------------ accounts

  Account? account(int? id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  String accountName(int? id) => account(id)?.name ?? 'Deleted account';

  int balanceOf(int id) => _balances[id] ?? 0;

  /// Accounts the user sees (credit cards hidden when that feature is off).
  List<Account> get visibleAccounts =>
      accounts.where((a) => !a.isCard || feature(Features.cards)).toList();

  /// Visible accounts that count in the user's own balance.
  List<Account> get countedAccounts => visibleAccounts.where((a) => a.counted).toList();

  /// The user's own money: family or company accounts are left out.
  int get totalBalance =>
      countedAccounts.fold(0, (sum, a) => sum + balanceOf(a.id!));

  /// Money in accounts that are not the user's own.
  int get notCountedBalance => visibleAccounts
      .where((a) => !a.counted)
      .fold(0, (sum, a) => sum + balanceOf(a.id!));

  /// Whether an income or expense counts towards totals and budgets (its
  /// account is the user's own). Unknown accounts count.
  bool countsEntry(Entry e) => account(e.accountId)?.counted ?? true;

  Future<int> saveAccount(Account a) async {
    final map = a.toMap();
    int id;
    if (a.id == null) {
      map.remove('id');
      map['sort'] = accounts.length;
      id = await _db.db.insert('accounts', map);
    } else {
      id = a.id!;
      await _db.db.update('accounts', map, where: 'id = ?', whereArgs: [id]);
    }
    await _reload();
    return id;
  }

  int entryCountFor(int accountId) => entries
      .where((e) => e.accountId == accountId || e.toAccountId == accountId)
      .length;

  /// Deletes the account, its entries and the plans that use it.
  Future<void> deleteAccount(int id) async {
    await _db.db.transaction((txn) async {
      await txn.delete('entries',
          where: 'account_id = ? OR to_account_id = ?', whereArgs: [id, id]);
      await txn.delete('plans', where: 'account_id = ?', whereArgs: [id]);
      await txn.delete('accounts', where: 'id = ?', whereArgs: [id]);
    });
    await _reload();
  }

  // ------------------------------------------------------------- entries

  /// Saves an entry. When [tagIds] is given, the entry gets exactly those
  /// tags.
  Future<void> saveEntry(Entry e, {Set<int>? tagIds}) async {
    final map = e.toMap();
    await _db.db.transaction((txn) async {
      int id;
      if (e.id == null) {
        map.remove('id');
        id = await txn.insert('entries', map);
      } else {
        id = e.id!;
        await txn.update('entries', map, where: 'id = ?', whereArgs: [id]);
      }
      if (tagIds != null) {
        await txn.delete('entry_tags', where: 'entry_id = ?', whereArgs: [id]);
        for (final t in tagIds) {
          await txn.insert('entry_tags', {'entry_id': id, 'tag_id': t},
              conflictAlgorithm: _replace);
        }
      }
      await txn.insert('settings', {'key': 'last_account', 'value': '${e.accountId}'},
          conflictAlgorithm: _replace);
    });
    await _reload();
  }

  Future<void> deleteEntry(int id) async {
    await _db.db.transaction((txn) async {
      await txn.delete('entry_tags', where: 'entry_id = ?', whereArgs: [id]);
      await txn.delete('entries', where: 'id = ?', whereArgs: [id]);
    });
    await _reload();
  }

  List<Entry> entriesFor(int accountId) => entries
      .where((e) => e.accountId == accountId || e.toAccountId == accountId)
      .toList();

  bool _inMonth(DateTime d, DateTime m) => d.year == m.year && d.month == m.month;

  int incomeInMonth(DateTime month) => entries
      .where((e) => e.type == EntryType.income && _inMonth(e.date, month) && countsEntry(e))
      .fold(0, (s, e) => s + e.amount);

  int expenseInMonth(DateTime month) => entries
      .where((e) => e.type == EntryType.expense && _inMonth(e.date, month) && countsEntry(e))
      .fold(0, (s, e) => s + e.amount);

  int spentInCategory(String category, DateTime month) => entries
      .where((e) =>
          e.type == EntryType.expense &&
          e.category == category &&
          _inMonth(e.date, month) &&
          countsEntry(e))
      .fold(0, (s, e) => s + e.amount);

  // --------------------------------------------------------------- plans

  bool planVisible(Plan p) => feature(p.kind.feature);

  List<Plan> plansOf(PlanKind k) => plans.where((p) => p.kind == k).toList();

  /// Monthly totals of active, visible plans.
  /// Whether a plan's account is the user's own.
  bool planCounted(Plan p) => account(p.accountId)?.counted ?? true;

  int get monthlyIn => plans
      .where((p) =>
          p.active && planVisible(p) && planCounted(p) && p.kind.isIncome && !isFinished(p))
      .fold(0, (s, p) => s + p.amount);

  int get monthlyOut => plans
      .where((p) =>
          p.active && planVisible(p) && planCounted(p) && !p.kind.isIncome && !isFinished(p))
      .fold(0, (s, p) => s + p.amount);



  Future<void> savePlan(Plan p) async {
    final map = p.toMap();
    if (p.id == null) {
      map.remove('id');
      await _db.db.insert('plans', map);
    } else {
      await _db.db.update('plans', map, where: 'id = ?', whereArgs: [p.id]);
    }
    await _load();
    await postDuePlans(notify: false);
    notifyListeners();
  }

  Future<void> deletePlan(int id) async {
    await _db.db.delete('plans', where: 'id = ?', whereArgs: [id]);
    await _reload();
  }

  /// Adds the entries for every plan whose date has come. Called when the
  /// app starts and whenever it comes back to the foreground.
  Future<void> postDuePlans({bool notify = true}) async {
    final now = DateTime.now();
    var changed = false;
    await _db.db.transaction((txn) async {
      for (final p in plans) {
        if (!planVisible(p) || account(p.accountId) == null) continue;
        final months = dueMonths(p, now);
        if (months.isEmpty) continue;
        // A SIP moves money into its fund; without a fund it waits.
        final sip = p.kind == PlanKind.sip;
        if (sip && fund(p.fundId) == null) continue;
        for (final m in months) {
          final entry = Entry(
            type: sip
                ? EntryType.investOut
                : (p.kind.isIncome ? EntryType.income : EntryType.expense),
            amount: p.amount,
            accountId: p.accountId,
            category: sip ? 'fund' : planCategory(p),
            note: sip ? '' : p.name,
            date: dueDateIn(m.year, m.month, p.day),
            createdAt: now.millisecondsSinceEpoch,
            planId: p.id,
            fundId: sip ? p.fundId : null,
          ).toMap()
            ..remove('id');
          await txn.insert('entries', entry);
        }
        await txn.update('plans', {'last_posted': monthKey(months.last)},
            where: 'id = ?', whereArgs: [p.id]);
        changed = true;
      }
    });
    if (changed) {
      await _load();
      if (notify) notifyListeners();
    }
  }

  /// Plans and credit card dues in the next [days] days, soonest first.
  List<Upcoming> upcoming({int days = 10}) {
    final t = today();
    final limit = t.add(Duration(days: days));
    final out = <Upcoming>[];
    for (final p in plans) {
      if (!planVisible(p)) continue;
      final d = nextDueDate(p);
      if (d == null || d.isAfter(limit) || d.isBefore(t)) continue;
      out.add(Upcoming(
        title: p.name,
        subtitle: accountName(p.accountId),
        date: d,
        amount: p.kind.isIncome ? p.amount : -p.amount,
        kind: p.kind,
      ));
    }
    if (feature(Features.cards)) {
      for (final a in accounts.where((a) => a.isCard && a.dueDay != null)) {
        final owed = -balanceOf(a.id!);
        if (owed <= 0) continue;
        var d = dueDateIn(t.year, t.month, a.dueDay!);
        if (d.isBefore(t)) {
          final n = addMonths(DateTime(t.year, t.month), 1);
          d = dueDateIn(n.year, n.month, a.dueDay!);
        }
        if (d.isAfter(limit)) continue;
        out.add(Upcoming(
          title: '${a.name} bill',
          subtitle: 'Credit card due',
          date: d,
          amount: -owed,
          isCardDue: true,
        ));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  // --------------------------------------------------------------- goals

  Future<void> saveGoal(Goal g) async {
    final map = g.toMap();
    if (g.id == null) {
      map.remove('id');
      await _db.db.insert('goals', map);
    } else {
      await _db.db.update('goals', map, where: 'id = ?', whereArgs: [g.id]);
    }
    await _reload();
  }

  Future<void> adjustGoal(Goal g, int delta) async {
    final saved = (g.saved + delta).clamp(0, 1 << 52);
    await _db.db.update('goals', {'saved': saved}, where: 'id = ?', whereArgs: [g.id]);
    await _reload();
  }

  Future<void> deleteGoal(int id) async {
    await _db.db.delete('goals', where: 'id = ?', whereArgs: [id]);
    await _reload();
  }

  // ------------------------------------------------ overall monthly budget

  /// One spending limit for the whole month, or null when not set.
  int? get overallBudget {
    final v = int.tryParse(_settings['overall_budget'] ?? '');
    return v == null || v <= 0 ? null : v;
  }

  /// Whether automatic SIP, bill and EMI entries count towards the budget.
  bool get budgetCountsPlans => _flag('overall_budget_plans', false);

  /// What counts against the monthly budget in [month].
  int overallSpent(DateTime month) => entries
      .where((e) =>
          e.type == EntryType.expense &&
          _inMonth(e.date, month) &&
          countsEntry(e) &&
          (budgetCountsPlans || e.planId == null))
      .fold(0, (s, e) => s + e.amount);

  Future<void> setOverallBudget(int? amount, {required bool countPlans}) async {
    await _db.db.transaction((txn) async {
      if (amount == null) {
        await txn.delete('settings', where: 'key = ?', whereArgs: ['overall_budget']);
      } else {
        await txn.insert('settings', {'key': 'overall_budget', 'value': '$amount'},
            conflictAlgorithm: _replace);
      }
      await txn.insert('settings',
          {'key': 'overall_budget_plans', 'value': countPlans ? '1' : '0'},
          conflictAlgorithm: _replace);
    });
    await _reload();
  }

  // ------------------------------------------------------------- budgets

  Future<void> saveBudget(String category, int amount, {int? replacingId}) async {
    await _db.db.transaction((txn) async {
      if (replacingId != null) {
        await txn.delete('budgets', where: 'id = ?', whereArgs: [replacingId]);
      }
      await txn.insert('budgets', {'category': category, 'amount': amount},
          conflictAlgorithm: _replace);
    });
    await _reload();
  }

  Future<void> deleteBudget(int id) async {
    await _db.db.delete('budgets', where: 'id = ?', whereArgs: [id]);
    await _reload();
  }

  // -------------------------------------------------------- lend & borrow

  Person? person(int? id) {
    for (final p in people) {
      if (p.id == id) return p;
    }
    return null;
  }

  Loan? loan(int? id) {
    for (final l in loans) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Entries of one loan, newest first.
  List<Entry> loanEntriesOf(int loanId) => _loanEntries[loanId] ?? const [];

  LoanStatus statusOf(Loan l, {DateTime? asOf}) =>
      loanStatus(l, loanEntriesOf(l.id!), asOf ?? today());

  /// Still owed and not marked settled.
  bool loanOpen(Loan l) {
    if (l.settled) return false;
    final st = statusOf(l);
    return st.given > 0 && st.total > 0;
  }

  List<Loan> loansOf(int personId) => loans.where((l) => l.personId == personId).toList();

  List<Loan> openLoansOf(int personId) => loansOf(personId).where(loanOpen).toList();

  Loan? openLoanFor(int personId, LoanDirection d) {
    for (final l in loansOf(personId)) {
      if (l.direction == d && loanOpen(l)) return l;
    }
    return null;
  }

  Person? personNamed(String name) {
    final n = name.trim().toLowerCase();
    for (final p in people) {
      if (p.name.trim().toLowerCase() == n) return p;
    }
    return null;
  }

  int _openTotal(LoanDirection d) => loans
      .where((l) => l.direction == d && loanOpen(l))
      .fold(0, (s, l) => s + statusOf(l).total);

  /// What people owe you, interest included.
  int get toGetBack => _openTotal(LoanDirection.lent);

  /// What you owe people, interest included.
  int get youOwe => _openTotal(LoanDirection.borrowed);

  /// People with an open loan in [d].
  int peopleCount(LoanDirection d) => loans
      .where((l) => l.direction == d && loanOpen(l))
      .map((l) => l.personId)
      .toSet()
      .length;

  /// Short title for an entry that belongs to a loan.
  String loanEntryTitle(Entry e) {
    final l = loan(e.loanId);
    final name = person(l?.personId)?.name ?? 'someone';
    if (l == null) return e.note.isEmpty ? 'Lend & borrow' : e.note;
    if (isGive(l, e)) return l.lent ? 'Lent to $name' : 'Borrowed from $name';
    if (isPrincipalBack(l, e)) return l.lent ? 'Got back from $name' : 'Paid back $name';
    return l.lent ? 'Interest from $name' : 'Interest paid to $name';
  }

  /// Records money lent or borrowed. Adds to the person's open loan in the
  /// same direction, or starts a new one with the given terms.
  Future<void> lendOrBorrow({
    required String name,
    required LoanDirection direction,
    required int amount,
    required int accountId,
    required DateTime date,
    String note = '',
    double rate = 0,
    RatePeriod period = RatePeriod.month,
    DateTime? dueDate,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existingPerson = personNamed(name);
    final existingLoan =
        existingPerson == null ? null : openLoanFor(existingPerson.id!, direction);

    await _db.db.transaction((txn) async {
      final personId = existingPerson?.id ??
          await txn.insert('people', {'name': name.trim(), 'created_at': now});
      int loanId;
      if (existingLoan != null) {
        loanId = existingLoan.id!;
        if (dueDate != null) {
          await txn.update('loans', {'due_date': dayKey(dueDate)},
              where: 'id = ?', whereArgs: [loanId]);
        }
      } else {
        final map = Loan(
          personId: personId,
          direction: direction,
          rate: rate,
          period: period,
          dueDate: dueDate,
          note: note,
          createdAt: now,
        ).toMap()
          ..remove('id');
        loanId = await txn.insert('loans', map);
      }
      final entry = Entry(
        type: direction == LoanDirection.lent ? EntryType.loanOut : EntryType.loanIn,
        amount: amount,
        accountId: accountId,
        category: 'loan',
        note: note,
        date: dateOnly(date),
        createdAt: now,
        loanId: loanId,
      ).toMap()
        ..remove('id');
      await txn.insert('entries', entry);
    });
    await _reload();
  }

  /// Records money paid back on [l]: interest first, then the amount.
  /// Returns the (interest, principal) split.
  Future<(int, int)> repay(Loan l, int amount, int accountId, DateTime date) async {
    final st = statusOf(l, asOf: date);
    final (interest, principal) = splitPayment(st, amount);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.transaction((txn) async {
      if (interest > 0) {
        await txn.insert(
          'entries',
          Entry(
            type: l.lent ? EntryType.income : EntryType.expense,
            amount: interest,
            accountId: accountId,
            category: l.lent ? 'interest' : 'interest_paid',
            date: dateOnly(date),
            createdAt: now,
            loanId: l.id,
          ).toMap()
            ..remove('id'),
        );
      }
      if (principal > 0) {
        await txn.insert(
          'entries',
          Entry(
            type: l.lent ? EntryType.loanIn : EntryType.loanOut,
            amount: principal,
            accountId: accountId,
            category: 'loan',
            date: dateOnly(date),
            createdAt: now + 1,
            loanId: l.id,
          ).toMap()
            ..remove('id'),
        );
      }
    });
    await _reload();
    return (interest, principal);
  }

  Future<void> updateLoanTerms(Loan l,
      {required double rate, required RatePeriod period, DateTime? dueDate}) async {
    await _db.db.update(
      'loans',
      {
        'rate': rate,
        'rate_period': period.name,
        'due_date': dueDate == null ? null : dayKey(dueDate),
      },
      where: 'id = ?',
      whereArgs: [l.id],
    );
    await _reload();
  }

  Future<void> setLoanSettled(Loan l, bool settled) async {
    await _db.db.update('loans', {'settled': settled ? 1 : 0},
        where: 'id = ?', whereArgs: [l.id]);
    await _reload();
  }

  Future<void> renamePerson(int id, String name) async {
    await _db.db.update('people', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);
    await _reload();
  }

  /// Deletes the person, their loans and every entry of those loans.
  Future<void> deletePerson(int id) async {
    final ids = loansOf(id).map((l) => l.id).toList();
    await _db.db.transaction((txn) async {
      for (final loanId in ids) {
        await txn.delete('entries', where: 'loan_id = ?', whereArgs: [loanId]);
      }
      await txn.delete('loans', where: 'person_id = ?', whereArgs: [id]);
      await txn.delete('people', where: 'id = ?', whereArgs: [id]);
    });
    await _reload();
  }

  // ------------------------------------------------------ fixed deposits

  Fd? fd(int? id) {
    for (final f in fds) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Running or matured (not yet withdrawn or renewed).
  List<Fd> get activeFds => fds.where((f) => !f.closed).toList();

  /// Reached its maturity date and waiting for Withdraw or Renew.
  bool fdMatured(Fd f) => !f.closed && !today().isBefore(f.maturityDate);

  /// Total value of active FDs today.
  int get fdWorth => activeFds.fold(0, (s, f) => s + fdValueOn(f, today()));

  int get fdInvested => activeFds.fold(0, (s, f) => s + f.principal);

  String fdEntryTitle(Entry e) {
    final name = fd(e.fdId)?.name ?? 'FD';
    return switch (e.type) {
      EntryType.depositOut => 'Put into $name',
      EntryType.depositIn => '$name money back',
      _ => 'Interest from $name',
    };
  }

  Map<String, Object?> _entryMap(Entry e) => e.toMap()..remove('id');

  /// The amount first put in, following renewals back to the first FD.
  int fdOriginalDeposit(Fd f) {
    var cur = f;
    for (var i = 0; i < 100; i++) {
      final prev = fd(cur.renewedFrom);
      if (prev == null) break;
      cur = prev;
    }
    return cur.principal;
  }

  /// Adds an FD. With [fromAccount] the amount is taken from its account.
  Future<void> addFd(Fd f, {required bool fromAccount}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.transaction((txn) async {
      final id = await txn.insert('fds', f.toMap()..remove('id'));
      if (fromAccount && f.accountId != null) {
        await txn.insert(
          'entries',
          _entryMap(Entry(
            type: EntryType.depositOut,
            amount: f.principal,
            accountId: f.accountId!,
            category: 'fd',
            date: f.startDate,
            createdAt: now,
            fdId: id,
          )),
        );
      }
    });
    await _reload();
  }

  /// Saves edited terms. The opening entry follows the amount, account and
  /// start date.
  Future<void> updateFd(Fd f) async {
    await _db.db.transaction((txn) async {
      await txn.update('fds', f.toMap(), where: 'id = ?', whereArgs: [f.id]);
      final values = <String, Object?>{'amount': f.principal, 'date': dayKey(f.startDate)};
      if (f.accountId != null) values['account_id'] = f.accountId;
      await txn.update('entries', values,
          where: 'fd_id = ? AND type = ?', whereArgs: [f.id, EntryType.depositOut.name]);
    });
    await _reload();
  }

  /// Closes the FD and adds [received] to the account: the deposit comes
  /// back and anything above it counts as interest income.
  Future<void> withdrawFd(Fd f,
      {required int received,
      required int accountId,
      required DateTime date,
      required bool early}) async {
    // What came from your account goes back; everything above it (including
    // interest rolled over by earlier renewals) is interest income.
    final base = fdOriginalDeposit(f);
    final principalPart = received < base ? received : base;
    final interest = received - principalPart;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.transaction((txn) async {
      if (principalPart > 0) {
        await txn.insert(
          'entries',
          _entryMap(Entry(
            type: EntryType.depositIn,
            amount: principalPart,
            accountId: accountId,
            category: 'fd',
            date: dateOnly(date),
            createdAt: now,
            fdId: f.id,
          )),
        );
      }
      if (interest > 0) {
        await txn.insert(
          'entries',
          _entryMap(Entry(
            type: EntryType.income,
            amount: interest,
            accountId: accountId,
            category: 'interest',
            date: dateOnly(date),
            createdAt: now + 1,
            fdId: f.id,
          )),
        );
      }
      await txn.update(
        'fds',
        {
          'closed': 1,
          'closed_date': dayKey(date),
          'closed_amount': received,
          'closed_how': early ? 'early' : 'withdrawn',
          'account_id': accountId,
        },
        where: 'id = ?',
        whereArgs: [f.id],
      );
    });
    await _reload();
  }

  /// Renews a matured FD from its maturity date. [withInterest] puts the
  /// whole maturity amount into the new FD; otherwise the interest goes to
  /// [accountId] and the new FD keeps the original amount.
  Future<void> renewFd(
    Fd old, {
    required bool withInterest,
    int? accountId,
    required double rate,
    required Compounding compounding,
    required DateTime maturity,
  }) async {
    final value = fdMaturityValue(old);
    final interest = value - old.principal;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.transaction((txn) async {
      final newId = await txn.insert(
        'fds',
        Fd(
          name: old.name,
          principal: withInterest ? value : old.principal,
          rate: rate,
          compounding: compounding,
          startDate: old.maturityDate,
          maturityDate: dateOnly(maturity),
          accountId: old.accountId,
          renewedFrom: old.id,
          createdAt: now,
        ).toMap()
          ..remove('id'),
      );
      if (!withInterest && interest > 0 && accountId != null) {
        await txn.insert(
          'entries',
          _entryMap(Entry(
            type: EntryType.income,
            amount: interest,
            accountId: accountId,
            category: 'interest',
            date: old.maturityDate,
            createdAt: now,
            fdId: old.id,
          )),
        );
      }
      await txn.update(
        'fds',
        {
          'closed': 1,
          'closed_date': dayKey(old.maturityDate),
          'closed_amount': value,
          'closed_how': 'renewed',
          'renewed_to': newId,
        },
        where: 'id = ?',
        whereArgs: [old.id],
      );
    });
    await _reload();
  }

  /// Deletes the FD and the entries it made (account balances go back).
  Future<void> deleteFd(Fd f) async {
    await _db.db.transaction((txn) async {
      await txn.delete('entries', where: 'fd_id = ?', whereArgs: [f.id]);
      await txn.delete('fds', where: 'id = ?', whereArgs: [f.id]);
      await txn.update('fds', {'renewed_to': null},
          where: 'renewed_to = ?', whereArgs: [f.id]);
    });
    await _reload();
  }

  // ------------------------------------------------------- tags & trips

  Tag? tag(int? id) {
    for (final t in tags) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Tag ids of one entry.
  Set<int> tagsOf(int? entryId) => _entryTags[entryId] ?? const {};

  /// Entries with this tag, newest first.
  List<Entry> entriesWithTag(int tagId) => _tagEntries[tagId] ?? const [];

  /// Trips that tag new entries on [day] by themselves.
  Set<int> autoTripsOn(DateTime day) => {
        for (final t in tags)
          if (t.isTrip && t.auto && t.covers(day)) t.id!,
      };

  /// The trip going on today, if any.
  Tag? get tripOnNow {
    final t = today();
    for (final x in tags) {
      if (x.covers(t)) return x;
    }
    return null;
  }

  /// What was spent with this tag (all accounts).
  int tagSpent(int tagId) => entriesWithTag(tagId)
      .where((e) => e.type == EntryType.expense)
      .fold(0, (s, e) => s + e.amount);

  /// Entries that could be tagged: normal spending and income, not added
  /// by a plan.
  static bool taggable(Entry e) =>
      (e.type == EntryType.expense || e.type == EntryType.income) &&
      e.planId == null &&
      e.loanId == null &&
      e.fdId == null;

  /// Spending inside the trip's dates that does not have its tag yet.
  List<Entry> untaggedInTrip(Tag t) => entries
      .where((e) =>
          e.type == EntryType.expense &&
          taggable(e) &&
          t.covers(e.date) &&
          !tagsOf(e.id).contains(t.id))
      .toList();

  Future<int> saveTag(Tag t) async {
    final map = t.toMap();
    int id;
    if (t.id == null) {
      map.remove('id');
      id = await _db.db.insert('tags', map);
    } else {
      id = t.id!;
      await _db.db.update('tags', map, where: 'id = ?', whereArgs: [id]);
    }
    await _reload();
    return id;
  }

  /// Adds the tag to these entries.
  Future<void> addTagTo(int tagId, Iterable<int> entryIds) async {
    final b = _db.db.batch();
    for (final id in entryIds) {
      b.insert('entry_tags', {'entry_id': id, 'tag_id': tagId}, conflictAlgorithm: _replace);
    }
    await b.commit(noResult: true);
    await _reload();
  }

  /// Removes the tag. Its entries stay.
  Future<void> deleteTag(int id) async {
    await _db.db.transaction((txn) async {
      await txn.delete('entry_tags', where: 'tag_id = ?', whereArgs: [id]);
      await txn.delete('tags', where: 'id = ?', whereArgs: [id]);
    });
    await _reload();
  }

  // -------------------------------------------------------- mutual funds

  MutualFund? fund(int? id) {
    for (final f in funds) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<MutualFund> get openFunds => funds.where((f) => !f.closed).toList();

  /// Money moves of one fund, newest first.
  List<Entry> fundEntriesOf(int fundId) => _fundEntries[fundId] ?? const [];

  /// The monthly SIP of a fund, if it has one.
  Plan? fundPlan(MutualFund f) {
    for (final p in plans) {
      if (p.kind == PlanKind.sip && p.fundId == f.id) return p;
    }
    return null;
  }

  /// When the money from before Funds counts from.
  DateTime _fundStart(MutualFund f) =>
      f.started ?? dateOnly(DateTime.fromMillisecondsSinceEpoch(f.createdAt));

  /// What is in the fund now (or at the end of [asOf]): money put in less
  /// money taken out. A closed fund holds nothing.
  int investedIn(MutualFund f, [DateTime? asOf]) {
    final d = asOf == null ? null : dateOnly(asOf);
    if (f.closed && (d == null || f.closedDate == null || !f.closedDate!.isAfter(d))) return 0;
    var v = (d == null || !_fundStart(f).isAfter(d)) ? f.alreadyInvested : 0;
    for (final e in fundEntriesOf(f.id!)) {
      if (d != null && e.date.isAfter(d)) continue;
      if (e.type == EntryType.investOut) v += e.amount;
      if (e.type == EntryType.investIn) v -= e.amount;
    }
    return v < 0 ? 0 : v;
  }

  /// Everything ever put in: before Funds, SIPs and lump sums.
  int putInto(MutualFund f) => fundEntriesOf(f.id!)
      .where((e) => e.type == EntryType.investOut)
      .fold(f.alreadyInvested, (s, e) => s + e.amount);

  /// Put in through Funds (SIPs and lump sums).
  int addedInFunds(MutualFund f) => putInto(f) - f.alreadyInvested;

  /// Taken out before closing (part withdrawals).
  int takenOut(MutualFund f) => fundEntriesOf(f.id!)
      .where((e) => e.type == EntryType.investIn)
      .fold(0, (s, e) => s + e.amount);

  int get totalInvested => openFunds.fold(0, (s, f) => s + investedIn(f));

  /// Active SIPs of open funds.
  List<Plan> get activeSips => [
        for (final f in openFunds)
          if (fundPlan(f) case final p? when p.active) p,
      ];

  int get sipMonthly => activeSips.fold(0, (s, p) => s + p.amount);

  /// The SIP that comes next.
  Plan? get nextSip {
    Plan? best;
    DateTime? bestDate;
    for (final p in activeSips) {
      final d = nextDueDate(p);
      if (d != null && (bestDate == null || d.isBefore(bestDate))) {
        best = p;
        bestDate = d;
      }
    }
    return best;
  }

  /// Money put into funds this calendar year (SIPs and lump sums).
  int get investedThisYear {
    final y = today().year;
    return entries
        .where((e) => e.type == EntryType.investOut && e.date.year == y && countsEntry(e))
        .fold(0, (s, e) => s + e.amount);
  }

  String fundEntryTitle(Entry e) {
    final name = fund(e.fundId)?.name ?? 'Mutual fund';
    return switch (e.type) {
      EntryType.investOut => e.planId != null ? 'SIP · $name' : 'Lump sum · $name',
      EntryType.investIn => 'Taken out of $name',
      _ => 'Profit from $name',
    };
  }

  /// Saves a fund. With [sipAmount], [sipDay] and [sipAccount] it has a
  /// monthly SIP (added or changed); without, any SIP is removed.
  Future<int> saveFund(MutualFund f, {int? sipAmount, int? sipDay, int? sipAccount}) async {
    final now = DateTime.now();
    final existing = f.id == null ? null : fundPlan(f);
    late int id;
    await _db.db.transaction((txn) async {
      if (f.id == null) {
        id = await txn.insert('funds', f.toMap()..remove('id'));
      } else {
        id = f.id!;
        await txn.update('funds', f.toMap(), where: 'id = ?', whereArgs: [id]);
      }
      final hasSip = sipAmount != null && sipDay != null && sipAccount != null;
      if (hasSip && existing != null) {
        await txn.update(
          'plans',
          {'name': f.name, 'amount': sipAmount, 'day': sipDay, 'account_id': sipAccount},
          where: 'id = ?',
          whereArgs: [existing.id],
        );
      } else if (hasSip) {
        await txn.insert(
          'plans',
          Plan(
            kind: PlanKind.sip,
            name: f.name,
            amount: sipAmount,
            day: sipDay,
            accountId: sipAccount,
            startMonth: firstMonthFor(sipDay, now),
            category: 'fund',
            createdAt: now.millisecondsSinceEpoch,
            fundId: id,
          ).toMap()
            ..remove('id'),
        );
      } else if (existing != null) {
        await txn.delete('plans', where: 'id = ?', whereArgs: [existing.id]);
      }
    });
    await _load();
    await postDuePlans(notify: false);
    notifyListeners();
    return id;
  }

  /// Puts extra money (a lump sum) into the fund.
  Future<void> addToFund(MutualFund f, int amount, int accountId, DateTime date) async {
    await _db.db.insert(
      'entries',
      Entry(
        type: EntryType.investOut,
        amount: amount,
        accountId: accountId,
        category: 'fund',
        date: dateOnly(date),
        createdAt: DateTime.now().millisecondsSinceEpoch,
        fundId: f.id,
      ).toMap()
        ..remove('id'),
    );
    await _reload();
  }

  /// Money taken out of a fund. A part withdrawal lowers what is invested.
  /// With [all] the fund is closed: up to what was invested comes back, and
  /// anything above it is profit (income). Returns (money back, profit).
  Future<(int, int)> withdrawFromFund(MutualFund f, int amount, int accountId, DateTime date,
      {required bool all}) async {
    final invested = investedIn(f);
    final back = all ? (amount < invested ? amount : invested) : amount;
    final profit = all ? amount - back : 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.transaction((txn) async {
      if (back > 0) {
        await txn.insert(
          'entries',
          Entry(
            type: EntryType.investIn,
            amount: back,
            accountId: accountId,
            category: 'fund',
            date: dateOnly(date),
            createdAt: now,
            fundId: f.id,
          ).toMap()
            ..remove('id'),
        );
      }
      if (profit > 0) {
        await txn.insert(
          'entries',
          Entry(
            type: EntryType.income,
            amount: profit,
            accountId: accountId,
            category: 'fund_profit',
            date: dateOnly(date),
            createdAt: now + 1,
            fundId: f.id,
          ).toMap()
            ..remove('id'),
        );
      }
      if (all) {
        await txn.update(
          'funds',
          {'closed': 1, 'closed_date': dayKey(date), 'closed_amount': amount},
          where: 'id = ?',
          whereArgs: [f.id],
        );
        // Its SIP stops; past SIP entries stay.
        await txn.delete('plans', where: 'fund_id = ? AND kind = ?', whereArgs: [f.id, PlanKind.sip.name]);
      }
    });
    await _reload();
    return (back, profit);
  }

  /// Pauses or restarts the fund's SIP. A restarted SIP begins on its next
  /// date; paused months are not added.
  Future<void> setSipActive(MutualFund f, bool active) async {
    final p = fundPlan(f);
    if (p == null) return;
    final values = <String, Object?>{'active': active ? 1 : 0};
    if (active) {
      final first = parseMonth(firstMonthFor(p.day, DateTime.now()));
      values['last_posted'] = monthKey(addMonths(first, -1));
    }
    await _db.db.update('plans', values, where: 'id = ?', whereArgs: [p.id]);
    await _reload();
  }

  /// Deletes the fund, its SIP and its money moves (account balances go
  /// back).
  Future<void> deleteFund(MutualFund f) async {
    await _db.db.transaction((txn) async {
      await txn.delete('entries', where: 'fund_id = ?', whereArgs: [f.id]);
      await txn.delete('plans', where: 'fund_id = ?', whereArgs: [f.id]);
      await txn.delete('funds', where: 'id = ?', whereArgs: [f.id]);
    });
    await _reload();
  }

  /// Older versions saved SIPs as spending. Each old SIP plan becomes a
  /// fund, and its past instalments become money moved into that fund.
  Future<void> _convertOldSips() async {
    final old = plans.where((p) => p.kind == PlanKind.sip && fund(p.fundId) == null).toList();
    if (old.isEmpty) return;
    await _db.db.transaction((txn) async {
      for (final p in old) {
        final id = await txn.insert(
          'funds',
          MutualFund(name: p.name, started: parseMonth(p.startMonth), createdAt: p.createdAt).toMap()
            ..remove('id'),
        );
        await txn.update('plans', {'fund_id': id, 'category': 'fund'},
            where: 'id = ?', whereArgs: [p.id]);
        await txn.update(
          'entries',
          {'type': EntryType.investOut.name, 'fund_id': id, 'category': 'fund', 'note': ''},
          where: 'plan_id = ? AND type = ?',
          whereArgs: [p.id, EntryType.expense.name],
        );
      }
    });
    await _load();
  }

  // ----------------------------------------------------------- net worth

  /// Balance of an account at the end of [day].
  int balanceOn(Account a, DateTime day) {
    final end = dateOnly(day);
    var b = a.opening;
    for (final e in entries) {
      if (e.date.isAfter(end)) continue;
      if (e.accountId == a.id || e.toAccountId == a.id) b += e.effectOn(a.id!);
    }
    return b;
  }

  /// Everything you have minus what you owe at the end of [day] (now when
  /// null): your own accounts, FDs and money lent, less money borrowed.
  int netWorthOn([DateTime? day]) =>
      netWorthParts(day).fold(0, (s, p) => s + p.amount);

  /// The pieces of net worth: positive ones are what you have, negative
  /// ones what you owe.
  List<WorthPart> netWorthParts([DateTime? day]) {
    final now = day == null;
    final d = dateOnly(day ?? today());
    final out = <WorthPart>[];

    final groups = <String, List<Account>>{};
    for (final a in countedAccounts) {
      final key = a.kind.isBank ? 'bank' : a.kind.name;
      groups.putIfAbsent(key, () => []).add(a);
    }
    const labels = {
      'bank': ('Bank accounts', 'Bank overdraft'),
      'cash': ('Cash', 'Cash'),
      'wallet': ('Wallets', 'Wallets'),
      'card': ('Credit cards', 'Credit card dues'),
    };
    for (final key in ['bank', 'cash', 'wallet', 'card']) {
      final list = groups[key];
      if (list == null) continue;
      final sum = list.fold(0, (s, a) => s + (now ? balanceOf(a.id!) : balanceOn(a, d)));
      if (sum == 0 && key == 'card') continue;
      final names = list.map((a) => a.name).toList();
      out.add(WorthPart(
        key,
        sum < 0 ? labels[key]!.$2 : labels[key]!.$1,
        names.length > 2 ? '${names.take(2).join(', ')} +${names.length - 2}' : names.join(', '),
        sum,
      ));
    }

    if (feature(Features.fds)) {
      var value = 0;
      var count = 0;
      for (final f in fds) {
        if (f.startDate.isAfter(d)) continue;
        if (f.closed && f.closedDate != null && !f.closedDate!.isAfter(d)) continue;
        value += fdValueOn(f, d);
        count++;
      }
      if (count > 0) {
        out.add(WorthPart('fd', 'Fixed deposits',
            '$count ${count == 1 ? 'FD' : 'FDs'} · value ${now ? 'today' : 'that day'}', value));
      }
    }

    if (feature(Features.sips)) {
      var value = 0;
      var count = 0;
      for (final f in funds) {
        final v = now ? investedIn(f) : investedIn(f, d);
        if (v <= 0) continue;
        value += v;
        count++;
      }
      if (count > 0) {
        out.add(WorthPart('mf', 'Mutual funds',
            '$count ${count == 1 ? 'fund' : 'funds'} · what you invested', value));
      }
    }

    if (feature(Features.lend)) {
      for (final dir in LoanDirection.values) {
        var sum = 0;
        final people = <int>{};
        var interest = false;
        for (final l in loans.where((l) => l.direction == dir && !l.settled)) {
          final st = statusOf(l, asOf: d);
          if (st.total <= 0) continue;
          sum += st.total;
          people.add(l.personId);
          if (st.interestDue > 0) interest = true;
        }
        if (sum == 0) continue;
        final n = people.length;
        final who = '$n ${n == 1 ? 'person' : 'people'}${interest ? ' · with interest' : ''}';
        out.add(dir == LoanDirection.lent
            ? WorthPart('lent', 'Money lent', who, sum)
            : WorthPart('borrowed', 'Money borrowed', who, -sum));
      }
    }
    return out;
  }

  /// Month-end net worth for the last [months] months, then today.
  List<(DateTime, int)> netWorthHistory(int months) {
    final t = today();
    final out = <(DateTime, int)>[];
    for (var i = months; i >= 1; i--) {
      final m = addMonths(DateTime(t.year, t.month), -i);
      final end = DateTime(m.year, m.month + 1, 0);
      out.add((end, netWorthOn(end)));
    }
    out.add((t, netWorthOn()));
    return out;
  }

  /// Months from the first entry (or account) to now, at most 120.
  int get monthsOfData {
    final t = today();
    var first = DateTime(t.year, t.month);
    if (entries.isNotEmpty) {
      final o = entries.last.date;
      final m = DateTime(o.year, o.month);
      if (m.isBefore(first)) first = m;
    }
    return monthsBetween(first, DateTime(t.year, t.month)).clamp(1, 120);
  }

  /// Whether any plan is a loan EMI (their remaining amount is not known).
  bool get hasEmiPlans =>
      feature(Features.loans) && plans.any((p) => p.kind == PlanKind.loan && p.active && !isFinished(p));

  // -------------------------------------------------------------- backup

  static const backupFormat = 'funds-backup';

  /// Settings that belong to this phone only and never go into a backup.
  static const _deviceOnlySettings = {
    'backup_password',
    'last_auto_backup',
    'auto_backup_error',
    'notif_asked',
  };

  Future<String> exportJson() async {
    final data = await _db.dump();
    data['settings'] = [
      for (final row in data['settings'] ?? const <Map<String, Object?>>[])
        if (!_deviceOnlySettings.contains(row['key'])) row,
    ];
    return const JsonEncoder.withIndent(' ').convert({
      'format': backupFormat,
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': data,
    });
  }

  /// Checks a backup file and returns its tables, or throws a
  /// [FormatException] with a message the user can read.
  static Map<String, List<Map<String, Object?>>> parseBackup(String text) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const FormatException('This file is not a Funds backup.');
    }
    if (decoded is! Map || decoded['format'] != backupFormat || decoded['data'] is! Map) {
      throw const FormatException('This file is not a Funds backup.');
    }
    final version = decoded['version'];
    if (version is! int || version > 1) {
      throw const FormatException('This backup was made by a newer version of Funds.');
    }
    final raw = decoded['data'] as Map;
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in FundsDb.tables) {
      final rows = raw[t];
      if (rows == null) continue;
      if (rows is! List) throw const FormatException('The backup file is damaged.');
      out[t] = [
        for (final r in rows)
          if (r is Map) Map<String, Object?>.from(r) else throw const FormatException('The backup file is damaged.'),
      ];
    }
    // Make sure every row can be read before touching the phone's data.
    try {
      out['accounts']?.forEach(Account.fromMap);
      out['entries']?.forEach(Entry.fromMap);
      out['plans']?.forEach(Plan.fromMap);
      out['goals']?.forEach(Goal.fromMap);
      out['budgets']?.forEach(Budget.fromMap);
      out['people']?.forEach(Person.fromMap);
      out['loans']?.forEach(Loan.fromMap);
      out['fds']?.forEach(Fd.fromMap);
      out['tags']?.forEach(Tag.fromMap);
      out['funds']?.forEach(MutualFund.fromMap);
      for (final r in out['entry_tags'] ?? const <Map<String, Object?>>[]) {
        if (r['entry_id'] is! int || r['tag_id'] is! int) throw const FormatException('');
      }
    } catch (_) {
      throw const FormatException('The backup file is damaged.');
    }
    return out;
  }

  Future<void> importBackup(Map<String, List<Map<String, Object?>>> data) async {
    // Keep this phone's own backup password and backup history.
    final keep = {
      for (final k in _deviceOnlySettings)
        if (_settings[k] != null) k: _settings[k]!,
    };
    final incoming = [
      for (final row in data['settings'] ?? const <Map<String, Object?>>[])
        if (!keep.containsKey(row['key'])) row,
      for (final e in keep.entries) {'key': e.key, 'value': e.value},
    ];
    await _db.restore({...data, 'settings': incoming});
    await _load();
    await _convertOldSips();
    amountsHidden = hideAmountsByDefault;
    await postDuePlans(notify: false);
    notifyListeners();
  }

  Future<void> markBackedUp() =>
      setSetting('last_backup', '${DateTime.now().millisecondsSinceEpoch}');
}

const _replace = ConflictAlgorithm.replace;
