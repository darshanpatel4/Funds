import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/budget_sheet.dart';
import '../widgets/ui.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final showGoals = s.feature(Features.goals);
    final showBudgets = s.feature(Features.budgets);
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);

    return Scaffold(
      appBar: AppBar(
        title: Text(showGoals && showBudgets
            ? 'Goals & budgets'
            : showBudgets
                ? 'Budgets'
                : 'Savings goals'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (!showGoals && !showBudgets)
            const EmptyCard(
              icon: Icons.flag_outlined,
              title: 'Goals and budgets are off',
              message: 'Turn them on in Settings.',
            ),
          if (showGoals) ...[
            const SectionLabel('Savings goals'),
            for (final g in s.goals)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GoalCard(goal: g, onTap: () => openGoalForm(context, goal: g)),
              ),
            DashedAddRow(
              icon: Icons.flag_outlined,
              color: C.teal,
              title: s.goals.isEmpty ? 'Start a savings goal' : 'New goal',
              subtitle: 'A trip, a gadget or an emergency fund',
              onTap: () => openGoalForm(context),
            ),
          ],
          if (showBudgets) ...[
            if (showGoals) const SizedBox(height: 28),
            SectionLabel('Monthly budget · ${monthTitle(month)}'),
            _OverallBudgetRow(state: s, month: month),
            const SizedBox(height: 20),
            const SectionLabel('Category budgets'),
            if (s.budgets.isEmpty)
              EmptyCard(
                icon: Icons.donut_large_rounded,
                color: C.yellow,
                title: 'No category budgets yet',
                message:
                    "Set a monthly limit for a category like Food or Shopping. You'll see how much is left as you spend.",
                action: 'Set a budget',
                onAction: () => openBudgetSheet(context),
              )
            else ...[
              CardBox(
                child: Column(
                  children: [
                    for (var i = 0; i < s.budgets.length; i++)
                      BudgetRow(
                        budget: s.budgets[i],
                        spent: s.spentInCategory(s.budgets[i].category, month),
                        divider: i < s.budgets.length - 1,
                        onTap: () => openBudgetSheet(context, budget: s.budgets[i]),
                      ),
                  ],
                ),
              ),
              if (s.budgets.length < expenseCats.length) ...[
                const SizedBox(height: 10),
                DashedAddRow(
                  icon: Icons.donut_large_rounded,
                  color: C.yellow,
                  title: 'Add a budget',
                  onTap: () => openBudgetSheet(context),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

/// The overall monthly budget, shown above the category budgets.
class _OverallBudgetRow extends StatelessWidget {
  const _OverallBudgetRow({required this.state, required this.month});

  final AppState state;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final budget = s.overallBudget;
    if (budget == null) {
      return DashedAddRow(
        icon: Icons.donut_large_rounded,
        color: C.accent,
        title: 'Set a monthly budget',
        subtitle: 'One limit for all your spending',
        onTap: () => openOverallBudgetSheet(context),
      );
    }
    final spent = s.overallSpent(month);
    final left = budget - spent;
    final ratio = spent / budget;
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);

    return CardBox(
      onTap: () => openOverallBudgetSheet(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const IconTile(Icons.donut_large_rounded, color: C.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('All spending', style: ts(15, weight: FontWeight.w700)),
                    Text(
                      '${m(spent)} of ${m(budget)}'
                      '${s.budgetCountsPlans ? '' : ' · SIPs, bills & EMIs not counted'}',
                      style: ts(13, color: C.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                left < 0 ? '${m(-left)} over' : '${m(left)} left',
                style: ts(13, weight: FontWeight.w800, color: left < 0 ? C.expense : C.income),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProgressBar(ratio,
              color: left < 0 ? C.expense : (ratio >= 0.8 ? C.yellow : C.accent)),
        ],
      ),
    );
  }
}

class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.goal, this.compact = false, this.onTap});

  final Goal goal;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final g = goal;
    final pct = (g.progress * 100).floor();
    final left = g.target - g.saved;
    final done = left <= 0;

    return CardBox(
      radius: compact ? 20 : 24,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(Icons.savings_outlined, color: C.teal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(15, weight: FontWeight.w800)),
                    Row(
                      children: [
                        Money(g.saved, size: 13, weight: FontWeight.w600, color: C.muted),
                        Text(' of ', style: ts(13, color: C.muted)),
                        Flexible(
                          child: Money(g.target,
                              size: 13, weight: FontWeight.w600, color: C.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text('$pct%', style: ts(15, weight: FontWeight.w800, color: C.accent)),
            ],
          ),
          const SizedBox(height: 14),
          ProgressBar(g.progress, color: done ? C.income : C.accent),
          const SizedBox(height: 10),
          if (done)
            Text('Goal reached', style: ts(13, weight: FontWeight.w700, color: C.income))
          else
            Row(
              children: [
                Money(left, size: 13, weight: FontWeight.w500, color: C.muted),
                Text(' to go', style: ts(13, color: C.muted)),
              ],
            ),
          if (!compact) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: C.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        final v = await askAmount(context,
                            title: 'Add money to ${g.name}', action: 'Add');
                        if (v != null) await s.adjustGoal(g, v);
                      },
                      child: Text('Add money',
                          style: ts(14, weight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlineBtn(
                    'Take out',
                    onPressed: g.saved <= 0
                        ? null
                        : () async {
                            final v = await askAmount(context,
                                title: 'Take out from ${g.name}', action: 'Take out');
                            if (v != null) await s.adjustGoal(g, -v);
                          },
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

class BudgetRow extends StatelessWidget {
  const BudgetRow({
    super.key,
    required this.budget,
    required this.spent,
    this.divider = false,
    this.onTap,
  });

  final Budget budget;
  final int spent;
  final bool divider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cat = catFor(budget.category);
    final over = spent > budget.amount;
    final left = budget.amount - spent;
    final ratio = budget.amount <= 0 ? 0.0 : spent / budget.amount;
    final hidden = context.select<AppState, bool>((s) => s.amountsHidden);
    String m(int v) => hidden ? '₹••••' : money(v);

    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          Row(
            children: [
              IconTile(cat.icon, color: cat.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cat.label, style: ts(15, weight: FontWeight.w700)),
                    Text('${m(spent)} of ${m(budget.amount)}',
                        style: ts(13, color: C.muted)),
                  ],
                ),
              ),
              Text(
                over ? '${m(-left)} over' : '${m(left)} left',
                style: ts(13, weight: FontWeight.w800, color: over ? C.expense : C.income),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProgressBar(ratio,
              color: over ? C.expense : (ratio >= 0.8 ? C.yellow : C.accent)),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? const Border(bottom: BorderSide(color: C.line)) : null,
      ),
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }
}

// ------------------------------------------------------------ goal form

Future<void> openGoalForm(BuildContext context, {Goal? goal}) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => _GoalForm(goal: goal)),
  );
}

class _GoalForm extends StatefulWidget {
  const _GoalForm({this.goal});

  final Goal? goal;

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _saved = TextEditingController();
  String? _nameError;
  String? _targetError;
  String? _savedError;

  bool get _editing => widget.goal != null;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    if (g != null) {
      _name.text = g.name;
      _target.text = amountInput(g.target);
      _saved.text = g.saved == 0 ? '' : amountInput(g.saved);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final target = parseAmount(_target.text);
    final saved = _saved.text.trim().isEmpty ? 0 : parseAmount(_saved.text);
    setState(() {
      _nameError = name.isEmpty ? 'Give the goal a name' : null;
      _targetError = target == null || target <= 0 ? 'Enter the amount you want to save' : null;
      _savedError = saved == null ? 'Enter a number' : null;
    });
    if (_nameError != null || _targetError != null || _savedError != null) return;
    final old = widget.goal;
    await context.read<AppState>().saveGoal(Goal(
          id: old?.id,
          name: name,
          target: target!,
          saved: saved!,
          createdAt: old?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
        ));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete ${widget.goal!.name}?',
      message: 'Your account balances are not affected.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    await context.read<AppState>().deleteGoal(widget.goal!.id!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit goal' : 'New goal'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Delete goal',
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
                    textCapitalization: TextCapitalization.sentences,
                    style: ts(16, weight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: 'Goal name',
                      hintText: 'e.g. Emergency fund, Goa trip',
                      errorText: _nameError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _target,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: ts(16, weight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: 'Target amount',
                      prefixText: '₹ ',
                      errorText: _targetError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _saved,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: ts(16, weight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: 'Saved so far',
                      prefixText: '₹ ',
                      hintText: '0',
                      errorText: _savedError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'A goal keeps track of money you set aside. It does not move money between your accounts.',
                    style: ts(13, color: C.muted, height: 1.45),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: PrimaryButton(_editing ? 'Save changes' : 'Create goal', onPressed: _save),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------- budget sheet

Future<void> openBudgetSheet(BuildContext context, {Budget? budget}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BudgetSheet(budget: budget),
  );
}

class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet({this.budget});

  final Budget? budget;

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  final _amount = TextEditingController();
  String? _category;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.budget;
    if (b != null) {
      _category = b.category;
      _amount.text = amountInput(b.amount);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = parseAmount(_amount.text);
    if (_category == null) {
      setState(() => _error = 'Pick a category');
      return;
    }
    if (v == null || v <= 0) {
      setState(() => _error = 'Enter a monthly limit');
      return;
    }
    await context
        .read<AppState>()
        .saveBudget(_category!, v, replacingId: widget.budget?.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await context.read<AppState>().deleteBudget(widget.budget!.id!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final used = s.budgets.map((b) => b.category).toSet()..remove(widget.budget?.category);
    final cats = expenseCats.where((c) => !used.contains(c.key)).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.budget == null ? 'New budget' : 'Edit budget',
                style: ts(20, weight: FontWeight.w800)),
            const SizedBox(height: 16),
            const SectionLabel('Category'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in cats)
                  ChoiceChip(
                    selected: _category == c.key,
                    onSelected: (_) => setState(() {
                      _category = c.key;
                      _error = null;
                    }),
                    avatar: Icon(c.icon, size: 18, color: c.color),
                    label: Text(c.label),
                    labelStyle: ts(14, weight: FontWeight.w700),
                    showCheckmark: false,
                    selectedColor: C.accentTint,
                    backgroundColor: C.surface,
                    side: BorderSide(color: _category == c.key ? C.accent : C.line, width: 1.5),
                    shape: const StadiumBorder(),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: ts(18, weight: FontWeight.w800),
              decoration: const InputDecoration(
                labelText: 'Monthly limit',
                prefixText: '₹ ',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: ts(13, weight: FontWeight.w700, color: C.expense)),
              ),
            const SizedBox(height: 16),
            PrimaryButton('Save budget', onPressed: _save),
            if (widget.budget != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _delete,
                  child: Text('Remove budget',
                      style: ts(14, weight: FontWeight.w700, color: C.expense)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
