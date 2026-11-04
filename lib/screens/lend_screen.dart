import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/lending.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';

// ------------------------------------------------------------ navigation

Future<void> openLend(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LendScreen()));

Future<void> openPerson(BuildContext context, int personId) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => PersonScreen(personId: personId)));

Future<void> openLendForm(BuildContext context,
        {LoanDirection direction = LoanDirection.lent, String? name}) =>
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LendFormScreen(direction: direction, name: name),
    ));

// --------------------------------------------------------------- helpers

const _avatarColors = [C.blue, C.pink, C.yellow, C.teal, C.orange, C.transfer];

class PersonAvatar extends StatelessWidget {
  const PersonAvatar(this.person, {super.key, this.size = 42});

  final Person person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = _avatarColors[(person.id ?? person.name.hashCode).abs() % _avatarColors.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(person.initial,
          style: ts(size * 0.38, weight: FontWeight.w800, color: Colors.black)),
    );
  }
}

/// "due in 6 days", "due today", "overdue by 2 days".
String dueText(DateTime due) {
  final n = dateOnly(due).difference(today()).inDays;
  if (n == 0) return 'due today';
  if (n == 1) return 'due tomorrow';
  if (n > 1) return 'due in $n days';
  return 'overdue by ${-n} ${n == -1 ? 'day' : 'days'}';
}

bool _overdue(DateTime due) => dateOnly(due).isBefore(today());

/// Summary of everything open with one person.
class _PersonSummary {
  _PersonSummary(this.state, this.person) {
    for (final l in state.loansOf(person.id!)) {
      if (!state.loanOpen(l)) continue;
      if (l.lent) {
        lent = l;
      } else {
        borrowed = l;
      }
    }
  }

  final AppState state;
  final Person person;
  Loan? lent;
  Loan? borrowed;

  int get owesYou => lent == null ? 0 : state.statusOf(lent!).total;
  int get youOwe => borrowed == null ? 0 : state.statusOf(borrowed!).total;
  int get net => owesYou - youOwe;
  bool get open => lent != null || borrowed != null;
  bool get hasHistory => state.loansOf(person.id!).isNotEmpty;
}

// ------------------------------------------------------------ people list

enum _Filter { open, owesYou, youOwe, settled }

class LendScreen extends StatefulWidget {
  const LendScreen({super.key});

  @override
  State<LendScreen> createState() => _LendScreenState();
}

class _LendScreenState extends State<LendScreen> {
  _Filter _filter = _Filter.open;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final all = s.people.map((p) => _PersonSummary(s, p)).where((r) => r.hasHistory).toList();
    final rows = all.where((r) {
      return switch (_filter) {
        _Filter.open => r.open,
        _Filter.owesYou => r.open && r.net > 0,
        _Filter.youOwe => r.open && r.net < 0,
        _Filter.settled => !r.open,
      };
    }).toList()
      ..sort((a, b) => b.net.abs().compareTo(a.net.abs()));

    return Scaffold(
      appBar: AppBar(title: const Text('Lend & borrow')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: _Tile('You\'ll get back', s.toGetBack, C.income,
                    '${s.peopleCount(LoanDirection.lent)} ${s.peopleCount(LoanDirection.lent) == 1 ? 'person' : 'people'}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile('You owe', s.youOwe, C.expense,
                    '${s.peopleCount(LoanDirection.borrowed)} ${s.peopleCount(LoanDirection.borrowed) == 1 ? 'person' : 'people'}'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final (f, label) in const [
                  (_Filter.open, 'Open'),
                  (_Filter.owesYou, 'Owe you'),
                  (_Filter.youOwe, 'You owe'),
                  (_Filter.settled, 'Settled'),
                ]) ...[
                  FilterPill(label, selected: _filter == f, onTap: () => setState(() => _filter = f)),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (all.isEmpty)
            const EmptyCard(
              icon: Icons.handshake_outlined,
              title: 'No one yet',
              message:
                  'Lent money to a friend or borrowed some? Tap a button below to keep track of it.',
            )
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Text('Nobody here.',
                  textAlign: TextAlign.center, style: ts(14, color: C.muted)),
            )
          else
            CardBox(
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    _PersonRow(summary: rows[i], divider: i < rows.length - 1),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: () => openLendForm(context, direction: LoanDirection.lent),
                    icon: const Icon(Icons.north_east_rounded, color: C.expense, size: 18),
                    label: Text('I lent money', style: ts(15, weight: FontWeight.w800)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: C.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: () => openLendForm(context, direction: LoanDirection.borrowed),
                    icon: const Icon(Icons.south_west_rounded, size: 18),
                    label: Text('I borrowed',
                        style: ts(15, weight: FontWeight.w800, color: Colors.white)),
                    style: FilledButton.styleFrom(
                      backgroundColor: C.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.amount, this.color, this.caption);

  final String label;
  final int amount;
  final Color color;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ts(12, weight: FontWeight.w600, color: C.muted)),
          const SizedBox(height: 4),
          Money(amount, size: 20, color: color),
          Text(caption, style: ts(12, weight: FontWeight.w600, color: C.muted)),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.summary, required this.divider});

  final _PersonSummary summary;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final r = summary;
    final s = r.state;
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);

    final parts = <String>[];
    if (r.lent != null) {
      final st = s.statusOf(r.lent!);
      var t = 'Lent ${m(st.given)}';
      if (st.since != null) t += ' on ${shortDate(st.since!)}';
      t += ' · ${r.lent!.rateLabel}';
      if (st.paidBack > 0) t += ' · ${m(st.paidBack)} returned';
      parts.add(t);
    }
    if (r.borrowed != null) {
      final st = s.statusOf(r.borrowed!);
      var t = 'Borrowed ${m(st.given)}';
      if (st.since != null) t += ' on ${shortDate(st.since!)}';
      t += ' · ${r.borrowed!.rateLabel}';
      if (st.paidBack > 0) t += ' · ${m(st.paidBack)} paid';
      parts.add(t);
    }
    if (!r.open) parts.add('All settled');

    String caption;
    Color captionColor = C.muted;
    Color amountColor;
    if (!r.open) {
      caption = 'settled';
      amountColor = C.muted;
    } else if (r.net >= 0) {
      final due = r.lent?.dueDate;
      caption = due == null ? 'owes you' : dueText(due);
      if (due != null && _overdue(due)) captionColor = C.yellow;
      amountColor = C.income;
    } else {
      final due = r.borrowed?.dueDate;
      caption = due == null ? 'you owe' : dueText(due);
      if (due != null) captionColor = C.yellow;
      amountColor = C.expense;
    }

    return ListRow(
      divider: divider,
      leading: PersonAvatar(r.person),
      title: r.person.name,
      subtitle: parts.join('\n'),
      onTap: () => openPerson(context, r.person.id!),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Money(r.net.abs(), color: amountColor),
          Text(caption, style: ts(12, weight: FontWeight.w700, color: captionColor)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- one person

class PersonScreen extends StatelessWidget {
  const PersonScreen({super.key, required this.personId});

  final int personId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.person(personId);
    if (p == null) return const Scaffold(body: SizedBox.shrink());
    final r = _PersonSummary(s, p);

    String headline;
    Color color;
    if (!r.open) {
      headline = 'All settled with ${p.name}';
      color = C.muted;
    } else if (r.net >= 0) {
      headline = '${p.name} owes you';
      color = C.income;
    } else {
      headline = 'You owe ${p.name}';
      color = C.expense;
    }

    final loanIds = s.loansOf(personId).map((l) => l.id).toSet();
    final history = s.entries.where((e) => loanIds.contains(e.loanId)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            color: C.surface2,
            onSelected: (v) {
              if (v == 'rename') _rename(context, p);
              if (v == 'delete') _delete(context, p);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text('Rename', style: ts(15))),
              PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete ${p.name}', style: ts(15, color: C.expense))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Center(child: PersonAvatar(p, size: 56)),
          const SizedBox(height: 10),
          Center(
            child: Text(headline, style: ts(13, weight: FontWeight.w700, color: C.muted)),
          ),
          Center(child: Money(r.net.abs(), size: 40, letterSpacing: -1.5, color: color)),
          if (r.lent != null) ...[
            const SizedBox(height: 18),
            _LoanCard(loan: r.lent!, person: p),
          ],
          if (r.borrowed != null) ...[
            const SizedBox(height: 18),
            _LoanCard(loan: r.borrowed!, person: p),
          ],
          if (!r.open) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlineBtn('I lent money',
                      onPressed: () =>
                          openLendForm(context, direction: LoanDirection.lent, name: p.name)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlineBtn('I borrowed',
                      onPressed: () => openLendForm(context,
                          direction: LoanDirection.borrowed, name: p.name)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const SectionLabel('History'),
          if (history.isEmpty)
            Text('Nothing yet.', style: ts(14, color: C.muted))
          else
            CardBox(
              child: Column(
                children: [
                  for (var i = 0; i < history.length; i++)
                    EntryRow(
                      history[i],
                      showDate: true,
                      divider: i < history.length - 1,
                      onTap: () => _deleteEntry(context, history[i]),
                    ),
                ],
              ),
            ),
          if (history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Tap an entry to delete it.',
                  textAlign: TextAlign.center, style: ts(12, color: C.muted)),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry(BuildContext context, Entry e) async {
    final s = context.read<AppState>();
    final ok = await confirm(
      context,
      title: 'Delete this entry?',
      message:
          '"${s.loanEntryTitle(e)}" of ${money(e.amount)} will be removed and the account balance updated.',
      confirmLabel: 'Delete',
    );
    if (ok) await s.deleteEntry(e.id!);
  }

  Future<void> _rename(BuildContext context, Person p) async {
    final ctrl = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: ts(16, weight: FontWeight.w700),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      await context.read<AppState>().renamePerson(p.id!, name);
    }
  }

  Future<void> _delete(BuildContext context, Person p) async {
    final ok = await confirm(
      context,
      title: 'Delete ${p.name}?',
      message:
          'Everything you lent to or borrowed from ${p.name} is deleted, and account balances go back to how they were without it. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !context.mounted) return;
    await context.read<AppState>().deletePerson(p.id!);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.loan, required this.person});

  final Loan loan;
  final Person person;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final l = loan;
    final st = s.statusOf(l);
    final days = st.since == null ? 0 : today().difference(st.since!).inDays;
    final interestColor = l.lent ? C.income : C.expense;
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);

    Widget line(String label, Widget value, {String? sub, bool strong = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: strong ? C.accentTint : null,
            border: strong ? null : const Border(bottom: BorderSide(color: C.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: ts(14,
                            weight: strong ? FontWeight.w800 : FontWeight.w600,
                            color: strong ? C.text : C.muted)),
                    if (sub != null)
                      Text(sub, style: ts(12, weight: FontWeight.w600, color: C.muted)),
                  ],
                ),
              ),
              value,
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(l.lent ? 'Money you lent' : 'Money you borrowed'),
        CardBox(
          child: Column(
            children: [
              line(l.lent ? 'You lent' : 'You borrowed', Money(st.given)),
              if (l.hasInterest || st.interestTotal > 0)
                line(
                  'Interest so far',
                  Money(st.interestTotal, plus: true, color: interestColor),
                  sub: '${l.rateLabel} · simple · $days ${days == 1 ? 'day' : 'days'}',
                ),
              line(l.lent ? 'Got back' : 'Paid back', Money(st.paidBack)),
              line(l.lent ? 'Total to get back' : 'Total to pay',
                  Money(st.total, size: 16, color: l.lent ? C.income : C.expense),
                  strong: true),
            ],
          ),
        ),
        if (l.hasInterest || l.dueDate != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: C.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      if (l.hasInterest)
                        'Interest adds about ${m(monthlyInterest(l, st.principal))} a month. '
                            '${l.lent ? 'Money ${person.name} returns' : 'Money you pay back'} '
                            'pays the interest first, then the amount.',
                      if (l.dueDate != null)
                        'Pay back by ${shortDate(l.dueDate!)} (${dueText(l.dueDate!)}).',
                    ].join(' '),
                    style: ts(13, color: C.muted, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _Action(
                icon: l.lent ? Icons.south_west_rounded : Icons.north_east_rounded,
                label: l.lent ? 'Got money back' : 'Paid back',
                primary: true,
                onTap: () => openPaymentSheet(context, l),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Action(
                icon: l.lent ? Icons.north_east_rounded : Icons.south_west_rounded,
                iconColor: l.lent ? C.expense : C.income,
                label: l.lent ? 'Lent more' : 'Borrowed more',
                onTap: () => openLendForm(context, direction: l.direction, name: person.name),
              ),
            ),
            if (l.lent) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _Action(
                  icon: Icons.chat_bubble_outline_rounded,
                  iconColor: C.income,
                  label: 'Send reminder',
                  onTap: () => _sendReminder(context, person, l, st),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => openTermsSheet(context, l),
                child: Text('Interest & due date',
                    style: ts(14, weight: FontWeight.w700, color: C.accent)),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => _settle(context, l, st),
                child: Text('Mark as settled',
                    style: ts(14, weight: FontWeight.w700, color: C.muted)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _settle(BuildContext context, Loan l, LoanStatus st) async {
    final ok = await confirm(
      context,
      title: 'Mark as settled?',
      message: l.lent
          ? 'The remaining ${money(st.total)} will no longer be counted as owed to you. Use this if ${person.name} does not need to pay the rest.'
          : 'The remaining ${money(st.total)} will no longer be counted as owed by you.',
      confirmLabel: 'Settle',
      destructive: false,
    );
    if (ok && context.mounted) await context.read<AppState>().setLoanSettled(l, true);
  }

  Future<void> _sendReminder(BuildContext context, Person p, Loan l, LoanStatus st) async {
    final s = context.read<AppState>();
    var msg = 'Hi ${p.name}, a gentle reminder: ${money(st.total)} is pending';
    if (l.hasInterest && st.interestDue > 0) {
      msg += ' (${money(st.principal)} + ${money(st.interestDue)} interest at ${l.rateLabel})';
    }
    if (l.dueDate != null) msg += ', due ${shortDate(l.dueDate!)}';
    msg += '. Thank you!';
    s.externalActivity = true;
    try {
      await SharePlus.instance.share(ShareParams(text: msg));
    } catch (_) {
      if (context.mounted) toast(context, 'Could not open sharing.');
    } finally {
      s.externalActivity = false;
    }
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? C.accent : C.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: primary ? BorderSide.none : const BorderSide(color: C.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, size: 20, color: primary ? Colors.white : (iconColor ?? C.text)),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: ts(13,
                      weight: primary ? FontWeight.w800 : FontWeight.w700,
                      color: primary ? Colors.white : C.text)),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- the form

class LendFormScreen extends StatefulWidget {
  const LendFormScreen({super.key, required this.direction, this.name});

  final LoanDirection direction;
  final String? name;

  @override
  State<LendFormScreen> createState() => _LendFormScreenState();
}

class _LendFormScreenState extends State<LendFormScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _rate = TextEditingController(text: '2');
  late LoanDirection _direction;
  int? _accountId;
  DateTime _date = today();
  DateTime? _due;
  bool _interest = false;
  RatePeriod _period = RatePeriod.month;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _direction = widget.direction;
    _name.text = widget.name ?? '';
    final own = s.visibleAccounts.where((a) => !a.isCard).toList();
    final last = s.account(s.lastAccountId);
    _accountId = (last != null && !last.isCard ? last : own.firstOrNull)?.id ??
        s.visibleAccounts.firstOrNull?.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    _rate.dispose();
    super.dispose();
  }

  bool get _lent => _direction == LoanDirection.lent;

  Loan? _existing(AppState s) {
    final p = s.personNamed(_name.text);
    return p == null ? null : s.openLoanFor(p.id!, _direction);
  }

  Future<void> _pickDate({required bool due}) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: due ? (_due ?? today().add(const Duration(days: 30))) : _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (d == null) return;
    setState(() => due ? _due = dateOnly(d) : _date = dateOnly(d));
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final name = _name.text.trim();
    final amount = parseAmount(_amount.text);
    final existing = _existing(s);
    final rate = double.tryParse(_rate.text.trim().replaceAll(',', '.'));
    String? err;
    if (name.isEmpty) {
      err = _lent ? 'Who did you lend to?' : 'Who did you borrow from?';
    } else if (amount == null || amount <= 0) {
      err = 'Enter an amount';
    } else if (_accountId == null) {
      err = 'Choose an account';
    } else if (existing == null && _interest && (rate == null || rate <= 0 || rate > 100)) {
      err = 'Enter an interest rate between 0 and 100';
    }
    setState(() => _error = err);
    if (err != null) return;

    setState(() => _saving = true);
    await s.lendOrBorrow(
      name: name,
      direction: _direction,
      amount: amount!,
      accountId: _accountId!,
      date: _date,
      note: _note.text.trim(),
      rate: existing == null && _interest ? rate! : 0,
      period: _period,
      dueDate: _due,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final existing = _existing(s);
    final name = _name.text.trim().isEmpty ? 'they' : _name.text.trim();
    final amount = parseAmount(_amount.text) ?? 0;
    final rate = double.tryParse(_rate.text.trim().replaceAll(',', '.')) ?? 0;
    final acc = s.account(_accountId);
    final typed = _name.text.trim().toLowerCase();
    final suggestions = s.people
        .where((p) => typed.isEmpty || p.name.toLowerCase().startsWith(typed))
        .where((p) => p.name.toLowerCase() != typed)
        .take(8)
        .toList();
    String m(int v) => money(v);

    String? preview;
    if (existing == null && _interest && amount > 0 && rate > 0) {
      final tmp = Loan(personId: 0, direction: _direction, rate: rate, period: _period, createdAt: 0);
      final perMonth = monthlyInterest(tmp, amount);
      preview = 'Interest: about ${m(perMonth)} a month (${m((perMonth / 30).round())} a day). '
          '${_lent ? 'In 6 months $name will owe you' : 'In 6 months you will owe $name'} '
          '${m(amount + perMonth * 6)}.';
    }

    final accountName = acc?.name ?? 'the account';
    final effect = _lent
        ? '$accountName goes down by ${amount > 0 ? m(amount) : 'this amount'}, but it is not spending: it does not touch your budget. $name will show under "You\'ll get back".'
        : '$accountName goes up by ${amount > 0 ? m(amount) : 'this amount'}, but it is not income. $name will show under "You owe".';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Lend or borrow'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  _DirectionToggle(
                    value: _direction,
                    onChanged: (d) => setState(() => _direction = d),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() => _error = null),
                    style: ts(16, weight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: _lent ? 'Lent to' : 'Borrowed from',
                      hintText: 'Name, e.g. Rahul',
                    ),
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in suggestions)
                          ActionChip(
                            avatar: PersonAvatar(p, size: 22),
                            label: Text(p.name),
                            labelStyle: ts(13, weight: FontWeight.w700),
                            backgroundColor: C.surface,
                            side: const BorderSide(color: C.line),
                            shape: const StadiumBorder(),
                            onPressed: () => setState(() => _name.text = p.name),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() => _error = null),
                    style: ts(26, weight: FontWeight.w800),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₹ ',
                      prefixStyle: ts(24, weight: FontWeight.w800, color: C.muted),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FieldBox(
                          label: _lent ? 'Paid from' : 'Received in',
                          value: acc?.name ?? 'Choose',
                          onTap: () async {
                            final id = await pickAccount(context,
                                title: _lent ? 'Paid from' : 'Received in',
                                selected: _accountId);
                            if (id != null) setState(() => _accountId = id);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FieldBox(
                          label: 'Date',
                          value: friendlyDay(_date),
                          icon: Icons.calendar_today_outlined,
                          onTap: () => _pickDate(due: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: FieldBox(
                          label: 'Pay back by',
                          value: _due == null ? 'Optional' : shortDate(_due!),
                          icon: _due == null ? Icons.event_outlined : Icons.close_rounded,
                          onTap: () =>
                              _due == null ? _pickDate(due: true) : setState(() => _due = null),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _note,
                          textCapitalization: TextCapitalization.sentences,
                          style: ts(15, weight: FontWeight.w700),
                          decoration: const InputDecoration(labelText: 'Note', hintText: 'Optional'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (existing != null)
                    CardBox(
                      color: C.accentTint,
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        'This adds to what ${_lent ? 'you already lent' : 'you already borrowed'} '
                        '(${m(s.statusOf(existing).total)} now, ${existing.rateLabel}). '
                        'Change the interest on ${existing.lent ? 'their' : 'the'} page.',
                        style: ts(13, weight: FontWeight.w600, height: 1.45),
                      ),
                    )
                  else
                    CardBox(
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: _interest,
                            onChanged: (v) => setState(() => _interest = v),
                            title: Text('Add interest', style: ts(15, weight: FontWeight.w700)),
                            subtitle: Text('Simple interest, worked out every day',
                                style: ts(13, color: C.muted)),
                          ),
                          if (_interest)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 110,
                                        child: TextField(
                                          controller: _rate,
                                          keyboardType: const TextInputType.numberWithOptions(
                                              decimal: true),
                                          onChanged: (_) => setState(() {}),
                                          style: ts(18, weight: FontWeight.w800),
                                          decoration: const InputDecoration(
                                            labelText: 'Rate',
                                            suffixText: '%',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Wrap(
                                          spacing: 8,
                                          children: [
                                            FilterPill('a month',
                                                selected: _period == RatePeriod.month,
                                                onTap: () =>
                                                    setState(() => _period = RatePeriod.month)),
                                            FilterPill('a year',
                                                selected: _period == RatePeriod.year,
                                                onTap: () =>
                                                    setState(() => _period = RatePeriod.year)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (preview != null) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: C.accentTint,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Text(preview,
                                          style: ts(13, weight: FontWeight.w600, height: 1.45)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(effect, style: ts(12, color: C.muted, height: 1.5)),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!,
                          style: ts(13, weight: FontWeight.w700, color: C.expense)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: PrimaryButton(
                amount > 0
                    ? (_lent ? 'Save: I lent ${m(amount)}' : 'Save: I borrowed ${m(amount)}')
                    : 'Save',
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectionToggle extends StatelessWidget {
  const _DirectionToggle({required this.value, required this.onChanged});

  final LoanDirection value;
  final ValueChanged<LoanDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.line),
      ),
      child: Row(
        children: [
          for (final (d, label) in const [
            (LoanDirection.lent, 'I lent'),
            (LoanDirection.borrowed, 'I borrowed'),
          ])
            Expanded(
              child: Semantics(
                selected: value == d,
                button: true,
                child: Material(
                  color: value == d ? C.text : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onChanged(d),
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(label,
                            style: ts(14,
                                weight: FontWeight.w800, color: value == d ? C.bg : C.muted)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- payment sheet

Future<void> openPaymentSheet(BuildContext context, Loan loan) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PaymentSheet(loan: loan),
  );
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.loan});

  final Loan loan;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _amount = TextEditingController();
  int? _accountId;
  DateTime _date = today();
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _amount.text = amountInput(s.statusOf(widget.loan).total);
    // Default to the account the money first moved through.
    final first = s.loanEntriesOf(widget.loan.id!).lastOrNull;
    _accountId = first?.accountId ?? s.lastAccountId ?? s.visibleAccounts.firstOrNull?.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final st = s.statusOf(widget.loan, asOf: _date);
    final v = parseAmount(_amount.text);
    String? err;
    if (v == null || v <= 0) {
      err = 'Enter an amount';
    } else if (v > st.total) {
      err = 'Only ${money(st.total)} is left to pay';
    } else if (_accountId == null) {
      err = 'Choose an account';
    }
    setState(() => _error = err);
    if (err != null) return;
    final (interest, principal) = await s.repay(widget.loan, v!, _accountId!, _date);
    if (!mounted) return;
    Navigator.pop(context);
    toast(
      context,
      interest > 0
          ? 'Saved: ${money(interest)} interest + ${money(principal)}'
          : 'Saved ${money(principal)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final l = widget.loan;
    final st = s.statusOf(l, asOf: _date);
    final v = parseAmount(_amount.text) ?? 0;
    final (interest, principal) = splitPayment(st, v);
    final name = s.person(l.personId)?.name ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.lent ? 'Money back from $name' : 'Pay back $name',
                style: ts(22, weight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${money(st.total)} left in total', style: ts(14, color: C.muted)),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _error = null),
              style: ts(26, weight: FontWeight.w800),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                prefixStyle: ts(24, weight: FontWeight.w800, color: C.muted),
                errorText: _error,
              ),
            ),
            if (v > 0 && v <= st.total && st.interestDue > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Goes to ${money(interest)} interest + ${money(principal)} of the amount.'
                '${v == st.total ? ' Fully paid.' : ''}',
                style: ts(13, weight: FontWeight.w600, color: C.muted),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FieldBox(
                    label: l.lent ? 'Received in' : 'Paid from',
                    value: s.account(_accountId)?.name ?? 'Choose',
                    onTap: () async {
                      final id = await pickAccount(context,
                          title: l.lent ? 'Received in' : 'Paid from', selected: _accountId);
                      if (id != null) setState(() => _accountId = id);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FieldBox(
                    label: 'Date',
                    value: friendlyDay(_date),
                    icon: Icons.calendar_today_outlined,
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(DateTime.now().year + 5, 12, 31),
                      );
                      if (d != null) setState(() => _date = dateOnly(d));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PrimaryButton('Save', onPressed: _save),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------- terms sheet

Future<void> openTermsSheet(BuildContext context, Loan loan) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TermsSheet(loan: loan),
  );
}

class _TermsSheet extends StatefulWidget {
  const _TermsSheet({required this.loan});

  final Loan loan;

  @override
  State<_TermsSheet> createState() => _TermsSheetState();
}

class _TermsSheetState extends State<_TermsSheet> {
  late bool _interest = widget.loan.hasInterest;
  late final _rate = TextEditingController(
      text: widget.loan.hasInterest ? widget.loan.rate.toString().replaceAll(RegExp(r'\.0$'), '') : '2');
  late RatePeriod _period = widget.loan.period;
  late DateTime? _due = widget.loan.dueDate;
  String? _error;

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rate = double.tryParse(_rate.text.trim().replaceAll(',', '.'));
    if (_interest && (rate == null || rate <= 0 || rate > 100)) {
      setState(() => _error = 'Enter a rate between 0 and 100');
      return;
    }
    await context.read<AppState>().updateLoanTerms(widget.loan,
        rate: _interest ? rate! : 0, period: _period, dueDate: _due);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Interest & due date', style: ts(22, weight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Changing the rate recalculates interest from the start.',
                style: ts(13, color: C.muted)),
            const SizedBox(height: 12),
            CardBox(
              child: SwitchListTile(
                value: _interest,
                onChanged: (v) => setState(() => _interest = v),
                title: Text('Add interest', style: ts(15, weight: FontWeight.w700)),
                subtitle: Text('Simple interest, worked out every day',
                    style: ts(13, color: C.muted)),
              ),
            ),
            if (_interest) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _rate,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: ts(18, weight: FontWeight.w800),
                      decoration: InputDecoration(
                          labelText: 'Rate', suffixText: '%', errorText: _error),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilterPill('a month',
                      selected: _period == RatePeriod.month,
                      onTap: () => setState(() => _period = RatePeriod.month)),
                  const SizedBox(width: 8),
                  FilterPill('a year',
                      selected: _period == RatePeriod.year,
                      onTap: () => setState(() => _period = RatePeriod.year)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            FieldBox(
              label: 'Pay back by',
              value: _due == null ? 'No due date' : shortDate(_due!),
              icon: _due == null ? Icons.event_outlined : Icons.close_rounded,
              onTap: () async {
                if (_due != null) {
                  setState(() => _due = null);
                  return;
                }
                final d = await showDatePicker(
                  context: context,
                  initialDate: today().add(const Duration(days: 30)),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(DateTime.now().year + 10, 12, 31),
                );
                if (d != null) setState(() => _due = dateOnly(d));
              },
            ),
            const SizedBox(height: 16),
            PrimaryButton('Save', onPressed: _save),
          ],
        ),
      ),
    );
  }
}
