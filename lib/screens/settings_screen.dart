import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/logo.dart';
import '../widgets/ui.dart';
import 'accounts_screen.dart';
import 'lock_screen.dart';

const appVersion = '1.0.0';

const _lockOptions = [
  (0, 'Immediately'),
  (30, '30 seconds'),
  (60, '1 minute'),
  (300, '5 minutes'),
  (900, '15 minutes'),
];

String _lockLabel(int seconds) {
  for (final (v, label) in _lockOptions) {
    if (v == seconds) return label;
  }
  return '$seconds seconds';
}

const _features = [
  (Features.salary, Icons.work_outline_rounded, C.accent, 'Salary',
      'Monthly salary credited automatically'),
  (Features.sips, Icons.trending_up_rounded, C.transfer, 'SIPs & investments',
      'Mutual fund SIPs deducted on their date'),
  (Features.bills, Icons.receipt_long_outlined, C.blue, 'Bills & rent',
      'Rent, subscriptions and fixed payments'),
  (Features.loans, Icons.account_balance_outlined, C.yellow, 'Loans & EMIs',
      'Loan tenure and EMI, deducted monthly'),
  (Features.cards, Icons.credit_card_rounded, C.pink, 'Credit cards',
      'Card limits, bill amounts and due dates'),
  (Features.budgets, Icons.donut_large_rounded, C.orange, 'Budgets',
      'Monthly budget and category limits'),
  (Features.goals, Icons.flag_outlined, C.teal, 'Savings goals',
      'Money set aside for a trip or a gadget'),
  (Features.lend, Icons.handshake_outlined, C.blue, 'Lend & borrow',
      'Money you lent to or borrowed from people'),
  (Features.fds, Icons.lock_outline_rounded, C.yellow, 'Fixed deposits',
      'FD value today, maturity amount, withdraw or renew'),
];

/// True when there is no backup yet or the last one is over 30 days old.
bool _backupDue(AppState s) {
  final last = s.lastBackup;
  return last == null || DateTime.now().difference(last).inDays > 30;
}

void _open(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

// ------------------------------------------------------------- main list

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();

    final security = s.appLock
        ? 'App lock on · locks after ${_lockLabel(s.lockAfterSeconds).toLowerCase()}'
        : 'App lock off';
    final onNames = [for (final f in _features) if (s.feature(f.$1)) f.$4];
    final featuresLine = onNames.isEmpty
        ? 'All off'
        : '${onNames.length} of ${_features.length} on · '
            '${onNames.take(3).join(', ')}${onNames.length > 3 ? '…' : ''}';
    final last = s.lastBackup;
    final due = _backupDue(s);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('Settings', style: ts(28, weight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 20),
          CardBox(
            child: Column(
              children: [
                _MenuRow(
                  icon: Icons.account_balance_outlined,
                  color: C.accent,
                  title: 'Accounts',
                  subtitle: s.accounts.isEmpty
                      ? 'Add your bank accounts and cash'
                      : '${s.visibleAccounts.length} '
                          '${s.visibleAccounts.length == 1 ? 'account' : 'accounts'} · '
                          '${s.amountsHidden ? '₹••••' : money(s.totalBalance)} total',
                  onTap: () => openAccounts(context),
                ),
                _MenuRow(
                  icon: Icons.shield_outlined,
                  color: C.accent,
                  title: 'Security',
                  subtitle: security,
                  onTap: () => _open(context, const SecuritySettingsScreen()),
                ),
                _MenuRow(
                  icon: Icons.grid_view_rounded,
                  color: C.teal,
                  title: 'Features',
                  subtitle: featuresLine,
                  onTap: () => _open(context, const FeaturesSettingsScreen()),
                ),
                _MenuRow(
                  icon: Icons.sync_rounded,
                  color: C.blue,
                  title: 'Backup & restore',
                  subtitle: last == null
                      ? 'Last backup: never'
                      : 'Last backup: ${friendlyDay(last)}',
                  attention: due,
                  onTap: () => _open(context, const BackupSettingsScreen()),
                ),
                _MenuRow(
                  icon: Icons.info_outline_rounded,
                  color: C.muted,
                  title: 'About',
                  subtitle: 'Funds · Version $appVersion',
                  divider: false,
                  onTap: () => _open(context, const AboutSettingsScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 14, color: C.muted),
              const SizedBox(width: 6),
              Text('All your data stays on this phone',
                  style: ts(12, weight: FontWeight.w600, color: C.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.attention = false,
    this.divider = true,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool attention;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle${attention ? '. Backup recommended' : ''}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: divider ? const Border(bottom: BorderSide(color: C.line)) : null,
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                IconTile(icon, color: color, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: ts(16, weight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(13, color: C.muted)),
                    ],
                  ),
                ),
                if (attention) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: C.yellow, shape: BoxShape.circle),
                  ),
                ],
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: C.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared layout for the sub-pages: back arrow, title, scrolling content.
class _SubPage extends StatelessWidget {
  const _SubPage({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (trailing != null)
            Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: trailing)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: children,
      ),
    );
  }
}

// --------------------------------------------------------------- security

class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return _SubPage(
      title: 'Security',
      children: [
        CardBox(
          child: Column(
            children: [
              _SwitchRow(
                icon: Icons.lock_outline_rounded,
                color: C.accent,
                title: 'App lock',
                subtitle: 'Ask for fingerprint or phone PIN when Funds opens',
                value: s.appLock,
                divider: true,
                onChanged: (v) => _setAppLock(context, v),
              ),
              _SwitchRow(
                icon: Icons.visibility_off_outlined,
                color: C.blue,
                title: 'Hide amounts',
                subtitle: 'Show ₹•••• until you tap the eye on Home',
                value: s.hideAmountsByDefault,
                divider: true,
                onChanged: (v) async {
                  await s.setFlag('hide_amounts', v);
                  if (s.amountsHidden != v) s.toggleHidden();
                },
              ),
              Opacity(
                opacity: s.appLock ? 1 : 0.45,
                child: ListRow(
                  leading: const IconTile(Icons.schedule_rounded, color: C.muted),
                  title: 'Lock again after',
                  subtitle: s.appLock
                      ? 'When Funds is in the background'
                      : 'Turn on app lock to use this',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_lockLabel(s.lockAfterSeconds),
                          style: ts(14, weight: FontWeight.w700, color: C.accent)),
                      const Icon(Icons.chevron_right_rounded, color: C.muted, size: 20),
                    ],
                  ),
                  onTap: s.appLock ? () => _pickLockAfter(context) : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Funds uses your phone's own fingerprint, face or PIN. Nothing about it is stored in the app.",
          style: ts(13, color: C.muted, height: 1.5),
        ),
      ],
    );
  }

  Future<void> _setAppLock(BuildContext context, bool on) async {
    final s = context.read<AppState>();
    if (on) {
      // Check the phone can actually unlock before turning it on.
      final error = await authenticate('Confirm to turn on app lock');
      if (error != null) {
        if (context.mounted) toast(context, error);
        return;
      }
    }
    await s.setFlag('app_lock', on);
    if (context.mounted) toast(context, on ? 'App lock is on' : 'App lock is off');
  }

  void _pickLockAfter(BuildContext context) {
    final s = context.read<AppState>();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lock again after', style: ts(20, weight: FontWeight.w800)),
              const SizedBox(height: 12),
              CardBox(
                child: Column(
                  children: [
                    for (var i = 0; i < _lockOptions.length; i++)
                      ListRow(
                        divider: i < _lockOptions.length - 1,
                        leading: const SizedBox.shrink(),
                        title: _lockOptions[i].$2,
                        trailing: s.lockAfterSeconds == _lockOptions[i].$1
                            ? const Icon(Icons.check_rounded, color: C.accent)
                            : null,
                        onTap: () {
                          s.setSetting('lock_after', '${_lockOptions[i].$1}');
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- features

class FeaturesSettingsScreen extends StatelessWidget {
  const FeaturesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final count = _features.where((f) => s.feature(f.$1)).length;
    return _SubPage(
      title: 'Features',
      trailing: Text('$count of ${_features.length} on',
          style: ts(13, weight: FontWeight.w700, color: C.muted)),
      children: [
        Text('Turn on what you use. Turning a feature off hides it; its data is kept.',
            style: ts(13, color: C.muted, height: 1.45)),
        const SizedBox(height: 12),
        CardBox(
          child: Column(
            children: [
              for (var i = 0; i < _features.length; i++)
                _SwitchRow(
                  icon: _features[i].$2,
                  color: _features[i].$3,
                  title: _features[i].$4,
                  subtitle: _features[i].$5,
                  value: s.feature(_features[i].$1),
                  divider: i < _features.length - 1,
                  onChanged: (v) => s.setFeature(_features[i].$1, v),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- backup

class BackupSettingsScreen extends StatelessWidget {
  const BackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final last = s.lastBackup;
    final due = _backupDue(s);

    return _SubPage(
      title: 'Backup & restore',
      children: [
        Text(
          'Everything stays on this phone. Before switching phones, export a backup and import it on the new one. Keep the backup file private; it is not encrypted.',
          style: ts(13, color: C.muted, height: 1.5),
        ),
        const SizedBox(height: 12),
        CardBox(
          child: Column(
            children: [
              ListRow(
                divider: true,
                leading: const IconTile(Icons.upload_file_rounded, color: C.accent),
                title: 'Export backup',
                subtitle: 'Save a file to Drive, WhatsApp or Files',
                trailing: const Icon(Icons.chevron_right_rounded, color: C.muted),
                onTap: () => _export(context),
              ),
              ListRow(
                leading: const IconTile(Icons.download_rounded, color: C.blue),
                title: 'Import backup',
                subtitle: 'Replace the data on this phone with a backup file',
                trailing: const Icon(Icons.chevron_right_rounded, color: C.muted),
                onTap: () => _import(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (due) ...[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: C.yellow, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                last == null
                    ? 'No backup yet. Export one so you never lose your data.'
                    : due
                        ? 'Last backup: ${friendlyDay(last)}. It has been over a month; export a new one.'
                        : 'Last backup: ${friendlyDay(last)}',
                style: ts(13,
                    weight: FontWeight.w600, color: due ? C.yellow : C.muted, height: 1.4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context) async {
    final s = context.read<AppState>();
    try {
      final json = await s.exportJson();
      final dir = await getTemporaryDirectory();
      // Remove older backup copies left in the app's cache.
      for (final f in dir.listSync().whereType<File>()) {
        if (p.basename(f.path).startsWith('funds-backup-')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
      final name = 'funds-backup-${dayKey(DateTime.now())}.json';
      final file = File(p.join(dir.path, name));
      await file.writeAsString(json, flush: true);

      s.externalActivity = true;
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json', name: name)],
        subject: 'Funds backup',
        title: 'Save Funds backup',
      ));
      if (result.status != ShareResultStatus.dismissed) {
        await s.markBackedUp();
        if (context.mounted) toast(context, 'Backup exported');
      }
    } catch (e) {
      if (context.mounted) toast(context, 'Could not export the backup.');
    } finally {
      s.externalActivity = false;
    }
  }

  Future<void> _import(BuildContext context) async {
    final s = context.read<AppState>();
    PlatformFile? picked;
    try {
      s.externalActivity = true;
      picked = await FilePicker.pickFile(
        dialogTitle: 'Choose a Funds backup',
        type: FileType.any,
      );
    } catch (_) {
      if (context.mounted) toast(context, 'Could not open the file.');
      return;
    } finally {
      s.externalActivity = false;
    }
    if (picked == null || picked.path == null) return;

    Map<String, List<Map<String, Object?>>> data;
    try {
      final text = await File(picked.path!).readAsString();
      data = AppState.parseBackup(text);
    } on FormatException catch (e) {
      if (context.mounted) toast(context, e.message);
      return;
    } catch (_) {
      if (context.mounted) toast(context, 'Could not read the file.');
      return;
    }
    if (!context.mounted) return;

    final accounts = data['accounts']?.length ?? 0;
    final entries = data['entries']?.length ?? 0;
    final ok = await confirm(
      context,
      title: 'Replace data on this phone?',
      message:
          'The backup has $accounts ${accounts == 1 ? 'account' : 'accounts'} and $entries ${entries == 1 ? 'entry' : 'entries'}. Everything currently on this phone will be replaced. This cannot be undone.',
      confirmLabel: 'Replace',
    );
    if (!ok) return;
    try {
      await s.importBackup(data);
      if (context.mounted) toast(context, 'Backup restored');
    } catch (_) {
      if (context.mounted) toast(context, 'Could not restore the backup. Your data was not changed.');
    }
  }
}

// ----------------------------------------------------------------- about

class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _SubPage(
      title: 'About',
      children: [
        const SizedBox(height: 24),
        const Center(child: FundsLogo(size: 80)),
        const SizedBox(height: 16),
        Center(child: Text('Funds', style: ts(26, weight: FontWeight.w800))),
        const SizedBox(height: 4),
        Center(
          child: Text('Version $appVersion',
              style: ts(14, weight: FontWeight.w600, color: C.muted)),
        ),
        const SizedBox(height: 28),
        CardBox(
          child: Column(
            children: const [
              ListRow(
                divider: true,
                leading: IconTile(Icons.phone_android_rounded, color: C.accent),
                title: 'Stays on your phone',
                subtitle: 'All your data is saved only on this phone. Funds never uses the internet.',
              ),
              ListRow(
                divider: true,
                leading: IconTile(Icons.cloud_off_rounded, color: C.blue),
                title: 'No account, no cloud',
                subtitle: 'There is no sign-in and nothing is uploaded. Android cloud backup is off for Funds.',
              ),
              ListRow(
                leading: IconTile(Icons.sync_rounded, color: C.teal),
                title: 'You control backups',
                subtitle: 'Move to a new phone with Export and Import in Backup & restore.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- shared

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.divider = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ListRow(
        divider: divider,
        leading: IconTile(icon, color: value ? color : C.faint),
        title: title,
        subtitle: subtitle,
        onTap: () => onChanged(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}
