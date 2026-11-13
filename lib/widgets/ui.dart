import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categories.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';

/// An amount in rupees. Shows ₹•••• when amounts are hidden.
class Money extends StatelessWidget {
  const Money(
    this.paise, {
    super.key,
    this.size = 15,
    this.weight = FontWeight.w800,
    this.color,
    this.plus = false,
    this.colorBySign = false,
    this.letterSpacing = 0,
  });

  final int paise;
  final double size;
  final FontWeight weight;
  final Color? color;
  final bool plus;

  /// Negative amounts in red, positive in green (when [plus]).
  final bool colorBySign;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    final hidden = context.select<AppState, bool>((s) => s.amountsHidden);
    var c = color ?? C.text;
    if (colorBySign) {
      if (paise < 0) {
        c = C.expense;
      } else if (plus && paise > 0) {
        c = C.income;
      }
    }
    final text = hidden ? '₹••••' : money(paise, plus: plus);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ts(size, weight: weight, color: c, letterSpacing: letterSpacing),
    );
  }
}

class CardBox extends StatelessWidget {
  const CardBox({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 20,
    this.color = C.surface,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: const BorderSide(color: C.line),
    );
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.color = C.accent, this.size = 40});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: C.surface2,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Small uppercase heading, e.g. "BANK ACCOUNTS".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text.toUpperCase(),
                style: ts(12, weight: FontWeight.w800, color: C.muted, letterSpacing: 0.6),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Larger heading with an optional "See all" link.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.trailing});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: ts(18, weight: FontWeight.w800)),
            ),
          ),
          ?trailing,
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: C.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(48, 44),
              ),
              child: Text(action!, style: ts(14, weight: FontWeight.w700, color: C.accent)),
            ),
        ],
      ),
    );
  }
}

/// A row inside a [CardBox] list: icon, title + subtitle, trailing widget.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.divider = false,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(15, weight: FontWeight.w700)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ts(13, color: C.muted, height: 1.35)),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? const Border(bottom: BorderSide(color: C.line)) : null,
      ),
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }
}

/// Amount with a small caption under it, right aligned.
class AmountWithCaption extends StatelessWidget {
  const AmountWithCaption(this.amount,
      {super.key, this.caption, this.plus = true, this.captionColor = C.muted});

  final int amount;
  final String? caption;
  final bool plus;
  final Color captionColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Money(amount, plus: plus, colorBySign: true),
        if (caption != null)
          Text(caption!, style: ts(12, weight: FontWeight.w700, color: captionColor)),
      ],
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label, {super.key, this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: C.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: C.surface2,
          disabledForegroundColor: C.faint,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
            Text(label, style: ts(16, weight: FontWeight.w800, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// Blue-tinted pill button, e.g. "+ Add account".
class TintButton extends StatelessWidget {
  const TintButton(this.label, {super.key, this.icon, this.onPressed});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: C.accentTint,
          foregroundColor: C.accent,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
            Text(label, style: ts(14, weight: FontWeight.w800, color: C.accent)),
          ],
        ),
      ),
    );
  }
}

class OutlineBtn extends StatelessWidget {
  const OutlineBtn(this.label, {super.key, this.onPressed, this.color = C.text});

  final String label;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: const BorderSide(color: C.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label, style: ts(14, weight: FontWeight.w700, color: color)),
      ),
    );
  }
}

/// Dashed "add something" row used for empty sections.
class DashedAddRow extends StatelessWidget {
  const DashedAddRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color = C.muted,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorder(radius: 20),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconTile(icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: ts(15, weight: FontWeight.w700)),
                      if (subtitle != null)
                        Text(subtitle!, style: ts(13, color: C.muted)),
                    ],
                  ),
                ),
                const Icon(Icons.add_rounded, color: C.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = C.dashed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(0.75);
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.radius != radius;
}

class ProgressBar extends StatelessWidget {
  const ProgressBar(this.value, {super.key, this.color = C.accent, this.height = 8});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      value: '${(v * 100).round()} percent',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: height,
          // Full width, so the bar is never centred inside a Column.
          width: double.infinity,
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: C.surface2)),
              FractionallySizedBox(
                widthFactor: v == 0 ? 0 : v.clamp(0.02, 1.0),
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One bar split into coloured parts, e.g. spending by category.
class SplitBar extends StatelessWidget {
  const SplitBar({super.key, required this.parts, this.height = 8});

  /// (amount, colour) pairs; zero amounts are skipped.
  final List<(int, Color)> parts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final shown = parts.where((p) => p.$1 > 0).toList();
    final total = shown.fold(0, (s, p) => s + p.$1);
    if (total == 0) return SizedBox(height: height);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: Row(
          // Stretch so the coloured parts fill the bar's height.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                flex: ((shown[i].$1 * 1000) ~/ total).clamp(8, 1000),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: shown[i].$2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tappable field showing a label and a value (account picker, date...).
class FieldBox extends StatelessWidget {
  const FieldBox({
    super.key,
    required this.label,
    required this.value,
    this.icon = Icons.keyboard_arrow_down_rounded,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      radius: 18,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: ts(12, weight: FontWeight.w700, color: C.muted)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(15, weight: FontWeight.w800)),
              ],
            ),
          ),
          Icon(icon, color: C.muted, size: 20),
        ],
      ),
    );
  }
}

/// Filter chip used for "All / Money in / Money out".
class FilterPill extends StatelessWidget {
  const FilterPill(this.label, {super.key, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? C.text : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? C.text : C.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: Text(label,
                style: ts(13,
                    weight: selected ? FontWeight.w800 : FontWeight.w700,
                    color: selected ? C.bg : C.text)),
          ),
        ),
      ),
    );
  }
}

/// One entry in a list (home, passbook, all activity).
class EntryRow extends StatelessWidget {
  const EntryRow(
    this.entry, {
    super.key,
    this.forAccount,
    this.runningBalance,
    this.showDate = false,
    this.divider = false,
    this.onTap,
  });

  final Entry entry;

  /// When set, the amount is shown from this account's point of view.
  final int? forAccount;
  final int? runningBalance;
  final bool showDate;
  final bool divider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final cat = catForEntry(entry);
    final isLoan = entry.loanId != null;
    final isFd = entry.fdId != null;
    final isFund = entry.fundId != null;
    final title = isLoan
        ? s.loanEntryTitle(entry)
        : isFd
            ? s.fdEntryTitle(entry)
            : isFund
                ? s.fundEntryTitle(entry)
                : entry.note.trim().isNotEmpty
                    ? entry.note.trim()
                    : cat.label;

    final parts = <String>[];
    if (showDate) parts.add(shortDate(entry.date));
    if (isLoan || isFd || isFund) {
      if (entry.note.trim().isNotEmpty) parts.add(entry.note.trim());
      if (forAccount == null) parts.add(s.accountName(entry.accountId));
    } else if (entry.type == EntryType.transfer) {
      parts.add('${s.accountName(entry.accountId)} → ${s.accountName(entry.toAccountId)}');
    } else {
      if (entry.note.trim().isNotEmpty) parts.add(cat.label);
      if (forAccount == null) parts.add(s.accountName(entry.accountId));
    }
    if (entry.planId != null) parts.add('Auto');
    if ((entry.type == EntryType.income || entry.type == EntryType.expense) &&
        !s.countsEntry(entry)) {
      parts.add('Not counted');
    }

    int signed;
    var plus = true;
    Color? color;
    if (forAccount != null) {
      signed = entry.effectOn(forAccount!);
    } else {
      switch (entry.type) {
        case EntryType.income:
          signed = entry.amount;
        case EntryType.expense:
          signed = -entry.amount;
        case EntryType.transfer:
          signed = entry.amount;
          plus = false;
          color = C.transfer;
        case EntryType.loanOut:
          signed = -entry.amount;
          color = C.blue;
        case EntryType.loanIn:
          signed = entry.amount;
          color = C.blue;
        case EntryType.depositOut:
          signed = -entry.amount;
          color = C.yellow;
        case EntryType.depositIn:
          signed = entry.amount;
          color = C.yellow;
        case EntryType.investOut:
          signed = entry.amount;
          plus = false;
          color = C.transfer;
        case EntryType.investIn:
          signed = entry.amount;
          color = C.transfer;
      }
    }

    return ListRow(
      leading: IconTile(cat.icon, color: cat.color),
      title: title,
      subtitle: parts.join(' · '),
      divider: divider,
      onTap: onTap,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Money(signed, plus: plus, colorBySign: color == null, color: color),
          if (runningBalance != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _BalanceCaption(runningBalance!),
            ),
        ],
      ),
    );
  }
}

class _BalanceCaption extends StatelessWidget {
  const _BalanceCaption(this.balance);

  final int balance;

  @override
  Widget build(BuildContext context) {
    final hidden = context.select<AppState, bool>((s) => s.amountsHidden);
    return Text('Bal ${hidden ? '₹••••' : money(balance)}',
        style: ts(12, weight: FontWeight.w600, color: C.muted));
  }
}

/// Uppercase day/month label above a group of entries.
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: ts(12, weight: FontWeight.w800, color: C.muted, letterSpacing: 0.5)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
    this.color = C.accent,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          IconTile(icon, color: color, size: 52),
          const SizedBox(height: 14),
          Text(title, style: ts(16, weight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: ts(13, color: C.muted, height: 1.5)),
          if (action != null) ...[
            const SizedBox(height: 16),
            TintButton(action!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- dialogs

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: ts(14, weight: FontWeight.w700, color: C.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel,
              style: ts(14,
                  weight: FontWeight.w800, color: destructive ? C.expense : C.accent)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Bottom sheet to pick an account. Returns the account id.
Future<int?> pickAccount(
  BuildContext context, {
  required String title,
  int? selected,
  int? exclude,
  bool includeCards = true,
}) {
  final s = context.read<AppState>();
  final list = s.visibleAccounts
      .where((a) => a.id != exclude && (includeCards || !a.isCard))
      .toList();
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(title, style: ts(20, weight: FontWeight.w800)),
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No accounts yet. Add one from the Accounts tab.',
                    style: ts(14, color: C.muted)),
              ),
            for (final a in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CardBox(
                  color: a.id == selected ? C.accentTint : C.surface,
                  onTap: () => Navigator.pop(ctx, a.id),
                  child: ListRow(
                    leading: IconTile(accountIcon(a.kind)),
                    title: a.name,
                    subtitle: a.counted ? a.kind.label : '${a.kind.label} · Not counted',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Money(s.balanceOf(a.id!), colorBySign: true),
                        if (a.id == selected) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle_rounded, color: C.accent, size: 20),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Bottom sheet to enter an amount. Returns paise.
Future<int?> askAmount(BuildContext context,
    {required String title, String action = 'Save', int? initial}) {
  final ctrl = TextEditingController(text: initial == null ? '' : amountInput(initial));
  String? error;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        void submit() {
          final v = parseAmount(ctrl.text);
          if (v == null || v <= 0) {
            setSt(() => error = 'Enter an amount');
            return;
          }
          Navigator.pop(ctx, v);
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: ts(20, weight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: ts(22, weight: FontWeight.w800),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  prefixStyle: ts(22, weight: FontWeight.w800, color: C.muted),
                  errorText: error,
                ),
                onSubmitted: (_) => submit(),
              ),
              const SizedBox(height: 16),
              PrimaryButton(action, onPressed: submit),
            ],
          ),
        );
      },
    ),
  );
}
