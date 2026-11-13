import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/categories.dart';
import '../services/backup_service.dart';
import '../services/report_export.dart';
import '../state/app_state.dart';
import '../state/report.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';
import 'net_worth_screen.dart';
import 'tags_screen.dart';

Future<void> openReport(BuildContext context, DateTime month) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => MonthReportScreen(month: month)));

/// The month before this one, whose report is shown on the 1st.
DateTime lastMonth() {
  final t = today();
  return addMonths(DateTime(t.year, t.month), -1);
}

String reportSeenKey(DateTime month) => 'report_seen_${monthKey(month)}';

class MonthReportScreen extends StatefulWidget {
  const MonthReportScreen({super.key, required this.month});

  final DateTime month;

  @override
  State<MonthReportScreen> createState() => _MonthReportScreenState();
}

class _MonthReportScreenState extends State<MonthReportScreen> {
  late DateTime _month = DateTime(widget.month.year, widget.month.month);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen());
  }

  /// Opening last month's report hides its card on Home.
  void _markSeen() {
    final s = context.read<AppState>();
    final key = reportSeenKey(_month);
    if (_month == lastMonth() && s.setting(key) != '1') s.setSetting(key, '1');
  }

  DateTime get _first {
    final s = context.read<AppState>();
    final t = today();
    var first = DateTime(t.year, t.month);
    if (s.entries.isNotEmpty) {
      final o = s.entries.last.date;
      final m = DateTime(o.year, o.month);
      if (m.isBefore(first)) first = m;
    }
    return first;
  }

  void _go(int delta) {
    setState(() => _month = addMonths(_month, delta));
    _markSeen();
  }

  Future<void> _export(AppState s, MonthReport r, {required bool pdf}) async {
    setState(() => _busy = true);
    try {
      final name = '${ReportExport.baseName(r.month)}.${pdf ? 'pdf' : 'csv'}';
      final mime = pdf ? 'application/pdf' : 'text/csv';
      final bytes = pdf ? await ReportExport.pdf(s, r) : ReportExport.csv(s, r.month);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes, flush: true);

      Future<void> share() async {
        s.externalActivity = true;
        try {
          await SharePlus.instance.share(ShareParams(
            files: [XFile(file.path, mimeType: mime, name: name)],
            subject: 'Funds report · ${monthTitle(r.month)}',
          ));
        } finally {
          s.externalActivity = false;
        }
      }

      if (await Downloads.supported()) {
        await Downloads.saveFile(name, bytes, mime);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('Saved to Downloads/Funds as $name'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(label: 'Share', onPressed: share),
          ));
      } else {
        await share();
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not make the file ($e).');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final r = MonthReport.build(s, _month);
    final t = today();
    final canNext = _month.isBefore(DateTime(t.year, t.month));
    final canPrev = _month.isAfter(_first);
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);
    final monthName = DateFormat('MMMM');

    return Scaffold(
      appBar: AppBar(
        title: Text('${monthTitle(_month)} report'),
        actions: [
          IconButton(
            tooltip: 'Previous month',
            onPressed: canPrev ? () => _go(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: canNext ? () => _go(1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            if (r.partial)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                    'This month is not over yet: 1 – ${r.daysCounted} ${DateFormat('MMM').format(_month)}.',
                    style: ts(13, weight: FontWeight.w600, color: C.muted)),
              ),
            _Summary(r: r, m: m, monthName: monthName),
            if (r.budget != null) ...[
              const SizedBox(height: 14),
              _BudgetBox(r: r, m: m),
            ],
            if (r.categories.isNotEmpty) ...[
              const SizedBox(height: 14),
              _WhereItWent(r: r, monthName: monthName),
            ],
            const SizedBox(height: 14),
            _SixMonths(r: r, budget: r.budget, hidden: s.amountsHidden),
            const SizedBox(height: 14),
            _Highlights(r: r, m: m, s: s),
            const SizedBox(height: 14),
            _NetWorthLink(r: r, m: m),
            const SizedBox(height: 24),
            Text('Save this report', style: ts(15, weight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _busy ? null : () => _export(s, r, pdf: true),
                      style: FilledButton.styleFrom(
                        backgroundColor: C.accent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('PDF', style: ts(14, weight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlineBtn('Excel (all entries)',
                      onPressed: _busy ? null : () => _export(s, r, pdf: false)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Saved to Downloads/Funds, then you can share it (for example with your CA or family). '
              'Made on the phone; nothing is uploaded.',
              style: ts(12, color: C.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.r, required this.m, required this.monthName});

  final MonthReport r;
  final String Function(int) m;
  final DateFormat monthName;

  @override
  Widget build(BuildContext context) {
    final change = r.spentChange;
    final text = r.changeText(monthName.format);
    final less = change != null && change <= 0;
    return CardBox(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You spent', style: ts(13, weight: FontWeight.w700, color: C.muted)),
          const SizedBox(height: 4),
          Text(m(r.spent), style: ts(36, weight: FontWeight.w800, letterSpacing: -1.2)),
          if (text != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: less ? const Color(0xFF0E2A1A) : const Color(0xFF2E0F14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${change == 0 ? '' : less ? '↓ ' : '↑ '}$text (${m(r.prevSpent)})',
                style: ts(13, weight: FontWeight.w800, color: less ? C.income : C.expense),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Tile('Money in', m(r.income), C.income)),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  r.saved >= 0 ? 'You saved' : 'Spent more than came in',
                  '${m(r.saved.abs())}${r.savedPercent == null || r.saved < 0 ? '' : ' · ${r.savedPercent}%'}',
                  r.saved >= 0 ? C.text : C.expense,
                ),
              ),
            ],
          ),
          if (r.invested > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.trending_up_rounded, size: 16, color: C.transfer),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: 'You invested ${m(r.invested)}',
                          style: ts(13, weight: FontWeight.w800, color: C.transfer)),
                      TextSpan(
                          text: ' in SIPs & funds. It is part of what you saved, not spending.',
                          style: ts(13, weight: FontWeight.w600, color: C.muted)),
                    ]),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: C.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(12, weight: FontWeight.w600, color: C.muted)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(18, weight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _BudgetBox extends StatelessWidget {
  const _BudgetBox({required this.r, required this.m});

  final MonthReport r;
  final String Function(int) m;

  @override
  Widget build(BuildContext context) {
    final budget = r.budget!;
    final within = r.budgetSpent <= budget;
    return CardBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Monthly budget', style: ts(15, weight: FontWeight.w800))),
              if (within && !r.partial) ...[
                const Icon(Icons.check_circle_rounded, size: 16, color: C.income),
                const SizedBox(width: 4),
              ],
              Text(within ? (r.partial ? 'Within so far' : 'Stayed within') : 'Went over',
                  style: ts(13, weight: FontWeight.w800, color: within ? C.income : C.expense)),
            ],
          ),
          const SizedBox(height: 10),
          ProgressBar(r.budgetSpent / budget,
              color: within ? C.accent : C.expense, height: 10),
          const SizedBox(height: 8),
          Text(
            within
                ? '${m(r.budgetSpent)} of ${m(budget)} used · ${m(budget - r.budgetSpent)} ${r.partial ? 'left' : 'left over'}'
                : '${m(r.budgetSpent)} of ${m(budget)} · ${m(r.budgetSpent - budget)} over',
            style: ts(13, weight: FontWeight.w600, color: C.muted),
          ),
          for (final o in r.overCategories) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: C.line),
            ),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '${catFor(o.category).label} went over ',
                    style: ts(13, weight: FontWeight.w800, color: C.expense)),
                TextSpan(
                    text: 'its ${m(o.limit)} limit by ${m(o.over)}.',
                    style: ts(13, weight: FontWeight.w600, color: C.muted)),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _WhereItWent extends StatelessWidget {
  const _WhereItWent({required this.r, required this.monthName});

  final MonthReport r;
  final DateFormat monthName;

  @override
  Widget build(BuildContext context) {
    final top = r.categories.first.amount;
    return CardBox(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Where it went', style: ts(15, weight: FontWeight.w800))),
              Text('vs ${monthName.format(r.prevMonth)}',
                  style: ts(12, weight: FontWeight.w700, color: C.muted)),
            ],
          ),
          const SizedBox(height: 6),
          for (final c in r.categories)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(catFor(c.category).icon, size: 18, color: catFor(c.category).color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(catFor(c.category).label,
                            style: ts(14, weight: FontWeight.w700)),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          c.change == null
                              ? 'new'
                              : c.change == 0
                                  ? 'same'
                                  : '${c.change! > 0 ? '↑' : '↓'}${c.change!.abs()}%',
                          textAlign: TextAlign.right,
                          style: ts(12,
                              weight: FontWeight.w800,
                              color: c.change == null || c.change == 0
                                  ? C.faint
                                  : c.change! > 0
                                      ? C.expense
                                      : C.income),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Money(c.amount, size: 14),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: ProgressBar(c.amount / top, color: catFor(c.category).color, height: 6),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SixMonths extends StatelessWidget {
  const _SixMonths({required this.r, required this.budget, required this.hidden});

  final MonthReport r;
  final int? budget;
  final bool hidden;

  String _short(int paise) {
    if (hidden) return '••';
    final v = paise / 100;
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final values = r.lastMonths.map((x) => x.$2).toList();
    final shown = values.where((v) => v > 0).toList();
    final avg = shown.isEmpty ? 0 : shown.fold(0, (a, b) => a + b) ~/ shown.length;
    var top = values.fold(0, (a, b) => b > a ? b : a);
    if (budget != null && budget! > top) top = budget!;
    const area = 96.0;
    String m(int v) => hidden ? '₹••••' : money((v / 100).round() * 100);

    return CardBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Last 6 months', style: ts(15, weight: FontWeight.w800))),
              Text('Average ${m(avg)}', style: ts(12, weight: FontWeight.w700, color: C.muted)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: area + 18,
            child: Stack(
              children: [
                if (budget != null && top > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: area * budget! / top,
                    child: const _DashedLine(),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < values.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: Semantics(
                          label: '${monthTitle(r.lastMonths[i].$1)}: ${hidden ? 'hidden' : money(values[i])}',
                          excludeSemantics: true,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(_short(values[i]),
                                  maxLines: 1,
                                  style: ts(10,
                                      weight: FontWeight.w800,
                                      color: i == values.length - 1 ? C.text : C.muted)),
                              const SizedBox(height: 4),
                              Container(
                                height: top == 0 ? 4 : (area * values[i] / top).clamp(4, area).toDouble(),
                                decoration: BoxDecoration(
                                  color: i == values.length - 1 ? C.accent : C.border,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < values.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: Text(DateFormat('MMM').format(r.lastMonths[i].$1),
                      textAlign: TextAlign.center,
                      style: ts(12,
                          weight: FontWeight.w700,
                          color: i == values.length - 1 ? C.text : C.muted)),
                ),
              ],
            ],
          ),
          if (budget != null) ...[
            const SizedBox(height: 10),
            Text('Dashed line: your ${m(budget!)} budget.',
                style: ts(12, weight: FontWeight.w600, color: C.muted)),
          ],
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = (c.maxWidth / 8).floor();
      return Row(
        children: [
          for (var i = 0; i < n; i++)
            Container(width: 4, height: 1, margin: const EdgeInsets.only(right: 4), color: C.faint),
        ],
      );
    });
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights({required this.r, required this.m, required this.s});

  final MonthReport r;
  final String Function(int) m;
  final AppState s;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String, String, VoidCallback?)>[];
    final b = r.biggest;
    if (b != null) {
      rows.add((
        'Biggest expense',
        m(b.amount),
        '${b.note.isEmpty ? catFor(b.category).label : b.note} · ${shortDate(b.date)}',
        null,
      ));
    }
    if (r.heaviestDay != null) {
      rows.add(('Heaviest day', m(r.heaviestAmount), DateFormat('EEE d MMM').format(r.heaviestDay!), null));
    }
    rows.add((
      'Daily average',
      m(r.dailyAverage),
      r.prevDailyAverage > 0 ? '${DateFormat('MMM').format(r.prevMonth)}: ${m(r.prevDailyAverage)}' : '',
      null,
    ));
    final nd = r.noSpendDays;
    rows.add((
      'No-spend days',
      '${nd.length} ${nd.length == 1 ? 'day' : 'days'}',
      nd.isEmpty || nd.length > 6 ? '' : _joinDays(nd, r.month),
      null,
    ));
    for (final (t, sum, n) in r.tags.take(3)) {
      rows.add(('#${t.name}', m(sum), '$n ${n == 1 ? 'entry' : 'entries'}',
          () => openTag(context, t.id!)));
    }

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Highlights', style: ts(15, weight: FontWeight.w800)),
          ),
          for (final (label, value, sub, onTap) in rows)
            InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(label, style: ts(14, weight: FontWeight.w600, color: C.muted)),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(value, style: ts(14, weight: FontWeight.w800)),
                          if (sub.isNotEmpty)
                            Text(sub,
                                textAlign: TextAlign.right,
                                style: ts(12, weight: FontWeight.w600, color: C.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _joinDays(List<int> days, DateTime month) {
    final mon = DateFormat('MMM').format(month);
    if (days.length == 1) return '${days.first} $mon';
    return '${days.sublist(0, days.length - 1).join(', ')} and ${days.last} $mon';
  }
}

class _NetWorthLink extends StatelessWidget {
  const _NetWorthLink({required this.r, required this.m});

  final MonthReport r;
  final String Function(int) m;

  @override
  Widget build(BuildContext context) {
    final up = r.netWorthChange >= 0;
    final label = r.partial
        ? 'Net worth today'
        : 'Net worth on ${DateFormat('d MMM').format(DateTime(r.month.year, r.month.month + 1, 0))}';
    return Material(
      color: C.accentTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: C.accentDeep),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => openNetWorth(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: ts(13, weight: FontWeight.w700, color: C.onAccentSoft)),
                    const SizedBox(height: 2),
                    Text(m(r.netWorthEnd), style: ts(20, weight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('${up ? '+' : '−'}${m(r.netWorthChange.abs())} this month',
                        style: ts(13, weight: FontWeight.w800, color: up ? C.income : C.expense)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
