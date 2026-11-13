import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';
import 'account_form_screen.dart';
import 'fd_screen.dart';
import 'lend_screen.dart';
import 'sip_screen.dart';
import 'tags_screen.dart';

/// Opens the add/edit entry screen.
Future<void> openEntryForm(
  BuildContext context, {
  Entry? entry,
  EntryType? type,
  int? accountId,
  int? toAccountId,
  Set<int>? tagIds,
  DateTime? date,
}) {
  // Lend & borrow entries are managed on the person's page.
  final loanId = entry?.loanId;
  if (loanId != null) {
    final personId = context.read<AppState>().loan(loanId)?.personId;
    if (personId != null) return openPerson(context, personId);
  }
  // Fixed deposit entries are managed on the FD's page.
  final fdId = entry?.fdId;
  if (fdId != null && context.read<AppState>().fd(fdId) != null) {
    return openFd(context, fdId);
  }
  // Mutual fund entries are managed on the fund's page.
  final fundId = entry?.fundId;
  if (fundId != null && context.read<AppState>().fund(fundId) != null) {
    return openFund(context, fundId);
  }
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => EntryFormScreen(
      entry: entry,
      initialType: type,
      initialAccountId: accountId,
      initialToAccountId: toAccountId,
      initialTags: tagIds,
      initialDate: date,
    ),
  ));
}

class EntryFormScreen extends StatefulWidget {
  const EntryFormScreen({
    super.key,
    this.entry,
    this.initialType,
    this.initialAccountId,
    this.initialToAccountId,
    this.initialTags,
    this.initialDate,
  });

  final Entry? entry;
  final EntryType? initialType;
  final int? initialAccountId;
  final int? initialToAccountId;
  final Set<int>? initialTags;
  final DateTime? initialDate;

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late EntryType _type;
  late String _category;
  int? _accountId;
  int? _toAccountId;
  late DateTime _date;
  String? _error;
  bool _saving = false;

  /// Tags picked for this entry.
  Set<int> _tags = {};

  /// Trip tags the user removed by hand (not added back when the date
  /// changes).
  final Set<int> _removedAuto = {};

  bool get _editing => widget.entry != null;

  static String _defaultCat(EntryType t) => t == EntryType.income ? 'salary' : 'food';

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    final e = widget.entry;
    if (e != null) {
      _type = e.type;
      _category = e.category;
      _accountId = e.accountId;
      _toAccountId = e.toAccountId;
      _date = e.date;
      _amount.text = amountInput(e.amount);
      _note.text = e.note;
      _tags = {...s.tagsOf(e.id)};
      return;
    }
    _type = widget.initialType ?? EntryType.expense;
    _category = _defaultCat(_type);
    _date = widget.initialDate == null ? today() : dateOnly(widget.initialDate!);
    _tags = {...?widget.initialTags};
    if (s.feature(Features.tags)) _tags.addAll(s.autoTripsOn(_date));
    _toAccountId = widget.initialToAccountId;

    final visible = s.visibleAccounts;
    bool ok(int? id) => id != null && visible.any((a) => a.id == id) && id != _toAccountId;
    if (ok(widget.initialAccountId)) {
      _accountId = widget.initialAccountId;
    } else if (ok(s.lastAccountId)) {
      _accountId = s.lastAccountId;
    } else {
      final candidates = visible.where((a) => a.id != _toAccountId).toList();
      final nonCard = candidates.where((a) => !a.isCard).toList();
      _accountId = (nonCard.isNotEmpty ? nonCard.first : candidates.firstOrNull)?.id;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setType(EntryType t) {
    if (t == _type) return;
    setState(() {
      _type = t;
      _category = _defaultCat(t);
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (d == null) return;
    setState(() {
      final s = context.read<AppState>();
      // A new entry follows the trips of its new date.
      if (!_editing && s.feature(Features.tags)) {
        _tags.removeAll(s.autoTripsOn(_date).difference(widget.initialTags ?? const {}));
        _tags.addAll(s.autoTripsOn(dateOnly(d)).difference(_removedAuto));
      }
      _date = dateOnly(d);
    });
  }

  bool get _canTag => _type == EntryType.expense || _type == EntryType.income;

  List<Widget> _tagsRow(AppState s) {
    if (!s.feature(Features.tags) || !_canTag) return const [];
    // Plain tags, trips around this date, and anything already picked.
    final shown = s.tags
        .where((t) => !t.isTrip || t.covers(_date) || _tags.contains(t.id))
        .toList()
      ..sort((a, b) {
        if (a.isTrip != b.isTrip) return a.isTrip ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return [
      const SizedBox(height: 16),
      const SectionLabel('Tags'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in shown)
            _TagChip(
              label: '#${t.name}',
              color: tagColor(t.color),
              selected: _tags.contains(t.id),
              onTap: () => setState(() {
                if (_tags.remove(t.id)) {
                  _removedAuto.add(t.id!);
                } else {
                  _tags.add(t.id!);
                  _removedAuto.remove(t.id);
                }
              }),
            ),
          _TagChip(
            label: '+ New',
            color: C.accent,
            selected: false,
            dashed: true,
            onTap: () async {
              final id = await quickNewTag(context);
              if (id != null) setState(() => _tags.add(id));
            },
          ),
        ],
      ),
      if (s.tags.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Group entries, like a trip or office claims, and see their total.',
              style: ts(12, color: C.muted)),
        ),
    ];
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    String? err;
    if (amount == null || amount <= 0) {
      err = 'Enter an amount';
    } else if (_accountId == null) {
      err = 'Choose an account';
    } else if (_type == EntryType.transfer && _toAccountId == null) {
      err = 'Choose where the money goes';
    } else if (_type == EntryType.transfer && _toAccountId == _accountId) {
      err = 'Pick two different accounts';
    }
    setState(() => _error = err);
    if (err != null) return;

    setState(() => _saving = true);
    final old = widget.entry;
    await context.read<AppState>().saveEntry(Entry(
          id: old?.id,
          type: _type,
          amount: amount!,
          accountId: _accountId!,
          toAccountId: _type == EntryType.transfer ? _toAccountId : null,
          category: _type == EntryType.transfer ? 'transfer' : _category,
          note: _note.text.trim(),
          date: _date,
          createdAt: old?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
          planId: old?.planId,
        ),
        tagIds: context.read<AppState>().feature(Features.tags)
            ? (_canTag ? _tags : <int>{})
            : null);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete this entry?',
      message: 'The account balance will be updated. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    await context.read<AppState>().deleteEntry(widget.entry!.id!);
    if (mounted) Navigator.of(context).pop();
  }

  /// "Food budget: ₹2,400 left of ₹5,000 in November 2026".
  List<Widget> _budgetHint(AppState s) {
    if (!s.feature(Features.budgets)) return const [];
    final b = s.budgets.where((b) => b.category == _category).firstOrNull;
    if (b == null) return const [];
    final spent = s.spentInCategory(_category, _date);
    final left = b.amount - spent;
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);
    final label = catFor(_category).label;
    final over = left < 0;
    final text = over
        ? '$label budget: ${m(-left)} over the ${m(b.amount)} limit in ${monthTitle(_date)}'
        : '$label budget: ${m(left)} left of ${m(b.amount)} in ${monthTitle(_date)}';
    return [
      const SizedBox(height: 10),
      Row(
        children: [
          Icon(Icons.donut_large_rounded, size: 16, color: over ? C.expense : C.yellow),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: ts(13, weight: FontWeight.w600, color: over ? C.expense : C.muted)),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final noAccounts = s.visibleAccounts.isEmpty;
    final amountColor = switch (_type) {
      EntryType.expense => C.expense,
      EntryType.income => C.income,
      _ => C.transfer,
    };
    final saveLabel = switch (_type) {
      EntryType.expense => 'Save expense',
      EntryType.income => 'Save income',
      _ => 'Save transfer',
    };

    String accLabel(int? id) {
      final a = s.account(id);
      if (a == null) return 'Choose account';
      final bal = s.amountsHidden ? '₹••••' : money(s.balanceOf(a.id!));
      return '${a.name} · $bal';
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_editing ? 'Edit entry' : 'New entry'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Delete entry',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: C.expense),
            ),
        ],
      ),
      body: SafeArea(
        child: noAccounts
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: EmptyCard(
                  icon: Icons.account_balance_outlined,
                  title: 'Add an account first',
                  message: 'Entries are saved to an account, like your bank or cash.',
                  action: 'Add account',
                  onAction: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const AccountFormScreen())),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      children: [
                        _Segmented(value: _type, onChanged: _setType),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _amount,
                          autofocus: !_editing,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: ts(48, weight: FontWeight.w800, letterSpacing: -2),
                          decoration: InputDecoration(
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: '0',
                            hintStyle: ts(48, weight: FontWeight.w800, color: C.faint),
                            prefixText: '₹ ',
                            prefixStyle: ts(32, weight: FontWeight.w800, color: amountColor),
                            semanticCounterText: 'Amount',
                          ),
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: ts(13, weight: FontWeight.w700, color: C.expense)),
                          ),
                        const SizedBox(height: 8),
                        if (_type != EntryType.transfer) ...[
                          const SectionLabel('Category'),
                          _CategoryGrid(
                            cats: _type == EntryType.income ? incomeCats : expenseCats,
                            selected: _category,
                            onPick: (k) => setState(() => _category = k),
                          ),
                          if (_type == EntryType.expense) ..._budgetHint(s),
                          const SizedBox(height: 16),
                          FieldBox(
                            label: _type == EntryType.income ? 'Received in' : 'Paid from',
                            value: accLabel(_accountId),
                            onTap: () async {
                              final id = await pickAccount(context,
                                  title: _type == EntryType.income ? 'Received in' : 'Paid from',
                                  selected: _accountId);
                              if (id != null) setState(() => _accountId = id);
                            },
                          ),
                        ] else ...[
                          FieldBox(
                            label: 'From',
                            value: accLabel(_accountId),
                            onTap: () async {
                              final id = await pickAccount(context,
                                  title: 'Move money from', selected: _accountId);
                              if (id != null) setState(() => _accountId = id);
                            },
                          ),
                          Center(
                            child: IconButton(
                              tooltip: 'Swap accounts',
                              onPressed: () => setState(() {
                                final t = _accountId;
                                _accountId = _toAccountId;
                                _toAccountId = t;
                              }),
                              icon: const Icon(Icons.swap_vert_rounded, color: C.transfer),
                            ),
                          ),
                          FieldBox(
                            label: 'To',
                            value: accLabel(_toAccountId),
                            onTap: () async {
                              final id = await pickAccount(context,
                                  title: 'Move money to', selected: _toAccountId);
                              if (id != null) setState(() => _toAccountId = id);
                            },
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: FieldBox(
                                label: 'Date',
                                value: friendlyDay(_date),
                                icon: Icons.calendar_today_outlined,
                                onTap: _pickDate,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _note,
                                textCapitalization: TextCapitalization.sentences,
                                style: ts(15, weight: FontWeight.w700),
                                decoration: const InputDecoration(
                                  labelText: 'Note',
                                  hintText: 'Optional',
                                ),
                              ),
                            ),
                          ],
                        ),
                        ..._tagsRow(s),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: PrimaryButton(_editing ? 'Save changes' : saveLabel,
                        onPressed: _saving ? null : _save),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.onChanged});

  final EntryType value;
  final ValueChanged<EntryType> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      (EntryType.expense, 'Expense'),
      (EntryType.income, 'Income'),
      (EntryType.transfer, 'Transfer'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.line),
      ),
      child: Row(
        children: [
          for (final (t, label) in items)
            Expanded(
              child: Semantics(
                selected: value == t,
                button: true,
                child: Material(
                  color: value == t ? C.text : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onChanged(t),
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(label,
                            style: ts(14,
                                weight: FontWeight.w800,
                                color: value == t ? C.bg : C.muted)),
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

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.cats, required this.selected, required this.onPick});

  final List<Cat> cats;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.95,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final c in cats)
          Semantics(
            selected: c.key == selected,
            button: true,
            child: Material(
              color: c.key == selected ? C.accentTint : C.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: c.key == selected ? C.accent : C.line, width: 1.5),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onPick(c.key),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(c.icon, color: c.color, size: 22),
                    const SizedBox(height: 6),
                    Text(c.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(12, weight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.dashed = false,
  });

  final String label;
  final Color color;
  final bool selected;
  final bool dashed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? Color.alphaBlend(color.withValues(alpha: 0.16), C.bg) : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? color : (dashed ? C.dashed : C.border), width: 1.5),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // widthFactor 1 keeps the chip as wide as its text.
            child: Align(
              widthFactor: 1,
              child: Text(label,
                  style: ts(13,
                      weight: FontWeight.w800,
                      color: selected ? color : (dashed ? C.accent : C.text))),
            ),
          ),
        ),
      ),
    );
  }
}
