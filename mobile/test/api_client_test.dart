import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servesync/services/api_client.dart';

ApiClient clientReturning(int status, Object body, {void Function(http.Request)? onRequest}) {
  return ApiClient(
    baseUrl: 'http://api.test',
    client: MockClient((req) async {
      onRequest?.call(req);
      return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
    }),
  );
}

void main() {
  test('login posts the PIN and returns token, user and shift status', () async {
    late http.Request sent;
    final api = clientReturning(200, {
      'token': 'abc',
      'user': {'user_id': 2, 'full_name': 'Kristian Napier', 'role': 'Manager', 'account_status': 'Active'},
      'shift_status': {'is_clocked_in': false, 'clock_in_time': null},
    }, onRequest: (r) => sent = r);

    final res = await api.login('2345');

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'http://api.test/login');
    expect(jsonDecode(sent.body), {'pin': '2345'});
    expect(res['token'], 'abc');
  });

  test('authenticated calls send the bearer token', () async {
    late http.Request sent;
    final api = clientReturning(200, {'is_clocked_in': true}, onRequest: (r) => sent = r)..token = 'tok123';
    await api.shiftStatus();
    expect(sent.headers['Authorization'], 'Bearer tok123');
  });

  test('wrong PIN (401) is a real answer, not an outage', () async {
    final api = clientReturning(401, {'error': 'Invalid Code'});
    await expectLater(
      api.login('9999'),
      throwsA(isA<ApiException>()
          .having((e) => e.status, 'status', 401)
          .having((e) => e.message, 'message', 'Invalid Code')
          .having((e) => e.isUnavailable, 'isUnavailable', false)),
    );
  });

  test('already-signed-in (409) is surfaced to the user', () async {
    final api = clientReturning(409, {'error': 'Employee already has an active session.'});
    await expectLater(
      api.login('2345'),
      throwsA(isA<ApiException>().having((e) => e.isUnavailable, 'isUnavailable', false)),
    );
  });

  test('database failure (500) triggers offline demo mode', () async {
    final api = clientReturning(500, {'error': 'Database or server error. Please retry.'});
    await expectLater(
      api.login('1234'),
      throwsA(isA<ApiException>().having((e) => e.isUnavailable, 'isUnavailable', true)),
    );
  });

  test('unreachable server triggers offline demo mode', () async {
    final api = ApiClient(
      baseUrl: 'http://api.test',
      client: MockClient((_) async => throw http.ClientException('connection refused')),
    );
    await expectLater(
      api.login('1234'),
      throwsA(isA<ApiException>()
          .having((e) => e.status, 'status', 0)
          .having((e) => e.isUnavailable, 'isUnavailable', true)),
    );
  });

  test('list endpoints decode JSON arrays', () async {
    final api = clientReturning(200, [
      {'inventory_id': 1, 'item_name': 'Ground Angus Beef', 'quantity': '38.50'},
    ])..token = 't';
    final rows = await api.inventory();
    expect(rows.single['item_name'], 'Ground Angus Beef');
  });
}
