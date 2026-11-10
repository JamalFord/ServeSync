import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import 'manage_widgets.dart';

/// FR-13 menu management and FR-14 price management.
/// All staff can read the menu; Managers and Administrators add, edit and remove
/// items and change prices. Every price change is kept in the price history, and
/// orders already taken keep the price they were sold at.
class MenuScreen extends StatefulWidget {
  /// API client to use; defaults to the signed-in session's client. Tests pass a mock.
  final ApiClient? api;

  const MenuScreen({super.key, this.api});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with ManageLoader {
  late final ApiClient _api = widget.api ?? AppState.instance.api;
  List<Map<String, dynamic>> _items = [];

  @override
  Future<void> fetch() async {
    _items = await _api.menu();
  }

  /// The API sends booleans as 1 or 0.
  static bool _isAvailable(Map<String, dynamic> item) {
    final v = item['available'];
    return v == true || v == 1 || v == '1';
  }

  List<String> get _categories => {for (final i in _items) strOf(i['category'], 'Other')}.toList()..sort();

  /// The POS reads its menu through AppState, so tell it the menu changed.
  void _syncPos() => unawaited(AppState.instance.refreshFromBackend());

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final name = TextEditingController(text: strOf(existing?['item_name']));
    final description = TextEditingController(text: strOf(existing?['description']));
    final category = TextEditingController(text: strOf(existing?['category']));
    final price = TextEditingController(text: existing == null ? '' : numOf(existing['price']).toStringAsFixed(2));
    bool available = existing == null || _isAvailable(existing);
    final categories = _categories;
    final saved = await showFormDialog(
      context,
      title: existing == null ? 'Add menu item' : 'Edit menu item',
      subtitle: existing == null
          ? 'The item can be ordered as soon as it is saved.'
          : 'A changed price is recorded in the price history. Existing orders keep their prices.',
      submitLabel: existing == null ? 'Add item' : 'Save changes',
      fields: (setState) => [
        FormTextField(label: 'Item name', controller: name, maxLength: 100),
        FormTextField(label: 'Description', controller: description, maxLines: 2, maxLength: 255),
        FormTextField(label: 'Category', controller: category, hint: 'Appetizers, Entrees, Desserts', maxLength: 50),
        if (categories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in categories)
                  ActionChip(
                    label: Text(c, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    tooltip: 'Use category $c',
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppTheme.surface,
                    side: BorderSide(color: AppTheme.border),
                    onPressed: () => setState(() => category.text = c),
                  ),
              ],
            ),
          ),
        FormTextField.decimal(label: 'Price (\$)', controller: price, hint: '0.00'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeColor: AppTheme.primary,
          title: const Text('Available to order', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          value: available,
          onChanged: (v) => setState(() => available = v),
        ),
      ],
      onSubmit: () async {
        if (name.text.trim().isEmpty) return 'Item name is required.';
        if (category.text.trim().isEmpty) return 'Category is required.';
        final value = double.tryParse(price.text.trim());
        if (value == null || value < 0) return 'Price must be a number that is zero or more.';
        final body = <String, dynamic>{
          'item_name': name.text.trim(),
          'description': description.text.trim(),
          'category': category.text.trim(),
          'price': value,
          'available': available,
        };
        return guard(() => existing == null
            ? _api.createMenuItem(body)
            : _api.updateMenuItem(intOf(existing['menu_item_id']), body));
      },
    );
    if (!saved || !mounted) return;
    showMessage(context, existing == null ? 'Menu item added.' : 'Menu item updated.');
    await reload(showSpinner: false);
    _syncPos();
  }

  Future<void> _changePrice(Map<String, dynamic> item) async {
    final current = numOf(item['price']);
    final price = TextEditingController();
    double? newPrice;
    final saved = await showFormDialog(
      context,
      title: 'Change price',
      subtitle: '${strOf(item['item_name'], 'Item')}: current price ${money(current)}',
      submitLabel: 'Save price',
      fields: (_) => [
        FormTextField.decimal(label: 'New price (\$)', controller: price, hint: current.toStringAsFixed(2)),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'New orders use the new price. Orders already taken keep the price they were sold at. '
            'The change is recorded with your name and the time.',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted, height: 1.3),
          ),
        ),
      ],
      onSubmit: () async {
        final value = double.tryParse(price.text.trim());
        if (value == null || value < 0) return 'Enter the new price as a number that is zero or more.';
        if ((value - current).abs() < 0.005) return 'The new price is the same as the current price.';
        newPrice = value;
        return guard(() => _api.updateMenuItem(intOf(item['menu_item_id']), {'price': value}));
      },
    );
    if (!saved || !mounted) return;
    showMessage(
      context,
      'Price changed from ${money(current)} to ${money(newPrice)}. '
      'The change was recorded in the price history; existing orders keep their prices.',
    );
    await reload(showSpinner: false);
    _syncPos();
  }

  Future<void> _toggleAvailable(Map<String, dynamic> item) async {
    final makeAvailable = !_isAvailable(item);
    final name = strOf(item['item_name'], 'Item');
    await act(
      () => _api.updateMenuItem(intOf(item['menu_item_id']), {'available': makeAvailable}),
      success: makeAvailable ? '$name can be ordered again.' : '$name is marked unavailable and cannot be ordered.',
    );
    _syncPos();
  }

  Future<void> _remove(Map<String, dynamic> item) async {
    final name = strOf(item['item_name'], 'this item');
    final ok = await confirmAction(
      context,
      title: 'Remove $name?',
      message: 'It will no longer be on the menu for new orders. '
          'Orders already taken keep this item and the price it was sold at.',
      confirmLabel: 'Remove item',
      danger: true,
    );
    if (!ok || !mounted) return;
    await act(() => _api.removeMenuItem(intOf(item['menu_item_id'])), success: '$name was removed from the menu.');
    _syncPos();
  }

  /// Shows the price changes of one item, or of the whole menu when [item] is null.
  Future<void> _showHistory([Map<String, dynamic>? item]) async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _api.priceHistory(menuItemId: item == null ? null : intOf(item['menu_item_id']));
    } catch (e) {
      if (mounted) showMessage(context, apiMessage(e), error: true);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          item == null ? 'All price changes' : 'Price history: ${strOf(item['item_name'], 'Item')}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 420,
          child: rows.isEmpty
              ? Text('No price changes have been recorded.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) Divider(height: 16, color: AppTheme.border),
                      if (item == null)
                        Text(strOf(rows[i]['item_name'], 'Item'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      Text(
                        '${money(rows[i]['previous_price'])} → ${money(rows[i]['new_price'])}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primaryLight),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatDateTime(serverTime(rows[i]['changed_at']))} · ${strOf(rows[i]['changed_by_name'], 'Staff')}',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = currentIsManager;
    final categories = _categories;
    return ManageScaffold(
      eyebrow: 'FR-13 · FR-14',
      title: 'Menu & Prices',
      icon: Icons.restaurant_menu_rounded,
      loading: loading,
      error: loadError,
      onRefresh: reload,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add item', style: TextStyle(fontWeight: FontWeight.w800)),
              onPressed: () => _openForm(),
            )
          : null,
      builder: () => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_items.length} ITEMS ON THE MENU',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppTheme.textSecondary),
                ),
              ),
              if (canEdit) CardAction('All price changes', Icons.history, () => _showHistory()),
            ],
          ),
          const SizedBox(height: 10),
          if (!canEdit)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Only a Manager or Administrator can change the menu or prices.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ),
          if (_items.isEmpty) const EmptyState(Icons.restaurant_menu_outlined, 'The menu has no items yet.'),
          for (final category in categories) ...[
            SectionHeading(category),
            for (final item in _items.where((i) => strOf(i['category'], 'Other') == category)) _itemCard(item, canEdit),
          ],
        ],
      ),
    );
  }

  Widget _itemCard(Map<String, dynamic> item, bool canEdit) {
    final available = _isAvailable(item);
    final description = strOf(item['description']);
    return ManageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(strOf(item['item_name'], 'Menu item'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Text(money(item['price']), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.primaryLight)),
            ],
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(description, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.25)),
            ),
          const SizedBox(height: 8),
          StatusChip(available ? 'Available' : 'Unavailable', available ? AppTheme.statusGreen : AppTheme.textMuted),
          if (canEdit) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                CardAction('Edit', Icons.edit_outlined, () => _openForm(item)),
                CardAction('Change price', Icons.sell_outlined, () => _changePrice(item)),
                CardAction(
                  available ? 'Mark unavailable' : 'Mark available',
                  available ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  () => _toggleAvailable(item),
                  color: available ? AppTheme.statusYellow : AppTheme.statusGreen,
                ),
                CardAction('Price history', Icons.history, () => _showHistory(item), color: AppTheme.textSecondary),
                CardAction('Remove', Icons.delete_outline, () => _remove(item), color: AppTheme.statusRed),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
