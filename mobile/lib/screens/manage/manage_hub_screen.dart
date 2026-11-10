import 'package:flutter/material.dart';

import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import 'customer_service_screen.dart';
import 'hiring_screen.dart';
import 'payroll_screen.dart';
import 'reservations_screen.dart';
import 'suppliers_screen.dart';
import 'user_accounts_screen.dart';

/// The "Manage" tab: entry point to the management modules.
/// Modules a role cannot use are hidden; all of them need the cloud connection.
class ManageHubScreen extends StatelessWidget {
  const ManageHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final emp = appState.currentEmployee;
        final isAdmin = emp?.isAdmin == true;
        final online = appState.isBackendOnline;

        final modules = <_Module>[
          _Module('Reservations', 'Book tables, seat guests, record no-shows', 'FR-7 · UC-03',
              Icons.event_seat_rounded, AppTheme.statusBlue, () => const ReservationsScreen()),
          _Module('Customer Service', 'Log guest issues and track them to resolution', 'FR-11 · UC-12',
              Icons.support_agent_rounded, AppTheme.statusYellow, () => const CustomerServiceScreen()),
          _Module('Suppliers', 'Supplier contacts and product categories', 'FR-1 · UC-05',
              Icons.local_shipping_rounded, AppTheme.statusGreen, () => const SuppliersScreen()),
          if (isAdmin)
            _Module('User Accounts', 'Add staff, change roles, reset PINs, deactivate', 'FR-2 · UC-08',
                Icons.manage_accounts_rounded, AppTheme.primary, () => const UserAccountsScreen()),
          if (isAdmin)
            _Module('Payroll', 'Review shifts, adjust hours and rates, mark paid', 'FR-4 · UC-09',
                Icons.payments_rounded, AppTheme.statusGreen, () => const PayrollScreen()),
          if (isAdmin)
            _Module('Hiring', 'Applicants, interview stages, hiring and onboarding', 'FR-12 · UC-10',
                Icons.badge_rounded, AppTheme.primaryLight, () => const HiringScreen()),
        ];

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: AppTheme.surface,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.dashboard_customize_rounded, color: AppTheme.primaryLight, size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RESTAURANT ADMINISTRATION',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppTheme.primary),
                    ),
                    const Text('Manage', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (!online)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.statusYellow.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.statusYellow.withOpacity(0.7)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_rounded, color: AppTheme.statusYellow, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'These modules need the ServeSync cloud connection. Sign in while online.',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900 ? 3 : (constraints.maxWidth >= 560 ? 2 : 1);
                  const gap = 12.0;
                  final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final m in modules) SizedBox(width: width, child: _ModuleTile(module: m, enabled: online)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                isAdmin
                    ? 'Signed in as Administrator: all modules are available.'
                    : 'User Accounts, Payroll and Hiring are available to Administrators only.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Module {
  final String title;
  final String description;
  final String reference;
  final IconData icon;
  final Color color;
  final Widget Function() screen;
  const _Module(this.title, this.description, this.reference, this.icon, this.color, this.screen);
}

class _ModuleTile extends StatelessWidget {
  final _Module module;
  final bool enabled;
  const _ModuleTile({required this.module, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled
              ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => module.screen()))
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: module.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(module.icon, color: module.color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(module.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(module.description, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.25)),
                      const SizedBox(height: 4),
                      Text(module.reference, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
