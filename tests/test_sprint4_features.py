"""ServeSync Sprint 4: automated tests for the features completed in this sprint.

Covers reservations (FR-7), customer reviews and summary (FR-8), stored customer
orders (FR-9), consumption analytics (FR-10), service issue status (FR-11),
hiring and onboarding (FR-12), payroll adjustment and pay rates (FR-4),
supplier and inventory management and purchase order cancellation (FR-1, FR-3).

Runs against a temporary SQLite database; no network access is needed.
    /usr/bin/python3 tests/test_sprint4_features.py
"""
import os, sys, tempfile, unittest
from datetime import timedelta
from decimal import Decimal
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'database'))
os.environ.pop('ANTHROPIC_API_KEY', None)  # tests use the built-in analysis engine
from service import Database, Service, APIError, now
from seed_database import seed_sqlite
from migrations import ensure_schema
import insights

SECRET = 'servesync-super-secret-lookup-key-2026-sprint3'
quiet = lambda *args: None


class Sprint4FeatureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
        self.tmp.close()
        sys.stdout = open(os.devnull, 'w')
        try:
            seed_sqlite(self.tmp.name)
        finally:
            sys.stdout.close()
            sys.stdout = sys.__stdout__
        self.db = Database(self.tmp.name)
        self.assertTrue(ensure_schema(self.db, log=quiet))
        self.svc = Service(self.db, SECRET)
        self.admin = self.svc.login({'pin': '1234'}, '10.0.0.1')['token']
        self.manager = self.svc.login({'pin': '2345'}, '10.0.0.2')['token']
        self.foh = self.svc.login({'pin': '4567'}, '10.0.0.3')['token']   # Sneha Patel, FOH Staff
        self.day = (now() + timedelta(days=1)).strftime('%Y-%m-%d')

    def tearDown(self):
        try: os.unlink(self.tmp.name)
        except OSError: pass

    def call(self, method, path, data=None, token=None):
        return self.svc.request(method, path, data or {}, token or self.admin)

    def fails(self, status, method, path, data=None, token=None):
        with self.assertRaises(APIError) as cm:
            self.call(method, path, data, token)
        self.assertEqual(cm.exception.status, status, cm.exception.message)
        return cm.exception.message

    def booking(self, **changes):
        data = {'guest_name': 'Dana Lee', 'phone_number': '404-555-0100', 'party_size': 4,
                'reservation_date': self.day, 'reservation_time': '18:00', 'table_number': 2}
        data.update(changes)
        return data

    # --- FR-7 ---------------------------------------------------------------
    def test_01_migration_is_repeatable(self):
        before = self.call('GET', '/reviews')['review_count']
        self.assertTrue(ensure_schema(self.db, log=quiet))
        self.assertEqual(self.call('GET', '/reviews')['review_count'], before)
        self.assertEqual(len(self.call('GET', '/tables')['records']), 8)

    def test_02_reservation_create_list_and_default_end_time(self):
        r = self.call('POST', '/reservations', self.booking(), self.foh)
        self.assertEqual((r['status'], r['reservation_time'], r['end_time']), ('Confirmed', '18:00', '19:30'))
        listed = self.call('GET', '/reservations', {'date': self.day}, self.foh)['records']
        self.assertEqual([x['reservation_id'] for x in listed], [r['reservation_id']])
        self.assertEqual(self.call('GET', '/reservations', {'date': '2030-01-01'})['records'], [])

    def test_03_reservation_validation(self):
        self.fails(400, 'POST', '/reservations', self.booking(guest_name=''))
        self.fails(400, 'POST', '/reservations', self.booking(party_size=0))
        self.fails(400, 'POST', '/reservations', self.booking(reservation_time='7pm'))
        self.fails(400, 'POST', '/reservations', self.booking(reservation_date='2020-01-01'))
        self.fails(400, 'POST', '/reservations', self.booking(party_size=5))       # table 2 seats 4
        self.fails(404, 'POST', '/reservations', self.booking(table_number=99))
        self.fails(401, 'GET', '/reservations', token='not-a-token')

    def test_04_reservation_double_booking_is_rejected(self):
        self.call('POST', '/reservations', self.booking())
        message = self.fails(409, 'POST', '/reservations', self.booking(reservation_time='19:00', guest_name='Sam'))
        self.assertIn('already reserved', message)
        # Same time on another table, and a later time on the same table, are both allowed.
        self.call('POST', '/reservations', self.booking(table_number=3))
        self.call('POST', '/reservations', self.booking(reservation_time='19:30'))

    def test_05_reservation_edit_and_status_flow(self):
        r = self.call('POST', '/reservations', self.booking())
        rid = r['reservation_id']
        edited = self.call('PATCH', f'/reservations/{rid}', {'party_size': 2, 'reservation_time': '20:00'})
        self.assertEqual((edited['party_size'], edited['reservation_time'], edited['end_time']), (2, '20:00', '21:30'))
        self.fails(400, 'POST', f'/reservations/{rid}/status', {'status': 'Finished'})
        self.assertEqual(self.call('POST', f'/reservations/{rid}/status', {'status': 'Seated'})['status'], 'Seated')
        self.fails(409, 'POST', f'/reservations/{rid}/status', {'status': 'Cancelled'})
        self.fails(409, 'PATCH', f'/reservations/{rid}', {'party_size': 3})
        # A cancelled reservation frees its time slot.
        other = self.call('POST', '/reservations', self.booking(table_number=4))
        self.call('POST', f"/reservations/{other['reservation_id']}/status", {'status': 'Cancelled'})
        self.call('POST', '/reservations', self.booking(table_number=4, guest_name='Replacement'))
        self.fails(404, 'POST', '/reservations/9999/status', {'status': 'No-Show'})

    # --- FR-9 ---------------------------------------------------------------
    def test_06_order_is_stored_and_uses_inventory(self):
        inv = {i['item_name']: Decimal(str(i['quantity'])) for i in self.call('GET', '/inventory')}
        order = self.call('POST', '/orders', {'table_number': 2, 'items': [
            {'name': 'ServeSync Smash Burger', 'quantity': 2, 'modifications': 'Seat 1: no onions'},
            {'name': 'Craft Cold Brew & Tonic', 'quantity': 1}]}, self.foh)
        self.assertEqual(order['subtotal'], '42.00')
        self.assertEqual(order['tax'], '3.47')            # 8.25 %
        self.assertEqual(Decimal(str(order['total_amount'])), Decimal('45.47'))
        self.assertEqual(order['server_name'], 'Sneha Patel')
        self.assertEqual(len(order['items']), 2)
        after = {i['item_name']: Decimal(str(i['quantity'])) for i in self.call('GET', '/inventory')}
        self.assertEqual(inv['Brioche Buns'] - after['Brioche Buns'], Decimal('2'))       # 1 bun per burger
        self.assertEqual(inv['Angus Beef Patties'] - after['Angus Beef Patties'], Decimal('1'))
        self.assertEqual(self.call('GET', '/orders', {'status': 'Active'})['records'][0]['order_id'], order['order_id'])
        table = [t for t in self.call('GET', '/tables')['records'] if t['table_number'] == 2][0]
        self.assertEqual(table['status'], 'Occupied')

    def test_07_order_validation_and_completion(self):
        self.fails(400, 'POST', '/orders', {'table_number': 2, 'items': []})
        self.fails(404, 'POST', '/orders', {'table_number': 2, 'items': [{'name': 'Lobster Roll'}]})
        self.fails(400, 'POST', '/orders', {'table_number': 2, 'items': [{'name': 'Crispy Calamari', 'quantity': 0}]})
        self.fails(404, 'POST', '/orders', {'table_number': 77, 'items': [{'name': 'Crispy Calamari'}]})
        order = self.call('POST', '/orders', {'table_number': 3, 'items': [{'name': 'Crispy Calamari'}]})
        self.fails(400, 'POST', f"/orders/{order['order_id']}/complete", {'payment_method': 'Bitcoin'})
        done = self.call('POST', f"/orders/{order['order_id']}/complete", {'payment_method': 'Cash'})
        self.assertEqual((done['order_status'], done['payment_method']), ('Completed', 'Cash'))
        self.fails(409, 'POST', f"/orders/{order['order_id']}/cancel")
        table = [t for t in self.call('GET', '/tables')['records'] if t['table_number'] == 3][0]
        self.assertEqual(table['status'], 'Available')

    def test_19_kitchen_tickets_are_shared_through_the_api(self):
        self.assertEqual(self.call('GET', '/kitchen/tickets', token=self.foh)['records'], [])
        first = self.call('POST', '/orders', {'table_number': 2, 'items': [
            {'name': 'ServeSync Smash Burger', 'quantity': 2, 'modifications': 'Seat 1: no onions'}]}, self.foh)
        second = self.call('POST', '/orders', {'table_number': 3, 'items': [{'name': 'Crispy Calamari'}]}, self.foh)
        # Another employee (another device) sees both tickets, oldest first.
        tickets = self.call('GET', '/kitchen/tickets', token=self.manager)['records']
        self.assertEqual([(t['order_id'], t['kitchen_status'], t['table_number']) for t in tickets],
                         [(first['order_id'], 'New', 2), (second['order_id'], 'New', 3)])
        self.assertEqual(tickets[0]['items'][0]['modifications'], 'Seat 1: no onions')
        path = f"/orders/{first['order_id']}/kitchen-status"
        self.fails(400, 'POST', path, {'status': 'Cooking'}, self.manager)
        self.fails(409, 'POST', path, {'status': 'Ready'}, self.manager)                 # cannot skip In Prep
        self.assertEqual(self.call('POST', path, {'status': 'In Prep'}, self.manager)['kitchen_status'], 'In Prep')
        self.assertEqual(self.call('POST', path, {'status': 'In Prep'}, self.foh)['kitchen_status'], 'In Prep')  # repeat is harmless
        self.call('POST', path, {'status': 'Ready'}, self.manager)
        seen = {t['order_id']: t['kitchen_status'] for t in self.call('GET', '/kitchen/tickets', token=self.foh)['records']}
        self.assertEqual(seen, {first['order_id']: 'Ready', second['order_id']: 'New'})
        self.call('POST', path, {'status': 'Served'}, self.manager)
        self.assertEqual([t['order_id'] for t in self.call('GET', '/kitchen/tickets')['records']], [second['order_id']])
        self.assertEqual(self.call('GET', '/orders', {'status': 'Active'})['records'][-1]['order_id'], first['order_id'])  # still open until paid
        self.call('POST', f"/orders/{second['order_id']}/cancel")
        self.assertEqual(self.call('GET', '/kitchen/tickets')['records'], [])
        self.fails(409, 'POST', f"/orders/{second['order_id']}/kitchen-status", {'status': 'In Prep'})
        self.fails(404, 'POST', '/orders/999/kitchen-status', {'status': 'In Prep'})

    # --- FR-8 ---------------------------------------------------------------
    def test_08_reviews_list_and_create(self):
        listing = self.call('GET', '/reviews', token=self.foh)
        self.assertEqual(listing['review_count'], 12)
        self.assertEqual(listing['average_rating'], 4.0)
        self.assertFalse(listing['google_connected'])
        self.fails(400, 'POST', '/reviews', {'rating': 6, 'review_text': 'x'})
        self.fails(400, 'POST', '/reviews', {'rating': 4, 'review_text': ''})
        self.fails(400, 'POST', '/reviews', {'rating': 4, 'review_text': 'Nice', 'source': 'Yelp'})
        made = self.call('POST', '/reviews', {'reviewer_name': 'Walk-in guest', 'rating': 5,
                                              'review_text': 'Great burger and friendly staff.'}, self.foh)
        self.assertEqual(made['source'], 'In-App')
        self.assertEqual(self.call('GET', '/reviews')['review_count'], 13)

    def test_09_review_summary(self):
        self.fails(403, 'GET', '/reviews/summary', token=self.foh)
        summary = self.call('GET', '/reviews/summary', token=self.manager)
        self.assertEqual(summary['engine'], insights.BUILT_IN_ENGINE)
        self.assertEqual((summary['review_count'], summary['average_rating'], summary['positive_percent']), (12, 4.0, 75))
        self.assertEqual(summary['rating_breakdown'], {'5': 6, '4': 3, '3': 1, '2': 1, '1': 1})
        self.assertTrue(summary['strengths'] and summary['improvements'] and summary['recommended_actions'])
        self.assertIn('Wait time', ' '.join(i['title'] for i in summary['improvements']))
        self.assertFalse(summary['is_out_of_date'])
        self.call('POST', '/reviews', {'rating': 1, 'review_text': 'Slow service and cold food.'})
        self.assertTrue(self.call('GET', '/reviews/summary')['is_out_of_date'])
        fresh = self.call('POST', '/reviews/summary', token=self.manager)
        self.assertEqual(fresh['review_count'], 13)
        self.assertFalse(fresh['is_out_of_date'])

    def test_10_google_import_reports_unavailable_when_not_connected(self):
        self.fails(403, 'POST', '/reviews/import-google', token=self.foh)
        message = self.fails(503, 'POST', '/reviews/import-google', token=self.manager)
        self.assertIn('not connected', message)

    # --- FR-10 --------------------------------------------------------------
    def test_11_consumption_forecast(self):
        self.fails(403, 'GET', '/analytics/consumption', token=self.foh)
        self.fails(400, 'GET', '/analytics/consumption', {'days': '0'}, self.manager)
        report = self.call('GET', '/analytics/consumption', {'days': '14'}, self.manager)
        self.assertEqual(report['period_days'], 14)
        self.assertEqual(report['engine'], insights.BUILT_IN_ENGINE)
        self.assertEqual(len(report['items']), 6)
        for item in report['items']:
            self.assertGreater(item['used'], 0)                     # sample usage history is read
            self.assertGreater(item['average_daily_usage'], 0)
            self.assertAlmostEqual(item['days_of_stock_left'], item['on_hand'] / (item['used'] / 14), delta=0.06)
            self.assertIn(item['risk'], ('Critical', 'Reorder soon', 'Healthy'))
        self.assertTrue(report['summary'])

    def test_12_forecast_reacts_to_real_usage_and_open_orders(self):
        def item(name):
            report = self.call('GET', '/analytics/consumption', {'days': '14'}, self.manager)
            return [i for i in report['items'] if i['item_name'] == name][0]
        before = item('Brioche Buns')
        for _ in range(3):
            self.call('POST', '/orders', {'table_number': 1, 'items': [{'name': 'ServeSync Smash Burger', 'quantity': 10}]})
        after = item('Brioche Buns')
        self.assertAlmostEqual(after['used'] - before['used'], 30, places=2)
        self.assertAlmostEqual(before['on_hand'] - after['on_hand'], 30, places=2)
        self.assertLess(after['days_of_stock_left'], before['days_of_stock_left'])
        # Stock pushed below the reorder level is flagged with an order quantity ...
        inv = [i for i in self.call('GET', '/inventory') if i['item_name'] == 'Brioche Buns'][0]
        self.call('PATCH', f"/inventory/{inv['inventory_id']}", {'quantity': 5, 'reason': 'Stock count'}, self.manager)
        low = item('Brioche Buns')
        self.assertEqual(low['risk'], 'Critical')
        self.assertGreater(low['recommended_order_quantity'], 0)
        # ... and an open purchase order for it reduces the quantity still to order.
        supplier = self.call('GET', '/suppliers')[0]
        self.call('POST', '/purchase-orders', {'supplier_id': supplier['supplier_id'], 'items': [
            {'inventory_id': inv['inventory_id'], 'quantity_ordered': 40, 'unit_cost': 0.85}]}, self.manager)
        covered = item('Brioche Buns')
        self.assertEqual(covered['on_order'], 40)
        self.assertEqual(low['recommended_order_quantity'] - covered['recommended_order_quantity'], 40)

    # --- FR-1 / FR-3 --------------------------------------------------------
    def test_13_supplier_management(self):
        new = {'supplier_name': 'Peachtree Dairy', 'contact_person': 'Ann Cole', 'phone_number': '404-555-0144',
               'email': 'orders@peachtreedairy.com', 'product_category': 'Dairy'}
        self.fails(403, 'POST', '/suppliers', new, self.foh)
        self.fails(400, 'POST', '/suppliers', dict(new, email='not-an-email'), self.manager)
        made = self.call('POST', '/suppliers', new, self.manager)
        self.fails(409, 'POST', '/suppliers', new, self.manager)
        changed = self.call('PATCH', f"/suppliers/{made['supplier_id']}", {'phone_number': '404-555-0999'}, self.manager)
        self.assertEqual((changed['phone_number'], changed['contact_person']), ('404-555-0999', 'Ann Cole'))
        self.fails(404, 'PATCH', '/suppliers/999', {'phone_number': '404-555-0000'}, self.manager)

    def test_14_purchase_order_cancellation(self):
        self.fails(403, 'POST', '/purchase-orders/1/cancel', token=self.foh)
        cancelled = self.call('POST', '/purchase-orders/1/cancel', token=self.manager)
        self.assertEqual(cancelled['status'], 'Cancelled')
        self.fails(409, 'POST', '/purchase-orders/1/cancel', token=self.manager)
        self.fails(400, 'POST', '/purchase-orders/1/receive', {'request_id': 'r1', 'received_items': [
            {'item_id': 1, 'quantity_received': 1}]}, self.manager)
        self.fails(404, 'POST', '/purchase-orders/999/cancel', token=self.manager)

    def test_15_inventory_item_management(self):
        new = {'item_name': 'Fresh Basil', 'category': 'Produce', 'quantity': 4, 'unit': 'bunches',
               'reorder_level': 2, 'unit_cost': 1.25}
        self.fails(403, 'POST', '/inventory', new, self.foh)
        self.fails(400, 'POST', '/inventory', dict(new, quantity=-1), self.manager)
        made = self.call('POST', '/inventory', new, self.manager)
        self.fails(409, 'POST', '/inventory', new, self.manager)
        path = f"/inventory/{made['inventory_id']}"
        self.fails(400, 'PATCH', path, {'quantity': 9}, self.manager)            # a reason is required
        changed = self.call('PATCH', path, {'quantity': 9, 'reason': 'Stock count', 'reorder_level': 3}, self.manager)
        self.assertEqual((Decimal(str(changed['quantity'])), Decimal(str(changed['reorder_level']))), (Decimal('9'), Decimal('3')))
        with self.db.transaction() as q:
            log = q.all('SELECT * FROM Inventory_Transactions WHERE inventory_id=%s ORDER BY transaction_id', (made['inventory_id'],))
        self.assertEqual([(Decimal(str(t['quantity_change'])), t['reason']) for t in log],
                         [(Decimal('4'), 'Manual adjustment: opening stock'), (Decimal('5'), 'Manual adjustment: Stock count')])

    # --- FR-4 / FR-5 --------------------------------------------------------
    def test_16_pay_rates_and_payroll_adjustment(self):
        users = {u['full_name']: u for u in self.call('GET', '/users')['users']}
        self.assertEqual(users['Salem Marye']['hourly_rate'], '28.00')
        self.assertEqual(users['Jamal Ford']['role'], 'Administrator')
        jamal = users['Sneha Patel']          # the FOH employee whose token is self.foh
        self.fails(400, 'PATCH', f"/users/{jamal['user_id']}", {'hourly_rate': -1})
        self.assertEqual(self.call('PATCH', f"/users/{jamal['user_id']}", {'hourly_rate': 18.25})['user']['hourly_rate'], '18.25')
        self.call('POST', '/clock-in', token=self.foh)
        self.fails(403, 'GET', '/payroll', token=self.manager)
        record = self.call('GET', '/payroll')['records'][0]
        self.assertEqual(Decimal(str(record['hourly_rate'])), Decimal('18.25'))      # shift uses the employee's own rate
        path = f"/payroll/{record['payroll_id']}"
        self.fails(409, 'PATCH', path, {'hours_worked': 5, 'reason': 'Forgot to clock out'})   # still open
        self.call('POST', '/clock-out', token=self.foh)
        self.fails(400, 'PATCH', path, {'hours_worked': 5})                                       # no reason
        self.fails(400, 'PATCH', path, {'hours_worked': 30, 'reason': 'Typo'})
        self.fails(403, 'PATCH', path, {'hours_worked': 5, 'reason': 'x y z'}, self.manager)
        fixed = self.call('PATCH', path, {'hours_worked': 5, 'reason': 'Forgot to clock in on time'})
        self.assertEqual((Decimal(str(fixed['gross_pay'])), fixed['adjustment_reason']), (Decimal('91.25'), 'Forgot to clock in on time'))
        paid = self.call('PATCH', path, {'payment_status': 'Paid', 'reason': 'Paid in weekly run'})
        self.assertEqual(paid['payment_status'], 'Paid')
        summary = [s for s in self.call('GET', '/payroll')['summary'] if s['full_name'] == 'Sneha Patel'][0]
        self.assertEqual((summary['hours'], summary['gross_pay'], summary['unpaid']), ('5.00', '91.25', '0.00'))

    # --- FR-12 --------------------------------------------------------------
    def test_17_hiring_pipeline_and_onboarding(self):
        applicants = self.call('GET', '/applicants')
        self.assertEqual(len(applicants), 2)
        aid = applicants[0]['applicant_id']
        self.fails(403, 'PATCH', f'/applicants/{aid}', {'application_status': 'Interview'}, self.manager)
        self.fails(400, 'PATCH', f'/applicants/{aid}', {'application_status': 'Maybe'})
        self.fails(400, 'PATCH', f'/applicants/{aid}', {'application_status': 'Hired'})
        self.fails(409, 'PATCH', f'/applicants/{aid}', {'onboarding_status': 'Complete'})
        moved = self.call('PATCH', f'/applicants/{aid}', {'application_status': 'Interview', 'notes': 'Strong references'})
        self.assertEqual((moved['application_status'], moved['notes']), ('Interview', 'Strong references'))
        self.fails(409, 'POST', f'/applicants/{aid}/hire', {'role': 'FOH Staff', 'pin': '1234'})   # PIN in use
        hired = self.call('POST', f'/applicants/{aid}/hire', {'role': 'FOH Staff', 'pin': '9081', 'hourly_rate': 17})
        self.assertEqual(hired['applicant']['application_status'], 'Hired')
        self.assertEqual(hired['applicant']['onboarding_status'], 'In Progress')
        self.assertEqual(hired['user']['hourly_rate'], '17.00')
        self.assertEqual(hired['applicant']['hired_user_id'], hired['user']['user_id'])
        # The new employee can sign in with the PIN chosen at hiring.
        self.assertEqual(self.svc.login({'pin': '9081'}, '10.0.0.9')['user']['full_name'], hired['applicant']['full_name'])
        self.fails(409, 'POST', f'/applicants/{aid}/hire', {'role': 'FOH Staff', 'pin': '9082'})
        done = self.call('PATCH', f'/applicants/{aid}', {'onboarding_status': 'Complete'})
        self.assertEqual(done['onboarding_status'], 'Complete')
        other = applicants[1]['applicant_id']
        self.call('PATCH', f'/applicants/{other}', {'application_status': 'Rejected'})
        self.fails(409, 'POST', f'/applicants/{other}/hire', {'role': 'FOH Staff', 'pin': '9083'})

    # --- FR-11 --------------------------------------------------------------
    def test_18_service_issue_status(self):
        issue = self.call('POST', '/service-issues', {'category': 'Food Quality', 'description': 'Cold soup'}, self.foh)
        path = f"/service-issues/{issue['issue_id']}/status"
        self.fails(403, 'POST', path, {'status': 'In Progress'}, self.foh)
        self.assertEqual(self.call('POST', path, {'status': 'In Progress'}, self.manager)['status'], 'In Progress')
        self.fails(400, 'POST', path, {'status': 'Resolved'}, self.manager)          # notes required
        self.fails(400, 'POST', path, {'status': 'Closed'}, self.manager)
        resolved = self.call('POST', path, {'status': 'Resolved', 'resolution_notes': 'Replaced and comped.'}, self.manager)
        self.assertEqual(resolved['status'], 'Resolved')
        self.assertIsNotNone(resolved['resolved_at'])
        self.fails(404, 'POST', '/service-issues/999/status', {'status': 'Open'}, self.manager)


    # --- FR-13 --------------------------------------------------------------
    def test_20_menu_management(self):
        menu = self.call('GET', '/menu', token=self.foh)['records']
        self.assertEqual(len(menu), 8)
        self.assertTrue(all(m['description'] for m in menu))
        new = {'item_name': 'Grilled Peach Salad', 'description': 'Arugula, goat cheese, pecans', 'category': 'Appetizers',
               'price': 13.5, 'available': True}
        self.fails(403, 'POST', '/menu', new, self.foh)
        self.fails(400, 'POST', '/menu', dict(new, item_name=''), self.manager)
        self.fails(400, 'POST', '/menu', dict(new, price=-1), self.manager)
        self.fails(400, 'POST', '/menu', dict(new, category=''), self.manager)
        made = self.call('POST', '/menu', new, self.manager)
        self.assertEqual((made['item_name'], Decimal(str(made['price'])), made['available']), ('Grilled Peach Salad', Decimal('13.5'), 1))
        self.fails(409, 'POST', '/menu', new, self.manager)                       # duplicate name
        # A new item can be ordered straight away.
        order = self.call('POST', '/orders', {'table_number': 1, 'items': [{'name': 'Grilled Peach Salad', 'quantity': 2}]}, self.foh)
        self.assertEqual(order['subtotal'], '27.00')
        path = f"/menu/{made['menu_item_id']}"
        edited = self.call('PATCH', path, {'description': 'Arugula, feta, pecans', 'category': 'Salads'}, self.manager)
        self.assertEqual((edited['description'], edited['category'], Decimal(str(edited['price']))), ('Arugula, feta, pecans', 'Salads', Decimal('13.5')))
        # An unavailable item stays on the menu list but cannot be ordered.
        self.call('PATCH', path, {'available': False}, self.manager)
        self.fails(409, 'POST', '/orders', {'table_number': 1, 'items': [{'name': 'Grilled Peach Salad'}]}, self.foh)
        self.call('PATCH', path, {'available': True}, self.manager)
        # Removing it takes it off the menu; the order already taken keeps its line.
        self.fails(403, 'DELETE', path, token=self.foh)
        self.call('DELETE', path, token=self.manager)
        self.assertNotIn('Grilled Peach Salad', [m['item_name'] for m in self.call('GET', '/menu')['records']])
        self.fails(404, 'POST', '/orders', {'table_number': 1, 'items': [{'name': 'Grilled Peach Salad'}]}, self.foh)
        self.fails(404, 'PATCH', path, {'price': 14}, self.manager)
        old = [o for o in self.call('GET', '/orders')['records'] if o['order_id'] == order['order_id']][0]
        self.assertEqual([(i['item_name'], i['quantity'], Decimal(str(i['unit_price']))) for i in old['items']],
                         [('Grilled Peach Salad', 2, Decimal('13.5'))])
        self.call('POST', '/menu', new, self.manager)                              # the name can be used again

    # --- FR-14 --------------------------------------------------------------
    def test_21_price_change_history(self):
        burger = [m for m in self.call('GET', '/menu')['records'] if m['item_name'] == 'ServeSync Smash Burger'][0]
        path = f"/menu/{burger['menu_item_id']}"
        before = self.call('POST', '/orders', {'table_number': 2, 'items': [{'name': 'ServeSync Smash Burger', 'quantity': 1}]})
        self.call('POST', f"/orders/{before['order_id']}/complete", {'payment_method': 'Card'})
        self.fails(403, 'PATCH', path, {'price': 19.5}, self.foh)
        self.fails(403, 'GET', '/menu/price-history', token=self.foh)
        self.fails(400, 'PATCH', path, {'price': 'free'}, self.manager)
        self.assertEqual(self.call('GET', '/menu/price-history', token=self.manager)['records'], [])
        self.call('PATCH', path, {'description': burger['description']}, self.manager)     # no price change: nothing recorded
        self.call('PATCH', path, {'price': 18}, self.manager)                              # same price: nothing recorded
        self.assertEqual(self.call('GET', '/menu/price-history', token=self.manager)['records'], [])
        self.call('PATCH', path, {'price': 19.5}, self.manager)
        self.call('PATCH', path, {'price': 21}, self.admin)
        history = self.call('GET', '/menu/price-history', {'menu_item_id': str(burger['menu_item_id'])}, self.manager)['records']
        self.assertEqual([(h['item_name'], Decimal(str(h['previous_price'])), Decimal(str(h['new_price'])), h['changed_by_name'])
                          for h in history],
                         [('ServeSync Smash Burger', Decimal('19.5'), Decimal('21'), 'Salem Marye'),
                          ('ServeSync Smash Burger', Decimal('18'), Decimal('19.5'), 'Kristian Napier')])
        self.assertTrue(all(h['changed_at'] for h in history))
        # New orders use the new price; the completed order keeps the price it was sold at.
        after = self.call('POST', '/orders', {'table_number': 2, 'items': [{'name': 'ServeSync Smash Burger', 'quantity': 1}]})
        self.assertEqual(after['subtotal'], '21.00')
        orders = {o['order_id']: o for o in self.call('GET', '/orders')['records']}
        self.assertEqual(Decimal(str(orders[before['order_id']]['items'][0]['unit_price'])), Decimal('18'))
        self.assertEqual(Decimal(str(orders[before['order_id']]['total_amount'])), Decimal('19.49'))

    # --- FR-15 --------------------------------------------------------------
    def test_22_delivery_platform_orders(self):
        for name in ('DOORDASH_WEBHOOK_SECRET', 'UBEREATS_WEBHOOK_SECRET', 'DOORDASH_STATUS_URL'):
            os.environ.pop(name, None)
        status = {p['name']: p for p in self.call('GET', '/delivery/status', token=self.foh)['platforms']}
        self.assertEqual({n: p['state'] for n, p in status.items()}, {'DoorDash': 'Not connected', 'Uber Eats': 'Not connected'})
        self.assertIn('Dine-in ordering is not affected', status['DoorDash']['detail'])
        incoming = {'external_order_id': 'DD-1001', 'customer_name': 'Ana P.', 'notes': 'Leave at door',
                    'items': [{'name': 'ServeSync Smash Burger', 'quantity': 2, 'modifications': 'No onions'},
                              {'name': 'Crispy Calamari', 'quantity': 1}]}
        # A platform that is not set up is refused, and dine-in ordering carries on.
        self.assertEqual(self._webhook('doordash', incoming, 'anything'), 503)
        self.call('POST', '/orders', {'table_number': 1, 'items': [{'name': 'Crispy Calamari'}]}, self.foh)
        os.environ['DOORDASH_WEBHOOK_SECRET'] = 'test-secret-for-doordash'
        try:
            self.assertEqual(self.call('GET', '/delivery/status')['platforms'][0]['state'], 'Connected')
            self.assertEqual(self._webhook('doordash', incoming, 'wrong-secret'), 401)
            self.assertEqual(self._webhook('grubhub', incoming, 'test-secret-for-doordash'), 404)
            self.assertEqual(self._webhook('doordash', dict(incoming, items=[{'name': 'Lobster Roll'}]), 'test-secret-for-doordash'), 404)
            buns = lambda: [Decimal(str(i['quantity'])) for i in self.call('GET', '/inventory') if i['item_name'] == 'Brioche Buns'][0]
            stock = buns()
            order = self.svc.request('POST', '/delivery/webhook/doordash', incoming, 'test-secret-for-doordash')
            self.assertEqual((order['source'], order['external_order_id'], order['customer_name'], order['table_number']),
                             ('DoorDash', 'DD-1001', 'Ana P.', None))
            self.assertEqual(order['subtotal'], '51.50')
            self.assertEqual(stock - buns(), Decimal('2'))                       # stock is deducted like any order
            again = self.svc.request('POST', '/delivery/webhook/doordash', incoming, 'test-secret-for-doordash')
            self.assertEqual(again['order_id'], order['order_id'])               # sent twice: saved once
            self.assertEqual(stock - buns(), Decimal('2'))
        finally:
            os.environ.pop('DOORDASH_WEBHOOK_SECRET', None)
        # The order is in the kitchen queue and in the delivery list, with its details.
        ticket = [t for t in self.call('GET', '/kitchen/tickets', token=self.foh)['records'] if t['order_id'] == order['order_id']][0]
        self.assertEqual((ticket['source'], ticket['kitchen_status'], len(ticket['items'])), ('DoorDash', 'New', 2))
        listed = self.call('GET', '/delivery/orders', token=self.foh)['records']
        self.assertEqual([(o['order_id'], o['delivery_notes']) for o in listed], [(order['order_id'], 'Leave at door')])
        path = f"/delivery/orders/{order['order_id']}/status"
        self.fails(400, 'POST', path, {'status': 'Delivered'}, self.foh)
        self.fails(409, 'POST', path, {'status': 'Picked Up'}, self.foh)          # not ready yet
        self.fails(404, 'POST', '/delivery/orders/1/status', {'status': 'In Prep'}, self.foh)   # order 1 is dine-in
        step = self.call('POST', path, {'status': 'In Prep'}, self.foh)
        self.assertEqual(step['kitchen_status'], 'In Prep')
        self.assertIn('not connected', step['platform_update'])
        self.call('POST', path, {'status': 'Ready'}, self.foh)
        done = self.call('POST', path, {'status': 'Picked Up'}, self.foh)
        self.assertEqual((done['order_status'], done['payment_method']), ('Completed', 'Platform'))
        self.fails(409, 'POST', path, {'status': 'Cancelled'}, self.foh)
        self.assertNotIn(order['order_id'], [t['order_id'] for t in self.call('GET', '/kitchen/tickets')['records']])
        # Test orders for demonstrations go through the same intake and are labelled.
        self.fails(403, 'POST', '/delivery/test-order', {'platform': 'ubereats'}, self.foh)
        self.fails(404, 'POST', '/delivery/test-order', {'platform': 'grubhub'}, self.manager)
        test = self.call('POST', '/delivery/test-order', {'platform': 'ubereats'}, self.manager)
        self.assertEqual(test['source'], 'Uber Eats')
        self.assertTrue(test['external_order_id'].startswith('TEST-'))
        cancelled = self.call('POST', f"/delivery/orders/{test['order_id']}/status", {'status': 'Cancelled'}, self.manager)
        self.assertEqual(cancelled['order_status'], 'Cancelled')
        self.assertIn('test order', cancelled['platform_update'])

    # --- AI Copilot ---------------------------------------------------------
    def test_23_copilot_question(self):
        self.fails(400, 'POST', '/copilot/ask', {'question': ''}, self.manager)
        message = self.fails(503, 'POST', '/copilot/ask', {'question': 'What should we reorder?'}, self.manager)
        self.assertIn('not connected', message)                                   # no API key in the test run
        seen = {}
        real = insights.ask_copilot

        def fake(question, history, context):
            seen.update(question=question, history=history, context=context)
            return 'Order tomatoes.', 'Claude (test double)'
        insights.ask_copilot = fake
        try:
            reply = self.call('POST', '/copilot/ask', {'question': 'What should we reorder?', 'history': [
                {'role': 'assistant', 'content': 'Hello'}, {'role': 'user', 'content': 'Hi'},
                {'role': 'assistant', 'content': 'How can I help?'}, {'role': 'system', 'content': 'ignored'}]}, self.manager)
            self.assertEqual(reply, {'answer': 'Order tomatoes.', 'engine': 'Claude (test double)'})
            self.assertEqual([t['role'] for t in seen['history']], ['user', 'assistant'])     # starts with the user
            manager_context = seen['context']
            self.assertEqual(manager_context['asked_by'], {'name': 'Kristian Napier', 'role': 'Manager'})
            self.assertEqual(len(manager_context['stock_forecast_last_14_days']), 6)
            self.assertEqual(manager_context['customer_reviews']['review_count'], 12)
            self.assertEqual(len(manager_context['menu']), 8)
            self.assertNotIn('staff_clocked_in', manager_context)                  # administrators only
            self.call('POST', '/copilot/ask', {'question': 'Is the burger available?'}, self.foh)
            foh_context = seen['context']
            self.assertEqual(foh_context['asked_by']['role'], 'FOH Staff')
            self.assertIn('menu', foh_context)
            for manager_only in ('stock_forecast_last_14_days', 'customer_reviews', 'delivery_platforms', 'staff_clocked_in'):
                self.assertNotIn(manager_only, foh_context)
            self.call('POST', '/clock-in', token=self.foh)
            self.call('POST', '/copilot/ask', {'question': 'Who is working?'}, self.admin)
            self.assertEqual([p['name'] for p in seen['context']['staff_clocked_in']], ['Sneha Patel'])
            json_size = len(__import__('json').dumps(seen['context'], default=str))
            self.assertLess(json_size, 20000)                                      # the data block stays small
        finally:
            insights.ask_copilot = real

    def test_24_gemini_is_used_when_its_key_is_set(self):
        import urllib.error, io, json as js
        calls = []
        real = insights._http_json

        def reply(text):
            return {'candidates': [{'content': {'parts': [{'text': text}]}, 'finishReason': 'STOP'}],
                    'modelVersion': 'gemini-3.8-flash'}

        def fake(url, body, headers, timeout):
            calls.append((url, body, headers))
            if 'gemini-flash-latest' in url:                       # the alias is not available: next model is tried
                raise urllib.error.HTTPError(url, 404, 'Not Found', {}, io.BytesIO(b'{"error": {"message": "model not found"}}'))
            if body['generationConfig']['responseMimeType'] == 'application/json':
                return reply('```json\n{"overview": "Guests like the burger.", "strengths": [], "improvements": [], '
                             '"recommended_actions": ["Add staff on Fridays."]}\n```')
            return reply('Order tomatoes today.')
        os.environ['GEMINI_API'] = 'test-key-not-real'
        insights._http_json = fake
        try:
            self.assertEqual(insights.ai_status()['provider'], 'gemini')
            answer = self.call('POST', '/copilot/ask', {'question': 'What should we reorder?', 'history': [
                {'role': 'user', 'content': 'Hi'}, {'role': 'assistant', 'content': 'Hello'}]}, self.manager)
            self.assertEqual(answer, {'answer': 'Order tomatoes today.', 'engine': 'Gemini (gemini-3.8-flash)'})
            url, body, headers = calls[-1]
            self.assertIn('/models/gemini-3.8-flash:generateContent', url)
            self.assertEqual(headers, {'x-goog-api-key': 'test-key-not-real'})
            self.assertNotIn('test-key-not-real', url)                                # the key is never put in the URL
            self.assertEqual([c['role'] for c in body['contents']], ['user', 'model', 'user'])
            self.assertIn('Restaurant data (JSON)', body['contents'][-1]['parts'][0]['text'])
            self.assertTrue(body['systemInstruction']['parts'][0]['text'].startswith('You are the ServeSync Copilot'))
            summary = self.call('POST', '/reviews/summary', token=self.manager)
            self.assertEqual((summary['engine'], summary['overview']), ('Gemini (gemini-3.8-flash)', 'Guests like the burger.'))
            self.assertEqual(summary['average_rating'], 4.0)                           # figures still come from the database

            def failing(url, body, headers, timeout):
                raise urllib.error.HTTPError(url, 400, 'Bad Request', {}, io.BytesIO(b'{"error": {"message": "API key not valid."}}'))
            insights._http_json = failing
            message = self.fails(503, 'POST', '/copilot/ask', {'question': 'Hi'}, self.manager)
            self.assertIn('the Gemini API returned error 400: API key not valid.', message)
            fallback = self.call('POST', '/reviews/summary', token=self.manager)
            self.assertEqual(fallback['engine'], insights.BUILT_IN_ENGINE)             # summaries fall back, with the reason
            self.assertIn('API key not valid', fallback['engine_note'])
        finally:
            insights._http_json = real
            os.environ.pop('GEMINI_API', None)
        self.assertIsNone(insights.ai_status()['provider'])

    # --- Sign in here instead (session take-over) ----------------------------
    def test_25_sign_in_here_ends_the_other_session(self):
        # Kristian (manager) is already signed in from setUp; a second sign-in is refused as before.
        with self.assertRaises(APIError) as refused:
            self.svc.login({'pin': '2345'}, '10.0.0.8')
        self.assertEqual(refused.exception.status, 409)
        self.assertEqual(self.call('GET', '/me', token=self.manager)['user']['full_name'], 'Kristian Napier')
        # A wrong PIN with take_over signs nobody in and ends nothing.
        with self.assertRaises(APIError) as wrong:
            self.svc.login({'pin': '9999', 'take_over': True}, '10.0.0.8')
        self.assertEqual(wrong.exception.status, 401)
        self.call('GET', '/me', token=self.manager)
        # With the right PIN and take_over, the new device is signed in and the old session ends.
        self.call('POST', '/clock-in', token=self.manager)
        fresh = self.svc.login({'pin': '2345', 'take_over': True}, '10.0.0.8')
        self.assertEqual(fresh['user']['full_name'], 'Kristian Napier')
        self.assertTrue(fresh['shift_status']['is_clocked_in'])                    # the open shift is untouched
        self.fails(401, 'GET', '/me', token=self.manager)                          # old device is signed out
        self.call('GET', '/me', token=fresh['token'])
        self.call('GET', '/me', token=self.admin)                                  # other employees are unaffected
        # take_over with no other session is an ordinary sign-in.
        self.call('POST', '/logout', token=fresh['token'])
        self.assertIn('token', self.svc.login({'pin': '2345', 'take_over': True}, '10.0.0.8'))

    def _webhook(self, platform, body, secret):
        try:
            self.svc.request('POST', f'/delivery/webhook/{platform}', body, secret)
            return 200
        except APIError as err:
            return err.status


if __name__ == '__main__':
    unittest.main(verbosity=2)
