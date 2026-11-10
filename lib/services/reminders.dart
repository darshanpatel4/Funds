import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/deposits.dart';
import '../data/models.dart';
import '../data/recurring.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';

/// One reminder to show at [when].
class PlannedReminder {
  final DateTime when;
  final String title;
  final String body;

  /// Where tapping it goes: `home`, `plans`, `accounts`, `add`,
  /// `person:ID` or `fd:ID`.
  final String payload;
  final bool addAction;

  const PlannedReminder(this.when, this.title, this.body, this.payload, {this.addAction = false});
}

/// Reminders shown as phone notifications. Everything is scheduled on the
/// phone; nothing uses the internet.
class Reminders {
  Reminders._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Set by the app to open the right page when a reminder is tapped.
  static void Function(String payload)? onOpen;

  static const _channel = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Bills, dues, FDs, budget and the evening reminder',
    icon: 'ic_notification',
    color: C.accent,
  );

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (r) =>
          onOpen?.call(r.actionId == 'add' ? 'add' : (r.payload ?? 'home')),
    );
    _ready = true;
  }

  /// Payload of the reminder that opened the app, if any.
  static Future<String?> launchPayload() async {
    if (!_ready) return null;
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    final r = d.notificationResponse;
    return r?.actionId == 'add' ? 'add' : r?.payload;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Asks Android 13+ for permission to show notifications.
  static Future<bool> requestPermission() async {
    if (!_ready) return false;
    return await _android?.requestNotificationsPermission() ?? true;
  }

  /// Whether reminders can come at the exact minute. Without this Android
  /// may delay them by up to an hour to save battery.
  static Future<bool> canExact() async {
    if (!_ready) return false;
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's "Alarms & reminders" setting for Funds.
  static Future<void> requestExact() async {
    if (!_ready) return;
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {}
  }


  /// Replaces all scheduled reminders with fresh ones from the data.
  static Future<void> reschedule(AppState s) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      if (!s.remindersOn) return;
      final now = DateTime.now();
      final list = plan(s, now)..sort((a, b) => a.when.compareTo(b.when));
      final mode = await canExact()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      var id = 1000;
      for (final r in list.take(100)) {
        await _plugin.zonedSchedule(
          id: id++,
          scheduledDate: tz.TZDateTime.from(r.when, tz.local),
          notificationDetails: NotificationDetails(android: _details(r.addAction)),
          androidScheduleMode: mode,
          title: r.title,
          body: r.body,
          payload: r.payload,
        );
      }
    } catch (e) {
      debugPrint('Reminders not scheduled: $e');
    }
  }

  static AndroidNotificationDetails _details(bool addAction) => addAction
      ? AndroidNotificationDetails(
          _channel.channelId,
          _channel.channelName,
          channelDescription: _channel.channelDescription,
          icon: _channel.icon,
          color: _channel.color,
          actions: const [
            AndroidNotificationAction('add', 'Add entry', showsUserInterface: true),
          ],
        )
      : _channel;

  /// Shows "80% / 100% of your budget is used" once a month each.
  static Future<void> checkBudget(AppState s) async {
    if (!_ready || !s.remindersOn || !s.reminderOn('budget')) return;
    final budget = s.overallBudget;
    if (budget == null || !s.feature(Features.budgets)) return;
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final spent = s.overallSpent(month);
    final ratio = spent / budget;
    final key = 'budget_alert_${monthKey(month)}';
    final already = int.tryParse(s.setting(key) ?? '') ?? 0;
    final monthName = DateFormat('MMMM').format(month);
    final daysLeft = daysInMonth(now.year, now.month) - now.day + 1;
    String m(int v) => s.reminderAmounts ? money(v) : '';

    String? title;
    String? body;
    int level = already;
    if (ratio >= 1 && already < 100) {
      level = 100;
      title = "You've used all of your $monthName budget";
      body = s.reminderAmounts
          ? '${m(spent - budget)} over the ${m(budget)} limit.'
          : 'Try to spend less until the 1st.';
    } else if (ratio >= 0.8 && already < 80) {
      level = 80;
      title = '80% of your $monthName budget is used';
      body = s.reminderAmounts
          ? '${m(budget - spent)} left for $daysLeft days.'
          : 'Go slow for the next $daysLeft days.';
    }
    if (title == null) return;
    await s.setSetting(key, '$level');
    try {
      await _plugin.show(
        id: level,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _channel),
        payload: 'home',
      );
    } catch (e) {
      debugPrint('Budget reminder not shown: $e');
    }
  }

  /// Every reminder due in the next 5 weeks, from the current data.
  static List<PlannedReminder> plan(AppState s, DateTime now) {
    final out = <PlannedReminder>[];
    final t = dateOnly(now);
    final end = t.add(const Duration(days: 35));
    final amounts = s.reminderAmounts;
    String m(int v) => money(v);
    DateTime at(DateTime day, int minutes) =>
        DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
    void add(DateTime when, String title, String body, String payload, {bool action = false}) {
      if (when.isAfter(now) && when.isBefore(end)) {
        out.add(PlannedReminder(when, title, body, payload, addAction: action));
      }
    }

    // Plans: bills, SIPs, EMIs the day before; salary on the day.
    for (final p in s.plans) {
      if (!p.active || !s.planVisible(p) || isFinished(p)) continue;
      final kind = p.kind.isIncome ? 'salary' : 'bills';
      if (!s.reminderOn(kind)) continue;
      final first = nextMonthToPost(p);
      for (var i = 0; i < 2; i++) {
        if (p.tenure != null && paidCount(p) + i >= p.tenure!) break;
        final month = addMonths(first, i);
        final due = dueDateIn(month.year, month.month, p.day);
        final account = s.accountName(p.accountId);
        if (p.kind.isIncome) {
          add(
            at(due, s.reminderTime),
            'Salary day',
            amounts
                ? '${m(p.amount)} is added to $account today.'
                : '${p.name} is added to $account today.',
            'home',
          );
        } else {
          add(
            at(due.subtract(const Duration(days: 1)), s.reminderTime),
            amounts ? '${p.name} (${m(p.amount)}) is due tomorrow' : '${p.name} is due tomorrow',
            'Taken from $account on ${shortDate(due)}.',
            'plans',
          );
        }
      }
    }

    // Credit card bills: 3 days before the due date.
    if (s.reminderOn('card') && s.feature(Features.cards)) {
      for (final a in s.accounts.where((a) => a.isCard && a.dueDay != null)) {
        final owed = -s.balanceOf(a.id!);
        if (owed <= 0) continue;
        for (var i = 0; i < 2; i++) {
          final month = addMonths(DateTime(t.year, t.month), i);
          final due = dueDateIn(month.year, month.month, a.dueDay!);
          add(
            at(due.subtract(const Duration(days: 3)), s.reminderTime),
            '${a.name} bill is due in 3 days',
            amounts ? '${m(owed)} outstanding. Due ${shortDate(due)}.' : 'Due ${shortDate(due)}.',
            'accounts',
          );
        }
      }
    }

    // Lend & borrow: the day before and on the day.
    if (s.reminderOn('lend') && s.feature(Features.lend)) {
      for (final l in s.loans) {
        final due = l.dueDate;
        if (due == null || !s.loanOpen(l)) continue;
        final name = s.person(l.personId)?.name ?? 'Someone';
        final total = s.statusOf(l).total;
        for (final (days, word) in const [(1, 'tomorrow'), (0, 'today')]) {
          add(
            at(due.subtract(Duration(days: days)), s.reminderTime),
            l.lent ? '$name should pay you back $word' : 'Pay $name back $word',
            amounts ? '${m(total)} · due ${shortDate(due)}.' : 'Due ${shortDate(due)}.',
            'person:${l.personId}',
          );
        }
      }
    }

    // Fixed deposits: 7 days before and on the maturity day.
    if (s.reminderOn('fd') && s.feature(Features.fds)) {
      for (final f in s.activeFds) {
        final due = f.maturityDate;
        final value = fdMaturityValue(f);
        for (final (days, title) in [
          (7, '${f.name} matures in 7 days'),
          (0, '${f.name} matures today'),
        ]) {
          add(
            at(due.subtract(Duration(days: days)), s.reminderTime),
            title,
            amounts
                ? 'You get ${m(value)}. Choose to withdraw or renew it.'
                : 'Choose to withdraw or renew it.',
            'fd:${f.id}',
          );
        }
      }
    }

    // Monthly report: on the 1st, about the month before.
    if (s.reminderOn('report')) {
      final thisMonth = DateTime(t.year, t.month);
      for (final first in [thisMonth, addMonths(thisMonth, 1)]) {
        final month = addMonths(first, -1);
        final spent = s.expenseInMonth(month);
        final before = s.expenseInMonth(addMonths(month, -1));
        final name = DateFormat('MMMM').format(month);
        String body = 'Tap to see how $name went.';
        if (amounts && spent > 0) {
          body = 'You spent ${m(spent)}';
          if (before > 0) {
            final c = ((spent - before) * 100 / before).round();
            final prev = DateFormat('MMMM').format(addMonths(month, -1));
            body += c == 0 ? ', same as $prev.' : ', ${c.abs()}% ${c < 0 ? 'less' : 'more'} than $prev.';
          } else {
            body += '.';
          }
        }
        add(at(first, s.reminderTime), 'Your $name report is ready', body,
            'report:${monthKey(month)}');
      }
    }

    // Evening reminder, only on days with nothing added.
    if (s.reminderOn('daily')) {
      final addedToday = s.entries.any((e) => sameDay(e.date, t) && e.planId == null);
      for (var i = 0; i < 7; i++) {
        if (i == 0 && addedToday) continue;
        add(
          at(t.add(Duration(days: i)), s.dailyReminderTime),
          "Add today's spending?",
          'Nothing added yet today.',
          'add',
          action: true,
        );
      }
    }
    return out;
  }
}
