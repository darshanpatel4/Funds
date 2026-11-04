import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../data/models.dart';
import '../data/recurring.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';

Future<void> openPlanForm(BuildContext context, {required PlanKind kind, Plan? plan}) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PlanFormScreen(kind: kind, plan: plan),
  ));
}

class PlanFormScreen extends StatefulWidget {
  const PlanFormScreen({super.key, required this.kind, this.plan});

  final PlanKind kind;
  final Plan? plan;

  @override
  State<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends State<PlanFormScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _tenure = TextEditingController();
  final _paid = TextEditingController();
  int _day = 1;
  int? _accountId;
  String _category = 'bills';
  bool _active = true;
  String? _nameError;
  String? _amountError;
  String? _tenureError;
  String? _formError;
  bool _saving = false;

  bool get _editing => widget.plan != null;
  PlanKind get _kind => widget.kind;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    final p = widget.plan;
    if (p != null) {
      _name.text = p.name;
      _amount.text = amountInput(p.amount);
      _day = p.day;
      _accountId = p.accountId;
      _category = p.category;
      _active = p.active;
      if (p.tenure != null) _tenure.text = '${p.tenure}';
    } else {
      _name.text = _kind == PlanKind.income ? 'Salary' : '';
      // Start on the 1st so nothing is added the moment the plan is saved;
      // the note under the form shows when the first one will be added.
      _day = 1;
      final nonCard = s.visibleAccounts.where((a) => !a.isCard).toList();
      _accountId = (nonCard.isNotEmpty ? nonCard.first : s.visibleAccounts.firstOrNull)?.id;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _tenure.dispose();
    _paid.dispose();
    super.dispose();
  }

  String get _title => switch (_kind) {
        PlanKind.income => _editing ? 'Edit salary' : 'New salary',
        PlanKind.sip => _editing ? 'Edit SIP' : 'New SIP',
        PlanKind.bill => _editing ? 'Edit bill' : 'New bill or rent',
        PlanKind.loan => _editing ? 'Edit loan' : 'New loan',
      };

  String get _nameHint => switch (_kind) {
        PlanKind.income => 'e.g. Salary',
        PlanKind.sip => 'e.g. Parag Parikh Flexi Cap',
        PlanKind.bill => 'e.g. House rent, YouTube, LIC',
        PlanKind.loan => 'e.g. Home loan, Bike loan',
      };

  String get _amountLabel => switch (_kind) {
        PlanKind.income => 'Amount credited',
        PlanKind.sip => 'Monthly amount',
        PlanKind.bill => 'Amount',
        PlanKind.loan => 'EMI amount',
      };

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
              Text('In shorter months the last day is used.',
                  style: ts(13, color: C.muted)),
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
                                  weight: FontWeight.w800,
                                  color: i == _day ? Colors.white : C.text)),
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

  Future<void> _save() async {
    final s = context.read<AppState>();
    final name = _name.text.trim();
    final amount = parseAmount(_amount.text);
    int? tenure;
    var alreadyPaid = 0;
    String? tenureErr;
    if (_kind == PlanKind.loan) {
      tenure = int.tryParse(_tenure.text.trim());
      alreadyPaid = int.tryParse(_paid.text.trim().isEmpty ? '0' : _paid.text.trim()) ?? -1;
      if (tenure == null || tenure < 1 || tenure > 600) {
        tenureErr = 'Enter the total number of EMIs';
      } else if (!_editing && (alreadyPaid < 0 || alreadyPaid >= tenure)) {
        tenureErr = 'EMIs already paid must be less than the total';
      }
    }
    setState(() {
      _nameError = name.isEmpty ? 'Give it a name' : null;
      _amountError = amount == null || amount <= 0 ? 'Enter an amount' : null;
      _tenureError = tenureErr;
      _formError = _accountId == null ? 'Choose an account' : null;
    });
    if (_nameError != null || _amountError != null || _tenureError != null || _formError != null) {
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final old = widget.plan;
    String startMonth;
    String? lastPosted;
    if (old != null && old.lastPosted != null) {
      startMonth = old.startMonth;
      lastPosted = old.lastPosted;
    } else {
      // Nothing added yet: start from the next time this day comes round.
      final first = firstMonthFor(_day, now);
      startMonth = first;
      if (alreadyPaid > 0) {
        final f = parseMonth(first);
        startMonth = monthKey(addMonths(f, -alreadyPaid));
        lastPosted = monthKey(addMonths(f, -1));
      }
    }

    await s.savePlan(Plan(
      id: old?.id,
      kind: _kind,
      name: name,
      amount: amount!,
      day: _day,
      accountId: _accountId!,
      startMonth: startMonth,
      lastPosted: lastPosted,
      tenure: _kind == PlanKind.loan ? tenure : null,
      active: _active,
      category: switch (_kind) {
        PlanKind.income => 'salary',
        PlanKind.sip => 'investment',
        PlanKind.loan => 'emi',
        PlanKind.bill => _category,
      },
      createdAt: old?.createdAt ?? now.millisecondsSinceEpoch,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete ${widget.plan!.name}?',
      message: 'Entries already added stay in your accounts. Nothing new will be added.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    await context.read<AppState>().deletePlan(widget.plan!.id!);
    if (mounted) Navigator.of(context).pop();
  }

  String _nextText(AppState s) {
    final acc = s.account(_accountId)?.name ?? 'the account';
    final verb = _kind == PlanKind.income ? 'added to' : 'taken from';
    if (!_active) return 'Paused. Nothing will be added until you turn it back on.';
    DateTime next;
    final old = widget.plan;
    if (old != null && old.lastPosted != null) {
      if (isFinished(old)) return 'All EMIs are paid.';
      final m = nextMonthToPost(old);
      next = dueDateIn(m.year, m.month, _day);
    } else {
      final m = parseMonth(firstMonthFor(_day, DateTime.now()));
      next = dueDateIn(m.year, m.month, _day);
    }
    return 'Next: ${friendlyDay(next)}. It will be $verb $acc automatically.';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final acc = s.account(_accountId);

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Delete',
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
                      hintText: _nameHint,
                      errorText: _nameError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: ts(16, weight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: _amountLabel,
                      prefixText: '₹ ',
                      errorText: _amountError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FieldBox(
                          label: 'Every month on',
                          value: 'the ${ordinal(_day)}',
                          icon: Icons.calendar_today_outlined,
                          onTap: _pickDay,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FieldBox(
                          label: _kind == PlanKind.income ? 'Credited to' : 'Paid from',
                          value: acc?.name ?? 'Choose',
                          onTap: () async {
                            final id = await pickAccount(context,
                                title: _kind == PlanKind.income ? 'Credited to' : 'Paid from',
                                selected: _accountId);
                            if (id != null) setState(() => _accountId = id);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_formError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_formError!,
                          style: ts(13, weight: FontWeight.w700, color: C.expense)),
                    ),
                  if (_kind == PlanKind.bill) ...[
                    const SizedBox(height: 20),
                    const SectionLabel('Category'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final key in billCats)
                          _CatChip(
                            cat: catFor(key),
                            selected: _category == key,
                            onTap: () => setState(() => _category = key),
                          ),
                      ],
                    ),
                  ],
                  if (_kind == PlanKind.loan) ...[
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tenure,
                            keyboardType: TextInputType.number,
                            style: ts(16, weight: FontWeight.w700),
                            decoration: InputDecoration(
                              labelText: 'Total EMIs',
                              hintText: 'e.g. 24',
                              errorText: _tenureError,
                              errorMaxLines: 2,
                            ),
                          ),
                        ),
                        if (!_editing) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _paid,
                              keyboardType: TextInputType.number,
                              style: ts(16, weight: FontWeight.w700),
                              decoration: const InputDecoration(
                                labelText: 'Already paid',
                                hintText: '0',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_editing && widget.plan!.tenure != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${paidCount(widget.plan!)} of ${widget.plan!.tenure} EMIs paid',
                          style: ts(13, color: C.muted),
                        ),
                      ),
                  ],
                  if (_editing) ...[
                    const SizedBox(height: 16),
                    CardBox(
                      child: SwitchListTile(
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                        title: Text('Active', style: ts(15, weight: FontWeight.w700)),
                        subtitle: Text('Turn off to pause it', style: ts(13, color: C.muted)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18, color: C.muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_nextText(s), style: ts(13, color: C.muted, height: 1.45)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: PrimaryButton(_editing ? 'Save changes' : 'Save plan',
                  onPressed: _saving ? null : _save),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  const _CatChip({required this.cat, required this.selected, required this.onTap});

  final Cat cat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? C.accentTint : C.surface,
        shape: StadiumBorder(
            side: BorderSide(color: selected ? C.accent : C.line, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(cat.icon, size: 18, color: cat.color),
                const SizedBox(width: 8),
                Text(cat.label, style: ts(14, weight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
