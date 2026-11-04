import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/deposits.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';

// ------------------------------------------------------------ navigation

Future<void> openFdList(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FdListScreen()));

Future<void> openFd(BuildContext context, int fdId) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FdScreen(fdId: fdId)));

Future<void> openFdForm(BuildContext context, {Fd? fd}) => Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => FdFormScreen(fd: fd)),
    );

const _tenures = <(String, int?)>[
  ('6 months', 6),
  ('1 year', 12),
  ('2 years', 24),
  ('3 years', 36),
  ('5 years', 60),
  ('Custom date', null),
];

String _longDate(DateTime d) => '${shortDate(d)} ${d.year}';

String _daysLeft(Fd f) {
  final n = f.maturityDate.difference(today()).inDays;
  if (n <= 0) return 'Matured';
  return '$n ${n == 1 ? 'day' : 'days'} left';
}

// ------------------------------------------------------------------ rows

/// One FD in a list: name, rate, maturity, progress and value today.
class FdRow extends StatelessWidget {
  const FdRow({super.key, required this.fd, this.divider = false});

  final Fd fd;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final f = fd;
    final matured = s.fdMatured(f);
    final now = today();

    String sub;
    if (f.closed) {
      sub = switch (f.closedHow) {
        'renewed' => 'Renewed on ${_longDate(f.closedDate ?? f.maturityDate)}',
        'early' => 'Closed early on ${_longDate(f.closedDate ?? now)}',
        _ => 'Withdrawn on ${_longDate(f.closedDate ?? f.maturityDate)}',
      };
    } else if (matured) {
      sub = 'Matured · choose Withdraw or Renew';
    } else {
      sub = '${f.rateLabel} · matures ${_longDate(f.maturityDate)}';
    }

    final value = f.closed ? (f.closedAmount ?? f.principal) : fdValueOn(f, now);

    return ListRow(
      divider: divider,
      onTap: () => openFd(context, f.id!),
      leading: IconTile(Icons.lock_outline_rounded, color: f.closed ? C.faint : C.yellow),
      title: f.name,
      subtitle: sub,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Money(value, color: f.closed ? C.muted : C.text),
          if (!f.closed)
            Text(_daysLeft(f),
                style: ts(12, weight: FontWeight.w700, color: matured ? C.yellow : C.muted)),
        ],
      ),
    );
  }
}

/// Summary at the top of the FD card / list.
class FdSummary extends StatelessWidget {
  const FdSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final n = s.activeFds.length;
    final interest = s.fdWorth - s.fdInvested;
    final hidden = s.amountsHidden;
    String m(int v) => hidden ? '₹••••' : money(v);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Worth today · $n ${n == 1 ? 'FD' : 'FDs'}',
              style: ts(12, weight: FontWeight.w700, color: C.muted)),
          const SizedBox(height: 4),
          Money(s.fdWorth, size: 26, letterSpacing: -0.8),
          const SizedBox(height: 2),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: '${m(s.fdInvested)} invested · ',
                style: ts(13, weight: FontWeight.w600, color: C.muted)),
            TextSpan(
                text: '+${m(interest)} interest so far',
                style: ts(13, weight: FontWeight.w600, color: C.income)),
          ])),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ list

class FdListScreen extends StatelessWidget {
  const FdListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final active = s.activeFds;
    final closed = s.fds.where((f) => f.closed).toList().reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fixed deposits'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: TintButton('Add FD',
                  icon: Icons.add_rounded, onPressed: () => openFdForm(context)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (s.fds.isEmpty)
            EmptyCard(
              icon: Icons.lock_outline_rounded,
              color: C.yellow,
              title: 'No fixed deposits yet',
              message: 'Add an FD to see what it is worth today and what you get at maturity.',
              action: 'Add FD',
              onAction: () => openFdForm(context),
            ),
          if (active.isNotEmpty) ...[
            CardBox(
              child: Column(
                children: [
                  const FdSummary(),
                  for (var i = 0; i < active.length; i++)
                    DecoratedBox(
                      decoration:
                          const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
                      child: FdRow(fd: active[i]),
                    ),
                ],
              ),
            ),
          ],
          if (closed.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionLabel('Closed'),
            CardBox(
              child: Column(
                children: [
                  for (var i = 0; i < closed.length; i++)
                    FdRow(fd: closed[i], divider: i < closed.length - 1),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- detail

class FdScreen extends StatelessWidget {
  const FdScreen({super.key, required this.fdId});

  final int fdId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final f = s.fd(fdId);
    if (f == null) return const Scaffold(body: SizedBox.shrink());
    final now = today();
    final matured = s.fdMatured(f);
    final worth = f.closed ? (f.closedAmount ?? f.principal) : fdValueOn(f, now);
    final maturity = fdMaturityValue(f);
    final progress = fdProgress(f, now);
    final account = s.account(f.accountId);
    final years = fdDays(f) / 365;
    final lengthLabel = _lengthLabel(f);

    Widget line(String label, String value) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.line))),
          child: Row(
            children: [
              Expanded(child: Text(label, style: ts(14, weight: FontWeight.w600, color: C.muted))),
              Text(value, style: ts(15, weight: FontWeight.w800)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(f.name),
        actions: [
          if (!f.closed)
            IconButton(
              tooltip: 'Edit FD',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => openFdForm(context, fd: f),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          const Center(child: IconTile(Icons.lock_outline_rounded, color: C.yellow, size: 56)),
          const SizedBox(height: 10),
          Center(
            child: Text(
              f.closed ? 'Closed' : (matured ? 'Worth at maturity' : 'Worth today'),
              style: ts(13, weight: FontWeight.w700, color: C.muted),
            ),
          ),
          Center(child: Money(worth, size: 40, letterSpacing: -1.5)),
          if (!f.closed)
            Center(
              child: Money(worth - f.principal,
                  size: 13, weight: FontWeight.w600, plus: true, color: C.income),
            ),
          const SizedBox(height: 20),
          if (matured) ...[
            _MaturedCard(fd: f, amount: maturity),
            const SizedBox(height: 20),
          ],
          if (f.closed) ...[
            _ClosedCard(fd: f),
            const SizedBox(height: 20),
          ],
          if (!f.closed && !matured) ...[
            Row(
              children: [
                Expanded(
                  child: Text('Started ${_longDate(f.startDate)}',
                      style: ts(12, weight: FontWeight.w700, color: C.muted)),
                ),
                Text('Matures ${_longDate(f.maturityDate)}',
                    style: ts(12, weight: FontWeight.w700, color: C.muted)),
              ],
            ),
            const SizedBox(height: 8),
            ProgressBar(progress, color: C.yellow, height: 10),
            const SizedBox(height: 8),
            Center(
              child: Text('${_daysLeft(f)} · ${(progress * 100).round()}% done',
                  style: ts(13, weight: FontWeight.w700)),
            ),
            const SizedBox(height: 20),
          ],
          CardBox(
            child: Column(
              children: [
                line('Amount put in', s.amountsHidden ? '₹••••' : money(f.principal)),
                line('Interest rate', '${f.rateLabel} a year'),
                line('Interest added', f.compounding.label),
                line('Time', lengthLabel),
                line('Dates', '${_longDate(f.startDate)} → ${_longDate(f.maturityDate)}'),
                if (account != null) line('Account', account.name),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  color: C.accentTint,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('At maturity', style: ts(14, weight: FontWeight.w800)),
                            Text(
                              '${s.amountsHidden ? '₹••••' : money(maturity - f.principal)} interest'
                              '${years > 0 ? ' in ${fdDays(f)} days' : ''}',
                              style: ts(12, weight: FontWeight.w600, color: C.onAccentSoft),
                            ),
                          ],
                        ),
                      ),
                      Money(maturity, size: 18, color: C.income),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!f.closed && !matured) ...[
            const SizedBox(height: 12),
            Text(
              'On ${_longDate(f.maturityDate)} Funds will ask whether to withdraw it or renew it.',
              style: ts(13, color: C.muted, height: 1.45),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              if (!f.closed && !matured) ...[
                Expanded(
                  child: OutlineBtn('Close early',
                      onPressed: () => openWithdrawSheet(context, f, early: true)),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: OutlineBtn('Delete FD',
                    color: C.expense, onPressed: () => _delete(context, f)),
              ),
            ],
          ),
          if (!f.closed && !matured)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Close early: enter the amount the bank actually paid you.',
                  textAlign: TextAlign.center, style: ts(12, color: C.muted)),
            ),
        ],
      ),
    );
  }

  String _lengthLabel(Fd f) {
    for (final (label, months) in _tenures) {
      if (months != null && addMonthsKeepDay(f.startDate, months) == f.maturityDate) return label;
    }
    return '${fdDays(f)} days';
  }

  Future<void> _delete(BuildContext context, Fd f) async {
    final ok = await confirm(
      context,
      title: 'Delete ${f.name}?',
      message:
          'The FD and the money it moved in and out of your accounts are removed. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !context.mounted) return;
    await context.read<AppState>().deleteFd(f);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _MaturedCard extends StatelessWidget {
  const _MaturedCard({required this.fd, required this.amount});

  final Fd fd;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final hidden = context.select<AppState, bool>((s) => s.amountsHidden);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1408),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A3A12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.celebration_outlined, color: C.yellow, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Matured on ${_longDate(fd.maturityDate)}',
                    style: ts(15, weight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${hidden ? '₹••••' : money(amount)} is ready. Withdraw it to your account, or renew it into a new FD.',
            style: ts(13, color: C.muted, height: 1.45),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlineBtn('Withdraw',
                    onPressed: () => openWithdrawSheet(context, fd, early: false)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: () => openRenewSheet(context, fd),
                    style: FilledButton.styleFrom(
                      backgroundColor: C.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Renew',
                        style: ts(14, weight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClosedCard extends StatelessWidget {
  const _ClosedCard({required this.fd});

  final Fd fd;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final f = fd;
    final amount = s.amountsHidden ? '₹••••' : money(f.closedAmount ?? 0);
    final text = switch (f.closedHow) {
      'renewed' => 'Renewed on ${_longDate(f.closedDate ?? f.maturityDate)} with $amount.',
      'early' => 'Closed early on ${_longDate(f.closedDate ?? f.maturityDate)}. You got $amount.',
      _ => 'Withdrawn on ${_longDate(f.closedDate ?? f.maturityDate)}. You got $amount.',
    };
    final next = s.fd(f.renewedTo);
    return CardBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: ts(14, weight: FontWeight.w700, height: 1.4)),
          if (next != null) ...[
            const SizedBox(height: 10),
            TintButton('Open the new FD', onPressed: () => openFd(context, next.id!)),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- form

class FdFormScreen extends StatefulWidget {
  const FdFormScreen({super.key, this.fd});

  final Fd? fd;

  @override
  State<FdFormScreen> createState() => _FdFormScreenState();
}

class _FdFormScreenState extends State<FdFormScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  DateTime _start = today();
  int? _months = 12;
  DateTime? _custom;
  Compounding _comp = Compounding.quarterly;
  int? _accountId;
  bool _fromAccount = true;
  String? _error;
  bool _saving = false;

  bool get _editing => widget.fd != null;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    final f = widget.fd;
    if (f != null) {
      _name.text = f.name;
      _amount.text = amountInput(f.principal);
      _rate.text = f.rate.toString().replaceAll(RegExp(r'\.0$'), '');
      _start = f.startDate;
      _comp = f.compounding;
      _accountId = f.accountId;
      _months = null;
      _custom = f.maturityDate;
      for (final (_, m) in _tenures) {
        if (m != null && addMonthsKeepDay(f.startDate, m) == f.maturityDate) {
          _months = m;
          _custom = null;
        }
      }
    } else {
      final own = s.visibleAccounts.where((a) => a.kind.isBank).toList();
      _accountId = (own.firstOrNull ?? s.visibleAccounts.firstOrNull)?.id;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _rate.dispose();
    super.dispose();
  }

  DateTime? get _maturity =>
      _months == null ? _custom : addMonthsKeepDay(_start, _months!);

  Future<void> _pickDate({required bool custom}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: custom ? (_custom ?? _start.add(const Duration(days: 365))) : _start,
      firstDate: custom ? _start.add(const Duration(days: 1)) : DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 30, 12, 31),
    );
    if (d == null) return;
    setState(() {
      if (custom) {
        _custom = dateOnly(d);
        _months = null;
      } else {
        _start = dateOnly(d);
        if (_custom != null && !_custom!.isAfter(_start)) _custom = null;
      }
    });
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final name = _name.text.trim();
    final amount = parseAmount(_amount.text);
    final rate = double.tryParse(_rate.text.trim().replaceAll(',', '.'));
    final maturity = _maturity;
    String? err;
    if (name.isEmpty) {
      err = 'Give the FD a name, e.g. SBI FD';
    } else if (amount == null || amount <= 0) {
      err = 'Enter the amount';
    } else if (rate == null || rate <= 0 || rate > 50) {
      err = 'Enter the interest rate (% a year)';
    } else if (maturity == null || !maturity.isAfter(_start)) {
      err = 'Choose when the FD matures';
    } else if (_fromAccount && !_editing && _accountId == null) {
      err = 'Choose the account the money came from';
    }
    setState(() => _error = err);
    if (err != null) return;

    setState(() => _saving = true);
    final old = widget.fd;
    final f = Fd(
      id: old?.id,
      name: name,
      principal: amount!,
      rate: rate!,
      compounding: _comp,
      startDate: _start,
      maturityDate: maturity!,
      accountId: _accountId,
      renewedFrom: old?.renewedFrom,
      createdAt: old?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );
    if (old == null) {
      await s.addFd(f, fromAccount: _fromAccount);
    } else {
      await s.updateFd(f);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final amount = parseAmount(_amount.text) ?? 0;
    final rate = double.tryParse(_rate.text.trim().replaceAll(',', '.')) ?? 0;
    final maturity = _maturity;
    final days = maturity == null ? 0 : maturity.difference(_start).inDays;
    final result = depositValue(amount, rate, _comp, days);
    final acc = s.account(_accountId);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_editing ? 'Edit FD' : 'New fixed deposit'),
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
                    textCapitalization: TextCapitalization.words,
                    style: ts(16, weight: FontWeight.w700),
                    decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. SBI FD'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    style: ts(24, weight: FontWeight.w800),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₹ ',
                      prefixStyle: ts(22, weight: FontWeight.w800, color: C.muted),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rate,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          style: ts(16, weight: FontWeight.w800),
                          decoration: const InputDecoration(
                            labelText: 'Interest rate',
                            hintText: 'e.g. 7.1',
                            suffixText: '% a year',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FieldBox(
                          label: 'Start date',
                          value: friendlyDay(_start),
                          icon: Icons.calendar_today_outlined,
                          onTap: () => _pickDate(custom: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('How long'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, months) in _tenures)
                        FilterPill(
                          months == null && _custom != null && _months == null
                              ? shortDate(_custom!)
                              : label,
                          selected: _months == months && (months != null || _custom != null),
                          onTap: () {
                            if (months == null) {
                              _pickDate(custom: true);
                            } else {
                              setState(() => _months = months);
                            }
                          },
                        ),
                    ],
                  ),
                  if (maturity != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Matures on ${_longDate(maturity)} ($days days)',
                          style: ts(13, weight: FontWeight.w600, color: C.muted)),
                    ),
                  const SizedBox(height: 20),
                  const SectionLabel('Interest is added'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in Compounding.values)
                        FilterPill(c.label,
                            selected: _comp == c, onTap: () => setState(() => _comp = c)),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Most Indian banks add FD interest every 3 months.',
                        style: ts(12, color: C.muted)),
                  ),
                  const SizedBox(height: 20),
                  FieldBox(
                    label: 'Account',
                    value: acc?.name ?? 'Choose',
                    onTap: () async {
                      final id = await pickAccount(context,
                          title: 'Money came from', selected: _accountId, includeCards: false);
                      if (id != null) setState(() => _accountId = id);
                    },
                  ),
                  if (!_editing) ...[
                    const SizedBox(height: 8),
                    CardBox(
                      child: SwitchListTile(
                        value: _fromAccount,
                        onChanged: (v) => setState(() => _fromAccount = v),
                        title: Text('Take the amount from this account',
                            style: ts(15, weight: FontWeight.w700)),
                        subtitle: Text(
                          _fromAccount
                              ? 'For a new FD: ${acc?.name ?? 'the account'} goes down by the amount (not spending).'
                              : 'For an FD you opened earlier: no money moves now.',
                          style: ts(13, color: C.muted, height: 1.4),
                        ),
                      ),
                    ),
                  ],
                  if (amount > 0 && rate > 0 && maturity != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: C.accentTint,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('At maturity you get',
                                    style: ts(14, weight: FontWeight.w800)),
                              ),
                              Text(money(result),
                                  style: ts(22, weight: FontWeight.w800, color: C.income)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('${money(amount)} + ${money(result - amount)} interest',
                              style: ts(13, weight: FontWeight.w600, color: C.onAccentSoft)),
                        ],
                      ),
                    ),
                  ],
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
              child: PrimaryButton(_editing ? 'Save changes' : 'Save FD',
                  onPressed: _saving ? null : _save),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------ withdraw sheet

Future<void> openWithdrawSheet(BuildContext context, Fd fd, {required bool early}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WithdrawSheet(fd: fd, early: early),
  );
}

class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({required this.fd, required this.early});

  final Fd fd;
  final bool early;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _amount = TextEditingController();
  int? _accountId;
  late DateTime _date;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    final f = widget.fd;
    _amount.text = amountInput(widget.early ? fdValueOn(f, today()) : fdMaturityValue(f));
    _date = widget.early ? today() : f.maturityDate;
    _accountId = f.accountId ?? s.visibleAccounts.firstOrNull?.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = parseAmount(_amount.text);
    String? err;
    if (v == null || v <= 0) {
      err = 'Enter the amount you got';
    } else if (_accountId == null) {
      err = 'Choose an account';
    }
    setState(() => _error = err);
    if (err != null) return;
    await context.read<AppState>().withdrawFd(widget.fd,
        received: v!, accountId: _accountId!, date: _date, early: widget.early);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final f = widget.fd;
    final v = parseAmount(_amount.text) ?? 0;
    final base = s.fdOriginalDeposit(f);
    final back = v < base ? v : base;
    final interest = v - back;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.early ? 'Close ${f.name} early' : 'Withdraw ${f.name}',
                style: ts(22, weight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              widget.early
                  ? 'Banks pay a little less when an FD is closed early. Enter what you actually got.'
                  : 'If the bank paid a little less (for example after tax), enter what you actually got.',
              style: ts(13, color: C.muted, height: 1.45),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _error = null),
              style: ts(26, weight: FontWeight.w800),
              decoration: InputDecoration(
                labelText: 'Amount received',
                prefixText: '₹ ',
                prefixStyle: ts(24, weight: FontWeight.w800, color: C.muted),
                errorText: _error,
              ),
            ),
            if (v > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  interest > 0
                      ? '${money(back)} back + ${money(interest)} interest (counted as income)'
                      : '${money(back)} back',
                  style: ts(13, weight: FontWeight.w600, color: C.muted),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FieldBox(
                    label: 'Added to',
                    value: s.account(_accountId)?.name ?? 'Choose',
                    onTap: () async {
                      final id = await pickAccount(context,
                          title: 'Added to', selected: _accountId, includeCards: false);
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
                        firstDate: f.startDate,
                        lastDate: DateTime(DateTime.now().year + 30, 12, 31),
                      );
                      if (d != null) setState(() => _date = dateOnly(d));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PrimaryButton(widget.early ? 'Close FD' : 'Withdraw', onPressed: _save),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------- renew sheet

Future<void> openRenewSheet(BuildContext context, Fd fd) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RenewSheet(fd: fd),
  );
}

class _RenewSheet extends StatefulWidget {
  const _RenewSheet({required this.fd});

  final Fd fd;

  @override
  State<_RenewSheet> createState() => _RenewSheetState();
}

class _RenewSheetState extends State<_RenewSheet> {
  bool _withInterest = true;
  late final _rate =
      TextEditingController(text: widget.fd.rate.toString().replaceAll(RegExp(r'\.0$'), ''));
  late Compounding _comp = widget.fd.compounding;
  int? _months = 12;
  DateTime? _custom;
  int? _accountId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final f = widget.fd;
    _accountId = f.accountId ?? context.read<AppState>().visibleAccounts.firstOrNull?.id;
    for (final (_, m) in _tenures) {
      if (m != null && addMonthsKeepDay(f.startDate, m) == f.maturityDate) _months = m;
    }
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  DateTime get _start => widget.fd.maturityDate;

  DateTime? get _maturity => _months == null ? _custom : addMonthsKeepDay(_start, _months!);

  Future<void> _save() async {
    final rate = double.tryParse(_rate.text.trim().replaceAll(',', '.'));
    final maturity = _maturity;
    String? err;
    if (rate == null || rate <= 0 || rate > 50) {
      err = 'Enter the new interest rate';
    } else if (maturity == null) {
      err = 'Choose when the new FD matures';
    } else if (!_withInterest && _accountId == null) {
      err = 'Choose where the interest goes';
    }
    setState(() => _error = err);
    if (err != null) return;
    await context.read<AppState>().renewFd(
          widget.fd,
          withInterest: _withInterest,
          accountId: _accountId,
          rate: rate!,
          compounding: _comp,
          maturity: maturity!,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final f = widget.fd;
    final value = fdMaturityValue(f);
    final interest = value - f.principal;
    final newPrincipal = _withInterest ? value : f.principal;
    final rate = double.tryParse(_rate.text.trim().replaceAll(',', '.')) ?? 0;
    final maturity = _maturity;
    final days = maturity == null ? 0 : maturity.difference(_start).inDays;
    final result = depositValue(newPrincipal, rate, _comp, days);
    final accName = s.account(_accountId)?.name ?? 'your account';

    Widget choice(bool withInterest, String title, String sub) {
      final on = _withInterest == withInterest;
      return Semantics(
        selected: on,
        button: true,
        child: Material(
          color: on ? C.accentTint : C.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: on ? C.accent : C.line, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _withInterest = withInterest),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(on ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: on ? C.accent : C.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: ts(15, weight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(sub, style: ts(13, color: C.muted, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Renew ${f.name}', style: ts(22, weight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('The new FD starts on ${_longDate(_start)}.', style: ts(13, color: C.muted)),
            const SizedBox(height: 14),
            choice(true, 'Renew with interest',
                'All ${money(value)} goes into the new FD.'),
            const SizedBox(height: 8),
            choice(false, 'Renew without interest',
                '${money(interest)} interest goes to $accName. ${money(f.principal)} stays in the FD.'),
            if (!_withInterest) ...[
              const SizedBox(height: 8),
              FieldBox(
                label: 'Interest goes to',
                value: s.account(_accountId)?.name ?? 'Choose',
                onTap: () async {
                  final id = await pickAccount(context,
                      title: 'Interest goes to', selected: _accountId, includeCards: false);
                  if (id != null) setState(() => _accountId = id);
                },
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              style: ts(16, weight: FontWeight.w800),
              decoration: const InputDecoration(
                labelText: 'New interest rate',
                suffixText: '% a year',
              ),
            ),
            const SizedBox(height: 14),
            const SectionLabel('How long'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, months) in _tenures)
                  FilterPill(
                    months == null && _custom != null && _months == null
                        ? shortDate(_custom!)
                        : label,
                    selected: _months == months && (months != null || _custom != null),
                    onTap: () async {
                      if (months != null) {
                        setState(() => _months = months);
                        return;
                      }
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _custom ?? _start.add(const Duration(days: 365)),
                        firstDate: _start.add(const Duration(days: 1)),
                        lastDate: DateTime(DateTime.now().year + 30, 12, 31),
                      );
                      if (d != null) {
                        setState(() {
                          _custom = dateOnly(d);
                          _months = null;
                        });
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const SectionLabel('Interest is added'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in Compounding.values)
                  FilterPill(c.label, selected: _comp == c, onTap: () => setState(() => _comp = c)),
              ],
            ),
            if (maturity != null && rate > 0) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: C.accentTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'New FD: ${money(newPrincipal)} until ${_longDate(maturity)}. '
                  'You get ${money(result)} at maturity.',
                  style: ts(13, weight: FontWeight.w700, height: 1.45),
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: ts(13, weight: FontWeight.w700, color: C.expense)),
              ),
            const SizedBox(height: 16),
            PrimaryButton('Renew', onPressed: _save),
          ],
        ),
      ),
    );
  }
}
