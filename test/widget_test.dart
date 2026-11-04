import 'package:flutter_test/flutter_test.dart';
import 'package:funds/data/deposits.dart';
import 'package:funds/data/lending.dart';
import 'package:funds/data/models.dart';
import 'package:funds/data/recurring.dart';
import 'package:funds/state/app_state.dart';
import 'package:funds/utils/format.dart';

Plan _plan({
  int day = 7,
  String start = '2026-11',
  String? last,
  int? tenure,
  bool active = true,
  PlanKind kind = PlanKind.income,
}) =>
    Plan(
      kind: kind,
      name: 'Salary',
      amount: 1980000,
      day: day,
      accountId: 1,
      startMonth: start,
      lastPosted: last,
      tenure: tenure,
      active: active,
      category: 'salary',
      createdAt: 0,
    );

void main() {
  group('money', () {
    test('formats rupees with Indian grouping', () {
      expect(money(8823500), '₹88,235');
      expect(money(10000000), '₹1,00,000');
      expect(money(-65500), '−₹655');
      expect(money(63000, plus: true), '+₹630');
      expect(money(12550), '₹125.50');
      expect(money(0, plus: true), '₹0');
    });

    test('parses user input to paise', () {
      expect(parseAmount('1,250.50'), 125050);
      expect(parseAmount('300'), 30000);
      expect(parseAmount('-300'), isNull);
      expect(parseAmount('-300', allowNegative: true), -30000);
      expect(parseAmount('abc'), isNull);
      expect(parseAmount(''), isNull);
      expect(amountInput(125050), '1250.50');
      expect(amountInput(-30000), '-300');
    });

    test('ordinals', () {
      expect(ordinal(1), '1st');
      expect(ordinal(2), '2nd');
      expect(ordinal(3), '3rd');
      expect(ordinal(11), '11th');
      expect(ordinal(22), '22nd');
      expect(ordinal(24), '24th');
    });
  });

  group('plans', () {
    test('first month is this month when the day has not passed', () {
      expect(firstMonthFor(7, DateTime(2026, 11, 3)), '2026-11');
      expect(firstMonthFor(3, DateTime(2026, 11, 3)), '2026-11');
      expect(firstMonthFor(1, DateTime(2026, 11, 3)), '2026-12');
      expect(firstMonthFor(31, DateTime(2026, 12, 31)), '2026-12');
      expect(firstMonthFor(5, DateTime(2026, 12, 20)), '2027-01');
    });

    test('nothing is due before the day', () {
      expect(dueMonths(_plan(), DateTime(2026, 11, 6)), isEmpty);
      expect(nextDueDate(_plan()), DateTime(2026, 11, 7));
    });

    test('due on the day and catches up missed months', () {
      expect(dueMonths(_plan(), DateTime(2026, 11, 7)), [DateTime(2026, 11)]);
      expect(dueMonths(_plan(), DateTime(2027, 1, 10)),
          [DateTime(2026, 11), DateTime(2026, 12), DateTime(2027, 1)]);
      expect(dueMonths(_plan(last: '2026-11'), DateTime(2026, 12, 6)), isEmpty);
      expect(nextDueDate(_plan(last: '2026-11')), DateTime(2026, 12, 7));
    });

    test('day 31 uses the last day of short months', () {
      final p = _plan(day: 31, start: '2027-02');
      expect(nextDueDate(p), DateTime(2027, 2, 28));
      expect(dueMonths(p, DateTime(2027, 2, 28)), [DateTime(2027, 2)]);
    });

    test('paused plans add nothing', () {
      expect(dueMonths(_plan(active: false), DateTime(2027, 5, 1)), isEmpty);
      expect(nextDueDate(_plan(active: false)), isNull);
    });

    test('loans stop after the last EMI', () {
      final loan = _plan(kind: PlanKind.loan, tenure: 3, start: '2026-11');
      expect(dueMonths(loan, DateTime(2027, 6, 1)).length, 3);
      final done = _plan(kind: PlanKind.loan, tenure: 3, start: '2026-11', last: '2027-01');
      expect(paidCount(done), 3);
      expect(isFinished(done), isTrue);
      expect(nextDueDate(done), isNull);
      expect(dueMonths(done, DateTime(2027, 6, 1)), isEmpty);
    });
  });

  group('entries', () {
    test('transfer moves money between two accounts', () {
      final t = Entry(
        type: EntryType.transfer,
        amount: 5000,
        accountId: 1,
        toAccountId: 2,
        date: DateTime(2026, 11, 3),
        createdAt: 0,
      );
      expect(t.effectOn(1), -5000);
      expect(t.effectOn(2), 5000);
      expect(t.effectOn(3), 0);
    });
  });

  group('accounts', () {
    test('accounts from older data count in the total balance', () {
      final old = Account.fromMap(
          {'id': 1, 'name': 'SBI', 'kind': 'savings', 'opening': 0, 'created_at': 0});
      expect(old.counted, isTrue);
    });

    test('a family account keeps its "not counted" setting', () {
      final family = Account(
          name: 'Papa SBI', kind: AccountKind.savings, createdAt: 0, counted: false);
      final back = Account.fromMap(family.toMap());
      expect(back.counted, isFalse);
      expect(family.toMap()['counted'], 0);
    });
  });

  group('lend & borrow', () {
    const rahul = Loan(
        id: 1, personId: 1, direction: LoanDirection.lent, rate: 2, createdAt: 0);
    Entry e(EntryType t, int paise, DateTime d, {int created = 0}) => Entry(
        type: t, amount: paise, accountId: 1, date: d, createdAt: created, loanId: 1);

    test('simple interest builds up per day (₹10,000 at 2% a month, 34 days)', () {
      final entries = [e(EntryType.loanOut, 1000000, DateTime(2026, 10, 1))];
      final st = loanStatus(rahul, entries, DateTime(2026, 11, 4));
      expect(st.given, 1000000);
      expect(st.principal, 1000000);
      expect(st.interestDue, 22667); // ₹226.67
      expect(st.total, 1022667);
      expect(monthlyInterest(rahul, 1000000), 20000); // ₹200 a month
    });

    test('a payment pays interest first, then the amount lent', () {
      final st = loanStatus(
          rahul, [e(EntryType.loanOut, 1000000, DateTime(2026, 10, 1))], DateTime(2026, 11, 4));
      final (interest, principal) = splitPayment(st, 200000); // ₹2,000 back
      expect(interest, 22667);
      expect(principal, 177333);

      final after = loanStatus(rahul, [
        e(EntryType.loanOut, 1000000, DateTime(2026, 10, 1)),
        e(EntryType.income, interest, DateTime(2026, 11, 4), created: 1),
        e(EntryType.loanIn, principal, DateTime(2026, 11, 4), created: 2),
      ], DateTime(2026, 11, 4));
      expect(after.interestDue, 0);
      expect(after.principal, 822667);
      expect(after.paidBack, 200000);

      // Interest then continues on the smaller amount.
      final later = loanStatus(rahul, [
        e(EntryType.loanOut, 1000000, DateTime(2026, 10, 1)),
        e(EntryType.income, interest, DateTime(2026, 11, 4), created: 1),
        e(EntryType.loanIn, principal, DateTime(2026, 11, 4), created: 2),
      ], DateTime(2026, 12, 4));
      expect(later.interestDue, 16453);
    });

    test('a payment above what is owed is capped', () {
      final st = loanStatus(
          rahul, [e(EntryType.loanOut, 100000, DateTime(2026, 11, 4))], DateTime(2026, 11, 4));
      expect(splitPayment(st, 500000), (0, 100000));
    });

    test('borrowing without interest', () {
      const amit = Loan(id: 1, personId: 2, direction: LoanDirection.borrowed, createdAt: 0);
      final st = loanStatus(amit, [
        e(EntryType.loanIn, 200000, DateTime(2026, 10, 25)),
        e(EntryType.loanOut, 50000, DateTime(2026, 11, 1)),
      ], DateTime(2026, 11, 4));
      expect(st.interestDue, 0);
      expect(st.principal, 150000);
      expect(st.cleared, isFalse);
      expect(amit.rateLabel, 'no interest');
      expect(rahul.rateLabel, '2% a month');
    });

    test('lending moves money out of the account, getting it back moves it in', () {
      final out = e(EntryType.loanOut, 5000, DateTime(2026, 11, 4));
      final back = e(EntryType.loanIn, 5000, DateTime(2026, 11, 4));
      expect(out.effectOn(1), -5000);
      expect(back.effectOn(1), 5000);
    });
  });

  group('fixed deposits', () {
    Fd fd({int days = 365, Compounding c = Compounding.quarterly, double rate = 7.1}) => Fd(
          id: 1,
          name: 'SBI FD',
          principal: 10000000, // ₹1,00,000
          rate: rate,
          compounding: c,
          startDate: DateTime(2026, 3, 15),
          maturityDate: DateTime(2026, 3, 15).add(Duration(days: days)),
          createdAt: 0,
        );

    test('₹1,00,000 at 7.1% for 1 year, added every 3 months, gives ₹1,07,291', () {
      expect((fdMaturityValue(fd()) - 10729128).abs() <= 2, isTrue);
    });

    test('simple interest: ₹1,00,000 at 10% for 1 year gives ₹1,10,000', () {
      expect(fdMaturityValue(fd(c: Compounding.simple, rate: 10)), 11000000);
    });

    test('value today grows, and stops growing at maturity', () {
      final f = fd();
      final start = fdValueOn(f, DateTime(2026, 3, 15));
      final mid = fdValueOn(f, DateTime(2026, 11, 4));
      final after = fdValueOn(f, DateTime(2028, 1, 1));
      expect(start, 10000000);
      expect(mid > start && mid < fdMaturityValue(f), isTrue);
      expect(after, fdMaturityValue(f));
      expect(fdProgress(f, DateTime(2028, 1, 1)), 1.0);
    });

    test('adding months keeps the day, or uses the last day of short months', () {
      expect(addMonthsKeepDay(DateTime(2026, 3, 15), 12), DateTime(2027, 3, 15));
      expect(addMonthsKeepDay(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonthsKeepDay(DateTime(2026, 11, 4), 6), DateTime(2027, 5, 4));
    });

    test('opening and getting back an FD moves money out of and into the account', () {
      final out = Entry(
          type: EntryType.depositOut, amount: 100, accountId: 1, date: DateTime(2026), createdAt: 0);
      final back = Entry(
          type: EntryType.depositIn, amount: 100, accountId: 1, date: DateTime(2026), createdAt: 0);
      expect(out.effectOn(1), -100);
      expect(back.effectOn(1), 100);
    });
  });

  group('backup', () {
    test('rejects files that are not Funds backups', () {
      expect(() => AppState.parseBackup('hello'), throwsFormatException);
      expect(() => AppState.parseBackup('{"format":"other"}'), throwsFormatException);
      expect(
        () => AppState.parseBackup('{"format":"funds-backup","version":9,"data":{}}'),
        throwsFormatException,
      );
    });

    test('reads a valid backup', () {
      final data = AppState.parseBackup('''
        {"format":"funds-backup","version":1,"data":{
          "accounts":[{"id":1,"name":"Cash","kind":"cash","opening":6500000,"sort":0,"created_at":0}],
          "entries":[{"id":1,"type":"expense","amount":200000,"account_id":1,"category":"other","note":"Skinray","date":"2026-11-02","created_at":0}]
        }}''');
      expect(data['accounts']!.length, 1);
      expect(Entry.fromMap(data['entries']!.first).note, 'Skinray');
    });
  });
}
