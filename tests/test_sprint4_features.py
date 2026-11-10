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
        self.foh = self.svc.login({'pin': '3456'}, '10.0.0.3')['token']
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
        self.assertEqual(order['server_name'], 'Jamal Ford')
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
        jamal = users['Jamal Ford']
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
        summary = [s for s in self.call('GET', '/payroll')['summary'] if s['full_name'] == 'Jamal Ford'][0]
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


if __name__ == '__main__':
    unittest.main(verbosity=2)
