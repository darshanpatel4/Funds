// Pure date logic for plans (salary, SIPs, bills, EMIs). Kept free of
// Flutter and the database so it can be unit tested.

import '../utils/format.dart';
import 'models.dart';

/// First month a new plan should run in: this month if its day has not
/// passed yet, otherwise next month.
String firstMonthFor(int day, DateTime now) {
  final t = dateOnly(now);
  final thisMonth = DateTime(t.year, t.month);
  final due = dueDateIn(t.year, t.month, day);
  return monthKey(due.isBefore(t) ? addMonths(thisMonth, 1) : thisMonth);
}

/// Next month that has not been added yet (may be past or future).
DateTime nextMonthToPost(Plan p) => p.lastPosted == null
    ? parseMonth(p.startMonth)
    : addMonths(parseMonth(p.lastPosted!), 1);

/// How many instalments have been added (or marked as already paid).
int paidCount(Plan p) => p.lastPosted == null
    ? 0
    : monthsBetween(parseMonth(p.startMonth), parseMonth(p.lastPosted!)) + 1;

/// True when a loan has had all of its EMIs.
bool isFinished(Plan p) => p.tenure != null && paidCount(p) >= p.tenure!;

/// Months whose due date is on or before [now] and have not been added yet.
List<DateTime> dueMonths(Plan p, DateTime now) {
  if (!p.active) return const [];
  final t = dateOnly(now);
  final start = parseMonth(p.startMonth);
  final out = <DateTime>[];
  var m = nextMonthToPost(p);
  while (out.length < 240) {
    if (p.tenure != null && monthsBetween(start, m) >= p.tenure!) break;
    final due = dueDateIn(m.year, m.month, p.day);
    if (due.isAfter(t)) break;
    out.add(m);
    m = addMonths(m, 1);
  }
  return out;
}

/// Next date this plan will add an entry, or null when paused or finished.
DateTime? nextDueDate(Plan p) {
  if (!p.active || isFinished(p)) return null;
  final m = nextMonthToPost(p);
  return dueDateIn(m.year, m.month, p.day);
}

/// Category used for the automatic entry.
String planCategory(Plan p) => switch (p.kind) {
      PlanKind.income => 'salary',
      PlanKind.sip => 'investment',
      PlanKind.loan => 'emi',
      PlanKind.bill => p.category,
    };
