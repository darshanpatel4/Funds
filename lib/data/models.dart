// Plain data classes. All money is stored as whole paise (int) so sums are
// exact; dates are stored as 'yyyy-MM-dd' and months as 'yyyy-MM'.

import '../utils/format.dart';

enum AccountKind { savings, current, cash, wallet, card }

extension AccountKindX on AccountKind {
  String get label => switch (this) {
        AccountKind.savings => 'Savings',
        AccountKind.current => 'Current',
        AccountKind.cash => 'Cash',
        AccountKind.wallet => 'Wallet',
        AccountKind.card => 'Credit card',
      };

  bool get isBank => this == AccountKind.savings || this == AccountKind.current;
  bool get isCashLike => this == AccountKind.cash || this == AccountKind.wallet;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

class Account {
  final int? id;
  final String name;
  final AccountKind kind;

  /// Balance before the first entry. For a credit card this is minus the
  /// outstanding amount when the card was added.
  final int opening;
  final int? creditLimit;
  final int? dueDay;
  final int sort;
  final int createdAt;

  /// False for money that is not the user's own (a family or company
  /// account): it is then left out of the total balance, money in/out and
  /// budgets.
  final bool counted;

  const Account({
    this.id,
    required this.name,
    required this.kind,
    this.opening = 0,
    this.creditLimit,
    this.dueDay,
    this.sort = 0,
    required this.createdAt,
    this.counted = true,
  });

  bool get isCard => kind == AccountKind.card;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'opening': opening,
        'credit_limit': creditLimit,
        'due_day': dueDay,
        'sort': sort,
        'created_at': createdAt,
        'counted': counted ? 1 : 0,
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int?,
        name: m['name'] as String,
        kind: _enumByName(AccountKind.values, m['kind'], AccountKind.savings),
        opening: (m['opening'] as int?) ?? 0,
        creditLimit: m['credit_limit'] as int?,
        dueDay: m['due_day'] as int?,
        sort: (m['sort'] as int?) ?? 0,
        createdAt: (m['created_at'] as int?) ?? 0,
        // Older data has no column: count it, as before.
        counted: (m['counted'] as int?) != 0,
      );
}

/// [loanOut] and [loanIn] move money between an account and a person
/// (lending, borrowing, paying back). [depositOut] and [depositIn] move
/// money into and out of a fixed deposit, [investOut] and [investIn] into
/// and out of a mutual fund (SIPs, lump sums, withdrawals). None of these
/// are spending or income.
enum EntryType {
  expense,
  income,
  transfer,
  loanOut,
  loanIn,
  depositOut,
  depositIn,
  investOut,
  investIn,
}

class Entry {
  final int? id;
  final EntryType type;

  /// Always positive; [type] decides the direction.
  final int amount;
  final int accountId;

  /// Destination account for transfers.
  final int? toAccountId;
  final String category;
  final String note;
  final DateTime date;
  final int createdAt;

  /// Set when the entry was added automatically by a plan (salary, SIP...).
  final int? planId;

  /// Set when the entry belongs to money lent to or borrowed from someone
  /// (including the interest paid on it).
  final int? loanId;

  /// Set when the entry belongs to a fixed deposit (opening it, getting the
  /// money back, or its interest).
  final int? fdId;

  /// Set when the entry belongs to a mutual fund (a SIP, a lump sum, a
  /// withdrawal or its profit).
  final int? fundId;

  const Entry({
    this.id,
    required this.type,
    required this.amount,
    required this.accountId,
    this.toAccountId,
    this.category = 'other',
    this.note = '',
    required this.date,
    required this.createdAt,
    this.planId,
    this.loanId,
    this.fdId,
    this.fundId,
  });

  bool get isLoanMove => type == EntryType.loanOut || type == EntryType.loanIn;

  /// Effect of this entry on [account]'s balance.
  int effectOn(int account) {
    switch (type) {
      case EntryType.income:
      case EntryType.loanIn:
      case EntryType.depositIn:
      case EntryType.investIn:
        return accountId == account ? amount : 0;
      case EntryType.expense:
      case EntryType.loanOut:
      case EntryType.depositOut:
      case EntryType.investOut:
        return accountId == account ? -amount : 0;
      case EntryType.transfer:
        var e = 0;
        if (accountId == account) e -= amount;
        if (toAccountId == account) e += amount;
        return e;
    }
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.name,
        'amount': amount,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'category': category,
        'note': note,
        'date': dayKey(date),
        'created_at': createdAt,
        'plan_id': planId,
        'loan_id': loanId,
        'fd_id': fdId,
        'fund_id': fundId,
      };

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
        id: m['id'] as int?,
        type: _enumByName(EntryType.values, m['type'], EntryType.expense),
        amount: m['amount'] as int,
        accountId: m['account_id'] as int,
        toAccountId: m['to_account_id'] as int?,
        category: (m['category'] as String?) ?? 'other',
        note: (m['note'] as String?) ?? '',
        date: parseDay(m['date'] as String),
        createdAt: (m['created_at'] as int?) ?? 0,
        planId: m['plan_id'] as int?,
        loanId: m['loan_id'] as int?,
        fdId: m['fd_id'] as int?,
        fundId: m['fund_id'] as int?,
      );
}

/// How often an FD adds interest to itself.
enum Compounding { quarterly, monthly, yearly, simple }

extension CompoundingX on Compounding {
  String get label => switch (this) {
        Compounding.quarterly => 'Every 3 months',
        Compounding.monthly => 'Every month',
        Compounding.yearly => 'Every year',
        Compounding.simple => 'Simple interest',
      };

  /// Times a year interest is added (0 for simple interest).
  int get perYear => switch (this) {
        Compounding.quarterly => 4,
        Compounding.monthly => 12,
        Compounding.yearly => 1,
        Compounding.simple => 0,
      };
}

/// A fixed deposit. Its value is worked out from these terms; entries only
/// record money moving between an account and the FD.
class Fd {
  final int? id;
  final String name;

  /// Amount put in, in paise.
  final int principal;

  /// Interest rate in percent a year.
  final double rate;
  final Compounding compounding;
  final DateTime startDate;
  final DateTime maturityDate;

  /// Account the money came from (and the default for getting it back).
  final int? accountId;
  final bool closed;
  final DateTime? closedDate;

  /// Amount received when closed (or carried into a renewal).
  final int? closedAmount;

  /// 'withdrawn', 'early' or 'renewed'.
  final String? closedHow;
  final int? renewedFrom;
  final int? renewedTo;
  final int createdAt;

  const Fd({
    this.id,
    required this.name,
    required this.principal,
    required this.rate,
    this.compounding = Compounding.quarterly,
    required this.startDate,
    required this.maturityDate,
    this.accountId,
    this.closed = false,
    this.closedDate,
    this.closedAmount,
    this.closedHow,
    this.renewedFrom,
    this.renewedTo,
    required this.createdAt,
  });

  String get rateLabel {
    final r = rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString();
    return '$r%';
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'principal': principal,
        'rate': rate,
        'compounding': compounding.name,
        'start_date': dayKey(startDate),
        'maturity_date': dayKey(maturityDate),
        'account_id': accountId,
        'closed': closed ? 1 : 0,
        'closed_date': closedDate == null ? null : dayKey(closedDate!),
        'closed_amount': closedAmount,
        'closed_how': closedHow,
        'renewed_from': renewedFrom,
        'renewed_to': renewedTo,
        'created_at': createdAt,
      };

  factory Fd.fromMap(Map<String, Object?> m) => Fd(
        id: m['id'] as int?,
        name: m['name'] as String,
        principal: m['principal'] as int,
        rate: ((m['rate'] as num?) ?? 0).toDouble(),
        compounding:
            _enumByName(Compounding.values, m['compounding'], Compounding.quarterly),
        startDate: parseDay(m['start_date'] as String),
        maturityDate: parseDay(m['maturity_date'] as String),
        accountId: m['account_id'] as int?,
        closed: (m['closed'] as int?) == 1,
        closedDate: m['closed_date'] == null ? null : parseDay(m['closed_date'] as String),
        closedAmount: m['closed_amount'] as int?,
        closedHow: m['closed_how'] as String?,
        renewedFrom: m['renewed_from'] as int?,
        renewedTo: m['renewed_to'] as int?,
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}

/// Someone the user lends money to or borrows from.
class Person {
  final int? id;
  final String name;
  final int createdAt;

  const Person({this.id, required this.name, required this.createdAt});

  String get initial => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  Map<String, Object?> toMap() => {'id': id, 'name': name, 'created_at': createdAt};

  factory Person.fromMap(Map<String, Object?> m) => Person(
        id: m['id'] as int?,
        name: m['name'] as String,
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}

enum LoanDirection { lent, borrowed }

enum RatePeriod { month, year }

/// Money lent to or borrowed from one person. The amounts live in entries
/// linked by loanId; this holds the terms.
class Loan {
  final int? id;
  final int personId;
  final LoanDirection direction;

  /// Simple interest rate in percent per [period]; 0 = no interest.
  final double rate;
  final RatePeriod period;
  final DateTime? dueDate;
  final String note;

  /// Marked settled by hand (for example the rest was let go).
  final bool settled;
  final int createdAt;

  const Loan({
    this.id,
    required this.personId,
    required this.direction,
    this.rate = 0,
    this.period = RatePeriod.month,
    this.dueDate,
    this.note = '',
    this.settled = false,
    required this.createdAt,
  });

  bool get lent => direction == LoanDirection.lent;
  bool get hasInterest => rate > 0;

  /// "2% a month", "12% a year" or "no interest".
  String get rateLabel {
    if (!hasInterest) return 'no interest';
    final r = rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString();
    return '$r% a ${period == RatePeriod.month ? 'month' : 'year'}';
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'person_id': personId,
        'direction': direction.name,
        'rate': rate,
        'rate_period': period.name,
        'due_date': dueDate == null ? null : dayKey(dueDate!),
        'note': note,
        'settled': settled ? 1 : 0,
        'created_at': createdAt,
      };

  factory Loan.fromMap(Map<String, Object?> m) => Loan(
        id: m['id'] as int?,
        personId: m['person_id'] as int,
        direction: _enumByName(LoanDirection.values, m['direction'], LoanDirection.lent),
        rate: ((m['rate'] as num?) ?? 0).toDouble(),
        period: _enumByName(RatePeriod.values, m['rate_period'], RatePeriod.month),
        dueDate: m['due_date'] == null ? null : parseDay(m['due_date'] as String),
        note: (m['note'] as String?) ?? '',
        settled: (m['settled'] as int?) == 1,
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}

enum PlanKind { income, sip, bill, loan }

extension PlanKindX on PlanKind {
  String get label => switch (this) {
        PlanKind.income => 'Salary',
        PlanKind.sip => 'SIP',
        PlanKind.bill => 'Bill or rent',
        PlanKind.loan => 'Loan EMI',
      };

  /// Settings feature that shows/hides this kind of plan.
  String get feature => switch (this) {
        PlanKind.income => Features.salary,
        PlanKind.sip => Features.sips,
        PlanKind.bill => Features.bills,
        PlanKind.loan => Features.loans,
      };

  bool get isIncome => this == PlanKind.income;
}

/// A fixed monthly money movement that is added to an account automatically
/// on its day: salary, SIP, bill/rent or loan EMI.
class Plan {
  final int? id;
  final PlanKind kind;
  final String name;
  final int amount;

  /// Day of month (1-31). Short months use their last day.
  final int day;
  final int accountId;

  /// First month this plan applies to ('yyyy-MM').
  final String startMonth;

  /// Last month an entry was added for ('yyyy-MM'), or null.
  final String? lastPosted;

  /// Loans only: total number of EMIs.
  final int? tenure;
  final bool active;
  final String category;
  final int createdAt;

  /// SIPs only: the mutual fund the money goes into.
  final int? fundId;

  const Plan({
    this.id,
    required this.kind,
    required this.name,
    required this.amount,
    required this.day,
    required this.accountId,
    required this.startMonth,
    this.lastPosted,
    this.tenure,
    this.active = true,
    required this.category,
    required this.createdAt,
    this.fundId,
  });

  Plan copyWith({String? lastPosted, bool? active}) => Plan(
        id: id,
        kind: kind,
        name: name,
        amount: amount,
        day: day,
        accountId: accountId,
        startMonth: startMonth,
        lastPosted: lastPosted ?? this.lastPosted,
        tenure: tenure,
        active: active ?? this.active,
        category: category,
        createdAt: createdAt,
        fundId: fundId,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'amount': amount,
        'day': day,
        'account_id': accountId,
        'start_month': startMonth,
        'last_posted': lastPosted,
        'tenure': tenure,
        'active': active ? 1 : 0,
        'category': category,
        'created_at': createdAt,
        'fund_id': fundId,
      };

  factory Plan.fromMap(Map<String, Object?> m) => Plan(
        id: m['id'] as int?,
        kind: _enumByName(PlanKind.values, m['kind'], PlanKind.bill),
        name: m['name'] as String,
        amount: m['amount'] as int,
        day: m['day'] as int,
        accountId: m['account_id'] as int,
        startMonth: m['start_month'] as String,
        lastPosted: m['last_posted'] as String?,
        tenure: m['tenure'] as int?,
        active: (m['active'] as int?) != 0,
        category: (m['category'] as String?) ?? 'bills',
        createdAt: (m['created_at'] as int?) ?? 0,
        fundId: m['fund_id'] as int?,
      );
}

/// A mutual fund the user invests in. Funds tracks what was put in (not
/// the market value): [alreadyInvested] from before the app, plus the SIP
/// and lump-sum entries linked by fundId, less withdrawals.
class MutualFund {
  final int? id;
  final String name;

  /// Key from [fundTypes], e.g. 'small' or 'elss'.
  final String type;

  /// Money put in before the fund was added to Funds (not taken from any
  /// account).
  final int alreadyInvested;

  /// Month the investing started, if known.
  final DateTime? started;
  final bool closed;
  final DateTime? closedDate;

  /// What was received when everything was sold.
  final int? closedAmount;
  final int createdAt;

  const MutualFund({
    this.id,
    required this.name,
    this.type = 'other',
    this.alreadyInvested = 0,
    this.started,
    this.closed = false,
    this.closedDate,
    this.closedAmount,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'already_invested': alreadyInvested,
        'started': started == null ? null : monthKey(started!),
        'closed': closed ? 1 : 0,
        'closed_date': closedDate == null ? null : dayKey(closedDate!),
        'closed_amount': closedAmount,
        'created_at': createdAt,
      };

  factory MutualFund.fromMap(Map<String, Object?> m) => MutualFund(
        id: m['id'] as int?,
        name: m['name'] as String,
        type: (m['type'] as String?) ?? 'other',
        alreadyInvested: (m['already_invested'] as int?) ?? 0,
        started: m['started'] == null ? null : parseMonth(m['started'] as String),
        closed: (m['closed'] as int?) == 1,
        closedDate: m['closed_date'] == null ? null : parseDay(m['closed_date'] as String),
        closedAmount: m['closed_amount'] as int?,
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}

/// Kinds of mutual fund: (key, label).
const fundTypes = [
  ('large', 'Large cap'),
  ('mid', 'Mid cap'),
  ('small', 'Small cap'),
  ('flexi', 'Flexi cap'),
  ('multi', 'Multi cap'),
  ('index', 'Index'),
  ('elss', 'ELSS (tax saver)'),
  ('hybrid', 'Hybrid'),
  ('debt', 'Debt'),
  ('other', 'Other'),
];

String fundTypeLabel(String key) {
  for (final (k, label) in fundTypes) {
    if (k == key) return label;
  }
  return 'Other';
}

class Goal {
  final int? id;
  final String name;
  final int target;
  final int saved;
  final int createdAt;

  const Goal({
    this.id,
    required this.name,
    required this.target,
    this.saved = 0,
    required this.createdAt,
  });

  double get progress => target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0);

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'target': target,
        'saved': saved,
        'created_at': createdAt,
      };

  factory Goal.fromMap(Map<String, Object?> m) => Goal(
        id: m['id'] as int?,
        name: m['name'] as String,
        target: m['target'] as int,
        saved: (m['saved'] as int?) ?? 0,
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}

class Budget {
  final int? id;
  final String category;
  final int amount;

  const Budget({this.id, required this.category, required this.amount});

  Map<String, Object?> toMap() => {'id': id, 'category': category, 'amount': amount};

  factory Budget.fromMap(Map<String, Object?> m) => Budget(
        id: m['id'] as int?,
        category: m['category'] as String,
        amount: m['amount'] as int,
      );
}

/// A label that groups entries from any account or month. A trip also has
/// dates (and maybe a budget); while it is on, new entries get it by
/// themselves when [auto] is set.
class Tag {
  final int? id;
  final String name;
  final bool isTrip;

  /// Index into the tag colours.
  final int color;
  final DateTime? start;
  final DateTime? end;

  /// Trip budget in paise, or null.
  final int? budget;
  final bool auto;
  final int createdAt;

  const Tag({
    this.id,
    required this.name,
    this.isTrip = false,
    this.color = 0,
    this.start,
    this.end,
    this.budget,
    this.auto = true,
    required this.createdAt,
  });

  bool get hasDates => isTrip && start != null && end != null;

  /// Whether [day] falls inside the trip's dates.
  bool covers(DateTime day) {
    if (!hasDates) return false;
    final d = dateOnly(day);
    return !d.isBefore(start!) && !d.isAfter(end!);
  }

  int get days => hasDates ? end!.difference(start!).inDays + 1 : 0;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'kind': isTrip ? 'trip' : 'tag',
        'color': color,
        'start_date': start == null ? null : dayKey(start!),
        'end_date': end == null ? null : dayKey(end!),
        'budget': budget,
        'auto': auto ? 1 : 0,
        'created_at': createdAt,
      };

  factory Tag.fromMap(Map<String, Object?> m) => Tag(
        id: m['id'] as int?,
        name: m['name'] as String,
        isTrip: m['kind'] == 'trip',
        color: (m['color'] as int?) ?? 0,
        start: m['start_date'] == null ? null : parseDay(m['start_date'] as String),
        end: m['end_date'] == null ? null : parseDay(m['end_date'] as String),
        budget: m['budget'] as int?,
        auto: (m['auto'] as int?) != 0,
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}

/// Keys for the feature switches in Settings.
class Features {
  Features._();
  static const salary = 'feature_salary';
  static const sips = 'feature_sips';
  static const bills = 'feature_bills';
  static const loans = 'feature_loans';
  static const cards = 'feature_cards';
  static const budgets = 'feature_budgets';
  static const goals = 'feature_goals';
  static const lend = 'feature_lend';
  static const fds = 'feature_fds';
  static const tags = 'feature_tags';

  static const all = [salary, sips, bills, loans, cards, budgets, goals, lend, fds, tags];
}
