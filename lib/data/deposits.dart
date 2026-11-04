// Fixed deposit maths, kept free of Flutter and the database so it can be
// unit tested. Interest compounds every 3 months / month / year (or is
// simple), using the exact number of days.

import 'dart:math' as math;

import '../utils/format.dart';
import 'models.dart';

/// Value of [principal] after [days] at [rate] % a year.
int depositValue(int principal, double rate, Compounding c, int days) {
  if (days <= 0 || rate <= 0) return principal;
  final years = days / 365;
  final r = rate / 100;
  final value = c == Compounding.simple
      ? principal * (1 + r * years)
      : principal * math.pow(1 + r / c.perYear, c.perYear * years);
  // Whole rupees, like a bank statement.
  return (value / 100).round() * 100;
}

/// Total days of the FD.
int fdDays(Fd fd) => fd.maturityDate.difference(fd.startDate).inDays;

/// What the FD is worth on [asOf] (stops growing at maturity).
int fdValueOn(Fd fd, DateTime asOf) {
  final d = dateOnly(asOf);
  final end = d.isAfter(fd.maturityDate) ? fd.maturityDate : d;
  return depositValue(fd.principal, fd.rate, fd.compounding, end.difference(fd.startDate).inDays);
}

/// What the FD pays on its maturity date.
int fdMaturityValue(Fd fd) => depositValue(fd.principal, fd.rate, fd.compounding, fdDays(fd));

/// 0..1 of the time gone.
double fdProgress(Fd fd, DateTime asOf) {
  final total = fdDays(fd);
  if (total <= 0) return 1;
  final done = dateOnly(asOf).difference(fd.startDate).inDays;
  return (done / total).clamp(0.0, 1.0);
}

/// [months] after [d], keeping the day where possible (31 Jan + 1 month =
/// 28/29 Feb).
DateTime addMonthsKeepDay(DateTime d, int months) {
  final first = DateTime(d.year, d.month + months);
  return dueDateIn(first.year, first.month, d.day);
}
