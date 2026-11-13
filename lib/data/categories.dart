import 'package:flutter/material.dart';

import '../theme.dart';
import 'models.dart';

class Cat {
  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const Cat(this.key, this.label, this.icon, this.color);
}

/// Categories the user can pick for an expense.
const expenseCats = <Cat>[
  Cat('food', 'Food', Icons.restaurant_rounded, C.orange),
  Cat('groceries', 'Groceries', Icons.shopping_cart_outlined, C.teal),
  Cat('fuel', 'Fuel', Icons.local_gas_station_outlined, C.yellow),
  Cat('shopping', 'Shopping', Icons.shopping_bag_outlined, C.pink),
  Cat('bills', 'Bills', Icons.receipt_long_outlined, C.blue),
  Cat('rent', 'Rent', Icons.home_outlined, C.transfer),
  Cat('travel', 'Travel', Icons.flight_takeoff_rounded, C.teal),
  Cat('health', 'Health', Icons.medical_services_outlined, C.orange),
  Cat('education', 'Education', Icons.school_outlined, C.blue),
  Cat('fun', 'Fun', Icons.local_activity_outlined, C.yellow),
  Cat('business', 'Business', Icons.business_center_outlined, C.transfer),
  Cat('other', 'Other', Icons.more_horiz_rounded, C.muted),
];

/// Categories the user can pick for income.
const incomeCats = <Cat>[
  Cat('salary', 'Salary', Icons.work_outline_rounded, C.accent),
  Cat('freelance', 'Freelance', Icons.laptop_mac_rounded, C.blue),
  Cat('interest', 'Interest', Icons.trending_up_rounded, C.income),
  Cat('gift', 'Gift', Icons.card_giftcard_rounded, C.pink),
  Cat('refund', 'Refund', Icons.replay_rounded, C.teal),
  Cat('other_in', 'Other', Icons.more_horiz_rounded, C.muted),
];

/// Categories only used by automatic entries.
const systemCats = <Cat>[
  Cat('investment', 'SIP', Icons.trending_up_rounded, C.transfer),
  Cat('emi', 'Loan EMI', Icons.account_balance_outlined, C.yellow),
  loanCat,
  Cat('interest_paid', 'Interest paid', Icons.percent_rounded, C.orange),
  fdCat,
  fundCat,
  Cat('fund_profit', 'Fund profit', Icons.trending_up_rounded, C.income),
];

/// Money put into or taken out of a mutual fund.
const fundCat = Cat('fund', 'Mutual fund', Icons.trending_up_rounded, C.transfer);

/// Colour for each kind of mutual fund.
Color fundTypeColor(String type) => switch (type) {
      'large' => C.blue,
      'mid' => C.purple,
      'small' => const Color(0xFFFF8FB1),
      'flexi' => C.transfer,
      'multi' => C.teal,
      'index' => C.accent,
      'elss' => C.yellow,
      'hybrid' => C.orange,
      'debt' => C.income,
      _ => C.muted,
    };

/// Money put into or taken out of a fixed deposit.
const fdCat = Cat('fd', 'Fixed deposit', Icons.lock_outline_rounded, C.yellow);

const transferCat = Cat('transfer', 'Transfer', Icons.swap_horiz_rounded, C.transfer);

/// Money lent to or borrowed from a person.
const loanCat = Cat('loan', 'Lend & borrow', Icons.handshake_outlined, C.blue);

/// Categories a bill/rent plan can use.
const billCats = <String>['bills', 'rent', 'fun', 'health', 'education', 'other'];

Cat catFor(String key) {
  for (final c in expenseCats) {
    if (c.key == key) return c;
  }
  for (final c in incomeCats) {
    if (c.key == key) return c;
  }
  for (final c in systemCats) {
    if (c.key == key) return c;
  }
  if (key == 'transfer') return transferCat;
  return expenseCats.last;
}

Cat catForEntry(Entry e) => switch (e.type) {
      EntryType.transfer => transferCat,
      EntryType.loanOut || EntryType.loanIn => loanCat,
      EntryType.depositOut || EntryType.depositIn => fdCat,
      EntryType.investOut || EntryType.investIn => fundCat,
      _ => catFor(e.category),
    };

/// Icon and colour for a plan kind.
(IconData, Color) planLook(PlanKind k) => switch (k) {
      PlanKind.income => (Icons.work_outline_rounded, C.accent),
      PlanKind.sip => (Icons.trending_up_rounded, C.transfer),
      PlanKind.bill => (Icons.receipt_long_outlined, C.blue),
      PlanKind.loan => (Icons.account_balance_outlined, C.yellow),
    };

IconData accountIcon(AccountKind k) => switch (k) {
      AccountKind.savings || AccountKind.current => Icons.account_balance_outlined,
      AccountKind.cash => Icons.payments_outlined,
      AccountKind.wallet => Icons.account_balance_wallet_outlined,
      AccountKind.card => Icons.credit_card_rounded,
    };
