import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/categories.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../state/report.dart';
import '../utils/format.dart';

/// Turns a monthly report into a PDF or an Excel-readable (CSV) file. Made
/// on the phone; nothing is uploaded.
class ReportExport {
  ReportExport._();

  static String baseName(DateTime month) =>
      'funds-report-${DateFormat('MMMM-y').format(month).toLowerCase()}';

  static String _catName(String key) => key == 'other_in' ? 'Other income' : catFor(key).label;

  // ------------------------------------------------------------------ CSV

  /// Every entry of the month, one per row. Opens in Excel or Google
  /// Sheets. Amounts are plain numbers (minus = money out).
  static List<int> csv(AppState s, DateTime month) {
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    String rupees(int paise) => (paise / 100).toStringAsFixed(2);
    final rows = <String>[
      ['Date', 'Type', 'Category', 'Note', 'Account', 'To account', 'Amount (₹)', 'Counted', 'Tags']
          .map(q)
          .join(','),
    ];
    final list = s.entries
        .where((e) => e.date.year == month.year && e.date.month == month.month)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final e in list) {
      final signed = switch (e.type) {
        EntryType.income || EntryType.loanIn || EntryType.depositIn => e.amount,
        EntryType.transfer => e.amount,
        _ => -e.amount,
      };
      final type = switch (e.type) {
        EntryType.expense => 'Expense',
        EntryType.income => 'Income',
        EntryType.transfer => 'Transfer',
        EntryType.loanOut || EntryType.loanIn => 'Lend & borrow',
        EntryType.depositOut || EntryType.depositIn => 'Fixed deposit',
      };
      final note = e.loanId != null
          ? s.loanEntryTitle(e)
          : e.fdId != null
              ? s.fdEntryTitle(e)
              : e.note;
      rows.add([
        q(dayKey(e.date)),
        q(type),
        q(catForEntry(e).key == 'other_in' ? 'Other income' : catForEntry(e).label),
        q(note),
        q(s.accountName(e.accountId)),
        q(e.toAccountId == null ? '' : s.accountName(e.toAccountId)),
        rupees(signed),
        q(s.countsEntry(e) ? 'Yes' : 'No'),
        q(s.tagsOf(e.id).map((t) => s.tag(t)?.name ?? '').where((n) => n.isNotEmpty).join('; ')),
      ].join(','));
    }
    // The byte order mark makes Excel read ₹ and other letters correctly.
    return [0xEF, 0xBB, 0xBF, ...utf8.encode(rows.join('\r\n'))];
  }

  // ------------------------------------------------------------------ PDF

  static Future<Uint8List> pdf(AppState s, MonthReport r) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/Manrope-Medium.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/Manrope-ExtraBold.ttf'));
    final doc = pw.Document(
      title: 'Funds report ${monthTitle(r.month)}',
      creator: 'Funds',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    const accent = PdfColor.fromInt(0xFF0077C5);
    const muted = PdfColor.fromInt(0xFF6B6B6B);
    const line = PdfColor.fromInt(0xFFDDDDDD);
    const green = PdfColor.fromInt(0xFF15803D);
    const red = PdfColor.fromInt(0xFFC81E2B);
    final monthName = DateFormat('MMMM');
    final small = pw.TextStyle(fontSize: 9, color: muted);

    pw.Widget heading(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
          child: pw.Text(t, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        );

    pw.Widget table(List<String> head, List<List<String>> rows,
            {List<int> right = const [], Map<int, PdfColor Function(String)>? colors}) =>
        pw.TableHelper.fromTextArray(
          headers: head,
          data: rows,
          border: null,
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: muted),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: line))),
          rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.5))),
          cellPadding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          cellAlignments: {for (final i in right) i: pw.Alignment.centerRight},
          headerAlignments: {
            for (var i = 0; i < head.length; i++)
              i: right.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
          },
          textStyleBuilder: colors == null
              ? null
              : (col, data, row) {
                  final f = colors[col];
                  if (f == null || row == 0) return null;
                  return pw.TextStyle(fontSize: 10, color: f(data.toString()));
                },
        );

    String pct(int? c) => c == null ? '' : c == 0 ? 'same' : '${c > 0 ? '+' : '−'}${c.abs()}%';

    final summary = <List<String>>[
      ['You spent', money(r.spent)],
      ['Money in', money(r.income)],
      ['You saved', '${money(r.saved)}${r.savedPercent == null ? '' : ' (${r.savedPercent}%)'}'],
      if (r.changeText(monthName.format) != null)
        ['Compared with ${monthName.format(r.prevMonth)}', r.changeText(monthName.format)!],
      if (r.budget != null)
        [
          'Monthly budget',
          '${money(r.budgetSpent)} of ${money(r.budget!)} · '
              '${r.budgetSpent <= r.budget! ? '${money(r.budget! - r.budgetSpent)} left' : '${money(r.budgetSpent - r.budget!)} over'}',
        ],
      ['Net worth at the end', '${money(r.netWorthEnd)} (${money(r.netWorthChange, plus: true)} this month)'],
    ];

    final entries = s.entries
        .where((e) => e.date.year == r.month.year && e.date.month == r.month.month)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Made with Funds on ${DateFormat('d MMM y').format(DateTime.now())}', style: small),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: small),
        ],
      ),
      build: (ctx) => [
        pw.Text('FUNDS', style: pw.TextStyle(fontSize: 10, color: accent, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
        pw.SizedBox(height: 4),
        pw.Text('${monthTitle(r.month)} report',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        if (r.partial)
          pw.Text('Month not over yet: 1 – ${r.daysCounted} ${DateFormat('MMM').format(r.month)}',
              style: small),
        pw.SizedBox(height: 6),
        pw.Text('Only your own accounts are counted. Transfers, FDs and money lent or borrowed are not spending.',
            style: small),
        heading('Summary'),
        table(const ['', ''], summary, right: const [1]),
        if (r.categories.isNotEmpty) ...[
          heading('Where it went'),
          table(
            ['Category', 'Amount', 'vs ${monthName.format(r.prevMonth)}'],
            [
              for (final c in r.categories)
                [_catName(c.category), money(c.amount), c.change == null ? 'new' : pct(c.change)],
            ],
            right: const [1, 2],
            colors: {
              2: (v) => v.startsWith('+') ? red : v.startsWith('−') ? green : muted,
            },
          ),
        ],
        if (r.overCategories.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          for (final o in r.overCategories)
            pw.Text('${_catName(o.category)} went over its ${money(o.limit)} limit by ${money(o.over)}.',
                style: const pw.TextStyle(fontSize: 10, color: red)),
        ],
        heading('Last 6 months'),
        table(
          const ['Month', 'Spent'],
          [for (final (m, v) in r.lastMonths) [monthTitle(m), money(v)]],
          right: const [1],
        ),
        heading('Highlights'),
        table(const ['', ''], [
          if (r.biggest != null)
            [
              'Biggest expense',
              '${money(r.biggest!.amount)} · ${r.biggest!.note.isEmpty ? _catName(r.biggest!.category) : r.biggest!.note} · ${shortDate(r.biggest!.date)}',
            ],
          if (r.heaviestDay != null)
            ['Heaviest day', '${money(r.heaviestAmount)} · ${DateFormat('EEE d MMM').format(r.heaviestDay!)}'],
          ['Daily average', money(r.dailyAverage)],
          ['No-spend days', '${r.noSpendDays.length}'],
          for (final (t, sum, n) in r.tags.take(5))
            ['#${t.name}', '${money(sum)} · $n ${n == 1 ? 'entry' : 'entries'}'],
        ], right: const [1]),
        heading('All entries (${entries.length})'),
        if (entries.isEmpty)
          pw.Text('No entries this month.', style: small)
        else
          table(
            const ['Date', 'Entry', 'Category', 'Account', 'Amount'],
            [
              for (final e in entries)
                [
                  DateFormat('d MMM').format(e.date),
                  e.loanId != null
                      ? s.loanEntryTitle(e)
                      : e.fdId != null
                          ? s.fdEntryTitle(e)
                          : (e.note.isEmpty ? catForEntry(e).label : e.note),
                  e.type == EntryType.transfer ? 'Transfer' : _catName(catForEntry(e).key),
                  e.type == EntryType.transfer
                      ? '${s.accountName(e.accountId)} → ${s.accountName(e.toAccountId)}'
                      : s.accountName(e.accountId),
                  switch (e.type) {
                    EntryType.income || EntryType.loanIn || EntryType.depositIn => money(e.amount, plus: true),
                    EntryType.transfer => money(e.amount),
                    _ => money(-e.amount),
                  },
                ],
            ],
            right: const [4],
            colors: {4: (v) => v.startsWith('+') ? green : v.startsWith('−') ? red : PdfColors.black},
          ),
      ],
    ));
    return doc.save();
  }
}
