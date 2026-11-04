# Funds

**A private, offline money manager for Android, built with Flutter.**
All your data stays on your phone: no account, no cloud, no internet access.

<p align="center">
  <img src="docs/screenshots/01_home.png" width="250" alt="Home: total balance, money in and out, monthly budget" />
  &nbsp;
  <img src="docs/screenshots/03_activity.png" width="250" alt="Activity: last 7 days chart and entries by day" />
  &nbsp;
  <img src="docs/screenshots/05_new_entry.png" width="250" alt="Adding an expense" />
</p>

## Features

- **Accounts:** bank (savings / current), cash, wallets and credit cards, each with a passbook showing the balance after every entry. Family or company accounts can be kept out of your own total.
- **Entries:** expense, income and transfer, with categories, notes and dates.
- **Activity:** one month at a time. Days fold up, there's a last-7-days spending chart, a by-category breakdown, filters by account and category, and search across all months.
- **Monthly budget:** one spending limit for the month, plus optional limits per category.
- **Plans:** salary, SIPs, bills & rent and loan EMIs are added to their account automatically on their day.
- **Lend & borrow:** keep track of money you lent to or borrowed from people, with optional simple interest. Payments go to interest first, and you can send WhatsApp reminders.
- **Fixed deposits:** worth today and at maturity (compounded quarterly, monthly, yearly or simple). At maturity you choose to withdraw or renew, with or without the interest.
- **Savings goals.**
- **Security:** fingerprint / face / phone PIN lock, and an option to hide amounts.
- **Backup & restore:** export a file and import it on a new phone.
- **Feature switches:** turn off anything you don't use. Its data is kept.

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/01_home.png" width="240" alt="Home" /><br /><b>Home</b><br />Total balance, money in and out, monthly budget</td>
    <td align="center"><img src="docs/screenshots/02_home_more.png" width="240" alt="Home, further down" /><br /><b>Home, further down</b><br />Fixed deposits and what's coming up</td>
    <td align="center"><img src="docs/screenshots/03_activity.png" width="240" alt="Activity by day" /><br /><b>Activity</b><br />Last 7 days chart, days that fold up</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/04_activity_categories.png" width="240" alt="Activity by category" /><br /><b>By category</b><br />Where the month's money went</td>
    <td align="center"><img src="docs/screenshots/05_new_entry.png" width="240" alt="New entry" /><br /><b>New entry</b><br />Expense, income or transfer</td>
    <td align="center"><img src="docs/screenshots/06_plans.png" width="240" alt="Plans" /><br /><b>Plans</b><br />Salary, SIPs, rent and EMIs added automatically</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/07_lend_borrow.png" width="240" alt="Lend and borrow" /><br /><b>Lend &amp; borrow</b><br />Who owes you, and whom you owe</td>
    <td align="center"><img src="docs/screenshots/08_person.png" width="240" alt="One person" /><br /><b>One person</b><br />Simple interest, payments and reminders</td>
    <td align="center"><img src="docs/screenshots/09_fixed_deposits.png" width="240" alt="Fixed deposits" /><br /><b>Fixed deposits</b><br />Worth today, matured FDs first</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/10_fd_detail.png" width="240" alt="One FD" /><br /><b>One FD</b><br />Progress and amount at maturity</td>
    <td align="center"><img src="docs/screenshots/11_accounts.png" width="240" alt="Accounts" /><br /><b>Accounts</b><br />Banks, cash, cards and family money kept separate</td>
    <td align="center"><img src="docs/screenshots/12_settings.png" width="240" alt="Settings" /><br /><b>Settings</b><br />Security, features, backup</td>
  </tr>
</table>

<sub>The screenshots show sample data.</sub>

## Privacy

Funds stores everything in a SQLite database on the phone. It makes no network requests, and Android cloud backup is turned off for the app. Moving to a new phone is done with your own backup file. The backup file is plain JSON and **not encrypted**, so keep it private.

## Build and run

Requires Flutter 3.x and the Android SDK.

```bash
flutter pub get
flutter run                                  # phone connected with USB debugging
flutter build apk --release --split-per-abi  # APKs in build/app/outputs/flutter-apk/
```

The release build is signed with the debug key. Before publishing to the Play Store, set up your own signing key: https://docs.flutter.dev/deployment/android#sign-the-app

## Tests

```bash
flutter test
```

The tests cover money formatting, plan dates, lend & borrow interest, fixed deposit maturity values and backup parsing.
## Code layout

| Path | What it holds |
|---|---|
| `lib/main.dart` | App start, app lock |
| `lib/theme.dart` | Colours and text styles |
| `lib/data/models.dart` | Account, Entry, Plan, Goal, Budget, Person, Loan, Fd |
| `lib/data/db.dart` | SQLite tables and upgrades, backup dump/restore |
| `lib/data/recurring.dart` | When plans (salary, SIPs, EMIs) are due |
| `lib/data/lending.dart` | Lend & borrow interest and payment split |
| `lib/data/deposits.dart` | Fixed deposit value and maturity |
| `lib/state/app_state.dart` | All data in memory, balances, saving, automatic entries |
| `lib/screens/` | One file per screen |
| `lib/widgets/` | Shared UI pieces |

Money is stored as whole paise (integers), so totals are always exact.

## License

Funds is released under the Apache License 2.0; see `LICENSE`.

The Manrope font (`assets/fonts/Manrope.ttf`) is by The Manrope Project Authors and is licensed under the SIL Open Font License 1.1; see `assets/fonts/OFL.txt`.
