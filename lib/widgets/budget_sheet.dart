import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'ui.dart';

/// Sheet to set, change or remove the overall monthly budget.
Future<void> openOverallBudgetSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _OverallBudgetSheet(),
  );
}

class _OverallBudgetSheet extends StatefulWidget {
  const _OverallBudgetSheet();

  @override
  State<_OverallBudgetSheet> createState() => _OverallBudgetSheetState();
}

class _OverallBudgetSheetState extends State<_OverallBudgetSheet> {
  static const _quick = [200000, 500000, 1000000, 2000000]; // paise

  final _amount = TextEditingController();
  late bool _countPlans;
  late final bool _existing;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    final b = s.overallBudget;
    _existing = b != null;
    _amount.text = amountInput(b ?? _quick.first);
    _countPlans = s.budgetCountsPlans;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = parseAmount(_amount.text);
    if (v == null || v <= 0) {
      setState(() => _error = 'Enter how much you want to spend in a month');
      return;
    }
    await context.read<AppState>().setOverallBudget(v, countPlans: _countPlans);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    await context.read<AppState>().setOverallBudget(null, countPlans: _countPlans);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final current = parseAmount(_amount.text);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monthly budget', style: ts(22, weight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'How much do you want to spend in a month, in total? It starts again on the 1st.',
              style: ts(14, color: C.muted, height: 1.45),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: ts(28, weight: FontWeight.w800),
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: 'Budget per month',
                prefixText: '₹ ',
                prefixStyle: ts(26, weight: FontWeight.w800, color: C.muted),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in _quick)
                  FilterPill(
                    money(q),
                    selected: current == q,
                    onTap: () => setState(() {
                      _amount.text = amountInput(q);
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            CardBox(
              color: C.bg,
              child: MergeSemantics(
                child: ListRow(
                  leading: const IconTile(Icons.event_repeat_outlined, color: C.transfer),
                  title: 'Count SIPs, bills & EMIs',
                  subtitle: _countPlans
                      ? 'On: rent, SIPs and EMIs also use up this budget.'
                      : 'Off: only day-to-day spending counts. Rent, SIPs and EMIs are left out.',
                  onTap: () => setState(() => _countPlans = !_countPlans),
                  trailing: Switch(
                    value: _countPlans,
                    onChanged: (v) => setState(() => _countPlans = v),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton('Save budget', onPressed: _save),
            if (_existing) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _remove,
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
