import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../services/backup_service.dart';
import '../services/reminders.dart';
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
                  icon: Icons.notifications_none_rounded,
                  color: C.orange,
                  title: 'Reminders',
                  subtitle: s.remindersOn
                      ? 'On · ${_reminderKinds.where((k) => s.reminderOn(k.$1)).length} kinds · ${_timeLabel(s.reminderTime)}'
                      : 'Off',
                  onTap: () => _open(context, const RemindersSettingsScreen()),
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
                  subtitle: [
                    if (s.autoBackup) 'Automatic, ${s.autoBackupFrequency}',
                    last == null ? 'Last backup: never' : 'Last: ${friendlyDay(last)}',
                  ].join(' · '),
                  attention: due || (s.autoBackup && s.autoBackupError != null),
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

String _timeLabel(int minutes) =>
    DateFormat('h:mm a').format(DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60));

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  late Future<(bool, int)> _info = _loadInfo();
  bool _busy = false;

  /// (automatic backup possible on this phone, copies in Downloads/Funds)
  Future<(bool, int)> _loadInfo() async {
    final ok = await Downloads.supported();
    var n = 0;
    if (ok) {
      try {
        n = (await Downloads.list()).length;
      } catch (_) {}
    }
    return (ok, n);
  }

  void _refresh() => setState(() => _info = _loadInfo());

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return FutureBuilder<(bool, int)>(
      future: _info,
      builder: (context, snap) {
        final supported = snap.data?.$1 ?? true;
        final copies = snap.data?.$2 ?? 0;
        return _SubPage(
          title: 'Backup & restore',
          children: [
            _status(s, copies),
            const SizedBox(height: 24),
            const SectionLabel('Automatic backup'),
            if (!supported)
              CardBox(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Automatic backup needs Android 10 or newer. Use "Share a backup" below instead.',
                  style: ts(13, color: C.muted, height: 1.45),
                ),
              )
            else
              CardBox(
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: Icons.autorenew_rounded,
                      color: C.income,
                      title: 'Back up automatically',
                      subtitle: 'When you open Funds and a backup is due',
                      value: s.autoBackup,
                      divider: s.autoBackup,
                      onChanged: (v) async {
                        await s.setFlag('auto_backup', v);
                        if (v) {
                          await BackupService.autoBackupIfDue(s);
                          _refresh();
                        }
                      },
                    ),
                    if (s.autoBackup) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: C.line))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('How often',
                                style: ts(13, weight: FontWeight.w700, color: C.muted)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final (key, label) in const [
                                  ('daily', 'Every day'),
                                  ('weekly', 'Every week'),
                                  ('monthly', 'Every month'),
                                ])
                                  FilterPill(label,
                                      selected: s.autoBackupFrequency == key,
                                      onTap: () => s.setSetting('auto_backup_freq', key)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      ListRow(
                        divider: true,
                        leading: const IconTile(Icons.folder_outlined, color: C.yellow),
                        title: 'Saved in',
                        subtitle: 'Downloads/Funds. Stays even if the app is uninstalled.',
                      ),
                      ListRow(
                        leading: const IconTile(Icons.layers_outlined, color: C.muted),
                        title: 'Copies to keep',
                        subtitle: 'Older copies are deleted',
                        trailing: Text('Last ${BackupService.keepCopies}',
                            style: ts(14, weight: FontWeight.w700, color: C.accent)),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 24),
            const SectionLabel('Protection'),
            CardBox(
              child: Column(
                children: [
                  _SwitchRow(
                    icon: Icons.lock_outline_rounded,
                    color: C.yellow,
                    title: 'Password-protect backups',
                    subtitle: s.backupPassword != null
                        ? 'On: backups need your password to open'
                        : 'Off: anyone with the file can read it',
                    value: s.backupPassword != null,
                    divider: s.backupPassword != null,
                    onChanged: (v) => v ? _setPassword(context) : _removePassword(context),
                  ),
                  if (s.backupPassword != null) ...[
                    ListRow(
                      divider: true,
                      leading: const IconTile(Icons.key_outlined, color: C.muted),
                      title: 'Change password',
                      trailing: const Icon(Icons.chevron_right_rounded, color: C.muted),
                      onTap: () => _setPassword(context),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      color: const Color(0xFF1A1408),
                      child: Text(
                        'If you forget this password, the backups cannot be opened by anyone, including you.',
                        style: ts(12, weight: FontWeight.w600, color: C.yellow, height: 1.45),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('By hand'),
            CardBox(
              child: Column(
                children: [
                  if (supported)
                    ListRow(
                      divider: true,
                      leading: const IconTile(Icons.save_alt_rounded, color: C.accent),
                      title: 'Back up now',
                      subtitle: 'Save a copy to Downloads/Funds',
                      trailing: _busy
                          ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.chevron_right_rounded, color: C.muted),
                      onTap: _busy ? null : () => _backupNow(context),
                    ),
                  ListRow(
                    divider: true,
                    leading: const IconTile(Icons.share_outlined, color: C.income),
                    title: 'Share a backup',
                    subtitle: 'Send to Google Drive, WhatsApp or email',
                    trailing: const Icon(Icons.chevron_right_rounded, color: C.muted),
                    onTap: () => _share(context),
                  ),
                  ListRow(
                    leading: const IconTile(Icons.download_rounded, color: C.blue),
                    title: 'Import backup',
                    subtitle: 'Asks for the password if the file has one',
                    trailing: const Icon(Icons.chevron_right_rounded, color: C.muted),
                    onTap: () => _import(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tip: if Google Drive or another app syncs your Downloads folder, your backups are also safe if the phone is lost.',
              style: ts(12, color: C.muted, height: 1.5),
            ),
          ],
        );
      },
    );
  }

  Widget _status(AppState s, int copies) {
    final last = s.lastAutoBackup ?? s.lastBackup;
    final err = s.autoBackup ? s.autoBackupError : null;
    final fresh = last != null &&
        today().difference(dateOnly(last)).inDays <= (s.autoBackupDays > 7 ? s.autoBackupDays : 7);

    String title;
    String body;
    Color bg;
    Color border;
    Color fg;
    IconData icon;
    if (err != null) {
      title = 'Last automatic backup failed';
      body = err;
      bg = const Color(0xFF2A0E12);
      border = const Color(0xFF5A1F26);
      fg = C.expense;
      icon = Icons.error_outline_rounded;
    } else if (fresh) {
      title = 'Your data is backed up';
      body = 'Last backup: ${friendlyDay(last).toLowerCase() == 'today' ? 'today' : friendlyDay(last)}, '
          '${DateFormat('h:mm a').format(last)}'
          '${copies > 0 ? '\n$copies ${copies == 1 ? 'copy' : 'copies'} in Downloads/Funds' : ''}';
      bg = const Color(0xFF0E2A1A);
      border = const Color(0xFF1F5A36);
      fg = C.income;
      icon = Icons.verified_user_outlined;
    } else {
      title = 'Back up your data';
      body = (last == null ? 'No backup yet.' : 'Last backup: ${friendlyDay(last)}.') +
          (s.autoBackup
              ? ' A new one is made the next time you open Funds.'
              : ' Turn on automatic backup below.');
      bg = const Color(0xFF1A1408);
      border = const Color(0xFF4A3A12);
      fg = C.yellow;
      icon = Icons.warning_amber_rounded;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ts(15, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(body, style: ts(13, color: C.muted, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _backupNow(BuildContext context) async {
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await BackupService.saveToDownloads(s);
      if (context.mounted) toast(context, 'Backup saved to Downloads/Funds');
    } catch (_) {
      if (context.mounted) toast(context, 'Could not save the backup.');
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  Future<void> _setPassword(BuildContext context) async {
    final s = context.read<AppState>();
    final a = TextEditingController();
    final b = TextEditingController();
    String? error;
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Backup password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Needed to open your backups. It is kept only on this phone.',
                  style: ts(13, color: C.muted, height: 1.45)),
              const SizedBox(height: 14),
              TextField(
                controller: a,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: b,
                obscureText: true,
                decoration: InputDecoration(labelText: 'Type it again', errorText: error),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (a.text.length < 4) {
                  setSt(() => error = 'Use at least 4 characters');
                } else if (a.text != b.text) {
                  setSt(() => error = 'The two passwords are different');
                } else {
                  Navigator.pop(ctx, a.text);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (pw == null) return;
    await s.setBackupPassword(pw);
    if (context.mounted) toast(context, 'New backups are password-protected');
  }

  Future<void> _removePassword(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'Turn off the password?',
      message: 'New backups can then be read by anyone who has the file. Older backups still need the old password.',
      confirmLabel: 'Turn off',
    );
    if (ok && context.mounted) await context.read<AppState>().setBackupPassword(null);
  }

  Future<void> _share(BuildContext context) async {
    final s = context.read<AppState>();
    try {
      final text = await BackupService.buildText(s);
      final dir = await getTemporaryDirectory();
      for (final f in dir.listSync().whereType<File>()) {
        if (p.basename(f.path).startsWith(Downloads.prefix)) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
      final name = BackupService.fileName(DateTime.now());
      final file = File(p.join(dir.path, name));
      await file.writeAsString(text, flush: true);

      s.externalActivity = true;
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json', name: name)],
        subject: 'Funds backup',
        title: 'Save Funds backup',
      ));
      if (result.status != ShareResultStatus.dismissed) {
        await s.markBackedUp();
        if (context.mounted) toast(context, 'Backup shared');
      }
    } catch (_) {
      if (context.mounted) toast(context, 'Could not share the backup.');
    } finally {
      s.externalActivity = false;
    }
  }

  Future<String?> _askPassword(BuildContext context) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('This backup has a password'),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Open')),
        ],
      ),
    );
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
    if (picked == null || picked.path == null || !context.mounted) return;

    Map<String, List<Map<String, Object?>>> data;
    try {
      final text = await File(picked.path!).readAsString();
      if (!context.mounted) return;
      data = await BackupService.read(text, () => _askPassword(context));
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

// ------------------------------------------------------------- reminders

const _reminderKinds = [
  ('bills', Icons.receipt_long_outlined, C.blue, 'Bills, SIPs & EMIs', '1 day before they are taken'),
  ('salary', Icons.work_outline_rounded, C.accent, 'Salary credited', 'On the day it is added'),
  ('card', Icons.credit_card_rounded, C.pink, 'Credit card bill due', '3 days before the due date'),
  ('lend', Icons.handshake_outlined, C.teal, 'Lend & borrow due dates', '1 day before and on the day'),
  ('fd', Icons.lock_outline_rounded, C.yellow, 'FD maturity', '7 days before and on the day'),
  ('budget', Icons.donut_large_rounded, C.orange, 'Budget almost used',
      'When 80% and 100% of the monthly budget is spent'),
  ('daily', Icons.add_circle_outline_rounded, C.muted, "Add today's spending",
      'Every evening, if nothing was added'),
];

class RemindersSettingsScreen extends StatelessWidget {
  const RemindersSettingsScreen({super.key});

  Future<void> _pickTime(BuildContext context, String key, int current) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (t != null && context.mounted) {
      await context.read<AppState>().setSetting(key, '${t.hour * 60 + t.minute}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final on = s.remindersOn;
    return _SubPage(
      title: 'Reminders',
      children: [
        CardBox(
          child: _SwitchRow(
            icon: Icons.notifications_none_rounded,
            color: C.accent,
            title: 'Allow reminders',
            subtitle: 'Made on this phone. No internet needed.',
            value: on,
            onChanged: (v) async {
              if (v) await Reminders.requestPermission();
              await s.setFlag('reminders_on', v);
            },
          ),
        ),
        Opacity(
          opacity: on ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !on,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const SectionLabel('Remind me about'),
                CardBox(
                  child: Column(
                    children: [
                      for (var i = 0; i < _reminderKinds.length; i++)
                        _SwitchRow(
                          icon: _reminderKinds[i].$2,
                          color: _reminderKinds[i].$3,
                          title: _reminderKinds[i].$4,
                          subtitle: _reminderKinds[i].$5,
                          value: s.reminderOn(_reminderKinds[i].$1),
                          divider: i < _reminderKinds.length - 1,
                          onChanged: (v) => s.setFlag('rem_${_reminderKinds[i].$1}', v),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionLabel('Times'),
                CardBox(
                  child: Column(
                    children: [
                      ListRow(
                        divider: true,
                        leading: const IconTile(Icons.wb_sunny_outlined, color: C.yellow),
                        title: 'Bills, dues and FDs',
                        subtitle: 'Time for date reminders',
                        trailing: Text(_timeLabel(s.reminderTime),
                            style: ts(15, weight: FontWeight.w800, color: C.accent)),
                        onTap: () => _pickTime(context, 'rem_time', s.reminderTime),
                      ),
                      ListRow(
                        leading: const IconTile(Icons.nightlight_outlined, color: C.blue),
                        title: 'Daily spending reminder',
                        subtitle: 'Skipped on days you already added entries',
                        trailing: Text(_timeLabel(s.dailyReminderTime),
                            style: ts(15, weight: FontWeight.w800, color: C.accent)),
                        onTap: () => _pickTime(context, 'rem_daily_time', s.dailyReminderTime),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionLabel('Privacy'),
                CardBox(
                  child: _SwitchRow(
                    icon: Icons.visibility_outlined,
                    color: C.muted,
                    title: 'Show amounts in reminders',
                    subtitle: s.reminderAmounts
                        ? 'On: "Netflix (₹649) is due tomorrow"'
                        : 'Off: "Netflix is due tomorrow". Safer on the lock screen.',
                    value: s.reminderAmounts,
                    onChanged: (v) => s.setFlag('rem_amounts', v),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (on) ...[
          const SizedBox(height: 24),
          const SectionLabel('Timing'),
          const CardBox(child: _ExactTimesRow()),
        ],
        const SizedBox(height: 14),
        Text(
          "If reminders don't appear, allow notifications for Funds in your phone's settings.",
          style: ts(12, color: C.muted, height: 1.5),
        ),
      ],
    );
  }
}

/// Shows whether reminders come at the exact minute, with a button to allow
/// it. Refreshes when you come back from Android's settings.
class _ExactTimesRow extends StatefulWidget {
  const _ExactTimesRow();

  @override
  State<_ExactTimesRow> createState() => _ExactTimesRowState();
}

class _ExactTimesRowState extends State<_ExactTimesRow> with WidgetsBindingObserver {
  late Future<bool> _exact = Reminders.canExact();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _exact = Reminders.canExact());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _exact,
      builder: (context, snap) {
        final exact = snap.data ?? false;
        return ListRow(
          leading: IconTile(exact ? Icons.alarm_on_rounded : Icons.alarm_rounded,
              color: exact ? C.income : C.yellow),
          title: exact ? 'Exact times allowed' : 'Allow exact times',
          subtitle: exact
              ? 'Reminders come right on time.'
              : 'Without this, Android may show reminders up to 1 hour late.',
          trailing: exact
              ? const Icon(Icons.check_circle_rounded, color: C.income)
              : TintButton('Allow', onPressed: () async {
                  await Reminders.requestExact();
                  if (mounted) setState(() => _exact = Reminders.canExact());
                }),
        );
      },
    );
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
