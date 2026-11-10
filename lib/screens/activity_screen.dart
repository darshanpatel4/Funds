import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../data/models.dart';
import '../data/recurring.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';
import 'entry_form_screen.dart';
import 'report_screen.dart';
import 'tags_screen.dart';

enum _View { byDay, byCategory, calendar }

enum _Type { all, moneyOut, moneyIn, transfers }

/// The Activity tab: the last 7 days, then entries one month at a time,
/// folded by day or summed by category.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late DateTime _month;
  _View _view = _View.byDay;
  _Type _type = _Type.all;
  Set<int> _accounts = {};
  Set<String> _cats = {};
  Set<int> _tagFilter = {};

  /// Day picked on the calendar.
  DateTime? _calDay;
  final _search = TextEditingController();
  bool _searching = false;
  final Set<DateTime> _open = {};
  final Set<DateTime> _full = {};
  bool _autoOpened = false;

  /// Day picked on the 7-day chart (null = none picked yet).
  DateTime? _pickedDay;

  static const _pageSize = 5;

  @override
  void initState() {
    super.initState();
    final t = today();
    _month = DateTime(t.year, t.month);
  }

  /// A bar on the 7-day chart was tapped: show that day's month with only
  /// that day open.
  void _pickDay(DateTime d) {
    setState(() {
      _pickedDay = d;
      final m = DateTime(d.year, d.month);
      if (m != _month) {
        _month = m;
        _full.clear();
      }
      _view = _View.byDay;
      _open
        ..clear()
        ..add(d);
      _autoOpened = true;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim().toLowerCase();

  bool _inMonth(Entry e) => e.date.year == _month.year && e.date.month == _month.month;

  bool _typeOk(Entry e) => switch (_type) {
        _Type.all => true,
        _Type.moneyOut => e.type == EntryType.expense,
        _Type.moneyIn => e.type == EntryType.income,
        _Type.transfers => e.type == EntryType.transfer,
      };

  bool _filterOk(Entry e, Set<int> accounts, Set<String> cats, [Set<int>? tagSet]) {
    final tags = tagSet ?? _tagFilter;
    if (tags.isNotEmpty &&
        !context.read<AppState>().tagsOf(e.id).any(tags.contains)) {
      return false;
    }
    if (accounts.isNotEmpty &&
        !accounts.contains(e.accountId) &&
        !accounts.contains(e.toAccountId)) {
      return false;
    }
    if (cats.isNotEmpty && (e.type == EntryType.transfer || !cats.contains(e.category))) {
      return false;
    }
    return true;
  }

  bool _queryOk(Entry e, AppState s) {
    final q = _query;
    if (q.isEmpty) return true;
    final hay = [
      e.note,
      catForEntry(e).label,
      s.accountName(e.accountId),
      if (e.toAccountId != null) s.accountName(e.toAccountId),
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  /// Entries the filters are applied to: this month, or everything while
  /// searching.
  Iterable<Entry> _base(AppState s) =>
      _query.isEmpty ? s.entries.where(_inMonth) : s.entries.where((e) => _queryOk(e, s));

  void _changeMonth(int delta) {
    setState(() {
      _month = addMonths(_month, delta);
      _open.clear();
      _full.clear();
      _autoOpened = false;
      _calDay = null;
    });
  }

  Future<void> _openFilter(AppState s) async {
    final base = _base(s).where(_typeOk).toList();
    final result = await showModalBottomSheet<(Set<int>, Set<String>, Set<int>)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        accounts: _accounts,
        cats: _cats,
        tags: _tagFilter,
        count: (a, c, t) => base.where((e) => _filterOk(e, a, c, t)).length,
      ),
    );
    if (result != null) {
      setState(() {
        _accounts = result.$1;
        _cats = result.$2;
        _tagFilter = result.$3;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final searching = _query.isNotEmpty;
    final list = _base(s)
        .where((e) => _typeOk(e) && _filterOk(e, _accounts, _cats))
        .toList();

    // Family / company accounts stay out of the totals, unless the user
    // filtered to specific accounts to look at them.
    bool counts(Entry e) => _accounts.isNotEmpty || s.countsEntry(e);
    final inn = list
        .where((e) => e.type == EntryType.income && counts(e))
        .fold(0, (a, e) => a + e.amount);
    final out = list
        .where((e) => e.type == EntryType.expense && counts(e))
        .fold(0, (a, e) => a + e.amount);

    // Month arrows only go as far as there are entries.
    final t = today();
    final thisMonth = DateTime(t.year, t.month);
    var latest = thisMonth;
    var earliest = thisMonth;
    if (s.entries.isNotEmpty) {
      final newest = s.entries.first.date;
      final oldest = s.entries.last.date;
      final nm = DateTime(newest.year, newest.month);
      final om = DateTime(oldest.year, oldest.month);
      if (nm.isAfter(latest)) latest = nm;
      if (om.isBefore(earliest)) earliest = om;
    }
    final canPrev = _month.isAfter(earliest);
    final canNext = _month.isBefore(latest);

    // Filters on tags that were deleted are dropped.
    _tagFilter.removeWhere((id) => s.tag(id) == null);
    final filterCount = _accounts.length + _cats.length + _tagFilter.length;
    final view = searching && _view == _View.calendar ? _View.byDay : _view;

    final showWeek = !searching && _month == thisMonth;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Activity',
                    style: ts(28, weight: FontWeight.w800, letterSpacing: -0.5)),
              ),
              if (s.feature(Features.tags))
                IconButton(
                  tooltip: 'Tags & trips',
                  icon: const Icon(Icons.sell_outlined),
                  onPressed: () => openTags(context),
                ),
              IconButton(
                tooltip: 'Report for ${monthTitle(_month)}',
                icon: const Icon(Icons.insights_rounded),
                onPressed: () => openReport(context, _month),
              ),
              IconButton(
                tooltip: _searching ? 'Close search' : 'Search',
                icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _search.clear();
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (showWeek) ...[
            _WeekChart(state: s, picked: _pickedDay, onPick: _pickDay),
            const SizedBox(height: 18),
          ],
          if (_searching) ...[
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: ts(15, weight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'Search notes, categories, accounts',
                prefixIcon: Icon(Icons.search_rounded, color: C.muted),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (searching)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${list.length} ${list.length == 1 ? 'result' : 'results'} in all months',
                style: ts(13, weight: FontWeight.w700, color: C.muted),
              ),
            )
          else
            _MonthSwitcher(
              month: _month,
              subtitle: _monthSubtitle(list.length),
              onPrev: canPrev ? () => _changeMonth(-1) : null,
              onNext: canNext ? () => _changeMonth(1) : null,
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Total('Money in', inn, C.income)),
              const SizedBox(width: 10),
              Expanded(child: _Total('Money out', -out, C.expense)),
            ],
          ),
          const SizedBox(height: 14),
          _ViewToggle(value: view, onChanged: (v) => setState(() => _view = v)),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                _FilterButton(count: filterCount, onTap: () => _openFilter(s)),
                for (final (f, label) in const [
                  (_Type.all, 'All'),
                  (_Type.moneyOut, 'Money out'),
                  (_Type.moneyIn, 'Money in'),
                  (_Type.transfers, 'Transfers'),
                ]) ...[
                  const SizedBox(width: 8),
                  FilterPill(label, selected: _type == f, onTap: () => setState(() => _type = f)),
                ],
              ],
            ),
          ),
          if (filterCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in _accounts)
                    _ActiveFilter(s.accountName(id),
                        onRemove: () => setState(() => _accounts = {..._accounts}..remove(id))),
                  for (final c in _cats)
                    _ActiveFilter(_catName(c),
                        onRemove: () => setState(() => _cats = {..._cats}..remove(c))),
                  for (final t in _tagFilter)
                    _ActiveFilter('#${s.tag(t)?.name ?? ''}',
                        onRemove: () => setState(() => _tagFilter = {..._tagFilter}..remove(t))),
                ],
              ),
            ),
          const SizedBox(height: 4),
          if (view == _View.byDay)
            ..._byDay(context, s, list)
          else if (view == _View.byCategory)
            ..._byCategory(list.where(counts).toList())
          else ...[
            const SizedBox(height: 10),
            _CalendarView(
              state: s,
              month: _month,
              entries: list,
              counts: counts,
              selected: _calDay,
              onPick: (d) => setState(() => _calDay = d),
            ),
          ],
        ],
      ),
    );
  }

  String _monthSubtitle(int count) {
    final t = today();
    final entries = '$count ${count == 1 ? 'entry' : 'entries'}';
    if (_month.year == t.year && _month.month == t.month && t.day > 1) {
      return '1 – ${t.day} ${DateFormat('MMM').format(t)} · $entries';
    }
    return entries;
  }

  String _dayTitle(DateTime d) {
    final t = today();
    final sameYear = d.year == t.year;
    final f = DateFormat(sameYear ? 'EEE d MMM' : 'EEE d MMM y').format(d);
    if (sameDay(d, t)) return 'Today · $f';
    if (sameDay(d, t.subtract(const Duration(days: 1)))) return 'Yesterday · $f';
    return f;
  }

  List<Widget> _byDay(BuildContext context, AppState s, List<Entry> list) {
    if (list.isEmpty) return [_emptyText(s)];
    final days = <DateTime, List<Entry>>{};
    for (final e in list) {
      days.putIfAbsent(dateOnly(e.date), () => []).add(e);
    }
    if (!_autoOpened) {
      _open.add(days.keys.first);
      _autoOpened = true;
    }

    return [
      for (final d in days.keys)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _DayCard(
            title: _dayTitle(d),
            entries: days[d]!,
            open: _open.contains(d),
            showAll: _full.contains(d),
            pageSize: _pageSize,
            onToggle: () => setState(() => _open.contains(d) ? _open.remove(d) : _open.add(d)),
            onShowMore: () => setState(() => _full.contains(d) ? _full.remove(d) : _full.add(d)),
            onEntry: (e) => openEntryForm(context, entry: e),
            counts: (e) => _accounts.isNotEmpty || s.countsEntry(e),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Text(
          _query.isEmpty
              ? 'Tap a day to open or close it. Use the arrows above for other months.'
              : 'Tap a day to open or close it.',
          textAlign: TextAlign.center,
          style: ts(12, weight: FontWeight.w600, color: C.muted),
        ),
      ),
    ];
  }

  List<Widget> _byCategory(List<Entry> list) {
    if (_type == _Type.transfers) {
      return [_note('Transfers move money between your own accounts, so they have no category.')];
    }
    final income = _type == _Type.moneyIn;
    final src = list.where((e) => e.type == (income ? EntryType.income : EntryType.expense));
    final sums = <String, int>{};
    final counts = <String, int>{};
    for (final e in src) {
      sums[e.category] = (sums[e.category] ?? 0) + e.amount;
      counts[e.category] = (counts[e.category] ?? 0) + 1;
    }
    if (sums.isEmpty) {
      return [_note(income ? 'No money came in for this view.' : 'No spending for this view.')];
    }
    final keys = sums.keys.toList()..sort((a, b) => sums[b]!.compareTo(sums[a]!));
    final total = sums.values.fold(0, (a, b) => a + b);
    final top = keys.first;
    final avg = sums[top]! ~/ counts[top]!;
    final hidden = context.read<AppState>().amountsHidden;

    return [
      const SizedBox(height: 16),
      CardBox(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(income ? 'Where the money came from' : 'Where the money went',
                style: ts(13, weight: FontWeight.w600, color: C.muted)),
            const SizedBox(height: 12),
            SplitBar(parts: [for (final k in keys) (sums[k]!, catFor(k).color)], height: 12),
            const SizedBox(height: 12),
            Text(
              '${catFor(top).label} was your biggest ${income ? 'source' : 'spend'}: '
              '${counts[top]} ${counts[top] == 1 ? 'entry' : 'entries'}'
              '${hidden ? '' : ', about ${money(avg)} each'}.',
              style: ts(13, color: C.muted, height: 1.4),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      CardBox(
        child: Column(
          children: [
            for (var i = 0; i < keys.length; i++)
              _CategoryRow(
                cat: catFor(keys[i]),
                amount: sums[keys[i]]!,
                count: counts[keys[i]]!,
                share: sums[keys[i]]! / total,
                ofTop: sums[keys[i]]! / sums[top]!,
                income: income,
                divider: i < keys.length - 1,
                onTap: () => setState(() {
                  _cats = {keys[i]};
                  _view = _View.byDay;
                  _open.clear();
                  _autoOpened = false;
                }),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text('Tap a category to see only its entries.',
            textAlign: TextAlign.center,
            style: ts(12, weight: FontWeight.w600, color: C.muted)),
      ),
    ];
  }

  Widget _emptyText(AppState s) {
    String msg;
    if (s.entries.isEmpty) {
      msg = 'No entries yet. Tap + on Home to add one.';
    } else if (_query.isNotEmpty) {
      msg = 'Nothing matches your search.';
    } else if (_type != _Type.all ||
        _accounts.isNotEmpty ||
        _cats.isNotEmpty ||
        _tagFilter.isNotEmpty) {
      msg = 'Nothing matches these filters in ${monthTitle(_month)}.';
    } else {
      msg = 'No entries in ${monthTitle(_month)}.';
    }
    return _note(msg);
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Text(text, textAlign: TextAlign.center, style: ts(14, color: C.muted)),
      );
}

String _catName(String key) => key == 'other_in' ? 'Other income' : catFor(key).label;

// ------------------------------------------------------------------ parts

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.subtitle,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final String subtitle;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, String label, VoidCallback? onTap) => Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: onTap == null ? C.line : C.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon,
                  color: onTap == null ? C.faint : C.text, semanticLabel: label, size: 22),
            ),
          ),
        );

    return Row(
      children: [
        arrow(Icons.chevron_left_rounded, 'Previous month', onPrev),
        Expanded(
          child: Column(
            children: [
              Text(monthTitle(month), style: ts(17, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, style: ts(12, weight: FontWeight.w600, color: C.muted)),
            ],
          ),
        ),
        arrow(Icons.chevron_right_rounded, 'Next month', onNext),
      ],
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.amount, this.color);

  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ts(12, weight: FontWeight.w600, color: C.muted)),
          const SizedBox(height: 4),
          Money(amount, size: 18, plus: true, color: color),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.value, required this.onChanged});

  final _View value;
  final ValueChanged<_View> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.line),
      ),
      child: Row(
        children: [
          for (final (v, label) in const [
            (_View.byDay, 'By day'),
            (_View.byCategory, 'By category'),
            (_View.calendar, 'Calendar'),
          ])
            Expanded(
              child: Semantics(
                selected: value == v,
                button: true,
                child: Material(
                  color: value == v ? C.text : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onChanged(v),
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(label,
                            style: ts(14,
                                weight: FontWeight.w800, color: value == v ? C.bg : C.muted)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.accentTint,
      shape: const StadiumBorder(side: BorderSide(color: C.accent)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.filter_list_rounded, size: 18, color: C.accent),
              const SizedBox(width: 6),
              Text(count == 0 ? 'Filter' : 'Filter · $count',
                  style: ts(13, weight: FontWeight.w800, color: C.accent)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveFilter extends StatelessWidget {
  const _ActiveFilter(this.label, {required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.surface2,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onRemove,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: ts(12, weight: FontWeight.w700)),
              const SizedBox(width: 4),
              Icon(Icons.close_rounded, size: 16, color: C.muted, semanticLabel: 'Remove $label'),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.title,
    required this.entries,
    required this.open,
    required this.showAll,
    required this.pageSize,
    required this.onToggle,
    required this.onShowMore,
    required this.onEntry,
    required this.counts,
  });

  final String title;
  final List<Entry> entries;
  final bool open;
  final bool showAll;
  final int pageSize;
  final VoidCallback onToggle;
  final VoidCallback onShowMore;
  final ValueChanged<Entry> onEntry;

  /// Whether an entry counts in the day's total.
  final bool Function(Entry) counts;

  @override
  Widget build(BuildContext context) {
    var net = 0;
    for (final e in entries.where(counts)) {
      if (e.type == EntryType.income) net += e.amount;
      if (e.type == EntryType.expense) net -= e.amount;
    }
    final visible = showAll ? entries : entries.take(pageSize).toList();
    final more = entries.length - pageSize;

    return CardBox(
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: ts(15, weight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text('${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}',
                              style: ts(12, weight: FontWeight.w600, color: C.muted)),
                        ],
                      ),
                    ),
                    if (net != 0) Money(net, plus: true, colorBySign: true),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.keyboard_arrow_down_rounded, color: C.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open) ...[
            for (final e in visible)
              DecoratedBox(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
                child: EntryRow(e, onTap: () => onEntry(e)),
              ),
            if (more > 0)
              DecoratedBox(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
                child: InkWell(
                  onTap: onShowMore,
                  child: SizedBox(
                    height: 44,
                    width: double.infinity,
                    child: Center(
                      child: Text(showAll ? 'Show less' : 'Show $more more',
                          style: ts(14, weight: FontWeight.w700, color: C.accent)),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.cat,
    required this.amount,
    required this.count,
    required this.share,
    required this.ofTop,
    required this.income,
    required this.divider,
    required this.onTap,
  });

  final Cat cat;
  final int amount;
  final int count;
  final double share;
  final double ofTop;
  final bool income;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? const Border(bottom: BorderSide(color: C.line)) : null,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                        Text(cat.key == 'other_in' ? 'Other income' : cat.label,
                            style: ts(15, weight: FontWeight.w700)),
                        Text('$count ${count == 1 ? 'entry' : 'entries'}',
                            style: ts(13, color: C.muted)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Money(income ? amount : -amount, plus: true, colorBySign: true),
                      Text('${(share * 100).round()}%',
                          style: ts(12, weight: FontWeight.w700, color: C.muted)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: ProgressBar(ofTop, color: cat.color, height: 6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.accounts,
    required this.cats,
    required this.tags,
    required this.count,
  });

  final Set<int> accounts;
  final Set<String> cats;
  final Set<int> tags;
  final int Function(Set<int>, Set<String>, Set<int>) count;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<int> _a = {...widget.accounts};
  late Set<String> _c = {...widget.cats};
  late Set<int> _t = {...widget.tags};

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final n = widget.count(_a, _c, _t);
    final cats = [...expenseCats, ...systemCats, ...incomeCats];

    Widget chip(String label, bool on, VoidCallback onTap, {Color? dot}) => Semantics(
          selected: on,
          button: true,
          child: Material(
            color: on ? C.accentTint : Colors.transparent,
            shape: StadiumBorder(side: BorderSide(color: on ? C.accent : C.border, width: 1.5)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dot != null) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(label,
                        style: ts(14, weight: FontWeight.w700, color: on ? C.accent : C.text)),
                  ],
                ),
              ),
            ),
          ),
        );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Filter entries', style: ts(22, weight: FontWeight.w800))),
                  TextButton(
                    onPressed: () => setState(() {
                      _a = {};
                      _c = {};
                      _t = {};
                    }),
                    child: Text('Clear all',
                        style: ts(14, weight: FontWeight.w700, color: C.accent)),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      const SectionLabel('Accounts'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final a in s.visibleAccounts)
                            chip(a.name, _a.contains(a.id), () => setState(() {
                                  _a.contains(a.id) ? _a.remove(a.id) : _a.add(a.id!);
                                })),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const SectionLabel('Categories'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in cats)
                            chip(_catName(c.key), _c.contains(c.key), () => setState(() {
                                  _c.contains(c.key) ? _c.remove(c.key) : _c.add(c.key);
                                }), dot: c.color),
                        ],
                      ),
                      if (s.feature(Features.tags) && s.tags.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const SectionLabel('Tags & trips'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final t in s.tags)
                              chip('#${t.name}', _t.contains(t.id), () => setState(() {
                                    _t.contains(t.id) ? _t.remove(t.id) : _t.add(t.id!);
                                  }), dot: tagColor(t.color)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              PrimaryButton(
                n == 0 ? 'No entries match' : 'Show $n ${n == 1 ? 'entry' : 'entries'}',
                onPressed: n == 0 ? null : () => Navigator.pop(context, (_a, _c, _t)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bar chart of spending over the last 7 days. Tapping a bar opens that day.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.state, required this.picked, required this.onPick});

  final AppState state;
  final DateTime? picked;
  final ValueChanged<DateTime> onPick;

  int _spentOn(DateTime day) => state.entries
      .where((e) => e.type == EntryType.expense && sameDay(e.date, day) && state.countsEntry(e))
      .fold(0, (a, e) => a + e.amount);

  String _short(int paise) {
    if (state.amountsHidden) return '••';
    if (paise == 0) return '';
    final r = paise / 100;
    if (r >= 100000) return '₹${(r / 100000).toStringAsFixed(1)}L';
    if (r >= 1000) return '₹${(r / 1000).toStringAsFixed(1)}k';
    return '₹${r.round()}';
  }

  @override
  Widget build(BuildContext context) {
    final t = today();
    final days = [for (var i = 6; i >= 0; i--) t.subtract(Duration(days: i))];
    final spent = [for (final d in days) _spentOn(d)];
    final maxSpent = spent.fold(0, (a, b) => b > a ? b : a);
    final total = spent.fold(0, (a, b) => a + b);
    final selected = picked ?? t;
    String m(int v) => state.amountsHidden ? '₹••••' : money(v);
    const barArea = 86.0;

    String note;
    if (picked != null) {
      final i = days.indexWhere((d) => sameDay(d, picked!));
      final amount = i < 0 ? 0 : spent[i];
      final label = DateFormat('EEE d MMM').format(picked!);
      note = amount == 0
          ? '$label: nothing spent.'
          : '$label: ${m(amount)} spent. Its entries are open below.';
    } else if (total == 0) {
      note = 'No spending in the last 7 days.';
    } else {
      note = 'About ${m((total / 7 / 100).round() * 100)} a day. Tap a day to see its entries.';
    }

    return CardBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Last 7 days', style: ts(15, weight: FontWeight.w800))),
              Money(-total, colorBySign: true),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: barArea + 22,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: sameDay(days[i], selected),
                      label: '${i == 6 ? 'Today' : DateFormat('EEEE d MMMM').format(days[i])}, '
                          'spent ${state.amountsHidden ? 'hidden' : money(spent[i])}',
                      excludeSemantics: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onPick(days[i]),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(_short(spent[i]),
                                maxLines: 1,
                                style: ts(10,
                                    weight: FontWeight.w700,
                                    color: sameDay(days[i], selected) ? C.text : C.muted)),
                            const SizedBox(height: 6),
                            Container(
                              height: maxSpent == 0
                                  ? 6
                                  : (barArea * spent[i] / maxSpent).clamp(6, barArea).toDouble(),
                              decoration: BoxDecoration(
                                color: sameDay(days[i], selected) ? C.accent : C.border,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    i == 6 ? 'Today' : DateFormat('EEEEE').format(days[i]),
                    textAlign: TextAlign.center,
                    style: ts(12,
                        weight: FontWeight.w700,
                        color: sameDay(days[i], selected) ? C.accent : C.muted),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(note, style: ts(13, color: C.muted)),
        ],
      ),
    );
  }
}

/// One month as a calendar: what was spent each day (darker = heavier),
/// plans due on coming days, and the picked day's entries below.
class _CalendarView extends StatelessWidget {
  const _CalendarView({
    required this.state,
    required this.month,
    required this.entries,
    required this.counts,
    required this.selected,
    required this.onPick,
  });

  final AppState state;
  final DateTime month;
  final List<Entry> entries;
  final bool Function(Entry) counts;
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;

  static const _none = Color(0xFF0A0A0A);
  static const _light = Color(0xFF3A1219);
  static const _mid = Color(0xFF55171F);
  static const _heavy = Color(0xFF7A1F2B);

  String _short(int paise) {
    if (state.amountsHidden) return '••';
    final r = paise / 100;
    if (r >= 100000) return '${(r / 100000).toStringAsFixed(1)}L';
    if (r >= 1000) return '${(r / 1000).toStringAsFixed(1)}k';
    return '${r.round()}';
  }

  /// Plans that will add an entry on [day] (a day after today).
  List<Plan> _plansOn(DateTime day) {
    final m = DateTime(day.year, day.month);
    return [
      for (final p in state.plans)
        if (p.active &&
            state.planVisible(p) &&
            !isFinished(p) &&
            !m.isBefore(nextMonthToPost(p)) &&
            (p.tenure == null || monthsBetween(parseMonth(p.startMonth), m) < p.tenure!) &&
            sameDay(dueDateIn(m.year, m.month, p.day), day))
          p,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = today();
    final n = daysInMonth(month.year, month.month);
    final lead = DateTime(month.year, month.month, 1).weekday % 7; // Sunday first

    final spent = <int, int>{};
    final income = <int>{};
    final byDay = <int, List<Entry>>{};
    for (final e in entries) {
      byDay.putIfAbsent(e.date.day, () => []).add(e);
      if (!counts(e)) continue;
      if (e.type == EntryType.expense) spent[e.date.day] = (spent[e.date.day] ?? 0) + e.amount;
      if (e.type == EntryType.income) income.add(e.date.day);
    }
    final trips = s.feature(Features.tags) ? s.tags.where((x) => x.hasDates).toList() : <Tag>[];

    // What a normal day is: the budget per day, or this month's average.
    final budget = s.feature(Features.budgets) ? s.overallBudget : null;
    final double normal = budget != null
        ? budget / n
        : (spent.isEmpty ? 0 : spent.values.fold(0, (a, b) => a + b) / spent.length);
    Color heat(int v) {
      if (v <= 0) return _none;
      if (normal <= 0 || v <= normal) return _light;
      return v <= normal * 2 ? _mid : _heavy;
    }

    final isThisMonth = month.year == t.year && month.month == t.month;
    var pick = selected;
    if (pick == null || pick.year != month.year || pick.month != month.month) {
      if (isThisMonth) {
        pick = t;
      } else {
        final last = byDay.keys.isEmpty ? 1 : byDay.keys.reduce((a, b) => a > b ? a : b);
        pick = DateTime(month.year, month.month, last);
      }
    }
    final picked = pick;

    final cells = <Widget>[];
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= n; d++) {
      final day = DateTime(month.year, month.month, d);
      final future = day.isAfter(t);
      final v = spent[d] ?? 0;
      final dots = <Color>[
        if (trips.any((x) => x.covers(day))) C.yellow,
        if (income.contains(d)) C.income,
        if (future)
          for (final p in _plansOn(day)) p.kind.isIncome ? C.income : C.accent,
      ];
      final isPick = sameDay(day, picked);
      final isToday = sameDay(day, t);
      cells.add(Semantics(
        button: true,
        selected: isPick,
        label: '${DateFormat('EEEE d MMMM').format(day)}'
            '${future ? '' : ', spent ${s.amountsHidden ? 'hidden' : money(v)}'}',
        excludeSemantics: true,
        child: Material(
          color: future ? Colors.transparent : heat(v),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isPick ? C.text : (isToday ? C.accent : Colors.transparent),
              width: 2,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onPick(day),
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Column(
                children: [
                  Text('$d',
                      style: ts(13,
                          weight: isToday ? FontWeight.w800 : FontWeight.w700,
                          color: future ? C.faint : C.text)),
                  Text(
                    future ? '' : (v > 0 ? _short(v) : '0'),
                    maxLines: 1,
                    style: ts(10,
                        weight: FontWeight.w800,
                        color: v > 0 ? const Color(0xFFFFD6DB) : C.income),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final c in dots.take(3))
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
    }

    Widget legend(Widget mark, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            mark,
            const SizedBox(width: 5),
            Text(text, style: ts(11, weight: FontWeight.w700, color: C.muted)),
          ],
        );
    Widget box(Color c) => Container(
        width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)));
    Widget dot(Color c) =>
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

    final pickFuture = picked.isAfter(t);
    final dayEntries = byDay[picked.day] ?? const <Entry>[];
    final plansDue = pickFuture ? _plansOn(picked) : const <Plan>[];
    final daySpent = spent[picked.day] ?? 0;
    final title = '${sameDay(picked, t) ? 'Today · ' : ''}${DateFormat('EEE d MMM').format(picked)}';
    final dayTrips = trips.where((x) => x.covers(picked)).map((x) => x.name).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardBox(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
          child: Column(
            children: [
              Row(
                children: [
                  for (final w in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                    Expanded(
                      child: Text(w,
                          textAlign: TextAlign.center,
                          style: ts(11, weight: FontWeight.w800, color: C.faint)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 0.82,
                children: cells,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    legend(box(_light), budget != null ? 'Within daily budget' : 'Light day'),
                    legend(box(_heavy), 'Heavy day'),
                    legend(dot(C.accent), 'Plan due'),
                    legend(dot(C.income), 'Money in'),
                    if (trips.isNotEmpty) legend(dot(C.yellow), 'Trip'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: ts(15, weight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(
                            pickFuture
                                ? (plansDue.isEmpty ? 'Nothing planned' : 'Coming up')
                                : [
                                    dayEntries.isEmpty
                                        ? 'No entries'
                                        : '${dayEntries.length} ${dayEntries.length == 1 ? 'entry' : 'entries'}',
                                    ...dayTrips,
                                  ].join(' · '),
                            style: ts(12, weight: FontWeight.w600, color: C.muted),
                          ),
                        ],
                      ),
                    ),
                    if (!pickFuture)
                      Money(-daySpent, colorBySign: true, color: daySpent == 0 ? C.income : null),
                  ],
                ),
              ),
              if (!pickFuture && dayEntries.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text('No spending this day.', style: ts(13, color: C.muted)),
                ),
              for (final e in dayEntries)
                DecoratedBox(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
                  child: EntryRow(e, onTap: () => openEntryForm(context, entry: e)),
                ),
              for (final p in plansDue)
                DecoratedBox(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
                  child: ListRow(
                    leading: IconTile(planLook(p.kind).$1, color: planLook(p.kind).$2),
                    title: p.name,
                    subtitle: 'Plan · ${s.accountName(p.accountId)}',
                    trailing: Money(p.kind.isIncome ? p.amount : -p.amount,
                        plus: true, colorBySign: true),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text('Tap any day. Coming days show plans that are due.',
              textAlign: TextAlign.center,
              style: ts(12, weight: FontWeight.w600, color: C.muted)),
        ),
      ],
    );
  }
}
