import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import 'manage_widgets.dart';

/// FR-11 / UC-12: customer service issues.
/// All staff can log and view issues; Managers and Administrators change status.
class CustomerServiceScreen extends StatefulWidget {
  /// API client to use; defaults to the signed-in session's client. Tests pass a mock.
  final ApiClient? api;

  const CustomerServiceScreen({super.key, this.api});

  @override
  State<CustomerServiceScreen> createState() => _CustomerServiceScreenState();
}

class _CustomerServiceScreenState extends State<CustomerServiceScreen> with ManageLoader {
  static const _categories = ['Food Quality', 'Service', 'Billing', 'Order Accuracy', 'Cleanliness', 'Other'];
  static const _filters = ['All', 'Open', 'In Progress', 'Resolved'];

  late final ApiClient _api = widget.api ?? AppState.instance.api;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _issues = [];
  String _filter = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Future<void> fetch() async {
    _issues = await _api.serviceIssues();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Open':
        return AppTheme.statusRed;
      case 'In Progress':
        return AppTheme.statusYellow;
      default:
        return AppTheme.statusGreen;
    }
  }

  Future<void> _logIssue() async {
    String category = _categories.first;
    final description = TextEditingController();
    final contact = TextEditingController();
    final saved = await showFormDialog(
      context,
      title: 'Log a customer issue',
      submitLabel: 'Log issue',
      fields: (setDialog) => [
        FormDropdown<String>(
          label: 'Category',
          value: category,
          options: _categories,
          labelOf: (c) => c,
          onChanged: (v) => setDialog(() => category = v ?? category),
        ),
        FormTextField(label: 'What happened', controller: description, maxLines: 4, hint: 'Describe the issue in the guest\'s words'),
        FormTextField(label: 'Customer contact (optional)', controller: contact, hint: 'Phone or email', maxLength: 100),
      ],
      onSubmit: () async {
        if (description.text.trim().isEmpty) return 'A description is required.';
        return guard(() => _api.createServiceIssue({
              'category': category,
              'description': description.text.trim(),
              'customer_contact': contact.text.trim(),
            }));
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, 'Issue logged.');
    await reload(showSpinner: false);
  }

  Future<void> _resolve(Map<String, dynamic> issue) async {
    final notes = TextEditingController(text: strOf(issue['resolution_notes']));
    final saved = await showFormDialog(
      context,
      title: 'Resolve issue #${intOf(issue['issue_id'])}',
      subtitle: strOf(issue['description']),
      submitLabel: 'Mark resolved',
      fields: (_) => [
        FormTextField(
          label: 'Resolution notes (required)',
          controller: notes,
          maxLines: 4,
          hint: 'What was done for the guest',
        ),
      ],
      onSubmit: () async {
        if (notes.text.trim().isEmpty) return 'Resolution notes are required to resolve an issue.';
        return guard(() => _api.setServiceIssueStatus(intOf(issue['issue_id']), 'Resolved', notes: notes.text.trim()));
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, 'Issue #${intOf(issue['issue_id'])} resolved.');
    await reload(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final counts = <String, int>{'All': _issues.length};
    for (final i in _issues) {
      final s = strOf(i['status'], 'Open');
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final visible = _issues.where((i) {
      if (_filter != 'All' && i['status'] != _filter) return false;
      if (query.isEmpty) return true;
      return [i['category'], i['description'], i['customer_contact'], i['resolution_notes']]
          .any((v) => strOf(v).toLowerCase().contains(query));
    }).toList();

    return ManageScaffold(
      eyebrow: 'FR-11 · UC-12',
      title: 'Customer Service',
      icon: Icons.support_agent_rounded,
      loading: loading,
      error: loadError,
      onRefresh: reload,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Log issue', style: TextStyle(fontWeight: FontWeight.w800)),
        onPressed: _logIssue,
      ),
      builder: () => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          TextField(
            controller: _search,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search category, description or contact',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          FilterChips(options: _filters, selected: _filter, counts: counts, onSelected: (f) => setState(() => _filter = f)),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            EmptyState(
              Icons.mark_chat_read_outlined,
              _issues.isEmpty ? 'No customer issues have been logged.' : 'No issues match this search or filter.',
            ),
          for (final issue in visible) _issueCard(issue),
        ],
      ),
    );
  }

  Widget _issueCard(Map<String, dynamic> issue) {
    final id = intOf(issue['issue_id']);
    final status = strOf(issue['status'], 'Open');
    final color = _statusColor(status);
    final contact = strOf(issue['customer_contact']);
    final resolution = strOf(issue['resolution_notes']);
    final handler = strOf(issue['assigned_to_name']);
    return ManageCard(
      borderColor: status == 'Open' ? color.withOpacity(0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#$id', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(strOf(issue['category'], 'Issue'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              StatusChip(status, color),
            ],
          ),
          const SizedBox(height: 6),
          Text(strOf(issue['description']), style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.3)),
          const SizedBox(height: 6),
          Text(
            [
              'Reported ${formatDateTime(serverTime(issue['reported_at']))}',
              if (contact.isNotEmpty) 'Contact: $contact',
              if (handler.isNotEmpty) 'Handled by $handler',
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          if (resolution.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppTheme.surfaceElevated, borderRadius: BorderRadius.circular(8)),
              child: Text('Resolution: $resolution', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ),
          ],
          if (currentIsManager) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (status == 'Open')
                  CardAction('Start', Icons.play_arrow_rounded,
                      () => act(() => _api.setServiceIssueStatus(id, 'In Progress'), success: 'Issue #$id is in progress.'),
                      color: AppTheme.statusYellow),
                if (status != 'Resolved')
                  CardAction('Resolve', Icons.check_circle_outline, () => _resolve(issue), color: AppTheme.statusGreen),
                if (status == 'Resolved')
                  CardAction('Reopen', Icons.replay_rounded,
                      () => act(() => _api.setServiceIssueStatus(id, 'Open'), success: 'Issue #$id reopened.')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
