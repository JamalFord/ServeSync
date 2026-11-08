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

  /// Bearer token for the current session, set after a successful login.
  String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await _client.send(req).timeout(_timeout));
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
