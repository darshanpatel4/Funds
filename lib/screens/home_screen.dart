import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/budget_sheet.dart';
import '../widgets/ui.dart';
import 'account_detail_screen.dart';
import 'account_form_screen.dart';
import 'accounts_screen.dart';
import 'goals_screen.dart';
import 'fd_screen.dart';
import 'lend_screen.dart';
import 'shell.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _Header(now: now, hidden: s.amountsHidden, onToggle: s.toggleHidden),
          const SizedBox(height: 16),
          if (s.accounts.isEmpty)
            EmptyCard(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Welcome to Funds',
              message:
                  'Add your bank accounts and cash to start tracking. Everything stays on this phone.',
              action: 'Add account',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountFormScreen()),
              ),
            )
          else ...[
            _BalanceCard(state: s, month: month),
            if (s.feature(Features.budgets)) ...[
              const SizedBox(height: 12),
              _BudgetCard(state: s, now: now),
            ],
            const SizedBox(height: 20),
            SectionHeader('Accounts',
                action: 'See all', onAction: () => openAccounts(context)),
            _AccountStrip(state: s),
            if (s.feature(Features.lend)) ...[
              const SizedBox(height: 20),
              _LendSection(state: s),
            ],
            if (s.feature(Features.fds)) ...[
              const SizedBox(height: 20),
              _FdSection(state: s),
            ],
            ..._comingUp(context, s),
            ..._goalsOrBudgets(context, s, month),
          ],
        ],
      ),
    );
  }

  List<Widget> _comingUp(BuildContext context, AppState s) {
    final items = s.upcoming(days: 10);
    if (items.isEmpty) return const [];
    return [
      const SizedBox(height: 20),
      SectionHeader('Coming up · next 10 days',
          action: 'All plans', onAction: () => currentTab.value = Tabs.plans),
      CardBox(
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++)
              ListRow(
                divider: i < items.length - 1,
                leading: _DateTile(items[i].date),
                title: items[i].title,
                subtitle: '${daysUntil(items[i].date)} · ${items[i].subtitle}',
                trailing: Money(items[i].amount, plus: true, colorBySign: true),
                onTap: () => items[i].isCardDue
                    ? openAccounts(context)
                    : currentTab.value = Tabs.plans,
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _goalsOrBudgets(BuildContext context, AppState s, DateTime month) {
    void openGoals() =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoalsScreen()));

    final out = <Widget>[];
    if (s.feature(Features.goals)) {
      out.addAll([
        const SizedBox(height: 20),
        SectionHeader('Savings goals', action: 'See all', onAction: openGoals),
        if (s.goals.isEmpty)
          DashedAddRow(
            icon: Icons.flag_outlined,
            color: C.teal,
            title: 'Start a savings goal',
            subtitle: 'A trip, a gadget or an emergency fund',
            onTap: () => openGoalForm(context),
          )
        else
          for (final g in s.goals.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GoalCard(goal: g, compact: true, onTap: openGoals),
            ),
      ]);
    }
    // Budgets get their own section so they are always easy to find.
    if (s.feature(Features.budgets)) {
      out.addAll([
        const SizedBox(height: 20),
        SectionHeader('Category budgets',
            action: s.budgets.isEmpty ? null : 'See all', onAction: openGoals),
        if (s.budgets.isEmpty)
          DashedAddRow(
            icon: Icons.donut_large_rounded,
            color: C.yellow,
            title: 'Set a category budget',
            subtitle: 'A limit for Food, Shopping or any category',
            onTap: () => openBudgetSheet(context),
          )
        else
        CardBox(
          child: Column(
            children: [
              for (var i = 0; i < s.budgets.length && i < 3; i++)
                BudgetRow(
                  budget: s.budgets[i],
                  spent: s.spentInCategory(s.budgets[i].category, month),
                  divider: i < s.budgets.length - 1 && i < 2,
                  onTap: openGoals,
                ),
            ],
          ),
        ),
      ]);
    }
    return out;
  }

}


class _Header extends StatelessWidget {
  const _Header({required this.now, required this.hidden, required this.onToggle});

  final DateTime now;
  final bool hidden;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(longDay(now), style: ts(13, weight: FontWeight.w600, color: C.muted)),
              const SizedBox(height: 4),
              Text(greeting(now),
                  style: ts(26, weight: FontWeight.w800, letterSpacing: -0.5)),
            ],
          ),
        ),
        Tooltip(
          message: hidden ? 'Show amounts' : 'Hide amounts',
          child: Material(
            color: C.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: C.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onToggle,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  semanticLabel: hidden ? 'Show amounts' : 'Hide amounts',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.state, required this.month});

  final AppState state;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final inc = s.incomeInMonth(month);
    final out = s.expenseInMonth(month);
    final count = s.countedAccounts.length;
    final mon = DateFormat('MMM').format(month);

    String summary;
    if (s.amountsHidden) {
      summary = 'Amounts are hidden.';
    } else if (inc == 0 && out == 0) {
      summary = 'No money in or out yet this month.';
    } else if (out > inc) {
      summary = '${money(out - inc)} more went out than came in this month.';
    } else if (inc > out) {
      summary = '${money(inc - out)} more came in than went out this month.';
    } else {
      summary = 'Money in and out are equal this month.';
    }

    return CardBox(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Total balance',
                    style: ts(13, weight: FontWeight.w600, color: C.muted)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: C.surface2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$count ${count == 1 ? 'account' : 'accounts'}',
                    style: ts(12, weight: FontWeight.w700, color: C.muted)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Money(s.totalBalance, size: 40, letterSpacing: -1.5, colorBySign: true),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  icon: Icons.south_west_rounded,
                  label: 'Money in · $mon',
                  amount: inc,
                  color: C.income,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Stat(
                  icon: Icons.north_east_rounded,
                  label: 'Money out · $mon',
                  amount: -out,
                  color: C.expense,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(summary, style: ts(13, color: C.muted)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.amount,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: C.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(12, weight: FontWeight.w600, color: C.muted)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Money(amount, size: 18, plus: true, color: color),
        ],
      ),
    );
  }
}

/// The overall monthly budget: left, per day, almost used up, or over.
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.state, required this.now});

  final AppState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final budget = s.overallBudget;
    if (budget == null) {
      return DashedAddRow(
        icon: Icons.donut_large_rounded,
        color: C.accent,
        title: 'Set a monthly budget',
        subtitle: "One limit for all your spending. See what's left every day.",
        onTap: () => openOverallBudgetSheet(context),
      );
    }

    final month = DateTime(now.year, now.month);
    final spent = s.overallSpent(month);
    final left = budget - spent;
    final ratio = spent / budget;
    final daysLeft = daysInMonth(now.year, now.month) - now.day + 1;
    // Whole rupees a day (no paise).
    final perDay = left > 0 ? (left / daysLeft / 100).floor() * 100 : 0;
    final over = left < 0;
    final warn = !over && ratio >= 0.8;
    final days = '$daysLeft ${daysLeft == 1 ? 'day' : 'days'}';
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);

    final bg = over ? C.danger : C.accent;
    final deep = over ? C.dangerDeep : C.accentDeep;
    final soft = over ? C.onDangerSoft : C.onAccentSoft;

    return Semantics(
      button: true,
      label: over
          ? '${DateFormat('MMMM').format(month)} budget: ${m(-left)} over. ${m(spent)} spent of ${m(budget)}.'
          : '${DateFormat('MMMM').format(month)} budget: ${m(left)} left. ${m(spent)} spent of ${m(budget)}.',
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => openOverallBudgetSheet(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${DateFormat('MMMM').format(month)} budget',
                          style: ts(13, weight: FontWeight.w700, color: Colors.white)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: deep,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(over ? '$days left' : '≈ ${m(perDay)} a day · $days',
                          style: ts(12, weight: FontWeight.w800, color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: m(over ? -left : left),
                        style: ts(32,
                            weight: FontWeight.w800, color: Colors.white, letterSpacing: -1)),
                    TextSpan(
                        text: over ? ' over' : ' left',
                        style: ts(16, weight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 8,
                    child: Stack(
                      children: [
                        Positioned.fill(child: ColoredBox(color: deep)),
                        FractionallySizedBox(
                          widthFactor: ratio.clamp(0.0, 1.0),
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: warn ? C.yellow : Colors.white,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text('${m(spent)} spent',
                          style: ts(13, weight: FontWeight.w600, color: soft)),
                    ),
                    Text('of ${m(budget)}', style: ts(13, weight: FontWeight.w600, color: soft)),
                  ],
                ),
                if (warn) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: deep,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 16, color: C.yellow),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${(ratio * 100).floor()}% used. Go slow for the rest of the month.',
                            style: ts(13, weight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountStrip extends StatelessWidget {
  const _AccountStrip({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final list = state.visibleAccounts;
    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: list.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (i == list.length) {
            return SizedBox(
              width: 110,
              child: CardBox(
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AccountFormScreen())),
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_rounded, color: C.accent),
                    const SizedBox(height: 6),
                    Text('Add', style: ts(13, weight: FontWeight.w700, color: C.accent)),
                  ],
                ),
              ),
            );
          }
          final a = list[i];
          return SizedBox(
            width: 150,
            child: CardBox(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AccountDetailScreen(accountId: a.id!))),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconTile(accountIcon(a.kind), size: 32, color: a.counted ? C.accent : C.faint),
                      const Spacer(),
                      if (!a.counted)
                        Text('Not counted',
                            style: ts(11, weight: FontWeight.w700, color: C.muted)),
                    ],
                  ),
                  const Spacer(),
                  Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(13, weight: FontWeight.w600, color: C.muted)),
                  const SizedBox(height: 2),
                  Money(state.balanceOf(a.id!), size: 18, colorBySign: true),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile(this.date);

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 48,
      decoration: BoxDecoration(
        color: C.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(DateFormat('MMM').format(date).toUpperCase(),
              style: ts(11, weight: FontWeight.w700, color: C.muted)),
          Text('${date.day}', style: ts(17, weight: FontWeight.w800, height: 1.1)),
        ],
      ),
    );
  }
}

/// Lend & borrow on Home: what people owe you, what you owe, and the most
/// urgent due date.
class _LendSection extends StatelessWidget {
  const _LendSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final open = s.loans.where(s.loanOpen).toList();
    if (open.isEmpty) {
      return DashedAddRow(
        icon: Icons.handshake_outlined,
        color: C.blue,
        title: 'Lent or borrowed money?',
        subtitle: 'Keep track of who owes whom',
        onTap: () => openLend(context),
      );
    }

    // Most urgent: the earliest due date among open loans.
    final withDue = open.where((l) => l.dueDate != null).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    final urgent = withDue.firstOrNull;
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);

    Widget half(String label, IconData icon, Color color, int amount, int people, String prep) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 6),
                    Text(label, style: ts(12, weight: FontWeight.w700, color: C.muted)),
                  ],
                ),
                const SizedBox(height: 6),
                Money(amount, size: 22, color: amount == 0 ? C.muted : color),
                Text(people == 0 ? 'nobody' : '$prep $people ${people == 1 ? 'person' : 'people'}',
                    style: ts(12, weight: FontWeight.w600, color: C.muted)),
              ],
            ),
          ),
        );

    return Column(
      children: [
        SectionHeader('Lend & borrow', action: 'See all', onAction: () => openLend(context)),
        CardBox(
          onTap: () => openLend(context),
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    half("You'll get back", Icons.south_west_rounded, C.income, s.toGetBack,
                        s.peopleCount(LoanDirection.lent), 'from'),
                    const VerticalDivider(width: 1, color: C.line),
                    half('You owe', Icons.north_east_rounded, C.expense, s.youOwe,
                        s.peopleCount(LoanDirection.borrowed), 'to'),
                  ],
                ),
              ),
              if (urgent != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1408),
                    border: Border(top: BorderSide(color: C.line)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 18, color: C.yellow),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          urgent.lent
                              ? '${s.person(urgent.personId)?.name ?? ''} pays you ${m(s.statusOf(urgent).total)}'
                              : 'Pay ${s.person(urgent.personId)?.name ?? ''} ${m(s.statusOf(urgent).total)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(13, weight: FontWeight.w700),
                        ),
                      ),
                      Text(dueText(urgent.dueDate!),
                          style: ts(12, weight: FontWeight.w700, color: C.yellow)),
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

/// Fixed deposits on Home: kept separate from the total balance.
class _FdSection extends StatelessWidget {
  const _FdSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s.fds.isEmpty) {
      return DashedAddRow(
        icon: Icons.lock_outline_rounded,
        color: C.yellow,
        title: 'Have a fixed deposit?',
        subtitle: 'See what it is worth and what you get at maturity',
        onTap: () => openFdForm(context),
      );
    }
    final active = s.activeFds;
    // Matured ones first: they need a choice.
    final shown = [
      ...active.where(s.fdMatured),
      ...active.where((f) => !s.fdMatured(f)),
    ].take(3).toList();

    return Column(
      children: [
        SectionHeader('Fixed deposits',
            action: active.length > 3 || s.fds.length > active.length ? 'See all' : '+ Add FD',
            onAction: () => active.length > 3 || s.fds.length > active.length
                ? openFdList(context)
                : openFdForm(context)),
        CardBox(
          child: Column(
            children: [
              if (active.isEmpty)
                ListRow(
                  leading: const IconTile(Icons.lock_outline_rounded, color: C.faint),
                  title: 'No running FDs',
                  subtitle: 'Tap to see closed ones or add a new FD',
                  onTap: () => openFdList(context),
                )
              else ...[
                InkWell(onTap: () => openFdList(context), child: const FdSummary()),
                for (final f in shown)
                  DecoratedBox(
                    decoration:
                        const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
                    child: FdRow(fd: f),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
