import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';
import 'account_form_screen.dart';
import 'entry_form_screen.dart';

enum _Filter { all, moneyIn, moneyOut }

/// The passbook: one account's entries with the balance after each one.
class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final int accountId;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = s.account(widget.accountId);
    if (a == null) {
      // The account was deleted.
      return const Scaffold(body: SizedBox.shrink());
    }
    final id = a.id!;
    final balance = s.balanceOf(id);

    // Running balance: walk from oldest to newest.
    final list = s.entriesFor(id);
    final after = <Entry, int>{};
    var run = a.opening;
    for (final e in list.reversed) {
      run += e.effectOn(id);
      after[e] = run;
    }

    final shown = list.where((e) {
      final eff = e.effectOn(id);
      return switch (_filter) {
        _Filter.all => true,
        _Filter.moneyIn => eff > 0,
        _Filter.moneyOut => eff < 0,
      };
    }).toList();

    final months = <DateTime, List<Entry>>{};
    for (final e in shown) {
      months.putIfAbsent(DateTime(e.date.year, e.date.month), () => []).add(e);
    }

    final owed = a.isCard && balance < 0 ? -balance : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(a.name),
        actions: [
          IconButton(
            tooltip: 'Edit account',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AccountFormScreen(account: a))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Center(child: IconTile(accountIcon(a.kind), size: 52)),
          const SizedBox(height: 12),
          Center(
            child: a.isCard
                ? Money(-owed, size: 40, letterSpacing: -1.5, colorBySign: true)
                : Money(balance, size: 40, letterSpacing: -1.5, colorBySign: true),
          ),
          const SizedBox(height: 2),
          Center(
            child: Text(
              '${a.isCard ? _cardLine(s, a, owed) : a.kind.label}'
              '${a.counted ? '' : ' · Not counted in your total balance'}',
              textAlign: TextAlign.center,
              style: ts(13, weight: FontWeight.w600, color: C.muted),
            ),
          ),
          if (a.isCard && a.creditLimit != null && a.creditLimit! > 0) ...[
            const SizedBox(height: 14),
            ProgressBar(owed / a.creditLimit!,
                color: owed > a.creditLimit! ? C.expense : C.accent),
          ],
          const SizedBox(height: 20),
          Row(
            children: a.isCard
                ? [
                    _Action(
                      icon: Icons.north_east_rounded,
                      color: C.expense,
                      label: 'Spend',
                      onTap: () => openEntryForm(context,
                          type: EntryType.expense, accountId: id),
                    ),
                    const SizedBox(width: 10),
                    _Action(
                      icon: Icons.payments_outlined,
                      color: C.income,
                      label: 'Pay bill',
                      onTap: () => openEntryForm(context,
                          type: EntryType.transfer, toAccountId: id),
                    ),
                  ]
                : [
                    _Action(
                      icon: Icons.north_east_rounded,
                      color: C.expense,
                      label: 'Expense',
                      onTap: () => openEntryForm(context,
                          type: EntryType.expense, accountId: id),
                    ),
                    const SizedBox(width: 10),
                    _Action(
                      icon: Icons.south_west_rounded,
                      color: C.income,
                      label: 'Income',
                      onTap: () =>
                          openEntryForm(context, type: EntryType.income, accountId: id),
                    ),
                    const SizedBox(width: 10),
                    _Action(
                      icon: Icons.swap_horiz_rounded,
                      color: C.transfer,
                      label: 'Transfer',
                      onTap: () => openEntryForm(context,
                          type: EntryType.transfer, accountId: id),
                    ),
                  ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterPill('All',
                  selected: _filter == _Filter.all,
                  onTap: () => setState(() => _filter = _Filter.all)),
              FilterPill('Money in',
                  selected: _filter == _Filter.moneyIn,
                  onTap: () => setState(() => _filter = _Filter.moneyIn)),
              FilterPill('Money out',
                  selected: _filter == _Filter.moneyOut,
                  onTap: () => setState(() => _filter = _Filter.moneyOut)),
            ],
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text(
                list.isEmpty
                    ? 'No entries yet. Use the buttons above to add one.'
                    : 'Nothing here for this filter.',
                textAlign: TextAlign.center,
                style: ts(14, color: C.muted),
              ),
            ),
          for (final m in months.keys) ...[
            GroupLabel(
              monthTitle(m),
              trailing: _MonthTotals(entries: months[m]!, accountId: id),
            ),
            CardBox(
              child: Column(
                children: [
                  for (var i = 0; i < months[m]!.length; i++)
                    EntryRow(
                      months[m]![i],
                      forAccount: id,
                      showDate: true,
                      runningBalance: after[months[m]![i]],
                      divider: i < months[m]!.length - 1,
                      onTap: () => openEntryForm(context, entry: months[m]![i]),
                    ),
                ],
              ),
            ),
          ],
          if (list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text('Opening balance ${s.amountsHidden ? '₹••••' : money(a.opening)}',
                  textAlign: TextAlign.center, style: ts(12, color: C.muted)),
            ),
        ],
      ),
    );
  }

  String _cardLine(AppState s, Account a, int owed) {
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);
    final parts = <String>[owed > 0 ? 'Outstanding' : 'Nothing due'];
    if (a.creditLimit != null && a.creditLimit! > 0) {
      final avail = a.creditLimit! - owed;
      parts.add('${m(avail < 0 ? 0 : avail)} available of ${m(a.creditLimit!)}');
    }
    if (a.dueDay != null) parts.add('Due on the ${ordinal(a.dueDay!)}');
    return parts.join(' · ');
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: CardBox(
        radius: 16,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(label, style: ts(13, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _MonthTotals extends StatelessWidget {
  const _MonthTotals({required this.entries, required this.accountId});

  final List<Entry> entries;
  final int accountId;

  @override
  Widget build(BuildContext context) {
    var inn = 0;
    var out = 0;
    for (final e in entries) {
      final x = e.effectOn(accountId);
      if (x > 0) inn += x;
      if (x < 0) out += x;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (inn > 0) ...[
          Text('In ', style: ts(12, weight: FontWeight.w700, color: C.muted)),
          Money(inn, size: 12, plus: true, color: C.income),
        ],
        if (inn > 0 && out < 0) const SizedBox(width: 10),
        if (out < 0) ...[
          Text('Out ', style: ts(12, weight: FontWeight.w700, color: C.muted)),
          Money(out, size: 12, color: C.expense),
        ],
      ],
    );
  }
}
