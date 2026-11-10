import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import 'manage_widgets.dart';

/// FR-1 / UC-05: supplier contact management.
/// All staff can look up a supplier; Managers and Administrators add and edit.
class SuppliersScreen extends StatefulWidget {
  /// API client to use; defaults to the signed-in session's client. Tests pass a mock.
  final ApiClient? api;

  const SuppliersScreen({super.key, this.api});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> with ManageLoader {
  late final ApiClient _api = widget.api ?? AppState.instance.api;
  List<Map<String, dynamic>> _suppliers = [];

  @override
  Future<void> fetch() async {
    _suppliers = await _api.suppliers();
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final name = TextEditingController(text: strOf(existing?['supplier_name']));
    final contact = TextEditingController(text: strOf(existing?['contact_person']));
    final phone = TextEditingController(text: strOf(existing?['phone_number']));
    final email = TextEditingController(text: strOf(existing?['email']));
    final category = TextEditingController(text: strOf(existing?['product_category']));
    final saved = await showFormDialog(
      context,
      title: existing == null ? 'Add supplier' : 'Edit supplier',
      submitLabel: existing == null ? 'Add supplier' : 'Save changes',
      fields: (_) => [
        FormTextField(label: 'Supplier name', controller: name, maxLength: 100),
        FormTextField(label: 'Contact person', controller: contact, maxLength: 100),
        FormTextField(label: 'Phone number', controller: phone, keyboardType: TextInputType.phone, maxLength: 20),
        FormTextField(label: 'Email', controller: email, keyboardType: TextInputType.emailAddress, maxLength: 100),
        FormTextField(label: 'Product category', controller: category, hint: 'Fresh Produce, Dairy, Seafood', maxLength: 100),
      ],
      onSubmit: () async {
        final body = <String, dynamic>{
          'supplier_name': name.text.trim(),
          'contact_person': contact.text.trim(),
          'phone_number': phone.text.trim(),
          'email': email.text.trim(),
          'product_category': category.text.trim(),
        };
        if (body.values.any((v) => (v as String).isEmpty)) return 'All five fields are required.';
        return guard(() => existing == null
            ? _api.createSupplier(body)
            : _api.updateSupplier(intOf(existing['supplier_id']), body));
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, existing == null ? 'Supplier added.' : 'Supplier updated.');
    await reload(showSpinner: false);
    // Keep the purchase-order screen's supplier list in step with this change.
    unawaited(AppState.instance.refreshFromBackend());
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = currentIsManager;
    return ManageScaffold(
      eyebrow: 'FR-1 · UC-05',
      title: 'Suppliers',
      icon: Icons.local_shipping_rounded,
      loading: loading,
      error: loadError,
      onRefresh: reload,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Add supplier', style: TextStyle(fontWeight: FontWeight.w800)),
              onPressed: () => _openForm(),
            )
          : null,
      builder: () => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          SectionHeading('${_suppliers.length} approved suppliers'),
          if (!canEdit)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Only a Manager or Administrator can add or edit suppliers.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ),
          if (_suppliers.isEmpty) const EmptyState(Icons.local_shipping_outlined, 'No suppliers have been added.'),
          for (final s in _suppliers)
            ManageCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(strOf(s['supplier_name'], 'Supplier'),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                      if (canEdit) CardAction('Edit', Icons.edit_outlined, () => _openForm(s)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  StatusChip(strOf(s['product_category'], 'General'), AppTheme.statusGreen),
                  const SizedBox(height: 10),
                  _line(Icons.person_outline, strOf(s['contact_person'], '—')),
                  _line(Icons.phone_outlined, strOf(s['phone_number'], '—')),
                  _line(Icons.mail_outline, strOf(s['email'], '—')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppTheme.textMuted),
            const SizedBox(width: 8),
            Expanded(child: SelectableText(value, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
          ],
        ),
      );
}
