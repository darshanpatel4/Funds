import 'package:flutter/material.dart';

import '../theme.dart';
import 'activity_screen.dart';
import 'entry_form_screen.dart';
import 'home_screen.dart';
import 'plans_screen.dart';
import 'settings_screen.dart';

/// Which bottom tab is showing. Screens use this to jump between tabs
/// (for example "See all" on Home opens Accounts).
final currentTab = ValueNotifier<int>(0);

class Tabs {
  Tabs._();
  static const home = 0;
  static const activity = 1;
  static const plans = 2;
  static const settings = 3;
}

class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: currentTab,
      builder: (context, tab, _) {
        return PopScope(
          // Back on another tab goes to Home first.
          canPop: tab == Tabs.home,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) currentTab.value = Tabs.home;
          },
          child: Scaffold(
            body: IndexedStack(
              index: tab,
              children: const [
                HomeScreen(),
                ActivityScreen(),
                PlansScreen(),
                SettingsScreen(),
              ],
            ),
            bottomNavigationBar: _BottomBar(tab: tab),
          ),
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.tab});

  final int tab;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: C.bg,
        border: Border(top: BorderSide(color: C.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                  selected: tab == Tabs.home,
                  onTap: () => currentTab.value = Tabs.home),
              _NavItem(
                  icon: Icons.format_list_bulleted_rounded,
                  activeIcon: Icons.format_list_bulleted_rounded,
                  label: 'Activity',
                  selected: tab == Tabs.activity,
                  onTap: () => currentTab.value = Tabs.activity),
              Expanded(
                child: Center(
                  child: Semantics(
                    button: true,
                    label: 'Add entry',
                    child: Material(
                      color: C.accent,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => openEntryForm(context),
                        child: const SizedBox(
                          width: 56,
                          height: 56,
                          child: Icon(Icons.add_rounded, color: Colors.white, size: 30),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _NavItem(
                  icon: Icons.event_repeat_outlined,
                  activeIcon: Icons.event_repeat_rounded,
                  label: 'Plans',
                  selected: tab == Tabs.plans,
                  onTap: () => currentTab.value = Tabs.plans),
              _NavItem(
                  icon: Icons.tune_rounded,
                  activeIcon: Icons.tune_rounded,
                  label: 'Settings',
                  selected: tab == Tabs.settings,
                  onTap: () => currentTab.value = Tabs.settings),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? C.accent : C.muted;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 40,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: selected ? C.accentTint : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(selected ? activeIcon : icon, color: color, size: 24),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: ts(11,
                      weight: selected ? FontWeight.w800 : FontWeight.w700, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
