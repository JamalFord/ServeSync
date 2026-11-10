import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import 'manage_widgets.dart';

/// FR-4 / UC-09: review and adjust employee payroll (Administrator only).
/// Every adjustment needs a reason, which is stored with the shift record.
class PayrollScreen extends StatefulWidget {
  /// API client to use; defaults to the signed-in session's client. Tests pass a mock.
  final ApiClient? api;

  const PayrollScreen({super.key, this.api});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> with ManageLoader {
  static const _filters = ['All', 'Pending', 'Pending Correction', 'Paid'];

  late final ApiClient _api = widget.api ?? AppState.instance.api;
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _employees = [];
  Map<int, Map<String, dynamic>> _summary = {};
  String _filter = 'All';

  @override
  Future<void> fetch() async {
    final data = await _api.payroll();
    List<Map<String, dynamic>> list(dynamic v) =>
        ((v as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    _records = list(data['records']);
    _employees = list(data['employees']);
    _summary = {for (final s in list(data['summary'])) intOf(s['user_id']): s};
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Paid':
        return AppTheme.statusGreen;
      case 'Pending Correction':
        return AppTheme.statusRed;
      default:
        return AppTheme.statusYellow;
    }
  }

  Future<void> _editRate(Map<String, dynamic> employee) async {
    final rate = TextEditingController(text: numOf(employee['hourly_rate']).toStringAsFixed(2));
    final name = strOf(employee['full_name'], 'Employee');
    final saved = await showFormDialog(
      context,
      title: 'Hourly rate for $name',
      subtitle: 'The new rate applies to shifts that start after this change. Past shifts keep their rate.',
      submitLabel: 'Save rate',
      fields: (_) => [FormTextField.decimal(label: 'Hourly rate (\$)', controller: rate)],
      onSubmit: () async {
        final value = double.tryParse(rate.text.trim());
        if (value == null || value < 0 || value > 500) return 'Hourly rate must be a number between 0 and 500.';
        return guard(() => _api.updateUser(intOf(employee['user_id']), {'hourly_rate': value}));
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, 'Hourly rate updated for $name.');
    await reload(showSpinner: false);
  }

  Future<void> _adjust(Map<String, dynamic> record) async {
    final hours = TextEditingController(text: numOf(record['hours_worked']).toStringAsFixed(2));
    final rate = TextEditingController(text: numOf(record['hourly_rate']).toStringAsFixed(2));
    final reason = TextEditingController();
    final saved = await showFormDialog(
      context,
      title: 'Adjust shift #${intOf(record['payroll_id'])}',
      subtitle: '${strOf(record['full_name'])} · ${formatDateTime(serverTime(record['clock_in']))}',
      submitLabel: 'Save adjustment',
      fields: (setDialog) => [
        FormTextField.decimal(label: 'Hours worked', controller: hours),
        FormTextField.decimal(label: 'Hourly rate (\$)', controller: rate),
        FormTextField(label: 'Reason (required)', controller: reason, hint: 'Forgot to clock out; manager approved', maxLength: 255),
      ],
      onSubmit: () async {
        final h = double.tryParse(hours.text.trim()), r = double.tryParse(rate.text.trim());
        if (h == null || h < 0 || h > 24) return 'Hours worked must be a number between 0 and 24.';
        if (r == null || r < 0) return 'Hourly rate must be a number of 0 or more.';
        if (reason.text.trim().length < 3) return 'A reason for the adjustment is required.';
        return guard(() => _api.adjustPayroll(intOf(record['payroll_id']), {
              'hours_worked': h,
              'hourly_rate': r,
              'reason': reason.text.trim(),
            }));
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, 'Shift #${intOf(record['payroll_id'])} adjusted.');
    await reload(showSpinner: false);
  }

  Future<void> _setStatus(Map<String, dynamic> record, String status) async {
    final paying = status == 'Paid';
    final reason = TextEditingController(text: paying ? 'Paid' : '');
    final saved = await showFormDialog(
      context,
      title: paying ? 'Mark shift as paid' : (status == 'Pending' ? 'Return shift to pending' : 'Flag shift for correction'),
      subtitle: '${strOf(record['full_name'])} · ${formatDateTime(serverTime(record['clock_in']))} · '
          '${money(record['gross_pay'])}',
      submitLabel: paying ? 'Mark paid' : (status == 'Pending' ? 'Set pending' : 'Flag'),
      fields: (_) => [
        FormTextField(
          label: paying ? 'Note (required)' : 'Reason (required)',
          controller: reason,
          hint: paying ? 'Paid in weekly run' : 'What needs to be corrected',
          maxLength: 255,
        ),
      ],
      onSubmit: () async {
        if (reason.text.trim().length < 3) return 'A reason of at least three characters is required.';
        return guard(() => _api.adjustPayroll(intOf(record['payroll_id']), {
              'payment_status': status,
              'reason': reason.text.trim(),
            }));
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, 'Shift #${intOf(record['payroll_id'])}: $status.');
    await reload(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    final closed = _records.where((r) => r['clock_out'] != null);
    final gross = closed.fold<double>(0, (sum, r) => sum + numOf(r['gross_pay']));
    final unpaid = closed.where((r) => r['payment_status'] != 'Paid').fold<double>(0, (sum, r) => sum + numOf(r['gross_pay']));
    final counts = <String, int>{'All': _records.length};
    for (final r in _records) {
      final s = strOf(r['payment_status'], 'Pending');
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final visible = _filter == 'All' ? _records : _records.where((r) => r['payment_status'] == _filter).toList();

    return ManageScaffold(
      eyebrow: 'FR-4 · UC-09',
      title: 'Payroll',
      icon: Icons.payments_rounded,
      loading: loading,
      error: loadError,
      onRefresh: reload,
      builder: () => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Row(
            children: [
              Expanded(child: _totalTile('Gross pay, all shifts', money(gross), AppTheme.textPrimary)),
              const SizedBox(width: 12),
              Expanded(child: _totalTile('Not yet paid', money(unpaid), unpaid > 0 ? AppTheme.statusYellow : AppTheme.statusGreen)),
            ],
          ),
          const SizedBox(height: 16),
          const SectionHeading('Employees'),
          for (final e in _employees) _employeeCard(e),
          const SizedBox(height: 8),
          const SectionHeading('Shift records'),
          FilterChips(options: _filters, selected: _filter, counts: counts, onSelected: (f) => setState(() => _filter = f)),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            EmptyState(Icons.receipt_long_outlined,
                _records.isEmpty ? 'No shifts have been recorded yet.' : 'No shifts with this payment status.'),
          for (final r in visible) _recordCard(r),
        ],
      ),
    );
  }

  Widget _totalTile(String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppTheme.textMuted)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      );

  Widget _employeeCard(Map<String, dynamic> e) {
    final s = _summary[intOf(e['user_id'])];
    final open = intOf(s?['open_shifts']);
    final inactive = e['account_status'] != null && e['account_status'] != 'Active';
    return ManageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strOf(e['full_name'], 'Employee'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text('${strOf(e['role'])}${inactive ? ' · Inactive' : ''}',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Text('${money(e['hourly_rate'])}/hr', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primaryLight)),
              const SizedBox(width: 8),
              CardAction('Rate', Icons.edit_outlined, () => _editRate(e)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat('Shifts', '${intOf(s?['shifts'])}${open > 0 ? ' ($open open)' : ''}'),
              _stat('Hours', numOf(s?['hours']).toStringAsFixed(2)),
              _stat('Gross', money(s?['gross_pay'])),
              _stat('Unpaid', money(s?['unpaid']), color: numOf(s?['unpaid']) > 0 ? AppTheme.statusYellow : null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? AppTheme.textPrimary)),
          ],
        ),
      );

  Widget _recordCard(Map<String, dynamic> r) {
    final isOpen = r['clock_out'] == null;
    final status = strOf(r['payment_status'], 'Pending');
    final reason = strOf(r['adjustment_reason']);
    return ManageCard(
      borderColor: status == 'Pending Correction' ? AppTheme.statusRed.withOpacity(0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#${intOf(r['payroll_id'])}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(strOf(r['full_name'], 'Employee'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              if (isOpen) ...[StatusChip('Open', AppTheme.statusBlue), const SizedBox(width: 6)],
              StatusChip(status, _statusColor(status)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'In ${formatDateTime(serverTime(r['clock_in']))}  →  Out ${isOpen ? 'still clocked in' : formatDateTime(serverTime(r['clock_out']))}',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            isOpen
                ? 'Rate ${money(r['hourly_rate'])}/hr · hours and pay are calculated at clock-out'
                : '${numOf(r['hours_worked']).toStringAsFixed(2)} h × ${money(r['hourly_rate'])} = ${money(r['gross_pay'])}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Last change: $reason', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontStyle: FontStyle.italic)),
          ],
          if (!isOpen) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                CardAction('Adjust', Icons.tune_rounded, () => _adjust(r)),
                if (status != 'Paid')
                  CardAction('Mark paid', Icons.check_circle_outline, () => _setStatus(r, 'Paid'), color: AppTheme.statusGreen),
                if (status != 'Pending Correction')
                  CardAction('Flag for correction', Icons.flag_outlined, () => _setStatus(r, 'Pending Correction'),
                      color: AppTheme.statusRed),
                if (status == 'Pending Correction')
                  CardAction('Set pending', Icons.undo_rounded, () => _setStatus(r, 'Pending'), color: AppTheme.statusYellow),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
