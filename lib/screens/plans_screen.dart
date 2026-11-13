import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../data/models.dart';
import '../data/recurring.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';
import 'plan_form_screen.dart';
import 'sip_screen.dart';

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  static const _sections = [
    (PlanKind.income, 'Income', 'Add your salary', 'Credited on its day every month'),
    (PlanKind.sip, 'SIPs & mutual funds', 'Add a fund', 'SIP moved into it on its date every month'),
    (PlanKind.bill, 'Bills & rent', 'Add a bill or rent', 'Rent, subscriptions, insurance'),
    (PlanKind.loan, 'Loans & EMIs', 'Add a loan', 'EMI amount and months left'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final kinds = PlanKind.values.where((k) => s.feature(k.feature)).toList();
    final inn = s.monthlyIn;
    final out = s.monthlyOut;
    final free = inn - out;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Plans', style: ts(28, weight: FontWeight.w800, letterSpacing: -0.5)),
              ),
              if (kinds.isNotEmpty)
                TintButton('New plan',
                    icon: Icons.add_rounded, onPressed: () => _chooseKind(context, kinds)),
            ],
          ),
          const SizedBox(height: 16),
          if (kinds.isEmpty)
            const EmptyCard(
              icon: Icons.event_repeat_outlined,
              title: 'Plans are turned off',
              message:
                  'Turn on Salary, SIPs, Bills or Loans in Settings to track money that moves every month.',
            )
          else ...[
            CardBox(
              radius: 24,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Every month', style: ts(13, weight: FontWeight.w600, color: C.muted)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _Figure('Comes in', inn, C.income)),
                      Expanded(child: _Figure('Goes out', out, C.expense)),
                      Expanded(child: _Figure('Free to spend', free, free < 0 ? C.expense : C.accent)),
                    ],
                  ),
                  if (inn > 0) ...[
                    const SizedBox(height: 14),
                    ProgressBar(out / inn, color: C.expense),
                    const SizedBox(height: 8),
                    Text(
                      '${(out * 100 / inn).round()}% of your income is already committed',
                      style: ts(12, weight: FontWeight.w600, color: C.muted),
                    ),
                  ],
                ],
              ),
            ),
            for (final (kind, title, addTitle, addSub) in _sections)
              if (s.feature(kind.feature)) ...[
                const SizedBox(height: 24),
                SectionLabel(
                  title,
                  trailing: kind == PlanKind.sip && s.funds.isNotEmpty
                      ? TextButton(
                          onPressed: () => openSips(context),
                          child: Text('My SIPs',
                              style: ts(13, weight: FontWeight.w800, color: C.accent)),
                        )
                      : null,
                ),
                _PlanList(
                  plans: s.plansOf(kind),
                  kind: kind,
                  addTitle: addTitle,
                  addSubtitle: addSub,
                ),
              ],
            const SizedBox(height: 16),
            Text(
              'Plans are added to their account automatically on their day. If Funds was closed, they are added the next time you open it.',
              style: ts(12, color: C.muted, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }

  void _chooseKind(BuildContext context, List<PlanKind> kinds) {
    const info = {
      PlanKind.income: ('Salary', 'Income credited every month'),
      PlanKind.sip: ('SIP', 'A mutual fund and its monthly SIP'),
      PlanKind.bill: ('Bill or rent', 'Rent, subscriptions, insurance premiums'),
      PlanKind.loan: ('Loan EMI', 'Loan name, tenure and EMI'),
    };
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New plan', style: ts(24, weight: FontWeight.w800)),
              const SizedBox(height: 16),
              CardBox(
                child: Column(
                  children: [
                    for (var i = 0; i < kinds.length; i++)
                      ListRow(
                        divider: i < kinds.length - 1,
                        leading: IconTile(planLook(kinds[i]).$1, color: planLook(kinds[i]).$2),
                        title: info[kinds[i]]!.$1,
                        subtitle: info[kinds[i]]!.$2,
                        trailing: const Icon(Icons.chevron_right_rounded, color: C.muted),
                        onTap: () {
                          Navigator.pop(ctx);
                          openPlanForm(context, kind: kinds[i]);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.amount, this.color);

  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ts(12, weight: FontWeight.w700, color: C.muted)),
        const SizedBox(height: 4),
        Money(amount, size: 17, color: color),
      ],
    );
  }
}

class _PlanList extends StatelessWidget {
  const _PlanList({
    required this.plans,
    required this.kind,
    required this.addTitle,
    required this.addSubtitle,
  });

  final List<Plan> plans;
  final PlanKind kind;
  final String addTitle;
  final String addSubtitle;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = planLook(kind);
    if (plans.isEmpty) {
      return DashedAddRow(
        icon: icon,
        color: color,
        title: addTitle,
        subtitle: addSubtitle,
        onTap: () => openPlanForm(context, kind: kind),
      );
    }
    final s = context.watch<AppState>();
    return CardBox(
      child: Column(
        children: [
          for (var i = 0; i < plans.length; i++)
            _PlanRow(plan: plans[i], state: s, divider: i < plans.length - 1),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan, required this.state, required this.divider});

  final Plan plan;
  final AppState state;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final p = plan;
    final (icon, color) = planLook(p.kind);
    final parts = ['Every ${ordinal(p.day)}', state.accountName(p.accountId)];
    if (p.kind == PlanKind.sip) {
      final f = state.fund(p.fundId);
      if (f != null) parts.insert(0, fundTypeLabel(f.type));
    }
    if (p.kind == PlanKind.loan && p.tenure != null) {
      parts.add('${paidCount(p)} of ${p.tenure} paid');
    }
    if (p.kind == PlanKind.bill) parts.insert(0, catFor(p.category).label);

    String caption;
    if (isFinished(p)) {
      caption = 'Completed';
    } else if (!p.active) {
      caption = 'Paused';
    } else {
      caption = daysUntil(nextDueDate(p)!);
    }

    return ListRow(
      divider: divider,
      leading: IconTile(icon, color: p.active ? color : C.faint),
      title: p.name,
      subtitle: parts.join(' · '),
      onTap: () => openPlanForm(context, kind: p.kind, plan: p),
      // A SIP moves money into a fund (blue), it is not spending.
      trailing: p.kind == PlanKind.sip
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Money(p.amount, color: p.active ? C.transfer : C.muted),
                Text(caption, style: ts(12, weight: FontWeight.w700, color: C.muted)),
              ],
            )
          : AmountWithCaption(p.kind.isIncome ? p.amount : -p.amount, caption: caption),
    );
  }
}
