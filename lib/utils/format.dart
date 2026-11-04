import 'package:intl/intl.dart';

final _inr = NumberFormat.decimalPattern('en_IN');

/// Formats an amount stored in paise as Indian rupees, e.g. 8823500 -> ₹88,235.
/// Negative amounts use a real minus sign (−₹655). [plus] adds + to positives.
String money(int paise, {bool plus = false}) {
  final neg = paise < 0;
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final p = abs % 100;
  var s = '₹${_inr.format(rupees)}';
  if (p != 0) s += '.${p.toString().padLeft(2, '0')}';
  if (neg) return '−$s';
  if (plus && paise > 0) return '+$s';
  return s;
}

/// Parses user input such as "1,250.50" or "-300" into paise. Returns null
/// when the text is not a number.
int? parseAmount(String text, {bool allowNegative = false}) {
  var t = text.replaceAll(',', '').replaceAll('₹', '').replaceAll('−', '-').trim();
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v.isNaN || v.isInfinite) return null;
  if (!allowNegative && v < 0) return null;
  return (v * 100).round();
}

/// Text for an amount input field (no symbol, no grouping).
String amountInput(int paise) {
  final abs = paise.abs();
  final r = abs ~/ 100;
  final p = abs % 100;
  final s = p == 0 ? '$r' : '$r.${p.toString().padLeft(2, '0')}';
  return paise < 0 ? '-$s' : s;
}

// ---------------------------------------------------------------- dates

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime today() => dateOnly(DateTime.now());

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String monthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

DateTime parseMonth(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]));
}

DateTime addMonths(DateTime month, int n) => DateTime(month.year, month.month + n);

int monthsBetween(DateTime a, DateTime b) =>
    (b.year - a.year) * 12 + (b.month - a.month);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// The given day-of-month inside [year]/[month], clamped (31 -> 30 Nov).
DateTime dueDateIn(int year, int month, int day) =>
    DateTime(year, month, day.clamp(1, daysInMonth(year, month)));

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Today", "Yesterday", "2 Nov" or "2 Nov 2025".
String friendlyDay(DateTime d, {DateTime? now}) {
  final t = dateOnly(now ?? DateTime.now());
  final x = dateOnly(d);
  if (sameDay(x, t)) return 'Today';
  if (sameDay(x, t.subtract(const Duration(days: 1)))) return 'Yesterday';
  if (x.year == t.year) return DateFormat('d MMM').format(x);
  return DateFormat('d MMM y').format(x);
}

String shortDate(DateTime d) => DateFormat('d MMM').format(d);

String longDay(DateTime d) => DateFormat('EEEE, d MMM').format(d);

String monthTitle(DateTime d) => DateFormat('MMMM y').format(d);

/// "Today", "Tomorrow", "In 4 days".
String daysUntil(DateTime d, {DateTime? now}) {
  final n = dateOnly(d).difference(dateOnly(now ?? DateTime.now())).inDays;
  if (n <= 0) return 'Today';
  if (n == 1) return 'Tomorrow';
  return 'In $n days';
}

/// 1 -> 1st, 2 -> 2nd, 23 -> 23rd, 11 -> 11th.
String ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

String greeting(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}
