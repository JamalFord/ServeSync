import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import 'manage_widgets.dart';

/// FR-2 / UC-08: user account administration (Administrator only).
/// PINs are never shown; they are only entered when creating or resetting.
class UserAccountsScreen extends StatefulWidget {
  /// API client to use; defaults to the signed-in session's client. Tests pass a mock.
  final ApiClient? api;

  const UserAccountsScreen({super.key, this.api});

  @override
  State<UserAccountsScreen> createState() => _UserAccountsScreenState();
}

class _UserAccountsScreenState extends State<UserAccountsScreen> with ManageLoader {
  static const _roles = ['FOH Staff', 'Manager', 'Administrator'];

  late final ApiClient _api = widget.api ?? AppState.instance.api;
  List<Map<String, dynamic>> _users = [];

  @override
  Future<void> fetch() async {
    _users = await _api.users();
  }

  bool _isMe(Map<String, dynamic> u) => AppState.instance.currentEmployee?.id == 'db_${intOf(u['user_id'])}';

  Color _roleColor(String role) {
    switch (role) {
      case 'Administrator':
        return AppTheme.primary;
      case 'Manager':
        return AppTheme.statusYellow;
      default:
        return AppTheme.statusGreen;
    }
  }

  String? _checkPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin) ? null : 'The PIN must be exactly four digits.';

  String? _checkRate(String text) {
    final rate = double.tryParse(text.trim());
    return (rate == null || rate < 0 || rate > 500) ? 'Hourly rate must be a number between 0 and 500.' : null;
  }

  Future<void> _addUser() async {
    final name = TextEditingController();
    final pin = TextEditingController();
    final rate = TextEditingController(text: '16.50');
    String role = _roles.first;
    final saved = await showFormDialog(
      context,
      title: 'Add user account',
      subtitle: 'The employee signs in with the PIN you set here.',
      submitLabel: 'Create account',
      fields: (setDialog) => [
        FormTextField(label: 'Full name', controller: name, maxLength: 100),
        FormDropdown<String>(
          label: 'Role',
          value: role,
          options: _roles,
          labelOf: (r) => r,
          onChanged: (v) => setDialog(() => role = v ?? role),
        ),
        FormTextField.pin(label: 'Access PIN', controller: pin),
        FormTextField.decimal(label: 'Hourly rate (\$)', controller: rate),
      ],
      onSubmit: () async {
        if (name.text.trim().isEmpty) return 'Full name is required.';
        final problem = _checkPin(pin.text) ?? _checkRate(rate.text);
        if (problem != null) return problem;
        return guard(() => _api.createUser({
              'full_name': name.text.trim(),
              'role': role,
              'pin': pin.text,
              'hourly_rate': double.parse(rate.text.trim()),
            }));
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, 'Account created for ${name.text.trim()}.');
    await reload(showSpinner: false);
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final name = TextEditingController(text: strOf(user['full_name']));
    final rate = TextEditingController(text: numOf(user['hourly_rate']).toStringAsFixed(2));
    String role = strOf(user['role'], _roles.first);
    final saved = await showFormDialog(
      context,
      title: 'Edit ${strOf(user['full_name'], 'account')}',
      subtitle: 'A role change takes effect immediately.',
      fields: (setDialog) => [
        FormTextField(label: 'Full name', controller: name, maxLength: 100),
        FormDropdown<String>(
          label: 'Role',
          value: role,
          options: _roles,
          labelOf: (r) => r,
          onChanged: (v) => setDialog(() => role = v ?? role),
        ),
        FormTextField.decimal(label: 'Hourly rate (\$)', controller: rate),
      ],
      onSubmit: () async {
        if (name.text.trim().isEmpty) return 'Full name is required.';
        final problem = _checkRate(rate.text);
        if (problem != null) return problem;
        return guard(() => _api.updateUser(intOf(user['user_id']), {
              'full_name': name.text.trim(),
              'role': role,
              'hourly_rate': double.parse(rate.text.trim()),
            }));
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, 'Account updated.');
    await reload(showSpinner: false);
  }

  Future<void> _resetPin(Map<String, dynamic> user) async {
    final pin = TextEditingController();
    final again = TextEditingController();
    final saved = await showFormDialog(
      context,
      title: 'Reset PIN',
      subtitle: _isMe(user)
          ? 'You will be signed out and must sign in again with the new PIN.'
          : '${strOf(user['full_name'])} will be signed out and must use the new PIN.',
      submitLabel: 'Reset PIN',
      fields: (_) => [
        FormTextField.pin(label: 'New PIN', controller: pin),
        FormTextField.pin(label: 'Repeat new PIN', controller: again),
      ],
      onSubmit: () async {
        final problem = _checkPin(pin.text);
        if (problem != null) return problem;
        if (pin.text != again.text) return 'The two PIN entries do not match.';
        return guard(() => _api.updateUser(intOf(user['user_id']), {'pin': pin.text}));
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, 'PIN reset for ${strOf(user['full_name'])}.');
    await reload(showSpinner: false);
  }

  Future<void> _setActive(Map<String, dynamic> user, bool active) async {
    final name = strOf(user['full_name'], 'this user');
    if (!active) {
      final ok = await confirmAction(
        context,
        title: 'Deactivate account?',
        message: '$name will be signed out and will not be able to sign in. Shift and payroll history is kept. '
            'The account can be reactivated later.',
        confirmLabel: 'Deactivate',
        danger: true,
      );
      if (!ok) return;
    }
    await act(
      () => _api.updateUser(intOf(user['user_id']), {'account_status': active ? 'Active' : 'Inactive'}),
      success: active ? '$name reactivated.' : '$name deactivated.',
    );
  }

  Future<void> _endSession(Map<String, dynamic> user) async {
    final name = strOf(user['full_name'], 'this user');
    final ok = await confirmAction(
      context,
      title: 'End session?',
      message: '$name will be signed out on their device. An open shift stays open.',
      confirmLabel: 'End session',
    );
    if (!ok) return;
    await act(() => _api.endUserSession(intOf(user['user_id'])), success: 'Session ended for $name.');
  }

  @override
  Widget build(BuildContext context) {
    final active = _users.where((u) => u['account_status'] == 'Active').length;
    return ManageScaffold(
      eyebrow: 'FR-2 · UC-08',
      title: 'User Accounts',
      icon: Icons.manage_accounts_rounded,
      loading: loading,
      error: loadError,
      onRefresh: reload,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add user', style: TextStyle(fontWeight: FontWeight.w800)),
        onPressed: _addUser,
      ),
      builder: () => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          SectionHeading('${_users.length} accounts · $active active'),
          for (final u in _users) _userCard(u),
        ],
      ),
    );
  }

  Widget _userCard(Map<String, dynamic> user) {
    final name = strOf(user['full_name'], 'Employee');
    final role = strOf(user['role'], 'FOH Staff');
    final isActive = user['account_status'] == 'Active';
    final me = _isMe(user);
    return ManageCard(
      child: Opacity(
        opacity: isActive ? 1.0 : 0.65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.surfaceElevated,
                  child: Text(name.substring(0, 1).toUpperCase(),
                      style: TextStyle(fontWeight: FontWeight.w800, color: _roleColor(role))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me ? '$name (you)' : name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('${money(user['hourly_rate'])} / hour',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusChip(role, _roleColor(role)),
                    const SizedBox(height: 4),
                    StatusChip(isActive ? 'Active' : 'Inactive', isActive ? AppTheme.statusGreen : AppTheme.textMuted),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                CardAction('Edit', Icons.edit_outlined, () => _editUser(user)),
                CardAction('Reset PIN', Icons.password_rounded, () => _resetPin(user)),
                if (isActive && !me)
                  CardAction('End session', Icons.logout_rounded, () => _endSession(user), color: AppTheme.statusYellow),
                if (!me)
                  isActive
                      ? CardAction('Deactivate', Icons.block_rounded, () => _setActive(user, false), color: AppTheme.statusRed)
                      : CardAction('Reactivate', Icons.check_circle_outline, () => _setActive(user, true),
                          color: AppTheme.statusGreen),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
