import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../data/models.dart';
import '../data/recurring.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';
import 'entry_form_screen.dart';

Future<void> openSips(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SipsScreen()));

Future<void> openFund(BuildContext context, int id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FundDetailScreen(fundId: id)));

Future<void> openFundForm(BuildContext context, {MutualFund? fund}) =>
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => FundFormScreen(fund: fund),
    ));

String _pct(int part, int total) => total <= 0 ? '0%' : '${(part * 100 / total).round()}%';

/// Rounded tile with the fund's trend icon in its type colour.
class _FundIcon extends StatelessWidget {
  const _FundIcon(this.type, {this.faded = false});

  final String type;
  final bool faded;

  @override
  Widget build(BuildContext context) =>
      IconTile(Icons.trending_up_rounded, color: faded ? C.faint : fundTypeColor(type));
}

/// Money invested per fund type, biggest first.
List<(String, int)> _byType(AppState s) {
  final sums = <String, int>{};
  for (final f in s.openFunds) {
    final v = s.investedIn(f);
    if (v > 0) sums[f.type] = (sums[f.type] ?? 0) + v;
  }
  final keys = sums.keys.toList()..sort((a, b) => sums[b]!.compareTo(sums[a]!));
  return [for (final k in keys) (k, sums[k]!)];
}

// ------------------------------------------------------------ Home card

/// "Mutual funds" on Home: what you invested, split by type.
class MutualFundsSection extends StatelessWidget {
  const MutualFundsSection({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final open = s.openFunds;
    if (open.isEmpty) {
      return DashedAddRow(
        icon: Icons.trending_up_rounded,
        color: C.transfer,
        title: 'Investing in mutual funds?',
        subtitle: 'Add your funds and SIPs to see what you invested',
        onTap: () => openFundForm(context),
      );
    }
    final total = s.totalInvested;
    final types = _byType(s);
    final next = s.nextSip;
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);
    return Column(
      children: [
        SectionHeader('Mutual funds', action: 'See all', onAction: () => openSips(context)),
        CardBox(
          onTap: () => openSips(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You invested · ${open.length} ${open.length == 1 ? 'fund' : 'funds'}',
                        style: ts(12, weight: FontWeight.w700, color: C.muted)),
                    const SizedBox(height: 4),
                    Money(total, size: 26, letterSpacing: -0.8),
                    if (next != null) ...[
                      const SizedBox(height: 2),
                      Text('Next SIP ${m(next.amount)} on ${shortDate(nextDueDate(next)!)}',
                          style: ts(13, weight: FontWeight.w600, color: C.muted)),
                    ],
                  ],
                ),
              ),
              if (types.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
                  child: Row(
                    children: [
                      Expanded(
                        child: SplitBar(
                            parts: [for (final (k, v) in types) (v, fundTypeColor(k))], height: 8),
                      ),
                      if (s.sipMonthly > 0) ...[
                        const SizedBox(width: 10),
                        Text('${m(s.sipMonthly)} a month',
                            style: ts(12, weight: FontWeight.w700, color: C.muted)),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- My SIPs

class SipsScreen extends StatelessWidget {
  const SipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final open = s.openFunds
      ..sort((a, b) => s.investedIn(b).compareTo(s.investedIn(a)));
    final closed = s.funds.where((f) => f.closed).toList();
    final total = s.totalInvested;
    final types = _byType(s);
    final next = s.nextSip;
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My SIPs'),
        actions: [
          TextButton(
            onPressed: () => openFundForm(context),
            child: Text('+ Add fund', style: ts(15, weight: FontWeight.w800, color: C.accent)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            if (s.funds.isEmpty)
              EmptyCard(
                icon: Icons.trending_up_rounded,
                color: C.transfer,
                title: 'No funds yet',
                message: 'Add each mutual fund you invest in: its SIP, and what you had put in before.',
                action: 'Add fund',
                onAction: () => openFundForm(context),
              )
            else ...[
              CardBox(
                radius: 24,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You invested · ${open.length} ${open.length == 1 ? 'fund' : 'funds'}',
                        style: ts(13, weight: FontWeight.w700, color: C.muted)),
                    const SizedBox(height: 4),
                    Money(total, size: 36, letterSpacing: -1.2),
                    if (s.investedThisYear > 0) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: C.accentTint, borderRadius: BorderRadius.circular(999)),
                        child: Text('+${m(s.investedThisYear)} put in this year',
                            style: ts(13, weight: FontWeight.w800, color: C.transfer)),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _Tile('SIPs every month', m(s.sipMonthly))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Tile(
                            'Next SIP',
                            next == null
                                ? 'None'
                                : '${m(next.amount)} · ${shortDate(nextDueDate(next)!)}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (types.isNotEmpty) ...[
                const SizedBox(height: 14),
                CardBox(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Where your money is', style: ts(15, weight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      SplitBar(parts: [for (final (k, v) in types) (v, fundTypeColor(k))], height: 12),
                      const SizedBox(height: 12),
                      Wrap(
                        runSpacing: 8,
                        children: [
                          for (final (k, v) in types)
                            FractionallySizedBox(
                              widthFactor: 0.5,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                          color: fundTypeColor(k), shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(fundTypeLabel(k),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: ts(13, weight: FontWeight.w700)),
                                    ),
                                    Text(_pct(v, total),
                                        style: ts(13, weight: FontWeight.w700, color: C.muted)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              // Funds grouped by their SIP: running, paused, none; sold last.
              for (final (title, list) in [
                ('Active SIPs', open.where((f) => s.fundPlan(f)?.active == true).toList()),
                ('Paused SIPs', open.where((f) => s.fundPlan(f)?.active == false).toList()),
                ('No monthly SIP', open.where((f) => s.fundPlan(f) == null).toList()),
                ('Sold', closed),
              ])
                if (list.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  SectionLabel(
                    '$title · ${list.length}',
                    trailing: title == 'Sold'
                        ? null
                        : Text(m(list.fold(0, (a, f) => a + s.investedIn(f))),
                            style: ts(12, weight: FontWeight.w800, color: C.muted)),
                  ),
                  CardBox(
                    child: Column(
                      children: [
                        for (var i = 0; i < list.length; i++)
                          _FundRow(fund: list[i], total: total, divider: i < list.length - 1),
                      ],
                    ),
                  ),
                ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: C.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What Funds counts', style: ts(13, weight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      'The money you put in: what you had before, every SIP and lump sum. '
                      'Market value and profit change every day, so check those in your fund app.',
                      style: ts(13, color: C.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value);

  final String label;
  final String value;

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
          Text(label, style: ts(12, weight: FontWeight.w600, color: C.muted)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(17, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _FundRow extends StatelessWidget {
  const _FundRow({required this.fund, required this.total, required this.divider});

  final MutualFund fund;
  final int total;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final f = fund;
    final p = s.fundPlan(f);
    final invested = s.investedIn(f);
    String sub;
    if (f.closed) {
      sub = 'Sold on ${DateFormat('d MMM y').format(f.closedDate ?? today())}';
    } else if (p == null) {
      sub = '${fundTypeLabel(f.type)} · no monthly SIP';
    } else if (!p.active) {
      sub = '${fundTypeLabel(f.type)} · SIP paused';
    } else {
      sub = '${fundTypeLabel(f.type)} · ${s.amountsHidden ? '₹••••' : money(p.amount)} on the ${ordinal(p.day)}';
    }
    return ListRow(
      divider: divider,
      leading: _FundIcon(f.type, faded: f.closed),
      title: f.name,
      subtitle: sub,
      onTap: () => openFund(context, f.id!),
      trailing: f.closed
          ? Money(f.closedAmount ?? 0, color: C.muted)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Money(invested),
                Text('${_pct(invested, total)} of total',
                    style: ts(12, weight: FontWeight.w700, color: C.muted)),
              ],
            ),
    );
  }
}

// ------------------------------------------------------------- one fund

class FundDetailScreen extends StatelessWidget {
  const FundDetailScreen({super.key, required this.fundId});

  final int fundId;

  Future<void> _delete(BuildContext context, AppState s, MutualFund f) async {
    final n = s.fundEntriesOf(f.id!).length;
    final ok = await confirm(
      context,
      title: 'Delete this fund?',
      message: n == 0
          ? 'The fund and its SIP are removed.'
          : 'The fund, its SIP and its $n money ${n == 1 ? 'move' : 'moves'} are removed, '
              'so your account balances go back. To keep the history, use Withdraw instead.',
      confirmLabel: 'Delete',
    );
    if (!ok || !context.mounted) return;
    await s.deleteFund(f);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final f = s.fund(fundId);
    if (f == null) return const Scaffold();
    final p = s.fundPlan(f);
    final invested = s.investedIn(f);
    final before = f.alreadyInvested;
    final added = s.addedInFunds(f);
    final moves = s.fundEntriesOf(f.id!);
    final color = fundTypeColor(f.type);
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);
    final next = p != null && p.active ? nextDueDate(p) : null;

    String line;
    if (f.closed) {
      line = 'Sold on ${DateFormat('d MMM y').format(f.closedDate ?? today())}';
    } else if (p == null) {
      line = 'No monthly SIP';
    } else if (!p.active) {
      line = '${m(p.amount)} a month · SIP paused';
    } else {
      line = '${m(p.amount)} every month · next on ${shortDate(next!)}';
    }

    final sips = moves.where((e) => e.type == EntryType.investOut && e.planId != null).length;
    final lumps = moves.where((e) => e.type == EntryType.investOut && e.planId == null).length;
    final rows = <(String, String, String)>[
      if (p != null)
        ('SIP', '${m(p.amount)} a month', 'On the ${ordinal(p.day)} · from ${s.accountName(p.accountId)}'),
      if (next != null) ('Next SIP', DateFormat('EEE d MMM').format(next), daysUntil(next)),
      if (f.started != null) ('Started', DateFormat('MMM y').format(f.started!), ''),
      if (before > 0) ('Already invested', m(before), 'When you added it to Funds'),
      if (!f.closed && s.totalInvested > 0)
        ('Share of your funds', _pct(invested, s.totalInvested),
            'Of ${m(s.totalInvested)} in ${s.openFunds.length} ${s.openFunds.length == 1 ? 'fund' : 'funds'}'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (!f.closed)
            IconButton(
              tooltip: 'Edit fund',
              onPressed: () => openFundForm(context, fund: f),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(color.withValues(alpha: 0.16), C.bg),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(fundTypeLabel(f.type).toUpperCase(),
                    style: ts(12, weight: FontWeight.w800, color: color)),
              ),
            ),
            const SizedBox(height: 10),
            if (f.closed) ...[
              Text('You got', textAlign: TextAlign.center, style: ts(13, weight: FontWeight.w700, color: C.muted)),
              Center(child: Money(f.closedAmount ?? 0, size: 40, letterSpacing: -1.5)),
              _ClosedResult(state: s, fund: f),
            ] else ...[
              Text('You invested',
                  textAlign: TextAlign.center, style: ts(13, weight: FontWeight.w700, color: C.muted)),
              Center(child: Money(invested, size: 40, letterSpacing: -1.5)),
            ],
            const SizedBox(height: 2),
            Text(line, textAlign: TextAlign.center, style: ts(14, weight: FontWeight.w700, color: C.muted)),
            if (!f.closed && before + added > 0) ...[
              const SizedBox(height: 20),
              CardBox(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Before Funds ${m(before)}',
                              style: ts(13, weight: FontWeight.w700, color: C.muted)),
                        ),
                        Text('Added in Funds ${m(added)}',
                            style: ts(13, weight: FontWeight.w700, color: color)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SplitBar(parts: [(before, const Color(0xFF4A4A4A)), (added, color)], height: 10),
                    if (sips + lumps > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Added in Funds: ${[
                          if (sips > 0) '$sips ${sips == 1 ? 'SIP' : 'SIPs'}',
                          if (lumps > 0) '$lumps ${lumps == 1 ? 'lump sum' : 'lump sums'}',
                        ].join(' and ')}'
                        '${s.takenOut(f) > 0 ? ' · ${m(s.takenOut(f))} taken out' : ''}',
                        style: ts(12, weight: FontWeight.w600, color: C.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 14),
              CardBox(
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        decoration: BoxDecoration(
                          border: i < rows.length - 1
                              ? const Border(bottom: BorderSide(color: C.line))
                              : null,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(rows[i].$1,
                                  style: ts(14, weight: FontWeight.w600, color: C.muted)),
                            ),
                            const SizedBox(width: 12),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(rows[i].$2, style: ts(14, weight: FontWeight.w800)),
                                  if (rows[i].$3.isNotEmpty)
                                    Text(rows[i].$3,
                                        textAlign: TextAlign.right,
                                        style: ts(12, weight: FontWeight.w600, color: C.muted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (moves.isNotEmpty || before > 0) ...[
              const SizedBox(height: 22),
              const SectionLabel('Money put in and taken out'),
              CardBox(
                child: Column(
                  children: [
                    for (var i = 0; i < moves.length; i++)
                      EntryRow(moves[i],
                          showDate: true,
                          divider: i < moves.length - 1 || before > 0,
                          onTap: () => openEntryForm(context, entry: moves[i])),
                    if (before > 0)
                      ListRow(
                        leading: const IconTile(Icons.history_rounded, color: C.muted),
                        title: 'Already invested',
                        subtitle: f.started == null
                            ? 'Before Funds'
                            : 'Before Funds · since ${DateFormat('MMM y').format(f.started!)}',
                        trailing: Money(before, color: C.muted),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (!f.closed) ...[
              Row(
                children: [
                  Expanded(child: OutlineBtn('Add lump sum', onPressed: () => _lumpSum(context, f))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlineBtn('Withdraw', onPressed: () => _withdraw(context, f))),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                if (!f.closed && p != null) ...[
                  Expanded(
                    child: OutlineBtn(p.active ? 'Pause SIP' : 'Restart SIP',
                        onPressed: () => s.setSipActive(f, !p.active)),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: OutlineBtn('Delete fund',
                      color: C.expense, onPressed: () => _delete(context, s, f)),
                ),
              ],
            ),
            if (!f.closed && p != null) ...[
              const SizedBox(height: 10),
              Text(
                p.active
                    ? 'Pause stops the monthly SIP but keeps the fund.'
                    : 'Restarting begins from the next ${ordinal(p.day)}. Paused months are not added.',
                textAlign: TextAlign.center,
                style: ts(12, color: C.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Profit or loss of a sold fund.
class _ClosedResult extends StatelessWidget {
  const _ClosedResult({required this.state, required this.fund});

  final AppState state;
  final MutualFund fund;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final f = fund;
    // What was still in it when sold.
    final inIt = s.putInto(f) - s.takenOut(f) + _backAtClose(s, f);
    final diff = (f.closedAmount ?? 0) - inIt;
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);
    return Text(
      diff >= 0 ? 'Profit ${m(diff)} on ${m(inIt)} invested' : 'Loss ${m(-diff)} on ${m(inIt)} invested',
      textAlign: TextAlign.center,
      style: ts(14, weight: FontWeight.w800, color: diff >= 0 ? C.income : C.expense),
    );
  }

  /// The money-back entry made when the fund was sold (it is also counted
  /// in takenOut).
  static int _backAtClose(AppState s, MutualFund f) => s
      .fundEntriesOf(f.id!)
      .where((e) => e.type == EntryType.investIn && f.closedDate != null && sameDay(e.date, f.closedDate!))
      .fold(0, (a, e) => a + e.amount);
}

// ------------------------------------------------------------ sheets

Future<void> _lumpSum(BuildContext context, MutualFund f) async {
  final s = context.read<AppState>();
  final ctrl = TextEditingController();
  var accountId = s.lastAccountId ?? s.visibleAccounts.firstOrNull?.id;
  var date = today();
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      final amount = parseAmount(ctrl.text) ?? 0;
      Future<void> save() async {
        final v = parseAmount(ctrl.text);
        if (v == null || v <= 0) return setSt(() => error = 'Enter an amount');
        if (accountId == null) return setSt(() => error = 'Choose an account');
        await s.addToFund(f, v, accountId!, date);
        if (ctx.mounted) Navigator.pop(ctx);
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add lump sum', style: ts(20, weight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${f.name} · you invested ${money(s.investedIn(f))}', style: ts(13, color: C.muted)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: ts(22, weight: FontWeight.w800),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                prefixStyle: ts(22, weight: FontWeight.w800, color: C.muted),
                errorText: error,
              ),
              onChanged: (_) => setSt(() => error = null),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FieldBox(
                    label: 'From',
                    value: s.account(accountId)?.name ?? 'Choose',
                    onTap: () async {
                      final id = await pickAccount(ctx, title: 'Paid from', selected: accountId);
                      if (id != null) setSt(() => accountId = id);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FieldBox(
                    label: 'Date',
                    value: friendlyDay(date),
                    icon: Icons.calendar_today_outlined,
                    onTap: () async {
                      final d = await showDatePicker(
                          context: ctx, initialDate: date, firstDate: DateTime(2000), lastDate: today());
                      if (d != null) setSt(() => date = dateOnly(d));
                    },
                  ),
                ),
              ],
            ),
            if (amount > 0) ...[
              const SizedBox(height: 12),
              Text('You invested becomes ${money(s.investedIn(f) + amount)}',
                  style: ts(13, weight: FontWeight.w700, color: C.transfer)),
            ],
            const SizedBox(height: 16),
            PrimaryButton(amount > 0 ? 'Add ${money(amount)}' : 'Add', onPressed: save),
          ],
        ),
      );
    }),
  );
}

Future<void> _withdraw(BuildContext context, MutualFund f) async {
  final s = context.read<AppState>();
  final ctrl = TextEditingController();
  final invested = s.investedIn(f);
  var all = false;
  var accountId = s.fundPlan(f)?.accountId ?? s.lastAccountId ?? s.visibleAccounts.firstOrNull?.id;
  var date = today();
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      final amount = parseAmount(ctrl.text) ?? 0;
      final back = all ? (amount < invested ? amount : invested) : amount;
      final profit = all ? amount - invested : 0;
      String m(int v) => money(v);

      Future<void> save() async {
        final v = parseAmount(ctrl.text);
        if (v == null || v <= 0) return setSt(() => error = 'Enter the amount you got');
        if (!all && v > invested) {
          return setSt(() => error =
              'More than you invested (${m(invested)}). If you sold everything, choose "Sold everything".');
        }
        if (accountId == null) return setSt(() => error = 'Choose an account');
        await s.withdrawFromFund(f, v, accountId!, date, all: all);
        if (ctx.mounted) Navigator.pop(ctx);
      }

      Widget line(String k, String v, [Color c = C.text]) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
            child: Row(
              children: [
                Expanded(child: Text(k, style: ts(13, weight: FontWeight.w600, color: C.muted))),
                Text(v, style: ts(13, weight: FontWeight.w800, color: c)),
              ],
            ),
          );

      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Withdraw', style: ts(20, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${f.name} · you invested ${m(invested)}', style: ts(13, color: C.muted)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: C.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: C.line),
                ),
                child: Row(
                  children: [
                    for (final (v, label) in const [(false, 'Take out part'), (true, 'Sold everything')])
                      Expanded(
                        child: Material(
                          color: all == v ? C.text : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setSt(() {
                              all = v;
                              error = null;
                            }),
                            child: SizedBox(
                              height: 40,
                              child: Center(
                                child: Text(label,
                                    style: ts(14, weight: FontWeight.w800, color: all == v ? C.bg : C.muted)),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: ts(22, weight: FontWeight.w800),
                decoration: InputDecoration(
                  labelText: 'Amount you got',
                  prefixText: '₹ ',
                  prefixStyle: ts(22, weight: FontWeight.w800, color: C.muted),
                  errorText: error,
                  errorMaxLines: 3,
                ),
                onChanged: (_) => setSt(() => error = null),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FieldBox(
                      label: 'Paid into',
                      value: s.account(accountId)?.name ?? 'Choose',
                      onTap: () async {
                        final id = await pickAccount(ctx, title: 'Paid into', selected: accountId);
                        if (id != null) setSt(() => accountId = id);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FieldBox(
                      label: 'Date',
                      value: friendlyDay(date),
                      icon: Icons.calendar_today_outlined,
                      onTap: () async {
                        final d = await showDatePicker(
                            context: ctx, initialDate: date, firstDate: DateTime(2000), lastDate: today());
                        if (d != null) setSt(() => date = dateOnly(d));
                      },
                    ),
                  ),
                ],
              ),
              if (amount > 0) ...[
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: C.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: C.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: all
                        ? [
                            line('Your money back', m(back)),
                            if (profit >= 0)
                              line('Profit (counts as income)', '+${m(profit)}', C.income)
                            else
                              line('Loss', '−${m(-profit)}', C.expense),
                            line('Left in the fund', '₹0 · fund closed', C.muted),
                          ]
                        : [
                            line('Comes out of what you invested', '−${m(amount)}'),
                            line('You invested', '${m(invested)} → ${m((invested - amount).clamp(0, invested))}'),
                            line('SIP', s.fundPlan(f)?.active == true ? 'Keeps going' : '—', C.muted),
                          ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                all
                    ? 'Anything above what you invested is profit. The fund is closed and its SIP stops; it stays in your history.'
                    : "Funds can't know the profit in a part withdrawal, so it lowers what you invested. Profit is counted when you sell everything.",
                style: ts(12, color: C.muted, height: 1.5),
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                all ? 'Withdraw all · close fund' : (amount > 0 ? 'Withdraw ${m(amount)}' : 'Withdraw'),
                onPressed: save,
              ),
            ],
          ),
        ),
      );
    }),
  );
}

// --------------------------------------------------------------- form

class FundFormScreen extends StatefulWidget {
  const FundFormScreen({super.key, this.fund});

  final MutualFund? fund;

  @override
  State<FundFormScreen> createState() => _FundFormScreenState();
}

class _FundFormScreenState extends State<FundFormScreen> {
  final _name = TextEditingController();
  final _sipAmount = TextEditingController();
  final _already = TextEditingController();
  String _type = 'flexi';
  bool _sip = true;
  int _day = 5;
  int? _accountId;
  DateTime? _started;
  String? _error;
  bool _saving = false;

  bool get _editing => widget.fund != null;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    final f = widget.fund;
    if (f != null) {
      _name.text = f.name;
      _type = f.type;
      _started = f.started;
      if (f.alreadyInvested > 0) _already.text = amountInput(f.alreadyInvested);
      final p = s.fundPlan(f);
      _sip = p != null;
      if (p != null) {
        _sipAmount.text = amountInput(p.amount);
        _day = p.day;
        _accountId = p.accountId;
      }
    }
    _accountId ??= () {
      final bank = s.visibleAccounts.where((a) => a.kind.isBank).toList();
      return (bank.isNotEmpty ? bank.first : s.visibleAccounts.firstOrNull)?.id;
    }();
  }

  @override
  void dispose() {
    _name.dispose();
    _sipAmount.dispose();
    _already.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final d = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Day of the month', style: ts(20, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('In shorter months the last day is used.', style: ts(13, color: C.muted)),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var i = 1; i <= 31; i++)
                    Material(
                      color: i == _day ? C.accent : C.surface2,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(ctx, i),
                        child: Center(
                          child: Text('$i',
                              style: ts(15,
                                  weight: FontWeight.w800, color: i == _day ? Colors.white : C.text)),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (d != null) setState(() => _day = d);
  }

  Future<void> _pickStarted() async {
    final t = today();
    final d = await showDatePicker(
      context: context,
      initialDate: _started ?? DateTime(t.year - 1, t.month),
      firstDate: DateTime(1990),
      lastDate: t,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'When did you start? (any day of that month)',
    );
    if (d != null) setState(() => _started = DateTime(d.year, d.month));
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final name = _name.text.trim();
    final sipAmount = parseAmount(_sipAmount.text);
    final already = _already.text.trim().isEmpty ? 0 : parseAmount(_already.text);
    String? err;
    if (name.isEmpty) {
      err = 'Enter the fund name';
    } else if (_sip && (sipAmount == null || sipAmount <= 0)) {
      err = 'Enter the SIP amount';
    } else if (_sip && _accountId == null) {
      err = 'Choose the account the SIP is taken from';
    } else if (already == null || already < 0) {
      err = 'Enter what you already invested, or leave it empty';
    }
    setState(() => _error = err);
    if (err != null) return;

    setState(() => _saving = true);
    final old = widget.fund;
    final id = await s.saveFund(
      MutualFund(
        id: old?.id,
        name: name,
        type: _type,
        alreadyInvested: already!,
        started: _started,
        createdAt: old?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      ),
      sipAmount: _sip ? sipAmount : null,
      sipDay: _sip ? _day : null,
      sipAccount: _sip ? _accountId : null,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    if (old == null) openFund(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final acc = s.account(_accountId);
    final sipAmount = parseAmount(_sipAmount.text) ?? 0;
    final already = parseAmount(_already.text) ?? 0;
    final next = dueDateIn(
        parseMonth(firstMonthFor(_day, DateTime.now())).year, parseMonth(firstMonthFor(_day, DateTime.now())).month, _day);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_editing ? 'Edit fund' : 'Add fund'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  TextField(
                    controller: _name,
                    autofocus: !_editing,
                    textCapitalization: TextCapitalization.words,
                    style: ts(16, weight: FontWeight.w700),
                    decoration: const InputDecoration(
                      labelText: 'Fund name',
                      hintText: 'e.g. Parag Parikh Flexi Cap',
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                  const SizedBox(height: 18),
                  const SectionLabel('Type'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (k, label) in fundTypes)
                        Semantics(
                          selected: _type == k,
                          button: true,
                          child: Material(
                            color: _type == k ? C.accentTint : Colors.transparent,
                            shape: StadiumBorder(
                                side: BorderSide(color: _type == k ? C.accent : C.border, width: 1.5)),
                            child: InkWell(
                              customBorder: const StadiumBorder(),
                              onTap: () => setState(() => _type = k),
                              child: Container(
                                height: 36,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Align(
                                  widthFactor: 1,
                                  child: Text(label,
                                      style: ts(13,
                                          weight: FontWeight.w800,
                                          color: _type == k ? C.accent : C.text)),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  CardBox(
                    child: SwitchListTile(
                      value: _sip,
                      onChanged: (v) => setState(() => _sip = v),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: Text('Monthly SIP', style: ts(14, weight: FontWeight.w700)),
                      subtitle: Text('Turn off for a fund you only bought once',
                          style: ts(12, color: C.muted)),
                    ),
                  ),
                  if (_sip) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _sipAmount,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: ts(16, weight: FontWeight.w700),
                            decoration: const InputDecoration(labelText: 'SIP amount', prefixText: '₹ '),
                            onChanged: (_) => setState(() => _error = null),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FieldBox(
                            label: 'Every month on',
                            value: 'the ${ordinal(_day)}',
                            icon: Icons.calendar_today_outlined,
                            onTap: _pickDay,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FieldBox(
                      label: 'Taken from',
                      value: acc == null
                          ? 'Choose account'
                          : '${acc.name} · ${s.amountsHidden ? '₹••••' : money(s.balanceOf(acc.id!))}',
                      onTap: () async {
                        final id = await pickAccount(context, title: 'SIP taken from', selected: _accountId);
                        if (id != null) setState(() => _accountId = id);
                      },
                    ),
                  ],
                  const SizedBox(height: 24),
                  const SectionLabel('Before Funds'),
                  Text('For a fund you already had before Funds. Leave empty for a new one.',
                      style: ts(12, color: C.muted, height: 1.5)),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _already,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: ts(16, weight: FontWeight.w700),
                          decoration:
                              const InputDecoration(labelText: 'Already invested', prefixText: '₹ '),
                          onChanged: (_) => setState(() => _error = null),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FieldBox(
                          label: 'Started (optional)',
                          value: _started == null ? 'Choose' : DateFormat('MMM y').format(_started!),
                          icon: Icons.calendar_month_outlined,
                          onTap: _pickStarted,
                        ),
                      ),
                    ],
                  ),
                  if (_started != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _started = null),
                        child: Text('Clear start month', style: ts(13, weight: FontWeight.w700, color: C.muted)),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: C.accentTint, borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      [
                        if (already > 0)
                          'The ${money(already)} already invested is not taken from any account; it was paid before.',
                        if (_sip && sipAmount > 0 && acc != null && !_editing)
                          'From ${DateFormat('d MMM').format(next)}, ${money(sipAmount)} moves from ${acc.name} into this fund each month.',
                        if (_sip && _editing) 'SIPs keep going on their day; past ones stay as they are.',
                        'This is not counted as spending.',
                      ].join(' '),
                      style: ts(12, weight: FontWeight.w600, color: C.onAccentSoft, height: 1.5),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: ts(13, weight: FontWeight.w700, color: C.expense)),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: PrimaryButton(_editing ? 'Save changes' : 'Save fund',
                  onPressed: _saving ? null : _save),
            ),
          ],
        ),
      ),
    );
  }
}
