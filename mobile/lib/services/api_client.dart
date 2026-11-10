import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin client for the ServeSync REST API (Python server on Railway, MySQL).
///
/// The base URL defaults to the production Railway deployment and can be
/// overridden at build time, e.g. for a local backend:
///   flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080
class ApiClient {
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://servesync-production-d1da.up.railway.app',
  );

  ApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? defaultBaseUrl,
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 10);

  /// The review summary and consumption report may wait on the AI service, which can take up to a minute.
  static const Duration _aiTimeout = Duration(seconds: 70);

  /// Bearer token for the current session, set after a successful login.
  String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(String method, String path, [Map<String, dynamic>? body, Duration timeout = _timeout]) async {
    final uri = Uri.parse('$baseUrl$path');
    final http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await _client.send(req).timeout(timeout));
    } on TimeoutException {
      throw const ApiException.network('The ServeSync server did not respond in time.');
    } catch (e) {
      throw ApiException.network('Could not reach the ServeSync server ($e).');
    }

    dynamic decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      decoded = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    final message = decoded is Map && decoded['error'] is String
        ? decoded['error'] as String
        : 'Server error (${res.statusCode}).';
    throw ApiException(res.statusCode, message);
  }

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send('POST', path, body ?? const {});
  Future<dynamic> patch(String path, Map<String, dynamic> body) => _send('PATCH', path, body);

  Future<Map<String, dynamic>> _getMap(String path) async => Map<String, dynamic>.from(await get(path) as Map);
  Future<Map<String, dynamic>> _postMap(String path, [Map<String, dynamic>? body]) async =>
      Map<String, dynamic>.from(await post(path, body) as Map);
  Future<Map<String, dynamic>> _patchMap(String path, Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(await patch(path, body) as Map);
  Future<List<Map<String, dynamic>>> _records(String path) async => _list((await _getMap(path))['records']);

  // --- Auth & shifts (UC-01) -----------------------------------------------
  Future<Map<String, dynamic>> login(String pin) async =>
      Map<String, dynamic>.from(await post('/login', {'pin': pin}) as Map);
  Future<void> logout() async => post('/logout');
  Future<Map<String, dynamic>> shiftStatus() async =>
      Map<String, dynamic>.from(await get('/shift-status') as Map);
  Future<Map<String, dynamic>> clockIn() async =>
      Map<String, dynamic>.from(await post('/clock-in') as Map);
  Future<Map<String, dynamic>> clockOut() async =>
      Map<String, dynamic>.from(await post('/clock-out') as Map);

  // --- Inventory & spoilage (UC-11, UC-04) ---------------------------------
  Future<List<Map<String, dynamic>>> inventory() async => _list(await get('/inventory'));
  Future<List<Map<String, dynamic>>> spoilageHistory() async => _list(await get('/inventory/spoilage'));
  Future<Map<String, dynamic>> recordSpoilage(Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(await post('/inventory/spoilage', body) as Map);

  // --- Suppliers & purchase orders (UC-05) ---------------------------------
  Future<List<Map<String, dynamic>>> suppliers() async => _list(await get('/suppliers'));
  Future<List<Map<String, dynamic>>> purchaseOrders() async => _list(await get('/purchase-orders'));
  Future<Map<String, dynamic>> createPurchaseOrder(Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(await post('/purchase-orders', body) as Map);
  Future<Map<String, dynamic>> receiveDelivery(int orderId, Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(await post('/purchase-orders/$orderId/receive', body) as Map);

  Future<Map<String, dynamic>> cancelPurchaseOrder(int orderId) => _postMap('/purchase-orders/$orderId/cancel');
  Future<Map<String, dynamic>> createSupplier(Map<String, dynamic> body) => _postMap('/suppliers', body);
  Future<Map<String, dynamic>> updateSupplier(int id, Map<String, dynamic> body) => _patchMap('/suppliers/$id', body);

  // --- Inventory items (FR-3). A quantity change needs a 'reason'. -----------
  Future<Map<String, dynamic>> createInventoryItem(Map<String, dynamic> body) => _postMap('/inventory', body);
  Future<Map<String, dynamic>> updateInventoryItem(int id, Map<String, dynamic> body) => _patchMap('/inventory/$id', body);

  // --- Reservations (FR-7, UC-03) -------------------------------------------
  /// [date] is YYYY-MM-DD; omit it to list every reservation.
  Future<List<Map<String, dynamic>>> reservations({String? date}) =>
      _records(date == null ? '/reservations' : '/reservations?date=$date');
  Future<List<Map<String, dynamic>>> diningTables() => _records('/tables');
  Future<Map<String, dynamic>> createReservation(Map<String, dynamic> body) => _postMap('/reservations', body);
  Future<Map<String, dynamic>> updateReservation(int id, Map<String, dynamic> body) => _patchMap('/reservations/$id', body);
  /// [status] is Seated, Cancelled or No-Show.
  Future<Map<String, dynamic>> setReservationStatus(int id, String status) =>
      _postMap('/reservations/$id/status', {'status': status});

  // --- Customer orders (FR-9, UC-02) ----------------------------------------
  /// body: {table_number, items: [{name, quantity, modifications}]}. Prices come from the server menu.
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> body) => _postMap('/orders', body);
  Future<List<Map<String, dynamic>>> orders({String? status}) =>
      _records(status == null ? '/orders' : '/orders?status=${Uri.encodeQueryComponent(status)}');
  Future<Map<String, dynamic>> completeOrder(int id, {String paymentMethod = 'Card'}) =>
      _postMap('/orders/$id/complete', {'payment_method': paymentMethod});
  Future<Map<String, dynamic>> cancelOrder(int id) => _postMap('/orders/$id/cancel');

  /// Open kitchen tickets, oldest first, the same for every device. Each is an order with
  /// kitchen_status (New | In Prep | Ready), table_number, server_name, order_time and items.
  Future<List<Map<String, dynamic>>> kitchenTickets() => _records('/kitchen/tickets');
  /// [status] is In Prep, Ready or Served; a ticket moves one step at a time.
  Future<Map<String, dynamic>> setKitchenStatus(int orderId, String status) =>
      _postMap('/orders/$orderId/kitchen-status', {'status': status});

  // --- Customer reviews and AI summary (FR-8, UC-07) ------------------------
  /// Returns {reviews: [...], review_count, average_rating, rating_breakdown, positive_percent,
  /// google_connected, ai_connected}.
  Future<Map<String, dynamic>> reviews() => _getMap('/reviews');
  /// body: {reviewer_name, rating 1-5, review_text, source: In-App | Comment Card | Phone | Google}
  Future<Map<String, dynamic>> createReview(Map<String, dynamic> body) => _postMap('/reviews', body);
  /// Manager/Administrator. Returns {overview, strengths: [{title, detail}], improvements: [{title, detail}],
  /// recommended_actions: [..], engine, engine_note?, generated_at, is_out_of_date, review_count,
  /// average_rating, positive_percent, rating_breakdown}.
  Future<Map<String, dynamic>> reviewSummary() async =>
      Map<String, dynamic>.from(await _send('GET', '/reviews/summary', null, _aiTimeout) as Map);
  Future<Map<String, dynamic>> regenerateReviewSummary() async =>
      Map<String, dynamic>.from(await _send('POST', '/reviews/summary', const {}, _aiTimeout) as Map);
  /// Throws ApiException(503) with a readable message when Google is not connected on the server.
  Future<Map<String, dynamic>> importGoogleReviews() => _postMap('/reviews/import-google');

  // --- Consumption analytics (FR-10, UC-06) ---------------------------------
  /// Manager/Administrator. Returns {period_days, generated_at, engine, engine_note?, summary,
  /// recommendations: [..], totals: {critical, reorder_soon, healthy, spoilage_cost}, items: [{inventory_id,
  /// item_name, unit, on_hand, reorder_level, used, spoiled, average_daily_usage, trend,
  /// days_of_stock_left (null when no usage), projected_stockout_date, on_order, risk
  /// (Critical | Reorder soon | Healthy), recommended_order_quantity, suggested_supplier
  /// ({supplier_id, supplier_name} or null), unit_cost, action}]}.
  Future<Map<String, dynamic>> consumptionReport({int days = 14}) async =>
      Map<String, dynamic>.from(await _send('GET', '/analytics/consumption?days=$days', null, _aiTimeout) as Map);

  // --- Customer service issues (FR-11, UC-12) -------------------------------
  Future<List<Map<String, dynamic>>> serviceIssues() async => _list(await get('/service-issues'));
  /// body: {category, description, customer_contact}
  Future<Map<String, dynamic>> createServiceIssue(Map<String, dynamic> body) => _postMap('/service-issues', body);
  /// Manager/Administrator. [status] is Open, In Progress or Resolved (Resolved needs notes).
  Future<Map<String, dynamic>> setServiceIssueStatus(int id, String status, {String notes = ''}) =>
      _postMap('/service-issues/$id/status', {'status': status, 'resolution_notes': notes});

  // --- Hiring and onboarding (FR-12, UC-10). Administrator only. ------------
  Future<List<Map<String, dynamic>>> applicants() async => _list(await get('/applicants'));
  /// body: {full_name, email, phone_number, applied_position, availability, years_experience}
  Future<Map<String, dynamic>> createApplicant(Map<String, dynamic> body) => _postMap('/applicants', body);
  /// body may hold application_status (New | Reviewed | Interview | Rejected), notes,
  /// onboarding_status (Not Started | In Progress | Complete; only after hiring).
  Future<Map<String, dynamic>> updateApplicant(int id, Map<String, dynamic> body) => _patchMap('/applicants/$id', body);
  /// Creates the staff account. body: {role, pin (4 digits), hourly_rate}. Returns {applicant, user}.
  Future<Map<String, dynamic>> hireApplicant(int id, Map<String, dynamic> body) => _postMap('/applicants/$id/hire', body);

  // --- User accounts (FR-2, UC-08). Administrator only. ---------------------
  /// Each user: {user_id, full_name, role, account_status, hourly_rate}.
  Future<List<Map<String, dynamic>>> users() async => _list((await _getMap('/users'))['users']);
  /// body: {full_name, role, pin, hourly_rate}
  Future<Map<String, dynamic>> createUser(Map<String, dynamic> body) async =>
      Map<String, dynamic>.from((await _postMap('/users', body))['user'] as Map);
  /// body may hold full_name, role, account_status (Active | Inactive), pin, hourly_rate.
  Future<Map<String, dynamic>> updateUser(int id, Map<String, dynamic> body) async =>
      Map<String, dynamic>.from((await _patchMap('/users/$id', body))['user'] as Map);
  Future<void> endUserSession(int id) async => post('/users/$id/end-session');

  // --- Payroll (FR-4, UC-09). Administrator only. ---------------------------
  /// Returns {records: [{payroll_id, user_id, full_name, role, clock_in, clock_out, hours_worked,
  /// hourly_rate, gross_pay, payment_status, adjustment_reason}], summary: [{user_id, full_name, role,
  /// shifts, open_shifts, hours, gross_pay, unpaid}], employees: [{user_id, full_name, role, hourly_rate}]}.
  Future<Map<String, dynamic>> payroll() => _getMap('/payroll');
  /// body: {reason (required), hours_worked?, hourly_rate?, payment_status? (Pending | Paid | Pending Correction)}
  Future<Map<String, dynamic>> adjustPayroll(int id, Map<String, dynamic> body) => _patchMap('/payroll/$id', body);

  static List<Map<String, dynamic>> _list(dynamic value) =>
      (value as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

class ApiException implements Exception {
  /// HTTP status code, or 0 when the server could not be reached at all.
  final int status;
  final String message;

  const ApiException(this.status, this.message);
  const ApiException.network(this.message) : status = 0;

  /// Network failures and server-side (5xx) errors mean the backend is
  /// unusable right now, so the app should fall back to offline demo mode.
  bool get isUnavailable => status == 0 || status >= 500;

  @override
  String toString() => 'ApiException($status): $message';
}
