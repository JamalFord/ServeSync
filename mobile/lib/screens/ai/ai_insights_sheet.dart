import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/kds_ticket.dart';
import '../../services/api_client.dart';
import '../../services/app_state.dart';

/// AI sheet: consumption analytics (FR-10), customer review summary (FR-08) and a
/// question box that answers from the same live data.
///
/// Every figure shown here comes from the ServeSync API (MySQL). Nothing is
/// hard-coded: when the device is offline, or the signed-in role is not allowed
/// to see a report, the tab says so instead of showing numbers.
class AIInsightsSheet extends StatefulWidget {
  const AIInsightsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AIInsightsSheet(),
    );
  }

  @override
  State<AIInsightsSheet> createState() => _AIInsightsSheetState();
}

class _AIInsightsSheetState extends State<AIInsightsSheet> with SingleTickerProviderStateMixin {
  static const _offlineTitle = 'Sign in while online';
  static const _offlineBody =
      'These figures are calculated by the ServeSync cloud from the inventory and review records. '
      'This device is in offline demo mode, so there is nothing to show.';
  static const _forbiddenTitle = 'Manager or Administrator access required';

  final AppState _app = AppState.instance;
  ApiClient get _api => _app.api;
  bool get _online => _app.isBackendOnline;

  late TabController _tabController;
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  // --- Copilot ---------------------------------------------------------------
  final List<Map<String, String>> _chatHistory = [
    {
      'role': 'assistant',
      'content': 'Ask about restocking, food waste, guest feedback or who is on shift. '
          'I answer from the live ServeSync records: the consumption forecast, the spoilage log, '
          'customer reviews and shift data. I do not have recipe cost or sales margin data.',
    }
  ];
  bool _answering = false;

  // --- Demand (FR-10) --------------------------------------------------------
  int _days = 14;
  Map<String, dynamic>? _report;
  bool _reportLoading = false;
  bool _reportForbidden = false;
  String? _reportError;
  String? _demandNotice;
  bool _demandNoticeIsError = false;
  final Set<int> _orderingItemIds = {};
  Future<void>? _reportTask;

  // --- Reviews (FR-08) -------------------------------------------------------
  Map<String, dynamic>? _reviews;
  Map<String, dynamic>? _summary;
  bool _reviewsLoading = false;
  bool _summaryForbidden = false;
  String? _reviewsError;
  String? _summaryError;
  String? _reviewsNotice;
  bool _reviewsNoticeIsError = false;
  bool _reviewsBusy = false;
  Future<void>? _reviewsTask;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_online) return;
      _loadReport();
      _loadReviews();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _promptController.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }

  // ---------------------------------------------------------------------------
  // Parsing helpers (the API sends DECIMAL columns as strings or numbers)
  // ---------------------------------------------------------------------------
  static double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

  static int? _id(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');

  /// Quantity without trailing zeros: 8.50 -> "8.5", 12.00 -> "12".
  static String _q(dynamic v) {
    var s = _n(v).toStringAsFixed(2);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    return s.replaceFirst(RegExp(r'\.$'), '');
  }

  static String _money(dynamic v) => '\$${_n(v).toStringAsFixed(2)}';

  static List<Map<String, dynamic>> _maps(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  static List<String> _strings(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];

  /// Server timestamps are naive UTC ("2026-11-08 03:54:17" or ISO "T" form).
  static DateTime? _parseServerTime(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim().replaceFirst(' ', 'T');
    if (s.isEmpty) return null;
    final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
    return DateTime.tryParse(hasZone ? s : '${s}Z')?.toLocal();
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _dateText(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  static String _dateTimeText(dynamic v) {
    final d = _parseServerTime(v);
    if (d == null) return v?.toString() ?? '';
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '${_dateText(d)}, $hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "2026-11-12" -> "Nov 12, 2026" (a calendar date, no time zone shift).
  static String _dayText(dynamic v) {
    final d = DateTime.tryParse(v?.toString() ?? '');
    return d == null ? (v?.toString() ?? '') : _dateText(d);
  }

  Color _riskColor(String risk) {
    switch (risk) {
      case 'Critical':
        return AppTheme.statusRed;
      case 'Reorder soon':
        return AppTheme.statusYellow;
      default:
        return AppTheme.statusGreen;
    }
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------
  Future<void> _loadReport() => _reportTask ??= _fetchReport().whenComplete(() => _reportTask = null);

  Future<void> _fetchReport() async {
    if (!_online) return;
    _set(() {
      _reportLoading = true;
      _reportError = null;
    });
    try {
      final report = await _api.consumptionReport(days: _days);
      _set(() {
        _report = report;
        _reportForbidden = false;
      });
    } on ApiException catch (e) {
      _set(() {
        _report = null;
        if (e.status == 403) {
          _reportForbidden = true;
        } else {
          _reportError = e.message;
        }
      });
    } catch (_) {
      _set(() {
        _report = null;
        _reportError = 'The server sent a response this app could not read.';
      });
    }
    _set(() => _reportLoading = false);
  }

  Future<void> _loadReviews() => _reviewsTask ??= _fetchReviews().whenComplete(() => _reviewsTask = null);

  Future<void> _fetchReviews() async {
    if (!_online) return;
    _set(() {
      _reviewsLoading = true;
      _reviewsError = null;
      _summaryError = null;
    });
    try {
      final listing = await _api.reviews();
      _set(() => _reviews = listing);
      // The summary is for managers; the server decides, so a 403 is a normal answer here.
      try {
        final summary = await _api.reviewSummary();
        _set(() {
          _summary = summary;
          _summaryForbidden = false;
        });
      } on ApiException catch (e) {
        _set(() {
          _summary = null;
          if (e.status == 403) {
            _summaryForbidden = true;
          } else {
            _summaryError = e.message;
          }
        });
      }
    } on ApiException catch (e) {
      _set(() => _reviewsError = e.message);
    } catch (_) {
      _set(() => _reviewsError = 'The server sent a response this app could not read.');
    }
    _set(() => _reviewsLoading = false);
  }

  // ---------------------------------------------------------------------------
  // Copilot: answers are assembled from the live reports, never from fixed text
  // ---------------------------------------------------------------------------
  Future<void> _sendQuery(String prompt) async {
    final question = prompt.trim();
    if (question.isEmpty || _answering) return;
    _promptController.clear();
    setState(() {
      _chatHistory.add({'role': 'user', 'content': question});
      _answering = true;
    });
    _scrollChatToEnd();

    String answer;
    try {
      answer = await _answer(question.toLowerCase());
    } on ApiException catch (e) {
      answer = 'I could not load that from the ServeSync cloud: ${e.message}';
    } catch (_) {
      answer = 'I could not read the data needed to answer that.';
    }
    _set(() {
      _chatHistory.add({'role': 'assistant', 'content': answer});
      _answering = false;
    });
    _scrollChatToEnd();
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  bool _mentions(String question, List<String> words) => words.any(question.contains);

  Future<String> _answer(String question) async {
    if (_mentions(question, ['labor', 'labour', 'shift', 'staff', 'clocked', 'payroll', 'who is working'])) {
      return _answerLabor();
    }
    if (_mentions(question, ['review', 'guest', 'feedback', 'customer', 'rating', 'complain', 'sentiment'])) {
      return _answerReviews();
    }
    if (_mentions(question, ['waste', 'spoil', 'spoilage', 'expired', 'loss'])) {
      return _answerWaste();
    }
    if (_mentions(question, ['restock', 'reorder', 'order', 'inventory', 'stock', 'supplier', 'ingredient', 'run out'])) {
      return _answerRestock();
    }
    return _answerOverview();
  }

  /// Loads the forecast if it is not cached yet. Returns a sentence explaining why it is
  /// unavailable, or null when [_report] is ready.
  Future<String?> _needReport() async {
    if (!_online) return 'The consumption forecast needs the ServeSync cloud, and this device is offline.';
    if (_report == null && !_reportForbidden) await _loadReport();
    if (_reportForbidden) return 'The consumption forecast is for Manager and Administrator accounts.';
    if (_report == null) return 'The consumption forecast could not be loaded: ${_reportError ?? 'no response'}';
    return null;
  }

  String _localLowStockText() {
    final low = _app.inventory.where((i) => i.isLowStock).toList();
    if (low.isEmpty) return 'On this device, no inventory item is at or below its reorder level.';
    return 'On this device, ${low.length} item(s) are at or below their reorder level:\n'
        '${low.map((i) => '- ${i.name}: ${_q(i.quantity)} ${i.unit} on hand, reorder level ${_q(i.reorderLevel)} ${i.unit}').join('\n')}';
  }

  Future<String> _answerRestock() async {
    final problem = await _needReport();
    if (problem != null) return '$problem\n\n${_localLowStockText()}';
    final report = _report!;
    final atRisk = _maps(report['items']).where((i) => i['risk'] != 'Healthy').toList();
    final header = 'Based on usage over the last ${report['period_days']} days (${report['engine']}):';
    if (atRisk.isEmpty) {
      return '$header\nNo item needs reordering. Every item has more than 5 days of stock and is above its reorder level.';
    }
    final lines = atRisk.map((i) {
      final left = i['days_of_stock_left'] == null ? 'no usage recorded' : '${_q(i['days_of_stock_left'])} days of stock left';
      return '- ${i['item_name']} (${i['risk']}): ${_q(i['on_hand'])} ${i['unit']} on hand, $left. ${i['action']}';
    }).join('\n');
    return '$header\n$lines\n\nOpen the Demand tab to create a purchase order from any of these.';
  }

  Future<String> _answerWaste() async {
    final problem = await _needReport();
    if (problem != null) {
      if (_app.spoilageHistory.isEmpty) return '$problem\n\nNo spoilage records are held on this device.';
      final recent = _app.spoilageHistory.take(5).map((s) => '- ${s.itemName}: ${_q(s.quantitySpoiled)} ${s.unit} (${s.reason})').join('\n');
      return '$problem\n\nMost recent spoilage records on this device:\n$recent';
    }
    final report = _report!;
    final spoiled = _maps(report['items']).where((i) => _n(i['spoiled']) > 0).toList()
      ..sort((a, b) => (_n(b['spoiled']) * _n(b['unit_cost'])).compareTo(_n(a['spoiled']) * _n(a['unit_cost'])));
    if (spoiled.isEmpty) return 'No spoilage was recorded in the last ${report['period_days']} days.';
    final total = (report['totals'] is Map) ? (report['totals'] as Map)['spoilage_cost'] : null;
    final lines = spoiled
        .map((i) => '- ${i['item_name']}: ${_q(i['spoiled'])} ${i['unit']} spoiled, about ${_money(_n(i['spoiled']) * _n(i['unit_cost']))} '
            '(${_q(i['used'])} ${i['unit']} used in the same period)')
        .join('\n');
    final advice = _strings(report['recommendations']).where((r) => r.toLowerCase().contains('spoil')).toList();
    return 'Spoilage in the last ${report['period_days']} days cost about ${_money(total)}:\n$lines'
        '${advice.isEmpty ? '' : '\n\n${advice.join('\n')}'}';
  }

  Future<String> _answerReviews() async {
    if (!_online) return 'Customer reviews are stored in the ServeSync cloud, and this device is offline.';
    if (_reviews == null) await _loadReviews();
    final reviews = _reviews;
    if (reviews == null) return 'Customer reviews could not be loaded: ${_reviewsError ?? 'no response'}';
    final count = _id(reviews['review_count']) ?? 0;
    if (count == 0) return 'No customer reviews have been recorded yet.';
    final stats = 'Average rating ${_n(reviews['average_rating']).toStringAsFixed(1)} out of 5 from $count reviews; '
        '${_q(reviews['positive_percent'])}% are 4 or 5 stars.';
    final summary = _summary;
    if (summary == null) {
      return _summaryForbidden
          ? '$stats\n\nThe written summary is for Manager and Administrator accounts.'
          : '$stats\n\nThe written summary could not be loaded${_summaryError == null ? '.' : ': $_summaryError'}';
    }
    final parts = <String>[summary['overview']?.toString() ?? stats];
    final strengths = _maps(summary['strengths']);
    final improvements = _maps(summary['improvements']);
    if (strengths.isNotEmpty) parts.add('Top strength: ${strengths.first['title']}. ${strengths.first['detail']}');
    if (improvements.isNotEmpty) parts.add('Top area to improve: ${improvements.first['title']}. ${improvements.first['detail']}');
    final actions = _strings(summary['recommended_actions']);
    if (actions.isNotEmpty) parts.add('Suggested action: ${actions.first}');
    parts.add('Summary generated by ${summary['engine']}${summary['is_out_of_date'] == true ? ' (new reviews have arrived since; regenerate it on the Reviews tab)' : ''}.');
    return parts.join('\n\n');
  }

  String _sinceText(DateTime? start) {
    if (start == null) return '';
    final mins = DateTime.now().difference(start).inMinutes;
    if (mins < 1) return ' (just clocked in)';
    return mins < 60 ? ' (for $mins min)' : ' (for ${mins ~/ 60} h ${mins % 60} min)';
  }

  Future<String> _answerLabor() async {
    final me = _app.currentEmployee;
    if (!_online) {
      final onShift = _app.employees.where((e) => e.isClockedIn).toList();
      if (onShift.isEmpty) return 'Offline demo data on this device shows nobody clocked in.';
      return 'Offline demo data on this device shows ${onShift.length} employee(s) clocked in:\n'
          '${onShift.map((e) => '- ${e.name}, ${e.role}${_sinceText(e.clockInTime)}').join('\n')}';
    }
    final mine = me == null
        ? ''
        : (me.isClockedIn ? 'You (${me.name}) are clocked in${_sinceText(me.clockInTime)}.' : 'You (${me.name}) are not clocked in.');
    if (me?.isAdmin != true) {
      return '$mine\n\nShift records for other employees are only available to Administrator accounts.';
    }
    // Administrators can read the payroll records: an open shift has no clock-out time.
    final payroll = await _api.payroll();
    final open = _maps(payroll['records']).where((r) => r['clock_out'] == null).toList();
    final summary = _maps(payroll['summary']);
    final unpaid = summary.fold<double>(0, (sum, s) => sum + _n(s['unpaid']));
    final lines = open.isEmpty
        ? 'Nobody has an open shift right now.'
        : '${open.length} employee(s) have an open shift:\n'
            '${open.map((r) => '- ${r['full_name']}, ${r['role']}, clocked in ${_dateTimeText(r['clock_in'])} at ${_money(r['hourly_rate'])}/h').join('\n')}';
    return '$lines\n\nCompleted shifts not yet paid total ${_money(unpaid)} across ${summary.length} employee(s).';
  }

  Future<String> _answerOverview() async {
    final openTickets = _app.kdsTickets.where((t) => t.status != TicketStatus.served).length;
    final lowStock = _app.inventory.where((i) => i.isLowStock).length;
    final floor = 'Right now: $openTickets open kitchen ticket(s) and $lowStock inventory item(s) at or below their reorder level.';
    final problem = await _needReport();
    const hint = 'You can ask about restocking, food waste, guest feedback or who is on shift.';
    if (problem != null) return '$floor\n\n$problem\n\n$hint';
    return '${_report!['summary']}\n\n$floor\n\n$hint';
  }

  // ---------------------------------------------------------------------------
  // Demand tab actions
  // ---------------------------------------------------------------------------
  Future<void> _changePeriod(int days) async {
    if (days == _days || _reportLoading) return;
    setState(() {
      _days = days;
      _demandNotice = null;
    });
    await _loadReport();
  }

  Future<void> _createPurchaseOrder(Map<String, dynamic> item) async {
    final inventoryId = _id(item['inventory_id']);
    if (inventoryId == null) return;
    final suppliers = List<Map<String, dynamic>>.from(_app.apiSuppliers);
    final suggested = item['suggested_supplier'];
    int? supplierId = suggested is Map ? _id(suggested['supplier_id']) : null;
    if (suggested is Map && supplierId != null && !suppliers.any((s) => _id(s['supplier_id']) == supplierId)) {
      suppliers.insert(0, Map<String, dynamic>.from(suggested));
    }
    if (suppliers.isEmpty) {
      setState(() {
        _demandNotice = 'No suppliers are loaded from the cloud yet. Add a supplier first, then try again.';
        _demandNoticeIsError = true;
      });
      return;
    }

    final qtyController = TextEditingController(text: _q(item['recommended_order_quantity']));
    final unit = item['unit']?.toString() ?? '';
    String? error; // dialog state lives here so a rebuild of the dialog cannot reset it
    final choice = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialog) {
            final qty = double.tryParse(qtyController.text.trim()) ?? 0;
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              title: const Text('Create purchase order', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${item['item_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'Recommended: ${_q(item['recommended_order_quantity'])} $unit at ${_money(item['unit_cost'])} per unit.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    value: supplierId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Supplier', isDense: true),
                    items: [
                      for (final s in suppliers)
                        if (_id(s['supplier_id']) != null)
                          DropdownMenuItem(value: _id(s['supplier_id']), child: Text('${s['supplier_name']}', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setDialog(() => supplierId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Quantity ($unit)', isDense: true),
                    onChanged: (_) => setDialog(() => error = null),
                  ),
                  const SizedBox(height: 10),
                  Text('Order total: ${_money(qty * _n(item['unit_cost']))}', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: TextStyle(fontSize: 12, color: AppTheme.statusRed)),
                  ],
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () {
                    if (supplierId == null) {
                      setDialog(() => error = 'Choose a supplier.');
                    } else if (qty <= 0) {
                      setDialog(() => error = 'Enter a quantity greater than 0.');
                    } else {
                      Navigator.pop(dialogContext, {'supplier_id': supplierId, 'quantity': qty});
                    }
                  },
                  child: const Text('Create order'),
                ),
              ],
            );
          },
        );
      },
    );
    // The controller is not disposed here: the dialog's closing animation still shows the field.
    if (choice == null || !mounted) return;

    setState(() {
      _orderingItemIds.add(inventoryId);
      _demandNotice = null;
    });
    try {
      final order = await _api.createPurchaseOrder({
        'supplier_id': choice['supplier_id'],
        'items': [
          {'inventory_id': inventoryId, 'quantity_ordered': choice['quantity'], 'unit_cost': _n(item['unit_cost'])},
        ],
      });
      _set(() {
        _demandNotice = 'Purchase order #${order['order_id']} created with ${order['supplier_name']} for '
            '${_q(choice['quantity'])} $unit of ${item['item_name']}.';
        _demandNoticeIsError = false;
      });
      await _app.refreshFromBackend();
      await _loadReport();
    } on ApiException catch (e) {
      _set(() {
        _demandNotice = e.status == 403 ? '$_forbiddenTitle to create purchase orders.' : 'Purchase order not created: ${e.message}';
        _demandNoticeIsError = true;
      });
    } catch (_) {
      _set(() {
        _demandNotice = 'Purchase order not created: unexpected response from the server.';
        _demandNoticeIsError = true;
      });
    }
    _set(() => _orderingItemIds.remove(inventoryId));
  }

  // ---------------------------------------------------------------------------
  // Reviews tab actions
  // ---------------------------------------------------------------------------
  Future<void> _reviewsAction(Future<String> Function() action) async {
    if (_reviewsBusy) return;
    setState(() {
      _reviewsBusy = true;
      _reviewsNotice = null;
    });
    try {
      final message = await action();
      _set(() {
        _reviewsNotice = message;
        _reviewsNoticeIsError = false;
      });
    } on ApiException catch (e) {
      _set(() {
        _reviewsNotice = e.status == 403 ? '$_forbiddenTitle.' : e.message;
        _reviewsNoticeIsError = true;
      });
    } catch (_) {
      _set(() {
        _reviewsNotice = 'The server sent a response this app could not read.';
        _reviewsNoticeIsError = true;
      });
    }
    _set(() => _reviewsBusy = false);
  }

  Future<void> _regenerateSummary() => _reviewsAction(() async {
        final summary = await _api.regenerateReviewSummary();
        _set(() {
          _summary = summary;
          _summaryForbidden = false;
          _summaryError = null;
        });
        return 'Summary regenerated from ${summary['review_count']} reviews by ${summary['engine']}.';
      });

  Future<void> _importGoogle() => _reviewsAction(() async {
        final result = await _api.importGoogleReviews();
        await _loadReviews();
        return 'Google import finished: ${result['imported']} new review(s) added out of ${result['found']} returned by Google.';
      });

  Future<void> _addReview() async {
    final nameController = TextEditingController();
    final textController = TextEditingController();
    const sources = ['In-App', 'Comment Card', 'Phone', 'Google'];
    // Dialog state lives here so a rebuild of the dialog cannot reset it.
    int rating = 5;
    String source = sources.first;
    String? error;
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialog) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Text('Add customer review', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    maxLength: 100,
                    decoration: const InputDecoration(labelText: 'Guest name (optional)', isDense: true, counterText: ''),
                  ),
                  const SizedBox(height: 12),
                  Text('Rating', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  Row(
                    children: [
                      for (var star = 1; star <= 5; star++)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: '$star star${star == 1 ? '' : 's'}',
                          icon: Icon(star <= rating ? Icons.star : Icons.star_border, color: const Color(0xFFFBBF24)),
                          onPressed: () => setDialog(() => rating = star),
                        ),
                    ],
                  ),
                  TextField(
                    controller: textController,
                    maxLines: 4,
                    maxLength: 4000,
                    decoration: const InputDecoration(labelText: 'What the guest said', isDense: true, counterText: ''),
                    onChanged: (_) {
                      if (error != null) setDialog(() => error = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: source,
                    decoration: const InputDecoration(labelText: 'Source', isDense: true),
                    items: [for (final s in sources) DropdownMenuItem(value: s, child: Text(s))],
                    onChanged: (v) => setDialog(() => source = v ?? source),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: TextStyle(fontSize: 12, color: AppTheme.statusRed)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  if (textController.text.trim().isEmpty) {
                    setDialog(() => error = 'Enter the review text.');
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'reviewer_name': nameController.text.trim(),
                    'rating': rating,
                    'review_text': textController.text.trim(),
                    'source': source,
                  });
                },
                child: const Text('Save review'),
              ),
            ],
          ),
        );
      },
    );
    // The controllers are not disposed here: the dialog's closing animation still shows the fields.
    if (body == null || !mounted) return;
    await _reviewsAction(() async {
      await _api.createReview(body);
      await _loadReviews();
      return 'Review saved. Regenerate the summary to include it.';
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _app,
      builder: (context, _) => Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppTheme.border),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Handle Bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              _buildHeader(context),
              TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primary,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textMuted,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                tabs: const [
                  Tab(icon: Icon(Icons.chat_bubble_outline, size: 16), text: 'AI Copilot'),
                  Tab(icon: Icon(Icons.trending_up, size: 16), text: 'Demand (FR-10)'),
                  Tab(icon: Icon(Icons.star_outline, size: 16), text: 'Reviews (FR-08)'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCopilotTab(),
                    _buildDemandTab(),
                    _buildReviewsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final badgeColor = _online ? AppTheme.statusGreen : AppTheme.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primaryLight.withOpacity(0.4)),
            ),
            child: Icon(Icons.auto_awesome, color: AppTheme.primaryLight, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'SERVESYNC AI COPILOT',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: badgeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        _online ? 'CLOUD DATA' : 'OFFLINE',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: badgeColor),
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Consumption Analytics & Review Summary',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }

  // --- shared pieces ----------------------------------------------------------
  Widget _message(IconData icon, String title, String body, {VoidCallback? onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.35)),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 16), label: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _notice(String text, bool isError, VoidCallback onClose) {
    final color = isError ? AppTheme.statusRed : AppTheme.statusGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: AppTheme.textPrimary, height: 1.3))),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
            icon: Icon(Icons.close, size: 16, color: AppTheme.textMuted),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppTheme.textSecondary),
        ),
      );

  Widget _card({required Widget child, Color? borderColor, EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor ?? AppTheme.border),
        ),
        child: child,
      );

  Widget _engineLine(Map<String, dynamic> source, {String? generatedAt}) {
    final note = source['engine_note']?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Generated by: ${source['engine'] ?? 'unknown'}${generatedAt == null ? '' : ' on $generatedAt'}',
          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
        if (note != null && note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(note, style: TextStyle(fontSize: 11, color: AppTheme.statusYellow)),
          ),
      ],
    );
  }

  Widget _bullet(String text, {IconData icon = Icons.arrow_right_rounded, Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color ?? AppTheme.primaryLight),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: AppTheme.textPrimary, height: 1.35))),
          ],
        ),
      );

  // --- Copilot tab --------------------------------------------------------------
  Widget _buildCopilotTab() {
    return Column(
      children: [
        // Quick Prompts Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _buildPromptChip('📦 Restock Forecast', 'What ingredients should we reorder right now?'),
              _buildPromptChip('📉 Cut Food Waste', 'How much food waste did we have and where?'),
              _buildPromptChip('⭐ Guest Feedback', 'What are guests saying in their reviews?'),
              _buildPromptChip('⏱️ Who Is On Shift', 'Who is on shift right now?'),
            ],
          ),
        ),

        // Chat Message Log
        Expanded(
          child: ListView.builder(
            controller: _chatScroll,
            padding: const EdgeInsets.all(16),
            itemCount: _chatHistory.length + (_answering ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _chatHistory.length) {
                return Padding(
                  padding: const EdgeInsets.only(left: 38, bottom: 12),
                  child: Row(
                    children: [
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text('Reading live records...', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                );
              }
              final msg = _chatHistory[index];
              final isAssistant = msg['role'] == 'assistant';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: isAssistant ? AppTheme.primary.withOpacity(0.15) : AppTheme.surfaceElevated,
                      child: Icon(
                        isAssistant ? Icons.auto_awesome : Icons.person,
                        size: 14,
                        color: isAssistant ? AppTheme.primaryLight : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isAssistant ? AppTheme.surface : AppTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isAssistant ? AppTheme.primaryLight.withOpacity(0.2) : AppTheme.border,
                          ),
                        ),
                        child: Text(
                          msg['content'] ?? '',
                          style: TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textPrimary),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Prompt Input Field
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promptController,
                  decoration: InputDecoration(
                    hintText: 'Ask about stock, waste, reviews or shifts...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: AppTheme.border),
                    ),
                  ),
                  onSubmitted: _sendQuery,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                tooltip: 'Send',
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                onPressed: _answering ? null : () => _sendQuery(_promptController.text),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPromptChip(String label, String query) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        backgroundColor: AppTheme.surfaceElevated,
        side: BorderSide(color: AppTheme.border),
        label: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
        ),
        onPressed: () => _sendQuery(query),
      ),
    );
  }

  // --- Demand tab (FR-10) ---------------------------------------------------------
  Widget _buildDemandTab() {
    if (!_online) return _message(Icons.cloud_off_rounded, _offlineTitle, _offlineBody);
    if (_reportForbidden) {
      return _message(Icons.lock_outline_rounded, _forbiddenTitle,
          'Consumption analytics and purchasing recommendations are available to Manager and Administrator accounts.');
    }
    final report = _report;
    if (report == null) {
      if (_reportError != null) {
        return _message(Icons.error_outline_rounded, 'Could not load the consumption report', _reportError!, onRetry: _loadReport);
      }
      return const Center(child: CircularProgressIndicator());
    }

    final items = _maps(report['items']);
    final totals = report['totals'] is Map ? Map<String, dynamic>.from(report['totals'] as Map) : <String, dynamic>{};
    final recommendations = _strings(report['recommendations']);

    return RefreshIndicator(
      onRefresh: _loadReport,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Reporting period
          Row(
            children: [
              Text('Reporting period', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(width: 10),
              for (final days in const [7, 14, 30])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('$days days', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    selected: _days == days,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _changePeriod(days),
                  ),
                ),
              const Spacer(),
              if (_reportLoading)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Refresh',
                  icon: Icon(Icons.refresh, size: 18, color: AppTheme.textSecondary),
                  onPressed: _loadReport,
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (_demandNotice != null) _notice(_demandNotice!, _demandNoticeIsError, () => setState(() => _demandNotice = null)),

          // Summary banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppTheme.primary.withOpacity(0.12), AppTheme.surface]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.insights_rounded, color: AppTheme.primaryLight, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'FR-10: Consumption analytics, last ${report['period_days']} days',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.primaryLight),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${report['summary'] ?? ''}', style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.35)),
                const SizedBox(height: 8),
                _engineLine(report, generatedAt: _dateTimeText(report['generated_at'])),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Totals
          Row(
            children: [
              _totalTile('Critical', '${_id(totals['critical']) ?? 0}', AppTheme.statusRed),
              const SizedBox(width: 8),
              _totalTile('Reorder soon', '${_id(totals['reorder_soon']) ?? 0}', AppTheme.statusYellow),
              const SizedBox(width: 8),
              _totalTile('Healthy', '${_id(totals['healthy']) ?? 0}', AppTheme.statusGreen),
              const SizedBox(width: 8),
              _totalTile('Spoilage cost', _money(totals['spoilage_cost']), AppTheme.textPrimary),
            ],
          ),
          const SizedBox(height: 16),

          if (recommendations.isNotEmpty) ...[
            _sectionLabel('RECOMMENDATIONS'),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final r in recommendations) _bullet(r)],
              ),
            ),
            const SizedBox(height: 16),
          ],

          _sectionLabel('STOCK FORECAST BY ITEM (${items.length})'),
          if (items.isEmpty)
            _card(child: Text('There are no inventory items yet.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
          for (final item in items) ...[
            _buildForecastCard(item, _id(report['period_days']) ?? _days),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _totalTile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            FittedBox(child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color))),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _fact(String label, String value) => RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          children: [
            TextSpan(text: '$label '),
            TextSpan(text: value, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _buildForecastCard(Map<String, dynamic> item, int periodDays) {
    final unit = item['unit']?.toString() ?? '';
    final risk = item['risk']?.toString() ?? 'Healthy';
    final riskColor = _riskColor(risk);
    final daysLeft = item['days_of_stock_left'];
    final inventoryId = _id(item['inventory_id']);
    final canOrder = _n(item['recommended_order_quantity']) > 0 && inventoryId != null;
    final ordering = inventoryId != null && _orderingItemIds.contains(inventoryId);
    final trend = item['trend']?.toString() ?? 'Steady';
    final trendIcon = trend == 'Rising'
        ? Icons.trending_up_rounded
        : trend == 'Falling'
            ? Icons.trending_down_rounded
            : Icons.trending_flat_rounded;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${item['item_name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: riskColor, width: 0.8),
                ),
                child: Text(risk.toUpperCase(), style: TextStyle(color: riskColor, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _fact('On hand', '${_q(item['on_hand'])} $unit'),
              _fact('Reorder level', '${_q(item['reorder_level'])} $unit'),
              _fact('Average use', '${_q(item['average_daily_usage'])} $unit/day'),
              _fact('Used in $periodDays days', '${_q(item['used'])} $unit'),
              _fact('Spoiled', '${_q(item['spoiled'])} $unit'),
              _fact('On order', '${_q(item['on_order'])} $unit'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(trendIcon, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text('Usage $trend', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(width: 10),
              Text('•', style: TextStyle(color: AppTheme.textMuted)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  daysLeft == null
                      ? 'No usage recorded'
                      : '${_q(daysLeft)} days of stock left, runs out about ${_dayText(item['projected_stockout_date'])}',
                  style: TextStyle(fontSize: 12, color: daysLeft == null ? AppTheme.textMuted : riskColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppTheme.surfaceElevated, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 14, color: AppTheme.primaryLight),
                const SizedBox(width: 6),
                Expanded(child: Text('${item['action'] ?? ''}', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary))),
              ],
            ),
          ),
          if (canOrder) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: ordering ? null : () => _createPurchaseOrder(item),
                icon: ordering
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_shopping_cart_rounded, size: 16),
                label: Text(ordering ? 'Creating...' : 'Create purchase order', style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Reviews tab (FR-08) ----------------------------------------------------------
  Widget _stars(double rating, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final icon = rating >= i + 0.75
            ? Icons.star
            : rating >= i + 0.25
                ? Icons.star_half
                : Icons.star_border;
        return Icon(icon, size: size, color: const Color(0xFFFBBF24));
      }),
    );
  }

  Widget _buildReviewsTab() {
    if (!_online) return _message(Icons.cloud_off_rounded, _offlineTitle, _offlineBody);
    final listing = _reviews;
    if (listing == null) {
      if (_reviewsError != null) {
        return _message(Icons.error_outline_rounded, 'Could not load customer reviews', _reviewsError!, onRetry: _loadReviews);
      }
      return const Center(child: CircularProgressIndicator());
    }

    final reviews = _maps(listing['reviews']);
    final count = _id(listing['review_count']) ?? reviews.length;
    final average = _n(listing['average_rating']);
    final positive = _n(listing['positive_percent']);
    final breakdown = listing['rating_breakdown'] is Map ? Map<String, dynamic>.from(listing['rating_breakdown'] as Map) : <String, dynamic>{};
    final googleConnected = listing['google_connected'] == true;
    final sentimentColor = positive >= 70
        ? AppTheme.statusGreen
        : positive >= 40
            ? AppTheme.statusYellow
            : AppTheme.statusRed;

    return RefreshIndicator(
      onRefresh: _loadReviews,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_reviewsNotice != null) _notice(_reviewsNotice!, _reviewsNoticeIsError, () => setState(() => _reviewsNotice = null)),

          // Rating header
          _card(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GUEST SATISFACTION (FR-08)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.textMuted)),
                const SizedBox(height: 4),
                if (count == 0)
                  Text('No customer reviews have been recorded yet.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))
                else ...[
                  Row(
                    children: [
                      Text(average.toStringAsFixed(1), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 8),
                      _stars(average),
                      const Spacer(),
                      Text('$count review${count == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                  Text('${_q(positive)}% positive (4 or 5 stars)', style: TextStyle(fontSize: 12, color: sentimentColor)),
                  const SizedBox(height: 10),
                  for (var star = 5; star >= 1; star--)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          SizedBox(width: 30, child: Text('$star ★', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary))),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: count == 0 ? 0 : (_n(breakdown['$star']) / count).clamp(0.0, 1.0),
                                minHeight: 7,
                                backgroundColor: AppTheme.surfaceElevated,
                                color: const Color(0xFFFBBF24),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text('${_id(breakdown['$star']) ?? 0}',
                                textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(googleConnected ? Icons.link_rounded : Icons.link_off_rounded,
                        size: 14, color: googleConnected ? AppTheme.statusGreen : AppTheme.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        googleConnected
                            ? 'Google reviews: Connected'
                            : 'Google reviews: Unavailable (the Google connection is not set up on the server)',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _reviewsBusy ? null : _addReview,
                      icon: const Icon(Icons.rate_review_outlined, size: 16),
                      label: const Text('Add review', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton.icon(
                      onPressed: _reviewsBusy ? null : _importGoogle,
                      icon: const Icon(Icons.cloud_download_outlined, size: 16),
                      label: const Text('Import from Google', style: TextStyle(fontSize: 12)),
                    ),
                    if (_reviewsBusy || _reviewsLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _sectionLabel('AI REVIEW SUMMARY'),
          _buildSummarySection(),
          const SizedBox(height: 16),

          _sectionLabel('REVIEWS (${reviews.length})'),
          for (final review in reviews) ...[
            _buildReviewCard(review),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    if (_summaryForbidden) {
      return _card(
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 18, color: AppTheme.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$_forbiddenTitle to view the AI summary. The reviews below are visible to all staff.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.35)),
            ),
          ],
        ),
      );
    }
    final summary = _summary;
    if (summary == null) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _summaryError == null ? 'Loading the summary...' : 'The summary could not be loaded: $_summaryError',
              style: TextStyle(fontSize: 12, color: _summaryError == null ? AppTheme.textSecondary : AppTheme.statusRed),
            ),
            if (_summaryError != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _loadReviews, icon: const Icon(Icons.refresh, size: 16), label: const Text('Try again')),
            ],
          ],
        ),
      );
    }

    final strengths = _maps(summary['strengths']);
    final improvements = _maps(summary['improvements']);
    final actions = _strings(summary['recommended_actions']);
    final outOfDate = summary['is_out_of_date'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${summary['overview'] ?? ''}', style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.4)),
              const SizedBox(height: 8),
              _engineLine(summary, generatedAt: _dateTimeText(summary['generated_at'])),
              Text('Covers ${summary['review_count']} review(s).', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              if (outOfDate)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.update_rounded, size: 14, color: AppTheme.statusYellow),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Out of date: reviews have been added or imported since this summary was written.',
                            style: TextStyle(fontSize: 11, color: AppTheme.statusYellow)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _reviewsBusy ? null : _regenerateSummary,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Regenerate summary', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        for (final s in strengths) ...[
          const SizedBox(height: 10),
          _buildSentimentBullet(
            icon: Icons.thumb_up_alt_rounded,
            color: AppTheme.statusGreen,
            title: '${s['title'] ?? ''}',
            body: '${s['detail'] ?? ''}',
          ),
        ],
        for (final s in improvements) ...[
          const SizedBox(height: 10),
          _buildSentimentBullet(
            icon: Icons.warning_amber_rounded,
            color: AppTheme.statusYellow,
            title: '${s['title'] ?? ''}',
            body: '${s['detail'] ?? ''}',
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recommended actions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                for (final a in actions) _bullet(a, icon: Icons.check_circle_outline_rounded),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${review['reviewer_name'] ?? 'Guest'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              _stars(_n(review['rating']), size: 14),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${review['source'] ?? ''} • ${_dateTimeText(review['review_date'])}',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 6),
          Text('${review['review_text'] ?? ''}', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.35)),
        ],
      ),
    );
  }

  Widget _buildSentimentBullet({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 3),
                Text(body, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
