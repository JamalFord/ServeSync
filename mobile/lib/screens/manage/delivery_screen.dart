import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import 'manage_widgets.dart';

/// FR-15: delivery platform orders (DoorDash, Uber Eats).
/// The connection status of each platform is always shown at the top, so staff can
/// see when an integration is not connected or unavailable. Delivery orders use the
/// same order and kitchen workflow as dine-in orders.
class DeliveryScreen extends StatefulWidget {
  /// API client to use; defaults to the signed-in session's client. Tests pass a mock.
  final ApiClient? api;

  const DeliveryScreen({super.key, this.api});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> with ManageLoader {
  static const _filters = ['All', 'Active', 'Completed', 'Cancelled'];
  static const _refreshEvery = Duration(seconds: 15);

  late final ApiClient _api = widget.api ?? AppState.instance.api;
  List<Map<String, dynamic>> _platforms = [];
  List<Map<String, dynamic>> _orders = [];
  String _filter = 'All';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // New platform orders arrive on the server, so the list is re-read while the screen is open.
    _timer = Timer.periodic(_refreshEvery, (_) {
      if (mounted && !loading) reload(showSpinner: false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Future<void> fetch() async {
    final results = await Future.wait([_api.deliveryStatus(), _api.deliveryOrders()]);
    _platforms = results[0];
    _orders = results[1];
  }

  // --- status shown to staff ---------------------------------------------------

  /// Cancelled / Picked up / otherwise the kitchen stage.
  static String _statusOf(Map<String, dynamic> order) {
    final orderStatus = strOf(order['order_status']);
    if (orderStatus == 'Cancelled') return 'Cancelled';
    if (orderStatus == 'Completed') return 'Picked up';
    switch (strOf(order['kitchen_status'], 'New')) {
      case 'In Prep':
        return 'In prep';
      case 'Ready':
      case 'Served':
        return 'Ready for pickup';
      default:
        return 'New';
    }
  }

  static String _groupOf(Map<String, dynamic> order) {
    final status = _statusOf(order);
    if (status == 'Cancelled') return 'Cancelled';
    if (status == 'Picked up') return 'Completed';
    return 'Active';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'New':
        return AppTheme.statusBlue;
      case 'In prep':
        return AppTheme.statusYellow;
      case 'Ready for pickup':
        return AppTheme.statusGreen;
      case 'Cancelled':
        return AppTheme.statusRed;
      default:
        return AppTheme.textMuted;
    }
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'Connected':
        return AppTheme.statusGreen;
      case 'Unavailable':
        return AppTheme.statusRed;
      default:
        return AppTheme.textMuted;
    }
  }

  // --- actions -----------------------------------------------------------------

  Future<void> _setStatus(Map<String, dynamic> order, String status, String done) async {
    String message;
    bool failed = false;
    try {
      final result = await _api.setDeliveryStatus(intOf(order['order_id']), status);
      final update = strOf(result['platform_update']);
      message = update.isEmpty ? done : '$done $update';
    } catch (e) {
      message = apiMessage(e);
      failed = true;
    }
    if (!mounted) return;
    showMessage(context, message, error: failed);
    await reload(showSpinner: false);
    // The kitchen display shows the same orders.
    unawaited(AppState.instance.refreshKitchenTickets());
  }

  Future<void> _pickedUp(Map<String, dynamic> order) async {
    final ok = await confirmAction(
      context,
      title: 'Hand ${_reference(order)} to the courier?',
      message: 'The order will be marked as picked up and closed. Payment was taken by ${strOf(order['source'], 'the platform')}.',
      confirmLabel: 'Mark picked up',
    );
    if (!ok || !mounted) return;
    await _setStatus(order, 'Picked Up', 'Order marked as picked up.');
  }

  Future<void> _cancel(Map<String, dynamic> order) async {
    final ok = await confirmAction(
      context,
      title: 'Cancel ${_reference(order)}?',
      message: 'The order will be cancelled and removed from the kitchen display. This cannot be undone.',
      confirmLabel: 'Cancel order',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _setStatus(order, 'Cancelled', 'Order cancelled.');
  }

  Future<void> _sendTestOrder() async {
    final options = _platforms.isNotEmpty
        ? _platforms
        : <Map<String, dynamic>>[
            {'platform': 'doordash', 'name': 'DoorDash'},
            {'platform': 'ubereats', 'name': 'Uber Eats'},
          ];
    String platform = strOf(options.first['platform'], 'doordash');
    final sent = await showFormDialog(
      context,
      title: 'Send a test order',
      subtitle: 'This creates a test order inside ServeSync. It is not placed on the delivery platform, '
          'and no customer or courier is involved.',
      submitLabel: 'Send test order',
      fields: (setState) => [
        FormDropdown<String>(
          label: 'Platform',
          value: platform,
          options: [for (final p in options) strOf(p['platform'])],
          labelOf: (key) => strOf(options.firstWhere((p) => strOf(p['platform']) == key)['name'], key),
          onChanged: (v) => setState(() => platform = v ?? platform),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'The order goes through the same steps as a real one: it is priced from the menu, uses stock, '
            'and appears on the kitchen display. It is labelled TEST.',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted, height: 1.3),
          ),
        ),
      ],
      onSubmit: () => guard(() => _api.createTestDeliveryOrder(platform)),
    );
    if (!sent || !mounted) return;
    showMessage(context, 'Test order created.');
    await reload(showSpinner: false);
    unawaited(AppState.instance.refreshKitchenTickets());
    unawaited(AppState.instance.refreshFromBackend());
  }

  static String _reference(Map<String, dynamic> order) {
    final external = strOf(order['external_order_id']);
    return external.isEmpty ? 'order #${order['order_id']}' : 'order $external';
  }

  // --- layout ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final canTest = currentIsManager;
    final counts = {
      for (final f in _filters) f: f == 'All' ? _orders.length : _orders.where((o) => _groupOf(o) == f).length,
    };
    final shown = _filter == 'All' ? _orders : _orders.where((o) => _groupOf(o) == _filter).toList();
    return ManageScaffold(
      eyebrow: 'FR-15',
      title: 'Delivery Orders',
      icon: Icons.delivery_dining_rounded,
      loading: loading,
      error: loadError,
      onRefresh: reload,
      floatingActionButton: canTest
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Send test order', style: TextStyle(fontWeight: FontWeight.w800)),
              onPressed: _sendTestOrder,
            )
          : null,
      builder: () => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          const SectionHeading('Connection status'),
          if (_platforms.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('No delivery platforms are set up.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ),
          for (final p in _platforms) _platformCard(p),
          const SizedBox(height: 4),
          const SectionHeading('Delivery orders'),
          FilterChips(options: _filters, selected: _filter, counts: counts, onSelected: (f) => setState(() => _filter = f)),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            EmptyState(
              Icons.delivery_dining_outlined,
              _orders.isEmpty
                  ? 'No delivery orders have been received.'
                  : 'No ${_filter.toLowerCase()} delivery orders.',
            ),
          for (final o in shown) _orderCard(o),
        ],
      ),
    );
  }

  Widget _platformCard(Map<String, dynamic> p) {
    final state = strOf(p['state'], 'Not connected');
    final color = _stateColor(state);
    final lastOrder = serverTime(p['last_order_at']);
    return ManageCard(
      borderColor: state == 'Connected' ? null : color.withOpacity(0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(state == 'Connected' ? Icons.link_rounded : Icons.link_off_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(strOf(p['name'], 'Delivery platform'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              StatusChip(state, color),
            ],
          ),
          const SizedBox(height: 8),
          Text(strOf(p['detail']), style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.3)),
          const SizedBox(height: 8),
          _fact('Last order', lastOrder == null ? 'None yet' : formatDateTime(lastOrder)),
          _fact('Open orders', '${intOf(p['open_orders'])}'),
          _fact('Status updates', strOf(p['status_updates'], '—')),
        ],
      ),
    );
  }

  Widget _fact(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$label: ', style: TextStyle(color: AppTheme.textMuted)),
              TextSpan(text: value, style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
            ],
          ),
          style: const TextStyle(fontSize: 11.5),
        ),
      );

  Widget _orderCard(Map<String, dynamic> order) {
    final status = _statusOf(order);
    final open = _groupOf(order) == 'Active';
    final external = strOf(order['external_order_id']);
    final notes = strOf(order['delivery_notes']);
    final items = ((order['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return ManageCard(
      borderColor: open ? _statusColor(status).withOpacity(0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(strOf(order['source'], 'Delivery'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    if (external.isNotEmpty)
                      Text(external, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
                    if (external.startsWith('TEST-')) StatusChip('Test', AppTheme.statusYellow),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(status, _statusColor(status)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${strOf(order['customer_name'], 'Delivery customer')} · Placed ${formatDateTime(serverTime(order['order_time']))}',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('Note: $notes', style: TextStyle(fontSize: 12, color: AppTheme.textMuted, fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 8),
          for (final line in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${intOf(line['quantity'])} × ', style: TextStyle(color: AppTheme.primaryLight, fontWeight: FontWeight.w800)),
                    TextSpan(text: strOf(line['item_name'], 'Item'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (strOf(line['modifications']).isNotEmpty)
                      TextSpan(text: '  (${strOf(line['modifications'])})', style: TextStyle(color: AppTheme.textMuted)),
                  ],
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          const SizedBox(height: 4),
          Text('Total ${money(order['total_amount'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          if (open) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (status == 'New')
                  CardAction('Start prep', Icons.local_fire_department_outlined,
                      () => _setStatus(order, 'In Prep', 'Order moved to In prep.'), color: AppTheme.statusYellow),
                if (status == 'In prep')
                  CardAction('Mark ready', Icons.check_circle_outline,
                      () => _setStatus(order, 'Ready', 'Order marked ready for pickup.'), color: AppTheme.statusGreen),
                if (status == 'Ready for pickup')
                  CardAction('Picked up', Icons.delivery_dining_outlined, () => _pickedUp(order), color: AppTheme.statusGreen),
                CardAction('Cancel order', Icons.close, () => _cancel(order), color: AppTheme.statusRed),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
