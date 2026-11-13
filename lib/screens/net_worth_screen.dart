import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';
import 'accounts_screen.dart';
import 'fd_screen.dart';
import 'lend_screen.dart';
import 'sip_screen.dart';

Future<void> openNetWorth(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => const NetWorthScreen()));

(IconData, Color) _look(String kind) => switch (kind) {
      'bank' => (Icons.account_balance_outlined, C.blue),
      'cash' => (Icons.payments_outlined, C.teal),
      'wallet' => (Icons.account_balance_wallet_outlined, C.purple),
      'card' => (Icons.credit_card_rounded, C.pink),
      'fd' => (Icons.lock_outline_rounded, C.yellow),
      'mf' => (Icons.trending_up_rounded, C.transfer),
      'lent' => (Icons.south_west_rounded, C.income),
      _ => (Icons.north_east_rounded, C.orange),
    };

/// Everything you have minus what you owe, and how it changed.
class NetWorthScreen extends StatefulWidget {
  const NetWorthScreen({super.key});

  @override
  State<NetWorthScreen> createState() => _NetWorthScreenState();
}

class _NetWorthScreenState extends State<NetWorthScreen> {
  /// 6, 12 or 0 (= all).
  int _range = 12;

  void _openPart(BuildContext context, String kind) {
    switch (kind) {
      case 'fd':
        openFdList(context);
      case 'mf':
        openSips(context);
      case 'lent':
      case 'borrowed':
        openLend(context);
      default:
        openAccounts(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final parts = s.netWorthParts();
    final total = parts.fold(0, (a, p) => a + p.amount);
    final have = parts.where((p) => p.amount > 0).toList();
    final owe = parts.where((p) => p.amount < 0).toList();
    final months = _range == 0 ? s.monthsOfData : _range;
    final history = s.netWorthHistory(months);
    final lastMonthEnd = history.length >= 2 ? history[history.length - 2] : null;
    final change = lastMonthEnd == null ? 0 : total - lastMonthEnd.$2;
    final growth = total - history.first.$2;
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);
    String signed(int v) => '${v >= 0 ? '+' : '−'}${m(v.abs())}';

    final notCounted = s.visibleAccounts.where((a) => !a.counted).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Net worth')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Text('Everything you have, minus what you owe',
                textAlign: TextAlign.center, style: ts(13, weight: FontWeight.w700, color: C.muted)),
            const SizedBox(height: 4),
            Center(child: Money(total, size: 40, letterSpacing: -1.5, colorBySign: true)),
            if (lastMonthEnd != null) ...[
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: signed(change),
                    style: ts(13, weight: FontWeight.w800, color: change >= 0 ? C.income : C.expense),
                  ),
                  TextSpan(
                    text: ' since ${DateFormat('d MMM').format(lastMonthEnd.$1)}',
                    style: ts(13, weight: FontWeight.w700, color: C.muted),
                  ),
                ]),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 18),
            CardBox(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (final (v, label) in const [(6, '6 months'), (12, '1 year'), (0, 'All')]) ...[
                        FilterPill(label, selected: _range == v, onTap: () => setState(() => _range = v)),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    label: 'Net worth chart from ${m(history.first.$2)} to ${m(total)}',
                    excludeSemantics: true,
                    child: SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: CustomPaint(painter: _LinePainter([for (final h in history) h.$2])),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(DateFormat('MMM y').format(history.first.$1),
                            style: ts(11, weight: FontWeight.w700, color: C.faint)),
                      ),
                      Text('Now', style: ts(11, weight: FontWeight.w700, color: C.faint)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${_range == 0 ? 'Since ${DateFormat('MMM y').format(history.first.$1)}' : 'In ${_range == 6 ? '6 months' : '1 year'}'}: ${signed(growth)}',
                    style: ts(13, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _PartList(
              title: 'What you have',
              parts: have,
              total: have.fold(0, (a, p) => a + p.amount),
              onTap: (p) => _openPart(context, p.kind),
            ),
            if (owe.isNotEmpty) ...[
              const SizedBox(height: 14),
              _PartList(
                title: 'What you owe',
                parts: owe,
                total: owe.fold(0, (a, p) => a + p.amount),
                onTap: (p) => _openPart(context, p.kind),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              [
                'Month-end values are worked out from your entries.',
                if (notCounted.isNotEmpty)
                  'Not included: accounts set to "Not in my balance" (${notCounted.map((a) => '${a.name} ${m(s.balanceOf(a.id!))}').join(', ')}).',
                if (s.hasEmiPlans)
                  "Loan EMIs in Plans don't know how much loan is left, so they aren't counted.",
              ].join(' '),
              style: ts(12, color: C.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartList extends StatelessWidget {
  const _PartList({required this.title, required this.parts, required this.total, required this.onTap});

  final String title;
  final List<WorthPart> parts;
  final int total;
  final ValueChanged<WorthPart> onTap;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(child: Text(title, style: ts(15, weight: FontWeight.w800))),
                Money(total, colorBySign: true, plus: total > 0),
              ],
            ),
          ),
          if (parts.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text('Nothing yet.', style: ts(13, color: C.muted)),
            ),
          for (final p in parts)
            DecoratedBox(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
              child: ListRow(
                leading: IconTile(_look(p.kind).$1, color: _look(p.kind).$2, size: 36),
                title: p.label,
                subtitle: p.subtitle,
                trailing: Money(p.amount, colorBySign: true),
                onTap: () => onTap(p),
              ),
            ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values);

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    var lo = values.reduce((a, b) => a < b ? a : b).toDouble();
    var hi = values.reduce((a, b) => a > b ? a : b).toDouble();
    final pad = (hi - lo).abs() * 0.1 + 1;
    lo -= pad;
    hi += pad;
    final n = values.length;
    Offset at(int i) => Offset(
          n == 1 ? size.width : size.width * i / (n - 1),
          size.height - (values[i] - lo) / (hi - lo) * size.height,
        );

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < n; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(at(n - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = C.accent.withValues(alpha: 0.14));
    canvas.drawPath(
      line,
      Paint()
        ..color = C.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final last = at(n - 1);
    canvas.drawCircle(last, 6, Paint()..color = C.surface);
    canvas.drawCircle(last, 4.5, Paint()..color = C.accent);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.values != values;
}
