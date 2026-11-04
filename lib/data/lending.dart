// Pure maths for lend & borrow: what is owed, interest built up, and how a
// payment is split. Simple interest, worked out per day, and payments pay
// the interest first, then the amount lent. Kept free of Flutter and the
// database so it can be unit tested.

import '../utils/format.dart';
import 'models.dart';

class LoanStatus {
  /// Total lent (or borrowed), including "lent more".
  final int given;

  /// Part of [given] already paid back.
  final int returned;

  /// Part of [given] still to be paid back.
  final int principal;

  /// Interest built up and not paid yet.
  final int interestDue;

  /// Interest already paid.
  final int interestPaid;

  /// First day money was lent or borrowed.
  final DateTime? since;

  const LoanStatus({
    required this.given,
    required this.returned,
    required this.principal,
    required this.interestDue,
    required this.interestPaid,
    this.since,
  });

  /// Everything still owed: the rest of the amount plus unpaid interest.
  int get total => principal + interestDue;

  /// All interest so far, paid or not.
  int get interestTotal => interestDue + interestPaid;

  /// Everything paid back so far, interest included.
  int get paidBack => returned + interestPaid;

  bool get cleared => given > 0 && total <= 0;
}

/// Money going out when lending (or paying back what you borrowed)...
bool isGive(Loan loan, Entry e) =>
    loan.lent ? e.type == EntryType.loanOut : e.type == EntryType.loanIn;

/// ...and money coming back.
bool isPrincipalBack(Loan loan, Entry e) =>
    loan.lent ? e.type == EntryType.loanIn : e.type == EntryType.loanOut;

/// Interest paid on the loan is a normal income or expense entry.
bool isInterestPayment(Loan loan, Entry e) =>
    loan.lent ? e.type == EntryType.income : e.type == EntryType.expense;

/// Interest per rupee per day.
double dailyRate(Loan loan) {
  if (!loan.hasInterest) return 0;
  return loan.rate / 100 / (loan.period == RatePeriod.year ? 365 : 30);
}

/// Interest for one month on [amount] paise.
int monthlyInterest(Loan loan, int amount) =>
    (amount * dailyRate(loan) * 30 / 100).round() * 100;

/// The state of [loan] on [asOf], from its [entries].
LoanStatus loanStatus(Loan loan, Iterable<Entry> entries, DateTime asOf) {
  final end = dateOnly(asOf);
  final list = entries.where((e) => e.loanId == loan.id && !e.date.isAfter(end)).toList()
    ..sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });

  final d = dailyRate(loan);
  var given = 0;
  var returned = 0;
  var principal = 0;
  var interestPaid = 0;
  var accrued = 0.0;
  DateTime? last;
  DateTime? since;

  void accrueTo(DateTime day) {
    final x = dateOnly(day);
    if (last != null && x.isAfter(last!)) {
      accrued += principal * d * x.difference(last!).inDays;
    }
    if (last == null || x.isAfter(last!)) last = x;
  }

  for (final e in list) {
    accrueTo(e.date);
    if (isGive(loan, e)) {
      given += e.amount;
      principal += e.amount;
      since ??= dateOnly(e.date);
    } else if (isPrincipalBack(loan, e)) {
      returned += e.amount;
      principal -= e.amount;
      if (principal < 0) principal = 0;
    } else if (isInterestPayment(loan, e)) {
      interestPaid += e.amount;
      accrued -= e.amount;
      if (accrued < 0) accrued = 0;
    }
  }
  accrueTo(end);

  return LoanStatus(
    given: given,
    returned: returned,
    principal: principal,
    // Interest is shown and paid in whole rupees.
    interestDue: (accrued / 100).round() * 100,
    interestPaid: interestPaid,
    since: since,
  );
}

/// Splits a payment of [amount] into (interest, principal): interest is
/// paid first. Anything above what is owed is not counted.
(int, int) splitPayment(LoanStatus status, int amount) {
  final interest = amount < status.interestDue ? amount : status.interestDue;
  final rest = amount - interest;
  final principal = rest < status.principal ? rest : status.principal;
  return (interest, principal);
}
