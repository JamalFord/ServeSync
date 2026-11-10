import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servesync/screens/inventory/inventory_spoilage_screen.dart';
import 'package:servesync/screens/manage/customer_service_screen.dart';
import 'package:servesync/screens/manage/hiring_screen.dart';
import 'package:servesync/screens/manage/manage_hub_screen.dart';
import 'package:servesync/screens/manage/payroll_screen.dart';
import 'package:servesync/screens/manage/reservations_screen.dart';
import 'package:servesync/screens/shell/main_shell_screen.dart';
import 'package:servesync/screens/manage/suppliers_screen.dart';
import 'package:servesync/screens/manage/user_accounts_screen.dart';
import 'package:servesync/services/api_client.dart';
import 'package:servesync/services/app_state.dart';
import 'package:servesync/theme/app_theme.dart';

/// Widget tests for the Manage screens. The API is replaced by a mock that
/// returns rows in the same shape as the ServeSync REST API (DECIMALs as
/// strings, timestamps as naive UTC) and records the requests it receives.
class FakeApi {
  final List<http.Request> requests = [];
  int? failStatus;
  String failMessage = '';

  late final ApiClient client = ApiClient(
    baseUrl: 'http://api.test',
    client: MockClient((req) async {
      requests.add(req);
      if (failStatus != null && req.method != 'GET') {
        return http.Response(jsonEncode({'error': failMessage}), failStatus!);
      }
      return http.Response(jsonEncode(_reply(req)), 200, headers: {'content-type': 'application/json'});
    }),
  );

  http.Request last(String method) => requests.lastWhere((r) => r.method == method);
  Map<String, dynamic> lastBody(String method) => jsonDecode(last(method).body) as Map<String, dynamic>;

  Object _reply(http.Request req) {
    final path = req.url.path;
    if (req.method != 'GET') {
      if (path.endsWith('/hire')) {
        return {
          'applicant': {'applicant_id': 1, 'application_status': 'Hired'},
          'user': {'user_id': 9, 'full_name': 'Riley Chen', 'role': 'FOH Staff', 'account_status': 'Active', 'hourly_rate': '17.00'},
        };
      }
      if (path.startsWith('/users')) {
        return {
          'user': {'user_id': 3, 'full_name': 'Jamal Ford', 'role': 'FOH Staff', 'account_status': 'Active', 'hourly_rate': '16.50'},
        };
      }
      return {'ok': true};
    }
    switch (path) {
      case '/tables':
        return {
          'records': [
            {'table_number': 2, 'capacity': 4, 'status': 'Available'},
            {'table_number': 7, 'capacity': 8, 'status': 'Available'},
          ],
        };
      case '/reservations':
        return {
          'records': [
            {
              'reservation_id': 5, 'guest_name': 'Dana Lee', 'phone_number': '404-555-0100', 'party_size': 4,
              'reservation_date': '2026-11-10', 'reservation_time': '18:00', 'end_time': '19:30',
              'table_number': 2, 'status': 'Confirmed', 'notes': 'Birthday', 'created_by': 1,
            },
            {
              'reservation_id': 6, 'guest_name': 'Omar Farouk', 'phone_number': '404-555-0101', 'party_size': 6,
              'reservation_date': '2026-11-10', 'reservation_time': '12:30', 'end_time': '14:00',
              'table_number': 7, 'status': 'Seated', 'notes': null, 'created_by': 1,
            },
          ],
        };
      case '/service-issues':
        return [
          {
            'issue_id': 2, 'category': 'Billing', 'description': 'Charged twice for a dessert.',
            'customer_contact': '404-555-0166', 'status': 'Open', 'reported_at': '2026-11-09 23:10:00',
            'resolution_notes': null, 'assigned_to_name': null,
          },
          {
            'issue_id': 1, 'category': 'Order Accuracy', 'description': 'Wrong entree at table 5.',
            'customer_contact': 'guest5@example.com', 'status': 'Resolved', 'reported_at': '2026-11-08 20:00:00',
            'resolution_notes': 'Replaced and comped.', 'assigned_to_name': 'Kristian Napier',
          },
        ];
      case '/suppliers':
        return [
          {
            'supplier_id': 1, 'supplier_name': 'Metro Farm Produce Co.', 'contact_person': 'Dave Miller',
            'phone_number': '404-555-0199', 'email': 'orders@metrofarm.com', 'product_category': 'Fresh Produce & Herbs',
          },
        ];
      case '/users':
        return {
          'users': [
            {'user_id': 1, 'full_name': 'Salem Marye', 'role': 'Administrator', 'account_status': 'Active', 'hourly_rate': '28.00'},
            {'user_id': 3, 'full_name': 'Jamal Ford', 'role': 'FOH Staff', 'account_status': 'Active', 'hourly_rate': '16.50'},
            {'user_id': 4, 'full_name': 'Sneha Patel', 'role': 'FOH Staff', 'account_status': 'Inactive', 'hourly_rate': '16.50'},
          ],
        };
      case '/payroll':
        return {
          'records': [
            {
              'payroll_id': 12, 'user_id': 3, 'full_name': 'Jamal Ford', 'role': 'FOH Staff',
              'clock_in': '2026-11-09 15:00:00', 'clock_out': null, 'hours_worked': null, 'hourly_rate': '16.50',
              'gross_pay': null, 'payment_status': 'Pending', 'adjustment_reason': null,
            },
            {
              'payroll_id': 11, 'user_id': 3, 'full_name': 'Jamal Ford', 'role': 'FOH Staff',
              'clock_in': '2026-11-08 15:00:00', 'clock_out': '2026-11-08 20:00:00', 'hours_worked': '5.00',
              'hourly_rate': '16.50', 'gross_pay': '82.50', 'payment_status': 'Pending',
              'adjustment_reason': 'Forgot to clock in on time',
            },
          ],
          'summary': [
            {
              'user_id': 3, 'full_name': 'Jamal Ford', 'role': 'FOH Staff', 'shifts': 2, 'open_shifts': 1,
              'hours': '5.00', 'gross_pay': '82.50', 'unpaid': '82.50',
            },
          ],
          'employees': [
            {'user_id': 3, 'full_name': 'Jamal Ford', 'role': 'FOH Staff', 'account_status': 'Active', 'hourly_rate': '16.50'},
            {'user_id': 1, 'full_name': 'Salem Marye', 'role': 'Administrator', 'account_status': 'Active', 'hourly_rate': '28.00'},
          ],
        };
      case '/applicants':
        return [
          {
            'applicant_id': 2, 'full_name': 'Andre Wallace', 'email': 'andre.wallace@example.com',
            'phone_number': '404-555-0122', 'applied_position': 'Line Cook', 'availability': 'Full time',
            'years_experience': 4, 'application_status': 'Hired', 'created_at': '2026-11-01 14:00:00',
            'notes': 'Strong references', 'hired_user_id': 8, 'onboarding_status': 'In Progress',
          },
          {
            'applicant_id': 1, 'full_name': 'Riley Chen', 'email': 'riley.chen@example.com',
            'phone_number': '404-555-0111', 'applied_position': 'Server', 'availability': 'Evenings and weekends',
            'years_experience': 2, 'application_status': 'New', 'created_at': '2026-11-05 14:00:00',
            'notes': null, 'hired_user_id': null, 'onboarding_status': 'Not Started',
          },
        ];
    }
    return {'records': []};
  }
}

Future<void> pumpScreen(WidgetTester tester, Widget screen, {Size size = const Size(390, 844)}) async {
  // Phone-sized by default, so layout overflows on small devices fail the test.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.themeData, home: screen));
  await tester.pumpAndSettle();
}

/// Scrolls the widget into view (lists build lazily and may be wider or taller than the phone), then taps it.
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder fieldLabelled(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
      matching: find.byType(TextField),
    );

void main() {
  final app = AppState.instance;
  final admin = app.employees.firstWhere((e) => e.role == 'Administrator');
  final manager = app.employees.firstWhere((e) => e.role == 'Manager');
  final foh = app.employees.firstWhere((e) => e.role == 'FOH Staff');

  tearDown(() {
    app.isBackendOnline = false;
    app.switchEmployee(manager);
  });

  testWidgets('Manage hub hides administrator modules from other roles and needs the cloud', (tester) async {
    app.switchEmployee(foh);
    await pumpScreen(tester, const ManageHubScreen());
    expect(find.text('Reservations'), findsOneWidget);
    expect(find.text('Customer Service'), findsOneWidget);
    expect(find.text('Suppliers'), findsOneWidget);
    expect(find.text('Payroll'), findsNothing);
    expect(find.text('Hiring'), findsNothing);
    expect(find.text('User Accounts'), findsNothing);
    expect(find.textContaining('need the ServeSync cloud connection'), findsOneWidget);

    // Offline: tapping a tile does nothing.
    await tester.tap(find.text('Reservations'));
    await tester.pumpAndSettle();
    expect(find.byType(ReservationsScreen), findsNothing);

    app.switchEmployee(admin);
    await tester.pumpAndSettle();
    for (final title in ['User Accounts', 'Payroll', 'Hiring']) {
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('Reservations: lists the day, seats a guest, and books a table', (tester) async {
    final api = FakeApi();
    await pumpScreen(tester, ReservationsScreen(api: api.client));
    expect(find.text('Dana Lee'), findsOneWidget);
    expect(find.text('6:00 PM – 7:30 PM'), findsOneWidget);
    expect(find.text('2 active · 10 guests'), findsNothing); // shown together with the date
    expect(find.textContaining('2 active · 10 guests'), findsOneWidget);
    // Sorted by time: the 12:30 reservation comes first.
    expect(tester.getTopLeft(find.text('Omar Farouk')).dy, lessThan(tester.getTopLeft(find.text('Dana Lee')).dy));
    // Only the Confirmed reservation has actions.
    expect(find.text('Seat'), findsOneWidget);

    await tapOn(tester, find.text('Seat'));
    expect(api.last('POST').url.path, '/reservations/5/status');
    expect(api.lastBody('POST'), {'status': 'Seated'});

    await tapOn(tester, find.text('New reservation'));
    await tapOn(tester, find.text('Book table'));
    expect(find.text('Guest name is required.'), findsOneWidget);

    await tester.enterText(fieldLabelled('Guest name'), 'Sam Ortiz');
    await tester.enterText(fieldLabelled('Phone number'), '404-555-0123');
    await tester.enterText(fieldLabelled('Party size'), '3');
    await tapOn(tester, find.byType(DropdownButtonFormField<int>));
    await tapOn(tester, find.text('Table 2 (seats 4)').last);
    await tapOn(tester, find.text('Book table'));
    final sent = api.requests.lastWhere((r) => r.method == 'POST' && r.url.path == '/reservations');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['guest_name'], 'Sam Ortiz');
    expect(body['party_size'], 3);
    expect(body['table_number'], 2);
    expect(body['reservation_time'], '18:00');
    expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(body['reservation_date'] as String), isTrue);
    expect(find.text('New reservation'), findsOneWidget); // dialog closed, back on the list
  });

  testWidgets('Reservations: a double-booking error from the server is shown as written', (tester) async {
    final api = FakeApi();
    await pumpScreen(tester, ReservationsScreen(api: api.client));
    api
      ..failStatus = 409
      ..failMessage = 'Table 2 is already reserved from 18:00 to 19:30 for Dana Lee.';
    await tapOn(tester, find.text('New reservation'));
    await tester.enterText(fieldLabelled('Guest name'), 'Sam Ortiz');
    await tester.enterText(fieldLabelled('Phone number'), '404-555-0123');
    await tapOn(tester, find.byType(DropdownButtonFormField<int>));
    await tapOn(tester, find.text('Table 2 (seats 4)').last);
    await tapOn(tester, find.text('Book table'));
    expect(find.text('Table 2 is already reserved from 18:00 to 19:30 for Dana Lee.'), findsOneWidget);
    expect(find.text('Book table'), findsOneWidget); // the form stays open for correction
  });

  testWidgets('Customer service: search, filter, and resolve needs notes', (tester) async {
    final api = FakeApi();
    app.switchEmployee(manager);
    await pumpScreen(tester, CustomerServiceScreen(api: api.client));
    expect(find.text('Billing'), findsOneWidget);
    expect(find.text('Order Accuracy'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'dessert');
    await tester.pumpAndSettle();
    expect(find.text('Billing'), findsOneWidget);
    expect(find.text('Order Accuracy'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();

    await tapOn(tester, find.text('Resolved (1)'));
    expect(find.text('Billing'), findsNothing);
    expect(find.text('Reopen'), findsOneWidget);
    await tapOn(tester, find.text('All (2)'));

    await tapOn(tester, find.text('Resolve'));
    await tapOn(tester, find.text('Mark resolved'));
    expect(find.text('Resolution notes are required to resolve an issue.'), findsOneWidget);
    await tester.enterText(fieldLabelled('Resolution notes (required)'), 'Refunded the second charge.');
    await tapOn(tester, find.text('Mark resolved'));
    expect(api.last('POST').url.path, '/service-issues/2/status');
    expect(api.lastBody('POST'), {'status': 'Resolved', 'resolution_notes': 'Refunded the second charge.'});
  });

  testWidgets('Customer service: front-of-house staff can log but not change status', (tester) async {
    final api = FakeApi();
    app.switchEmployee(foh);
    await pumpScreen(tester, CustomerServiceScreen(api: api.client));
    expect(find.text('Resolve'), findsNothing);
    expect(find.text('Start'), findsNothing);
    await tapOn(tester, find.text('Log issue'));
    await tester.enterText(fieldLabelled('What happened'), 'Soup arrived cold.');
    await tapOn(tester, find.text('Log issue').last);
    expect(api.last('POST').url.path, '/service-issues');
    expect(api.lastBody('POST')['category'], 'Food Quality');
    expect(api.lastBody('POST')['description'], 'Soup arrived cold.');
  });

  testWidgets('Suppliers: managers can edit, other staff can only view', (tester) async {
    final api = FakeApi();
    app.switchEmployee(foh);
    await pumpScreen(tester, SuppliersScreen(api: api.client));
    expect(find.text('Metro Farm Produce Co.'), findsOneWidget);
    expect(find.text('orders@metrofarm.com'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Add supplier'), findsNothing);

    app.switchEmployee(manager);
    await pumpScreen(tester, SuppliersScreen(api: api.client, key: UniqueKey()));
    await tapOn(tester, find.text('Edit'));
    await tester.enterText(fieldLabelled('Phone number'), '404-555-0999');
    await tapOn(tester, find.text('Save changes'));
    expect(api.last('PATCH').url.path, '/suppliers/1');
    expect(api.lastBody('PATCH')['phone_number'], '404-555-0999');
    expect(api.lastBody('PATCH')['contact_person'], 'Dave Miller');
  });

  testWidgets('User accounts: validates the PIN, never shows one, and deactivates after confirmation', (tester) async {
    final api = FakeApi();
    app.switchEmployee(admin);
    await pumpScreen(tester, UserAccountsScreen(api: api.client));
    expect(find.text('3 ACCOUNTS · 2 ACTIVE'), findsOneWidget);
    expect(find.text('\$28.00 / hour'), findsOneWidget);
    expect(find.text('Reactivate'), findsOneWidget); // the inactive account

    await tapOn(tester, find.text('Add user'));
    await tester.enterText(fieldLabelled('Full name'), 'Casey Brooks');
    await tester.enterText(fieldLabelled('Access PIN'), '12');
    await tapOn(tester, find.text('Create account'));
    expect(find.text('The PIN must be exactly four digits.'), findsOneWidget);
    await tester.enterText(fieldLabelled('Access PIN'), '7421');
    expect(tester.widget<TextField>(fieldLabelled('Access PIN')).obscureText, isTrue);
    await tapOn(tester, find.text('Create account'));
    expect(api.last('POST').url.path, '/users');
    expect(api.lastBody('POST'), {'full_name': 'Casey Brooks', 'role': 'FOH Staff', 'pin': '7421', 'hourly_rate': 16.5});
    expect(find.text('7421'), findsNothing);
    await tapOn(tester, find.text('Deactivate').first);
    expect(find.text('Deactivate account?'), findsOneWidget);
    await tapOn(tester, find.text('Deactivate').last);
    expect(api.last('PATCH').url.path, '/users/1');
    expect(api.lastBody('PATCH'), {'account_status': 'Inactive'});
  });

  testWidgets('Payroll: open shifts cannot be adjusted and an adjustment needs a reason', (tester) async {
    final api = FakeApi();
    app.switchEmployee(admin);
    await pumpScreen(tester, PayrollScreen(api: api.client));
    expect(find.text('\$82.50'), findsNWidgets(4)); // both totals, and Gross and Unpaid on the employee card
    expect(find.text('2 (1 open)'), findsOneWidget);
    expect(find.text('5.00 h × \$16.50 = \$82.50'), findsOneWidget);
    expect(find.text('Last change: Forgot to clock in on time'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    expect(find.text('Adjust'), findsOneWidget); // only on the closed shift
    await tapOn(tester, find.text('Adjust'));
    await tester.enterText(fieldLabelled('Hours worked'), '6');
    await tapOn(tester, find.text('Save adjustment'));
    expect(find.text('A reason for the adjustment is required.'), findsOneWidget);
    await tester.enterText(fieldLabelled('Reason (required)'), 'Stayed late to close');
    await tapOn(tester, find.text('Save adjustment'));
    expect(api.last('PATCH').url.path, '/payroll/11');
    expect(api.lastBody('PATCH'), {'hours_worked': 6.0, 'hourly_rate': 16.5, 'reason': 'Stayed late to close'});
    await tapOn(tester, find.text('Mark paid'));
    await tapOn(tester, find.text('Mark paid').last);
    expect(api.lastBody('PATCH'), {'payment_status': 'Paid', 'reason': 'Paid'});
    await tapOn(tester, find.text('Rate').first);
    await tester.enterText(fieldLabelled('Hourly rate (\$)'), '18.25');
    await tapOn(tester, find.text('Save rate'));
    expect(api.last('PATCH').url.path, '/users/3');
    expect(api.lastBody('PATCH'), {'hourly_rate': 18.25});
  });

  testWidgets('Hiring: stage change, hire creates an account, onboarding is set for hired applicants', (tester) async {
    final api = FakeApi();
    app.switchEmployee(admin);
    await pumpScreen(tester, HiringScreen(api: api.client));
    expect(find.text('Riley Chen'), findsOneWidget);
    expect(find.text('Andre Wallace'), findsOneWidget);
    expect(find.text('ONBOARDING'), findsOneWidget); // only for the hired applicant
    expect(find.text('Hire'), findsOneWidget); // only for the applicant not yet hired
    await tapOn(tester, find.text('Complete'));
    expect(api.last('PATCH').url.path, '/applicants/2');
    expect(api.lastBody('PATCH'), {'onboarding_status': 'Complete'});
    await tapOn(tester, find.text('Interview').last);
    expect(api.last('PATCH').url.path, '/applicants/1');
    expect(api.lastBody('PATCH'), {'application_status': 'Interview'});
    await tapOn(tester, find.text('Hire'));
    await tapOn(tester, find.text('Hire and create account'));
    expect(find.text('The PIN must be exactly four digits.'), findsOneWidget);
    await tester.enterText(fieldLabelled('Access PIN for the new account'), '9081');
    await tester.enterText(fieldLabelled('Hourly rate (\$)'), '17');
    await tapOn(tester, find.text('Hire and create account'));
    expect(api.last('POST').url.path, '/applicants/1/hire');
    expect(api.lastBody('POST'), {'role': 'FOH Staff', 'pin': '9081', 'hourly_rate': 17.0});
    expect(find.textContaining('Staff account created for Riley Chen'), findsOneWidget);
  });

  testWidgets('Shell has a Manage tab that opens the hub', (tester) async {
    await pumpScreen(tester, const MainShellScreen(), size: const Size(900, 1200));
    expect(find.byType(ManageHubScreen), findsNothing); // built, but not the visible tab yet
    await tapOn(tester, find.text('Manage').last);
    expect(find.byType(ManageHubScreen), findsOneWidget);
    expect(find.text('RESTAURANT ADMINISTRATION').hitTestable(), findsOneWidget);
  });

  testWidgets('Inventory (offline demo data): add an item, adjust stock with a reason, cancel a pending order', (tester) async {
    app.switchEmployee(manager);
    await pumpScreen(tester, const InventorySpoilageScreen(), size: const Size(900, 1200));

    await tapOn(tester, find.text('Add item'));
    await tester.enterText(fieldLabelled('Item name'), 'Fresh Basil');
    await tester.enterText(fieldLabelled('Category'), 'Produce');
    await tester.enterText(fieldLabelled('Unit'), 'bunches');
    await tester.enterText(fieldLabelled('Reorder level'), '2');
    await tester.enterText(fieldLabelled('Unit cost (\$)'), 'abc');
    await tapOn(tester, find.text('Add item').last);
    expect(find.text('Reorder level, unit cost and quantity must be numbers.'), findsOneWidget);
    await tester.enterText(fieldLabelled('Unit cost (\$)'), '1.25');
    await tester.enterText(fieldLabelled('Opening quantity'), '4');
    await tapOn(tester, find.text('Add item').last);
    final basil = app.inventory.firstWhere((i) => i.name == 'Fresh Basil');
    expect((basil.quantity, basil.unit, basil.reorderLevel, basil.unitCost), (4.0, 'bunches', 2.0, 1.25));

    // Changing the quantity of an existing item needs a reason.
    final beef = app.inventory.firstWhere((i) => i.name == 'Ground Angus Beef');
    await tapOn(tester, find.byTooltip('Edit item').first);
    expect(find.text('Edit ${app.inventory.first.name}'), findsOneWidget);
    await tester.enterText(fieldLabelled('Quantity on hand'), '30');
    await tapOn(tester, find.text('Save changes'));
    expect(find.text('A reason is required to adjust the stock quantity.'), findsOneWidget);
    await tester.enterText(fieldLabelled('Reason for quantity change (required if the quantity changes)'), 'Stock count');
    await tapOn(tester, find.text('Save changes'));
    expect(app.inventory.firstWhere((i) => i.id == beef.id).quantity, 30.0);

    // UC-05 "Remove Order": only the pending order offers Cancel.
    await tapOn(tester, find.text('Supplier Orders'));
    expect(find.text('Cancel order'), findsOneWidget);
    await tapOn(tester, find.text('Cancel order'));
    expect(find.text('Cancel PO-2026-081?'), findsOneWidget);
    await tapOn(tester, find.text('Cancel order').last);
    expect(app.supplierOrders.firstWhere((o) => o.id == 'PO-2026-081').status, 'Cancelled');
    expect(find.text('CANCELLED'), findsOneWidget);
    expect(find.text('Cancel order'), findsNothing);

    // Front-of-house staff get neither action.
    app.switchEmployee(foh);
    await tester.pumpAndSettle();
    await tapOn(tester, find.text('On-Hand Stock'));
    expect(find.text('Add item'), findsNothing);
    expect(find.byTooltip('Edit item'), findsNothing);
  });

  testWidgets('A screen shows the server error and a retry button when loading fails', (tester) async {
    final api = ApiClient(
      baseUrl: 'http://api.test',
      client: MockClient((_) async => http.Response(jsonEncode({'error': 'Administrator access required.'}), 403)),
    );
    await pumpScreen(tester, PayrollScreen(api: api));
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
