import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';
import 'account_detail_screen.dart';
import 'account_form_screen.dart';

/// Opens the Accounts page (from Settings or the Accounts strip on Home).
Future<void> openAccounts(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => const AccountsScreen()));

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final showCards = s.feature(Features.cards);
    final own = s.accounts.where((a) => a.counted).toList();
    final banks = own.where((a) => a.kind.isBank).toList();
    final cash = own.where((a) => a.kind.isCashLike).toList();
    final cards = own.where((a) => a.isCard).toList();
    final anyCard = s.accounts.any((a) => a.isCard);
    // Family / company accounts: shown on their own, kept out of totals.
    final others =
        s.accounts.where((a) => !a.counted && (!a.isCard || showCards)).toList();

    final nonCard = [...banks, ...cash];
    final have = nonCard.map((a) => s.balanceOf(a.id!)).where((b) => b > 0).fold(0, (x, y) => x + y);
    final overdrawn =
        nonCard.map((a) => s.balanceOf(a.id!)).where((b) => b < 0).fold(0, (x, y) => x + y);
    final cardOwed = showCards
        ? cards.map((a) => s.balanceOf(a.id!)).where((b) => b < 0).fold(0, (x, y) => x + y)
        : 0;

    void add({AccountKind? kind}) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AccountFormScreen(initialKind: kind)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: TintButton('Add account', icon: Icons.add_rounded, onPressed: add),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          CardBox(
            radius: 24,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total balance', style: ts(13, weight: FontWeight.w600, color: C.muted)),
                const SizedBox(height: 4),
                Money(s.totalBalance, size: 36, letterSpacing: -1, colorBySign: true),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 20,
                  runSpacing: 6,
                  children: [
                    _Pair('You have', have, C.income),
                    if (overdrawn < 0) _Pair('Overdrawn', overdrawn, C.expense),
                    if (cardOwed < 0) _Pair('Cards owed', cardOwed, C.expense),
                    if (others.isNotEmpty) _Pair('Not counted', s.notCountedBalance, C.muted),
                  ],
                ),
              ],
            ),
          ),
          if (s.accounts.isEmpty) ...[
            const SizedBox(height: 24),
            EmptyCard(
              icon: Icons.account_balance_outlined,
              title: 'No accounts yet',
              message: 'Add a bank account, cash or a wallet to start.',
              action: 'Add account',
              onAction: add,
            ),
          ],
          if (banks.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionLabel('Bank accounts'),
            _Group(accounts: banks),
          ],
          if (cash.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionLabel('Cash & wallets'),
            _Group(accounts: cash),
          ],
          if (showCards && s.accounts.isNotEmpty && (!anyCard || cards.isNotEmpty)) ...[
            const SizedBox(height: 24),
            const SectionLabel('Credit cards'),
            if (cards.isEmpty)
              DashedAddRow(
                icon: Icons.credit_card_rounded,
                color: C.pink,
                title: 'Add a credit card',
                subtitle: 'Track limit, bill amount and due date',
                onTap: () => add(kind: AccountKind.card),
              )
            else
              _Group(accounts: cards),
          ],
          if (others.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionLabel('Not in my balance'),
            Text(
              'Family or company money you look after. Not counted in your total balance, money in/out or budget.',
              style: ts(13, color: C.muted, height: 1.4),
            ),
            const SizedBox(height: 8),
            _Group(accounts: others),
          ],
          if (s.accounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text('Tap an account to see its passbook and add entries.',
                  style: ts(13, color: C.muted)),
            ),
        ],
      ),
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair(this.label, this.amount, this.color);

  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: ts(13, weight: FontWeight.w600, color: C.muted)),
        Money(amount, size: 13, color: color),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.accounts});

  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return CardBox(
      child: Column(
        children: [
          for (var i = 0; i < accounts.length; i++)
            _AccountRow(
              account: accounts[i],
              balance: s.balanceOf(accounts[i].id!),
              divider: i < accounts.length - 1,
            ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.balance, required this.divider});

  final Account account;
  final int balance;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final a = account;
    String subtitle = a.kind.label;
    String? caption;
    var captionColor = C.muted;

    if (a.isCard) {
      final owed = balance < 0 ? -balance : 0;
      final parts = <String>[];
      if (a.creditLimit != null && a.creditLimit! > 0) {
        final hidden = context.select<AppState, bool>((s) => s.amountsHidden);
        parts.add('Limit ${hidden ? '₹••••' : money(a.creditLimit!)}');
      }
      if (a.dueDay != null) parts.add('Due on the ${ordinal(a.dueDay!)}');
      subtitle = parts.isEmpty ? 'Credit card' : parts.join(' · ');
      caption = owed > 0 ? 'Outstanding' : 'Nothing due';
    } else if (balance < 0) {
      caption = 'Overdrawn';
      captionColor = C.expense;
    }

    return ListRow(
      divider: divider,
      leading: IconTile(accountIcon(a.kind)),
      title: a.name,
      subtitle: subtitle,
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AccountDetailScreen(accountId: a.id!))),
      trailing: AmountWithCaption(balance,
          plus: false, caption: caption, captionColor: captionColor),
    );
  }
}
