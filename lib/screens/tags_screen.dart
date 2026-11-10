import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/categories.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';
import 'entry_form_screen.dart';

Future<void> openTags(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TagsScreen()));

Future<void> openTag(BuildContext context, int id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TagDetailScreen(tagId: id)));

/// Opens the new / edit form. Returns the tag's id when saved.
Future<int?> openTagForm(BuildContext context, {Tag? tag, bool trip = true}) =>
    Navigator.of(context).push<int>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TagFormScreen(tag: tag, trip: trip),
    ));

/// "6 – 9 Nov 2026", "28 Oct – 2 Nov 2026" or "30 Dec 2025 – 2 Jan 2026".
String tripDates(Tag t) {
  if (!t.hasDates) return '';
  final a = t.start!, b = t.end!;
  if (sameDay(a, b)) return DateFormat('d MMM y').format(a);
  if (a.year != b.year) return '${DateFormat('d MMM y').format(a)} – ${DateFormat('d MMM y').format(b)}';
  if (a.month != b.month) return '${DateFormat('d MMM').format(a)} – ${DateFormat('d MMM y').format(b)}';
  return '${a.day} – ${DateFormat('d MMM y').format(b)}';
}

/// Round icon for a tag or trip.
class TagIcon extends StatelessWidget {
  const TagIcon(this.tag, {super.key, this.size = 40});

  final Tag tag;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = tagColor(tag.color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.16), C.surface),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: tag.isTrip
          ? Icon(Icons.flight_takeoff_rounded, color: color, size: size * 0.5)
          : Text('#', style: ts(size * 0.45, weight: FontWeight.w800, color: color)),
    );
  }
}

// ------------------------------------------------------------------ list

class TagsScreen extends StatelessWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = today();
    final trips = s.tags.where((x) => x.isTrip).toList()
      ..sort((a, b) {
        // On now first, then coming up, then the latest past trips.
        int rank(Tag x) => x.covers(t) ? 0 : (x.start != null && x.start!.isAfter(t) ? 1 : 2);
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        final sa = a.start ?? DateTime(2000), sb = b.start ?? DateTime(2000);
        return rank(a) == 1 ? sa.compareTo(sb) : sb.compareTo(sa);
      });
    final plain = s.tags.where((x) => !x.isTrip).toList()
      ..sort((a, b) => s.tagSpent(b.id!).compareTo(s.tagSpent(a.id!)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tags & trips'),
        actions: [
          TextButton(
            onPressed: () => openTagForm(context),
            child: Text('+ New', style: ts(15, weight: FontWeight.w800, color: C.accent)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Text(
              'Group entries from any account or month, like a trip, a wedding or office claims, and see the total.',
              style: ts(13, color: C.muted, height: 1.5),
            ),
            if (s.tags.isEmpty) ...[
              const SizedBox(height: 20),
              EmptyCard(
                icon: Icons.sell_outlined,
                title: 'No tags yet',
                message: 'Make a trip with dates, or a simple tag like "Wedding gifts".',
                action: 'New trip or tag',
                onAction: () => openTagForm(context),
              ),
            ],
            if (trips.isNotEmpty) ...[
              const SizedBox(height: 22),
              const SectionLabel('Trips'),
              CardBox(
                child: Column(
                  children: [
                    for (var i = 0; i < trips.length; i++)
                      _TagRow(tag: trips[i], divider: i < trips.length - 1),
                  ],
                ),
              ),
            ],
            if (plain.isNotEmpty) ...[
              const SizedBox(height: 22),
              const SectionLabel('Tags'),
              CardBox(
                child: Column(
                  children: [
                    for (var i = 0; i < plain.length; i++)
                      _TagRow(tag: plain[i], divider: i < plain.length - 1),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trip or tag?', style: ts(13, weight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(style: ts(13, color: C.muted, height: 1.5), children: [
                      TextSpan(text: 'Trip', style: ts(13, weight: FontWeight.w800)),
                      const TextSpan(
                          text: " has dates. While it's on, every new entry gets its tag by itself, "
                              'and it can have a budget. '),
                      TextSpan(text: 'Tag', style: ts(13, weight: FontWeight.w800)),
                      const TextSpan(text: ' has no dates; you add it to entries yourself.'),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({required this.tag, required this.divider});

  final Tag tag;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final spent = s.tagSpent(tag.id!);
    final n = s.entriesWithTag(tag.id!).length;
    final count = '$n ${n == 1 ? 'entry' : 'entries'}';
    String? note;
    Color noteColor = C.muted;
    if (tag.covers(today())) {
      note = 'On now';
      noteColor = tagColor(tag.color);
    } else if (tag.budget != null && tag.budget! > 0 && n > 0) {
      final left = tag.budget! - spent;
      final m = s.amountsHidden ? '₹••••' : money(left.abs());
      note = left >= 0 ? '$m under budget' : '$m over budget';
      noteColor = left >= 0 ? C.income : C.expense;
    }
    return ListRow(
      divider: divider,
      leading: TagIcon(tag),
      title: tag.name,
      subtitle: tag.isTrip ? '${tripDates(tag)} · $count' : count,
      onTap: () => openTag(context, tag.id!),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Money(spent),
          if (note != null) Text(note, style: ts(12, weight: FontWeight.w700, color: noteColor)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- detail

enum _Split { category, day, account }

class TagDetailScreen extends StatefulWidget {
  const TagDetailScreen({super.key, required this.tagId});

  final int tagId;

  @override
  State<TagDetailScreen> createState() => _TagDetailScreenState();
}

class _TagDetailScreenState extends State<TagDetailScreen> {
  _Split _split = _Split.category;

  Map<String, (int, int)> _groups(AppState s, List<Entry> spending) {
    final out = <String, (int, int)>{};
    for (final e in spending) {
      final key = switch (_split) {
        _Split.category => e.category,
        _Split.day => dayKey(e.date),
        _Split.account => '${e.accountId}',
      };
      final cur = out[key] ?? (0, 0);
      out[key] = (cur.$1 + e.amount, cur.$2 + 1);
    }
    return out;
  }

  String _summary(AppState s, Tag t, List<Entry> spending, int total) {
    final cats = <String, int>{};
    for (final e in spending) {
      cats[e.category] = (cats[e.category] ?? 0) + e.amount;
    }
    final keys = cats.keys.toList()..sort((a, b) => cats[b]!.compareTo(cats[a]!));
    final days = t.hasDates ? t.days : 0;
    return [
      '${t.name}${t.hasDates ? ' · ${tripDates(t)}' : ''}',
      'Total ${money(total)}${days > 1 ? ' (${money((total / days / 100).round() * 100)}/day)' : ''}',
      if (keys.isNotEmpty) keys.map((k) => '${catFor(k).label} ${money(cats[k]!)}').join(' · '),
    ].join('\n');
  }

  Future<void> _share(AppState s, String text) async {
    s.externalActivity = true;
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } finally {
      s.externalActivity = false;
    }
  }

  Future<void> _delete(AppState s, Tag t, int count) async {
    final ok = await confirm(
      context,
      title: 'Delete ${t.isTrip ? 'this trip' : 'this tag'}?',
      message: count == 0
          ? 'It has no entries.'
          : 'Only the tag is removed. The $count ${count == 1 ? 'entry stays' : 'entries stay'}.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    await s.deleteTag(t.id!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = s.tag(widget.tagId);
    if (t == null) return const Scaffold();
    final all = s.entriesWithTag(t.id!);
    final spending = all.where((e) => e.type == EntryType.expense).toList();
    final incomeTotal =
        all.where((e) => e.type == EntryType.income).fold(0, (a, e) => a + e.amount);
    final total = spending.fold(0, (a, e) => a + e.amount);
    final days = t.hasDates ? t.days : 0;
    final groups = _groups(s, spending);
    final keys = groups.keys.toList()
      ..sort((a, b) => _split == _Split.day ? a.compareTo(b) : groups[b]!.$1.compareTo(groups[a]!.$1));
    final top = keys.isEmpty ? 1 : groups.values.map((g) => g.$1).reduce((a, b) => a > b ? a : b);
    String m(int v) => s.amountsHidden ? '₹••••' : money(v);
    final color = tagColor(t.color);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.name),
        actions: [
          IconButton(
            tooltip: 'Share summary',
            onPressed: () => _share(s, _summary(s, t, spending, total)),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: () => openTagForm(context, tag: t),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Center(child: TagIcon(t, size: 56)),
            const SizedBox(height: 10),
            Text(
              [
                if (t.hasDates) '${tripDates(t)} · $days ${days == 1 ? 'day' : 'days'}',
                '${all.length} ${all.length == 1 ? 'entry' : 'entries'}',
              ].join(' · '),
              textAlign: TextAlign.center,
              style: ts(13, weight: FontWeight.w700, color: C.muted),
            ),
            const SizedBox(height: 2),
            Center(child: Money(total, size: 40, letterSpacing: -1.5)),
            if (days > 1 && total > 0)
              Text('About ${m((total / days / 100).round() * 100)} a day',
                  textAlign: TextAlign.center, style: ts(13, weight: FontWeight.w700, color: C.muted)),
            if (incomeTotal > 0)
              Text('Money in: ${m(incomeTotal)}',
                  textAlign: TextAlign.center, style: ts(13, weight: FontWeight.w700, color: C.income)),
            if (t.covers(today()) && t.auto) ...[
              const SizedBox(height: 8),
              Text('On now: new entries get #${t.name} by themselves.',
                  textAlign: TextAlign.center, style: ts(12, weight: FontWeight.w700, color: color)),
            ],
            if (t.budget != null && t.budget! > 0) ...[
              const SizedBox(height: 18),
              CardBox(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('${t.isTrip ? 'Trip' : 'Tag'} budget ${m(t.budget!)}',
                              style: ts(13, weight: FontWeight.w700)),
                        ),
                        Text(
                          total <= t.budget! ? '${m(t.budget! - total)} left' : '${m(total - t.budget!)} over',
                          style: ts(13,
                              weight: FontWeight.w800,
                              color: total <= t.budget! ? C.income : C.expense),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ProgressBar(total / t.budget!,
                        color: total <= t.budget! ? color : C.expense, height: 10),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (spending.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  t.isTrip
                      ? 'No spending yet. Entries dated in the trip get this tag by themselves.'
                      : 'No spending yet. Add this tag when you save an entry.',
                  textAlign: TextAlign.center,
                  style: ts(14, color: C.muted, height: 1.5),
                ),
              )
            else ...[
              _SplitToggle(value: _split, onChanged: (v) => setState(() => _split = v)),
              const SizedBox(height: 14),
              CardBox(
                child: Column(
                  children: [
                    for (var i = 0; i < keys.length; i++)
                      _GroupRow(
                        split: _split,
                        keyName: keys[i],
                        amount: groups[keys[i]]!.$1,
                        count: groups[keys[i]]!.$2,
                        share: groups[keys[i]]!.$1 / top,
                        divider: i < keys.length - 1,
                      ),
                  ],
                ),
              ),
            ],
            if (all.isNotEmpty) ...[
              const SizedBox(height: 22),
              SectionLabel('Entries (${all.length})'),
              CardBox(
                child: Column(
                  children: [
                    for (var i = 0; i < all.length; i++)
                      EntryRow(all[i],
                          showDate: true,
                          divider: i < all.length - 1,
                          onTap: () => openEntryForm(context, entry: all[i])),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlineBtn('Add entry',
                      onPressed: () => openEntryForm(
                            context,
                            tagIds: {t.id!},
                            date: t.hasDates && !t.covers(today()) ? t.start : null,
                          )),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlineBtn('Delete ${t.isTrip ? 'trip' : 'tag'}',
                      color: C.expense, onPressed: () => _delete(s, t, all.length)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Deleting only removes the tag. The entries stay.',
                textAlign: TextAlign.center, style: ts(12, color: C.muted)),
          ],
        ),
      ),
    );
  }
}

class _SplitToggle extends StatelessWidget {
  const _SplitToggle({required this.value, required this.onChanged});

  final _Split value;
  final ValueChanged<_Split> onChanged;

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
            (_Split.category, 'Category'),
            (_Split.day, 'Day'),
            (_Split.account, 'Account'),
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
                            style: ts(14, weight: FontWeight.w800, color: value == v ? C.bg : C.muted)),
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

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.split,
    required this.keyName,
    required this.amount,
    required this.count,
    required this.share,
    required this.divider,
  });

  final _Split split;
  final String keyName;
  final int amount;
  final int count;
  final double share;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    IconData icon;
    Color color;
    String title;
    switch (split) {
      case _Split.category:
        final c = catFor(keyName);
        icon = c.icon;
        color = c.color;
        title = c.label;
      case _Split.day:
        icon = Icons.calendar_today_outlined;
        color = C.muted;
        title = DateFormat('EEE d MMM').format(parseDay(keyName));
      case _Split.account:
        final a = s.account(int.tryParse(keyName));
        icon = a == null ? Icons.account_balance_outlined : accountIcon(a.kind);
        color = C.accent;
        title = s.accountName(int.tryParse(keyName));
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? const Border(bottom: BorderSide(color: C.line)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                IconTile(icon, color: color, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: ts(14, weight: FontWeight.w700)),
                      Text('$count ${count == 1 ? 'entry' : 'entries'}',
                          style: ts(12, color: C.muted)),
                    ],
                  ),
                ),
                Money(amount, size: 14),
              ],
            ),
            if (split == _Split.category) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: ProgressBar(share, color: color, height: 5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ form

class TagFormScreen extends StatefulWidget {
  const TagFormScreen({super.key, this.tag, this.trip = true});

  final Tag? tag;
  final bool trip;

  @override
  State<TagFormScreen> createState() => _TagFormScreenState();
}

class _TagFormScreenState extends State<TagFormScreen> {
  final _name = TextEditingController();
  final _budget = TextEditingController();
  late bool _trip;
  DateTime? _start;
  DateTime? _end;
  bool _auto = true;
  int _color = 0;
  String? _error;
  bool _saving = false;

  bool get _editing => widget.tag != null;

  @override
  void initState() {
    super.initState();
    final t = widget.tag;
    if (t != null) {
      _trip = t.isTrip;
      _name.text = t.name;
      _start = t.start;
      _end = t.end;
      _auto = t.auto;
      _color = t.color;
      if (t.budget != null) _budget.text = amountInput(t.budget!);
    } else {
      _trip = widget.trip;
      final n = context.read<AppState>().tags.length;
      _color = n % tagColors.length;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final now = today();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: _start != null && _end != null
          ? DateTimeRange(start: _start!, end: _end!)
          : DateTimeRange(start: now, end: now.add(const Duration(days: 3))),
    );
    if (r != null) {
      setState(() {
        _start = dateOnly(r.start);
        _end = dateOnly(r.end);
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final name = _name.text.trim();
    final budget = _budget.text.trim().isEmpty ? null : parseAmount(_budget.text);
    String? err;
    if (name.isEmpty) {
      err = 'Enter a name';
    } else if (s.tags.any((t) => t.id != widget.tag?.id && t.name.toLowerCase() == name.toLowerCase())) {
      err = 'You already have "$name"';
    } else if (_trip && (_start == null || _end == null)) {
      err = 'Choose the trip dates';
    } else if (_budget.text.trim().isNotEmpty && (budget == null || budget <= 0)) {
      err = 'Enter a budget, or leave it empty';
    }
    setState(() => _error = err);
    if (err != null) return;

    setState(() => _saving = true);
    final old = widget.tag;
    final tag = Tag(
      id: old?.id,
      name: name,
      isTrip: _trip,
      color: _color,
      start: _trip ? _start : null,
      end: _trip ? _end : null,
      budget: budget,
      auto: _trip && _auto,
      createdAt: old?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );
    final id = await s.saveTag(tag);
    final saved = s.tag(id);

    // Spending already added in the trip's dates can get the tag too.
    if (saved != null && saved.isTrip && saved.auto && mounted) {
      final missing = s.untaggedInTrip(saved);
      if (missing.isNotEmpty) {
        final ok = await confirm(
          context,
          title: 'Tag ${missing.length} ${missing.length == 1 ? 'entry' : 'entries'}?',
          message: 'You already have ${missing.length} '
              '${missing.length == 1 ? 'expense' : 'expenses'} from ${tripDates(saved)}. '
              'Add #${saved.name} to ${missing.length == 1 ? 'it' : 'them'}?',
          confirmLabel: 'Tag them',
          destructive: false,
        );
        if (ok) await s.addTagTo(id, missing.map((e) => e.id!));
      }
    }
    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final word = _trip ? 'trip' : 'tag';
    String day(DateTime? d) => d == null ? 'Choose' : DateFormat('EEE d MMM y').format(d);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_editing ? 'Edit $word' : 'New $word'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  if (!_editing) ...[
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: C.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: C.line),
                      ),
                      child: Row(
                        children: [
                          for (final (v, label) in const [(true, 'Trip (with dates)'), (false, 'Tag')])
                            Expanded(
                              child: Semantics(
                                selected: _trip == v,
                                button: true,
                                child: Material(
                                  color: _trip == v ? C.text : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => setState(() {
                                      _trip = v;
                                      _error = null;
                                    }),
                                    child: SizedBox(
                                      height: 40,
                                      child: Center(
                                        child: Text(label,
                                            style: ts(14,
                                                weight: FontWeight.w800,
                                                color: _trip == v ? C.bg : C.muted)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  TextField(
                    controller: _name,
                    autofocus: !_editing,
                    textCapitalization: TextCapitalization.sentences,
                    style: ts(16, weight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: _trip ? 'Goa trip' : 'Wedding gifts',
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                  if (_trip) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FieldBox(
                            label: 'From',
                            value: day(_start),
                            icon: Icons.calendar_today_outlined,
                            onTap: _pickDates,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FieldBox(
                            label: 'To',
                            value: day(_end),
                            icon: Icons.calendar_today_outlined,
                            onTap: _pickDates,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _budget,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: ts(16, weight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: '${_trip ? 'Trip' : 'Tag'} budget (optional)',
                      prefixText: '₹ ',
                    ),
                  ),
                  if (_trip) ...[
                    const SizedBox(height: 14),
                    CardBox(
                      child: SwitchListTile(
                        value: _auto,
                        onChanged: (v) => setState(() => _auto = v),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        title: Text('Tag new entries by itself', style: ts(14, weight: FontWeight.w700)),
                        subtitle: Text(
                          _start != null && _end != null
                              ? 'Entries dated ${tripDates(Tag(name: '', isTrip: true, start: _start, end: _end, createdAt: 0))} '
                                  'get this tag. You can still remove it from one entry.'
                              : 'Entries dated in the trip get this tag. You can still remove it from one entry.',
                          style: ts(12, color: C.muted, height: 1.4),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const SectionLabel('Colour'),
                  Wrap(
                    spacing: 12,
                    children: [
                      for (var i = 0; i < tagColors.length; i++)
                        Semantics(
                          button: true,
                          selected: _color == i,
                          label: 'Colour ${i + 1}',
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => setState(() => _color = i),
                            child: Container(
                              width: 40,
                              height: 40,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: _color == i ? C.text : Colors.transparent, width: 2),
                              ),
                              child: DecoratedBox(
                                decoration:
                                    BoxDecoration(color: tagColors[i], shape: BoxShape.circle),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: ts(13, weight: FontWeight.w700, color: C.expense)),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: PrimaryButton(_editing ? 'Save changes' : 'Save $word',
                  onPressed: _saving ? null : _save),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small dialog to make a plain tag from the entry form. Returns its id.
Future<int?> quickNewTag(BuildContext context) async {
  final s = context.read<AppState>();
  final ctrl = TextEditingController();
  String? error;
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        void submit() {
          final v = ctrl.text.trim();
          if (v.isEmpty) {
            setSt(() => error = 'Enter a name');
          } else if (s.tags.any((t) => t.name.toLowerCase() == v.toLowerCase())) {
            setSt(() => error = 'You already have "$v"');
          } else {
            Navigator.pop(ctx, v);
          }
        }

        return AlertDialog(
          title: const Text('New tag'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: 'Office claim', errorText: error),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: ts(14, weight: FontWeight.w700, color: C.muted)),
            ),
            TextButton(
              onPressed: submit,
              child: Text('Add', style: ts(14, weight: FontWeight.w800, color: C.accent)),
            ),
          ],
        );
      },
    ),
  );
  if (name == null) return null;
  return s.saveTag(Tag(
    name: name,
    color: s.tags.length % tagColors.length,
    auto: false,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  ));
}
