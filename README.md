# Funds

**A private, offline money manager for Android, built with Flutter.**
All your data stays on your phone: no account, no cloud, no internet access.

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
