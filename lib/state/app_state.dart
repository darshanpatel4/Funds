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

  Future<void> saveEntry(Entry e) async {
    final map = e.toMap();
    if (e.id == null) {
      map.remove('id');
      await _db.db.insert('entries', map);
    } else {
      await _db.db.update('entries', map, where: 'id = ?', whereArgs: [e.id]);
    }
    await _db.db.insert('settings', {'key': 'last_account', 'value': '${e.accountId}'},
        conflictAlgorithm: _replace);
    await _reload();
  }

  Future<void> deleteEntry(int id) async {
    await _db.db.delete('entries', where: 'id = ?', whereArgs: [id]);
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
        for (final m in months) {
          final entry = Entry(
            type: p.kind.isIncome ? EntryType.income : EntryType.expense,
            amount: p.amount,
            accountId: p.accountId,
            category: planCategory(p),
            note: p.name,
            date: dueDateIn(m.year, m.month, p.day),
            createdAt: now.millisecondsSinceEpoch,
            planId: p.id,
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

  // -------------------------------------------------------------- backup

  static const backupFormat = 'funds-backup';

  Future<String> exportJson() async {
    final data = await _db.dump();
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
    } catch (_) {
      throw const FormatException('The backup file is damaged.');
    }
    return out;
  }

  Future<void> importBackup(Map<String, List<Map<String, Object?>>> data) async {
    await _db.restore(data);
    await _load();
    amountsHidden = hideAmountsByDefault;
    await postDuePlans(notify: false);
    notifyListeners();
  }

  Future<void> markBackedUp() =>
      setSetting('last_backup', '${DateTime.now().millisecondsSinceEpoch}');
}

const _replace = ConflictAlgorithm.replace;
