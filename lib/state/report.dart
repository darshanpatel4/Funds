import '../data/models.dart';
import '../utils/format.dart';
import 'app_state.dart';

/// Spending in one category this month and the month before.
class CatLine {
  final String category;
  final int amount;
  final int before;

  const CatLine(this.category, this.amount, this.before);

  /// Change against the month before in percent, or null when there was
  /// nothing before.
  int? get change => before == 0 ? null : ((amount - before) * 100 / before).round();
}

/// A category that went over its limit.
class OverLine {
  final String category;
  final int limit;
  final int over;

  const OverLine(this.category, this.limit, this.over);
}

/// Everything shown in the monthly report. Built from the data on the
/// phone; only the user's own accounts count, as everywhere else.
class MonthReport {
  final DateTime month;
  final DateTime prevMonth;
  final int spent;
  final int prevSpent;
  final int income;

  /// Money put into mutual funds (not spending).
  final int invested;
  final int? budget;
  final int budgetSpent;
  final List<OverLine> overCategories;
  final List<CatLine> categories;
  final List<(DateTime, int)> lastMonths;
  final Entry? biggest;
  final DateTime? heaviestDay;
  final int heaviestAmount;
  final int dailyAverage;
  final int prevDailyAverage;
  final List<int> noSpendDays;

  /// Days of the month looked at (up to today for the current month).
  final int daysCounted;
  final List<(Tag, int, int)> tags;
  final int netWorthEnd;
  final int netWorthChange;
  final int entryCount;

  /// True while the month is not over yet.
  final bool partial;

  const MonthReport({
    required this.month,
    required this.prevMonth,
    required this.spent,
    required this.prevSpent,
    required this.income,
    required this.invested,
    required this.budget,
    required this.budgetSpent,
    required this.overCategories,
    required this.categories,
    required this.lastMonths,
    required this.biggest,
    required this.heaviestDay,
    required this.heaviestAmount,
    required this.dailyAverage,
    required this.prevDailyAverage,
    required this.noSpendDays,
    required this.daysCounted,
    required this.tags,
    required this.netWorthEnd,
    required this.netWorthChange,
    required this.entryCount,
    required this.partial,
  });

  int get saved => income - spent;

  /// Change in spending against the month before, in percent.
  int? get spentChange =>
      prevSpent == 0 ? null : ((spent - prevSpent) * 100 / prevSpent).round();

  int? get savedPercent => income <= 0 ? null : (saved * 100 / income).round();

  /// "8% less than September" style text, or null.
  String? changeText(String Function(DateTime) monthName) {
    final c = spentChange;
    if (c == null) return null;
    final name = monthName(prevMonth);
    if (c == 0) return 'Same as $name';
    return '${c.abs()}% ${c < 0 ? 'less' : 'more'} than $name';
  }

  static MonthReport build(AppState s, DateTime month) {
    final m = DateTime(month.year, month.month);
    final prev = addMonths(m, -1);
    final t = today();
    final partial = m.year == t.year && m.month == t.month;
    final days = partial ? t.day : daysInMonth(m.year, m.month);

    bool inMonth(Entry e, DateTime x) => e.date.year == x.year && e.date.month == x.month;
    final mine = s.entries.where(s.countsEntry);
    final spending = mine.where((e) => e.type == EntryType.expense);

    final cats = <String, int>{};
    final prevCats = <String, int>{};
    final perDay = <int, int>{};
    Entry? biggest;
    var count = 0;
    for (final e in s.entries) {
      if (inMonth(e, m)) count++;
    }
    for (final e in spending) {
      if (inMonth(e, m)) {
        cats[e.category] = (cats[e.category] ?? 0) + e.amount;
        // Highlights leave out automatic plan entries (rent, SIPs, EMIs).
        if (e.planId == null) {
          perDay[e.date.day] = (perDay[e.date.day] ?? 0) + e.amount;
          if (biggest == null || e.amount > biggest.amount) biggest = e;
        }
      } else if (inMonth(e, prev)) {
        prevCats[e.category] = (prevCats[e.category] ?? 0) + e.amount;
      }
    }
    final keys = cats.keys.toList()..sort((a, b) => cats[b]!.compareTo(cats[a]!));

    var heavyDay = 0;
    var heavy = 0;
    perDay.forEach((d, v) {
      if (v > heavy) {
        heavy = v;
        heavyDay = d;
      }
    });

    final spent = s.expenseInMonth(m);
    final prevSpent = s.expenseInMonth(prev);

    final over = <OverLine>[];
    if (s.feature(Features.budgets)) {
      for (final b in s.budgets) {
        final used = s.spentInCategory(b.category, m);
        if (used > b.amount) over.add(OverLine(b.category, b.amount, used - b.amount));
      }
    }

    final tagLines = <(Tag, int, int)>[];
    if (s.feature(Features.tags)) {
      for (final tag in s.tags) {
        final list = s.entriesWithTag(tag.id!).where((e) => inMonth(e, m));
        final sum = list
            .where((e) => e.type == EntryType.expense)
            .fold(0, (a, e) => a + e.amount);
        if (sum > 0) tagLines.add((tag, sum, list.length));
      }
      tagLines.sort((a, b) => b.$2.compareTo(a.$2));
    }

    final end = partial ? t : DateTime(m.year, m.month + 1, 0);
    final worthEnd = s.netWorthOn(partial ? null : end);
    final worthBefore = s.netWorthOn(DateTime(m.year, m.month, 0));

    return MonthReport(
      month: m,
      prevMonth: prev,
      spent: spent,
      prevSpent: prevSpent,
      income: s.incomeInMonth(m),
      invested: mine
          .where((e) => e.type == EntryType.investOut && inMonth(e, m))
          .fold(0, (a, e) => a + e.amount),
      budget: s.feature(Features.budgets) ? s.overallBudget : null,
      budgetSpent: s.overallSpent(m),
      overCategories: over,
      categories: [for (final k in keys) CatLine(k, cats[k]!, prevCats[k] ?? 0)],
      lastMonths: [
        for (var i = 5; i >= 0; i--)
          (addMonths(m, -i), s.expenseInMonth(addMonths(m, -i))),
      ],
      biggest: biggest,
      heaviestDay: heavyDay == 0 ? null : DateTime(m.year, m.month, heavyDay),
      heaviestAmount: heavy,
      dailyAverage: days == 0 ? 0 : (spent / days / 100).round() * 100,
      prevDailyAverage: (prevSpent / daysInMonth(prev.year, prev.month) / 100).round() * 100,
      noSpendDays: [
        for (var d = 1; d <= days; d++)
          if (!perDay.containsKey(d)) d,
      ],
      daysCounted: days,
      tags: tagLines,
      netWorthEnd: worthEnd,
      netWorthChange: worthEnd - worthBefore,
      entryCount: count,
      partial: partial,
    );
  }
}
