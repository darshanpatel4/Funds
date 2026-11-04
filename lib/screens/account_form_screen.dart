import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';

/// Add or edit an account (bank, cash, wallet or credit card).
class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({super.key, this.account, this.initialKind});

  final Account? account;
  final AccountKind? initialKind;

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _name = TextEditingController();
  final _balance = TextEditingController();
  final _limit = TextEditingController();
  final _dueDay = TextEditingController();
  late AccountKind _kind;
  late bool _counted;
  String? _nameError;
  String? _balanceError;
  String? _dueError;
  bool _saving = false;

  bool get _editing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _kind = a?.kind ?? widget.initialKind ?? AccountKind.savings;
    _counted = a?.counted ?? true;
    if (a != null) {
      _name.text = a.name;
      // Cards store minus the outstanding amount.
      final shown = a.isCard ? -a.opening : a.opening;
      _balance.text = shown == 0 ? '' : amountInput(shown);
      if (a.creditLimit != null) _limit.text = amountInput(a.creditLimit!);
      if (a.dueDay != null) _dueDay.text = '${a.dueDay}';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _limit.dispose();
    _dueDay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final name = _name.text.trim();
    final isCard = _kind == AccountKind.card;
    int? bal = _balance.text.trim().isEmpty
        ? 0
        : parseAmount(_balance.text, allowNegative: !isCard);
    int? due;
    if (isCard && _dueDay.text.trim().isNotEmpty) {
      due = int.tryParse(_dueDay.text.trim());
    }

    setState(() {
      _nameError = name.isEmpty ? 'Give the account a name' : null;
      _balanceError = bal == null ? 'Enter a number' : null;
      _dueError = isCard && _dueDay.text.trim().isNotEmpty && (due == null || due < 1 || due > 31)
          ? 'Use a day from 1 to 31'
          : null;
    });
    if (_nameError != null || _balanceError != null || _dueError != null) return;

    setState(() => _saving = true);
    final old = widget.account;
    await s.saveAccount(Account(
      id: old?.id,
      name: name,
      kind: _kind,
      opening: isCard ? -bal! : bal!,
      creditLimit: isCard ? parseAmount(_limit.text) : null,
      dueDay: isCard ? due : null,
      sort: old?.sort ?? 0,
      createdAt: old?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      counted: _counted,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final s = context.read<AppState>();
    final a = widget.account!;
    final n = s.entryCountFor(a.id!);
    final ok = await confirm(
      context,
      title: 'Delete ${a.name}?',
      message: n == 0
          ? 'This account will be removed.'
          : 'Its $n ${n == 1 ? 'entry' : 'entries'} and any plans using it will be deleted too. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    await s.deleteAccount(a.id!);
    if (!mounted) return;
    // Close the form and the passbook behind it.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final isCard = _kind == AccountKind.card;
    final kinds = [
      AccountKind.savings,
      AccountKind.current,
      AccountKind.cash,
      AccountKind.wallet,
      if (s.feature(Features.cards) || _kind == AccountKind.card) AccountKind.card,
    ];

    String balanceLabel;
    if (isCard) {
      balanceLabel = _editing ? 'Outstanding when added' : 'Current outstanding';
    } else {
      balanceLabel = _editing ? 'Opening balance' : 'Current balance';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit account' : 'New account'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Delete account',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: C.expense),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    style: ts(16, weight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: isCard ? 'e.g. HDFC Millennia' : 'e.g. SBI, Cash, Paytm',
                      errorText: _nameError,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('Type'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final k in kinds)
                        _KindChip(
                          kind: k,
                          selected: _kind == k,
                          // A card can't become a bank account and back,
                          // because its balance means something different.
                          enabled: !_editing || (k == AccountKind.card) == (widget.account!.isCard),
                          onTap: () => setState(() => _kind = k),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _balance,
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true, signed: !isCard),
                    style: ts(16, weight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: balanceLabel,
                      prefixText: '₹ ',
                      hintText: '0',
                      errorText: _balanceError,
                      helperText: isCard
                          ? 'How much you owe on this card right now.'
                          : _editing
                              ? 'Balance before your first entry. Changing it changes the current balance.'
                              : 'Put a minus sign (-) if the account is overdrawn.',
                      helperMaxLines: 2,
                      helperStyle: ts(12, color: C.muted),
                    ),
                  ),
                  if (isCard) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _limit,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: ts(16, weight: FontWeight.w700),
                      decoration: const InputDecoration(
                        labelText: 'Credit limit (optional)',
                        prefixText: '₹ ',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _dueDay,
                      keyboardType: TextInputType.number,
                      style: ts(16, weight: FontWeight.w700),
                      decoration: InputDecoration(
                        labelText: 'Bill due day (optional)',
                        hintText: '1 to 31',
                        errorText: _dueError,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  CardBox(
                    child: SwitchListTile(
                      value: _counted,
                      onChanged: (v) => setState(() => _counted = v),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: Text('Count in my total balance',
                          style: ts(15, weight: FontWeight.w700)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _counted
                              ? 'This is your own money. It adds to your total balance, money in/out and budget.'
                              : 'Not your own money, like a family or company account. It is kept out of your total balance, money in/out and budget.',
                          style: ts(13, color: C.muted, height: 1.4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: PrimaryButton(_editing ? 'Save changes' : 'Add account',
                  onPressed: _saving ? null : _save),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.kind,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AccountKind kind;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled ? C.faint : (selected ? C.accent : C.text);
    return Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      child: Material(
        color: selected ? C.accentTint : C.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? C.accent : C.line, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(accountIcon(kind), size: 18, color: color),
                const SizedBox(width: 8),
                Text(kind.label, style: ts(14, weight: FontWeight.w700, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
