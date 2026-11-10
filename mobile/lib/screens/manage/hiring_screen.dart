import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import 'manage_widgets.dart';

/// FR-12 / UC-10: applications, hiring and onboarding (Administrator only).
/// Hiring an applicant creates their staff account in the same step.
class HiringScreen extends StatefulWidget {
  /// API client to use; defaults to the signed-in session's client. Tests pass a mock.
  final ApiClient? api;

  const HiringScreen({super.key, this.api});

  @override
  State<HiringScreen> createState() => _HiringScreenState();
}

class _HiringScreenState extends State<HiringScreen> with ManageLoader {
  static const _filters = ['All', 'New', 'Reviewed', 'Interview', 'Hired', 'Rejected'];
  static const _roles = ['FOH Staff', 'Manager', 'Administrator'];
  static const _onboarding = ['Not Started', 'In Progress', 'Complete'];

  late final ApiClient _api = widget.api ?? AppState.instance.api;
  List<Map<String, dynamic>> _applicants = [];
  String _filter = 'All';

  @override
  Future<void> fetch() async {
    _applicants = await _api.applicants();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'New':
        return AppTheme.statusBlue;
      case 'Reviewed':
        return AppTheme.primaryLight;
      case 'Interview':
        return AppTheme.statusYellow;
      case 'Hired':
        return AppTheme.statusGreen;
      default:
        return AppTheme.statusRed; // Rejected
    }
  }

  Future<void> _addApplicant() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final position = TextEditingController();
    final availability = TextEditingController();
    final years = TextEditingController(text: '0');
    final saved = await showFormDialog(
      context,
      title: 'Add applicant',
      submitLabel: 'Add applicant',
      fields: (_) => [
        FormTextField(label: 'Full name', controller: name, maxLength: 100),
        FormTextField(label: 'Email', controller: email, keyboardType: TextInputType.emailAddress, maxLength: 100),
        FormTextField(label: 'Phone number (optional)', controller: phone, keyboardType: TextInputType.phone, maxLength: 20),
        FormTextField(label: 'Position applied for', controller: position, hint: 'Server, Line Cook, Host', maxLength: 100),
        FormTextField(label: 'Availability (optional)', controller: availability, hint: 'Evenings and weekends', maxLength: 100),
        FormTextField(label: 'Years of experience', controller: years, keyboardType: TextInputType.number, digitsOnly: true, maxLength: 2),
      ],
      onSubmit: () async {
        if (name.text.trim().isEmpty) return 'Full name is required.';
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.text.trim())) return 'Enter a valid email address.';
        if (position.text.trim().isEmpty) return 'The position applied for is required.';
        return guard(() => _api.createApplicant({
              'full_name': name.text.trim(),
              'email': email.text.trim(),
              'phone_number': phone.text.trim(),
              'applied_position': position.text.trim(),
              'availability': availability.text.trim(),
              'years_experience': int.tryParse(years.text.trim()) ?? 0,
            }));
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, 'Applicant ${name.text.trim()} added.');
    await reload(showSpinner: false);
  }

  Future<void> _move(Map<String, dynamic> a, String status) async {
    final name = strOf(a['full_name'], 'this applicant');
    if (status == 'Rejected') {
      final ok = await confirmAction(
        context,
        title: 'Reject applicant?',
        message: '$name will be marked as rejected and cannot be hired unless moved back to an earlier stage.',
        confirmLabel: 'Reject',
        danger: true,
      );
      if (!ok) return;
    }
    await act(() => _api.updateApplicant(intOf(a['applicant_id']), {'application_status': status}),
        success: '$name moved to $status.');
  }

  Future<void> _editNotes(Map<String, dynamic> a) async {
    final notes = TextEditingController(text: strOf(a['notes']));
    final saved = await showFormDialog(
      context,
      title: 'Notes for ${strOf(a['full_name'])}',
      submitLabel: 'Save notes',
      fields: (_) => [
        FormTextField(label: 'Notes', controller: notes, maxLines: 5, hint: 'Interview feedback, references, documents received'),
      ],
      onSubmit: () => guard(() => _api.updateApplicant(intOf(a['applicant_id']), {'notes': notes.text.trim()})),
    );
    if (!saved || !mounted) return;
    showMessage(context, 'Notes saved.');
    await reload(showSpinner: false);
  }

  Future<void> _hire(Map<String, dynamic> a) async {
    final name = strOf(a['full_name'], 'Applicant');
    final pin = TextEditingController();
    final rate = TextEditingController(text: '16.50');
    String role = _roles.first;
    String? createdName;
    final saved = await showFormDialog(
      context,
      title: 'Hire $name',
      subtitle: 'This creates the staff account. Give the PIN to the new employee; it is not shown again.',
      submitLabel: 'Hire and create account',
      fields: (setDialog) => [
        FormDropdown<String>(
          label: 'Role',
          value: role,
          options: _roles,
          labelOf: (r) => r,
          onChanged: (v) => setDialog(() => role = v ?? role),
        ),
        FormTextField.pin(label: 'Access PIN for the new account', controller: pin),
        FormTextField.decimal(label: 'Hourly rate (\$)', controller: rate),
      ],
      onSubmit: () async {
        if (!RegExp(r'^\d{4}$').hasMatch(pin.text)) return 'The PIN must be exactly four digits.';
        final value = double.tryParse(rate.text.trim());
        if (value == null || value < 0 || value > 500) return 'Hourly rate must be a number between 0 and 500.';
        return guard(() async {
          final result = await _api.hireApplicant(intOf(a['applicant_id']), {
            'role': role,
            'pin': pin.text,
            'hourly_rate': value,
          });
          createdName = strOf((result['user'] as Map?)?['full_name'], name);
        });
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, 'Hired. Staff account created for ${createdName ?? name} ($role). Onboarding is in progress.');
    await reload(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{'All': _applicants.length};
    for (final a in _applicants) {
      final s = strOf(a['application_status'], 'New');
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final visible =
        _filter == 'All' ? _applicants : _applicants.where((a) => a['application_status'] == _filter).toList();

    return ManageScaffold(
      eyebrow: 'FR-12 · UC-10',
      title: 'Hiring',
      icon: Icons.badge_rounded,
      loading: loading,
      error: loadError,
      onRefresh: reload,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add applicant', style: TextStyle(fontWeight: FontWeight.w800)),
        onPressed: _addApplicant,
      ),
      builder: () => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          FilterChips(options: _filters, selected: _filter, counts: counts, onSelected: (f) => setState(() => _filter = f)),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            EmptyState(Icons.assignment_ind_outlined,
                _applicants.isEmpty ? 'No applicants yet. Use "Add applicant" to record one.' : 'No applicants at this stage.'),
          for (final a in visible) _applicantCard(a),
        ],
      ),
    );
  }

  Widget _applicantCard(Map<String, dynamic> a) {
    final status = strOf(a['application_status'], 'New');
    final hired = status == 'Hired';
    final rejected = status == 'Rejected';
    final notes = strOf(a['notes']);
    final availability = strOf(a['availability']);
    final phone = strOf(a['phone_number']);
    final onboarding = strOf(a['onboarding_status'], 'Not Started');
    final years = intOf(a['years_experience']);
    return ManageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(strOf(a['full_name'], 'Applicant'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              StatusChip(status, _statusColor(status)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${strOf(a['applied_position'], 'Position not given')} · $years ${years == 1 ? 'year' : 'years'} experience',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            [strOf(a['email']), if (phone.isNotEmpty) phone, if (availability.isNotEmpty) 'Available: $availability'].join(' · '),
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          Text('Applied ${formatDateTime(serverTime(a['created_at']))}', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppTheme.surfaceElevated, borderRadius: BorderRadius.circular(8)),
              child: Text(notes, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ),
          ],
          if (hired) ...[
            const SizedBox(height: 10),
            Text('ONBOARDING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppTheme.textMuted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final step in _onboarding)
                  ChoiceChip(
                    label: Text(step),
                    selected: step == onboarding,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppTheme.surfaceElevated,
                    selectedColor: AppTheme.statusGreen.withOpacity(0.25),
                    side: BorderSide(color: step == onboarding ? AppTheme.statusGreen : AppTheme.border),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: step == onboarding ? AppTheme.statusGreen : AppTheme.textSecondary,
                    ),
                    onSelected: step == onboarding
                        ? null
                        : (_) => act(
                              () => _api.updateApplicant(intOf(a['applicant_id']), {'onboarding_status': step}),
                              success: 'Onboarding for ${strOf(a['full_name'])}: $step.',
                            ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (status == 'New') CardAction('Mark reviewed', Icons.fact_check_outlined, () => _move(a, 'Reviewed')),
              if (status == 'New' || status == 'Reviewed')
                CardAction('Interview', Icons.event_available_outlined, () => _move(a, 'Interview'), color: AppTheme.statusYellow),
              if (!hired && !rejected)
                CardAction('Hire', Icons.how_to_reg_outlined, () => _hire(a), color: AppTheme.statusGreen),
              if (!hired && !rejected)
                CardAction('Reject', Icons.close_rounded, () => _move(a, 'Rejected'), color: AppTheme.statusRed),
              if (rejected) CardAction('Reconsider', Icons.replay_rounded, () => _move(a, 'Reviewed')),
              CardAction('Notes', Icons.sticky_note_2_outlined, () => _editNotes(a), color: AppTheme.textSecondary),
            ],
          ),
        ],
      ),
    );
  }
}
