"""ServeSync Sprint 3: Automated Verification Test Suite.
Validates all backend and business logic for Sprint 3:
1. UC-01: Authentication & Explicit Shift Clock-In/Clock-Out (Client Requirement: logout does not clock out).
2. UC-05: Supplier PO Creation & Atomic Delivery Receiving (Sprint 3 Native Feature A).
3. UC-11: Spoilage Logging & Atomic Stock Deduction (Sprint 3 Native Feature B).
4. UC-10: Job Applicants & Hiring Status Management (Sprint 3 Database Case).
5. UC-12: Customer Service Issues & Resolution Notes (Sprint 3 Database Case).
6. Security: RBAC permissions (FOH denied administrative mutations) and Idempotency guarantees.
"""
import os, sys, tempfile, unittest
from decimal import Decimal
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'database'))
from service import Database, Service, APIError, now, stamp
from seed_database import seed_sqlite

SECRET = 'servesync-super-secret-lookup-key-2026-sprint3'

class Sprint3BackendTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
        self.tmp.close()
        seed_sqlite(self.tmp.name)
        self.db = Database(self.tmp.name)
        self.svc = Service(self.db, SECRET)

    def tearDown(self):
        try: os.unlink(self.tmp.name)
        except OSError: pass

    def test_01_authentication_and_explicit_clock_in_out(self):
        """Test UC-01: Login, Explicit Clock-In, Logout (preserves shift), Re-login, Explicit Clock-Out."""
        # 1. Login with Admin PIN (1234)
        login_res = self.svc.login({'pin': '1234'}, '127.0.0.1')
        token = login_res['token']
        self.assertEqual(login_res['user']['role'], 'Administrator')
        self.assertFalse(login_res['shift_status']['is_clocked_in'])

        # 2. Explicit Clock-In
        clock_in_res = self.svc.request('POST', '/clock-in', {}, token)
        self.assertTrue(clock_in_res['is_clocked_in'])
        self.assertIsNotNone(clock_in_res['clock_in_time'])

        # 3. Repeated Clock-In must be rejected
        with self.assertRaises(APIError) as cm:
            self.svc.request('POST', '/clock-in', {}, token)
        self.assertEqual(cm.exception.status, 409)

        # 4. Logout ends session BUT MUST NOT CLOSE SHIFT (Client Requirement)
        logout_res = self.svc.request('POST', '/logout', {}, token)
        self.assertIn('Active shifts remain open', logout_res['message'])

        # Verify old token revoked
        with self.assertRaises(APIError) as cm:
            self.svc.request('GET', '/me', {}, token)
        self.assertEqual(cm.exception.status, 401)

        # 5. Re-login: Shift should still be active!
        login_res2 = self.svc.login({'pin': '1234'}, '127.0.0.1')
        token2 = login_res2['token']
        self.assertTrue(login_res2['shift_status']['is_clocked_in'])

        # 6. Explicit Clock-Out
        clock_out_res = self.svc.request('POST', '/clock-out', {}, token2)
        self.assertFalse(clock_out_res['is_clocked_in'])

    def test_02_supplier_purchase_order_and_delivery_receiving(self):
        """Test UC-05: Create PO, partial receipt, full receipt, atomic stock updates, and idempotency."""
        admin_login = self.svc.login({'pin': '1234'}, '127.0.0.1')
        token = admin_login['token']

        # Check initial inventory of Vine Tomatoes (ID 1 = 45.0)
        with self.db.transaction() as q:
            initial_stock = Decimal(str(q.one('SELECT quantity FROM Inventory WHERE inventory_id=1')['quantity']))
        self.assertEqual(initial_stock, Decimal('45.0'))

        # 1. Create a PO for 20 lbs of Tomatoes at $2.00/lb
        po_res = self.svc.request('POST', '/purchase-orders', {
            'supplier_id': 1,
            'items': [{'inventory_id': 1, 'quantity_ordered': 20.0, 'unit_cost': 2.00}]
        }, token)
        po_id = po_res['order_id']
        self.assertEqual(po_res['status'], 'Pending')
        self.assertEqual(Decimal(str(po_res['total_amount'])), Decimal('40.00'))

        # Creating PO must NOT increase stock yet
        with self.db.transaction() as q:
            stock_after_po = Decimal(str(q.one('SELECT quantity FROM Inventory WHERE inventory_id=1')['quantity']))
        self.assertEqual(stock_after_po, Decimal('45.0'))

        # 2. Receive partial delivery (10 lbs)
        rcv_res = self.svc.request('POST', f'/purchase-orders/{po_id}/receive', {
            'request_id': 'req-delivery-001',
            'notes': 'First truck delivery (partial)',
            'received_items': [{'item_id': po_res['items'][0]['item_id'], 'quantity_received': 10.0}]
        }, token)
        self.assertEqual(rcv_res['status'], 'Partial')
        self.assertEqual(rcv_res['items'][0]['quantity_received'], 10.0)

        # Inventory must be atomically incremented by 10.0 (45 + 10 = 55)
        with self.db.transaction() as q:
            stock_after_rcv1 = Decimal(str(q.one('SELECT quantity FROM Inventory WHERE inventory_id=1')['quantity']))
            tx = q.one('SELECT * FROM Inventory_Transactions WHERE inventory_id=1 ORDER BY transaction_id DESC')
        self.assertEqual(stock_after_rcv1, Decimal('55.0'))
        self.assertIn(f'PO #{po_id}', tx['reason'])

        # 3. Idempotency test: Resending same request_id must NOT increment stock twice!
        rcv_res_dup = self.svc.request('POST', f'/purchase-orders/{po_id}/receive', {
            'request_id': 'req-delivery-001',
            'notes': 'Duplicate retry',
            'received_items': [{'item_id': po_res['items'][0]['item_id'], 'quantity_received': 10.0}]
        }, token)
        with self.db.transaction() as q:
            stock_after_dup = Decimal(str(q.one('SELECT quantity FROM Inventory WHERE inventory_id=1')['quantity']))
        self.assertEqual(stock_after_dup, Decimal('55.0'))

        # 4. Attempting to receive more than remaining (15 lbs > 10 lbs remaining) must fail
        with self.assertRaises(APIError) as cm:
            self.svc.request('POST', f'/purchase-orders/{po_id}/receive', {
                'request_id': 'req-delivery-002',
                'received_items': [{'item_id': po_res['items'][0]['item_id'], 'quantity_received': 15.0}]
            }, token)
        self.assertEqual(cm.exception.status, 400)

        # 5. Receive remaining 10 lbs -> PO status transitions to 'Received'
        rcv_res2 = self.svc.request('POST', f'/purchase-orders/{po_id}/receive', {
            'request_id': 'req-delivery-003',
            'received_items': [{'item_id': po_res['items'][0]['item_id'], 'quantity_received': 10.0}]
        }, token)
        self.assertEqual(rcv_res2['status'], 'Received')
        with self.db.transaction() as q:
            final_stock = Decimal(str(q.one('SELECT quantity FROM Inventory WHERE inventory_id=1')['quantity']))
        self.assertEqual(final_stock, Decimal('65.0'))

    def test_03_inventory_spoilage_logging(self):
        """Test UC-11: Spoilage logging, atomic stock deduction, validation, and idempotency."""
        admin_login = self.svc.login({'pin': '1234'}, '127.0.0.1')
        token = admin_login['token']

        # Initial Angus Beef Patties stock (ID 2 = 80.0)
        with self.db.transaction() as q:
            init_stock = Decimal(str(q.one('SELECT quantity FROM Inventory WHERE inventory_id=2')['quantity']))
        self.assertEqual(init_stock, Decimal('80.0'))

        # 1. Log valid spoilage of 5.0 patties
        spoil_res = self.svc.request('POST', '/inventory/spoilage', {
            'request_id': 'spoil-req-001',
            'inventory_id': 2,
            'quantity': 5.0,
            'reason': 'Temperature Fluctuation',
            'notes': 'Freezer door left ajar overnight'
        }, token)
        self.assertEqual(spoil_res['quantity_spoiled'], 5.0)
        self.assertEqual(spoil_res['stock_before'], 80.0)
        self.assertEqual(spoil_res['stock_after'], 75.0)

        # Inventory must be atomically reduced to 75.0
        with self.db.transaction() as q:
            stock_after = Decimal(str(q.one('SELECT quantity FROM Inventory WHERE inventory_id=2')['quantity']))
            tx = q.one('SELECT * FROM Inventory_Transactions WHERE inventory_id=2 ORDER BY transaction_id DESC')
        self.assertEqual(stock_after, Decimal('75.0'))
        self.assertEqual(Decimal(str(tx['quantity_change'])), Decimal('-5.0'))

        # 2. Excessive spoilage (e.g. 100 > 75) must be rejected
        with self.assertRaises(APIError) as cm:
            self.svc.request('POST', '/inventory/spoilage', {
                'request_id': 'spoil-req-002',
                'inventory_id': 2,
                'quantity': 100.0,
                'reason': 'Contaminated'
            }, token)
        self.assertEqual(cm.exception.status, 400)

        # 3. Idempotent retry with spoil-req-001 must return existing record without duplicate reduction
        spoil_dup = self.svc.request('POST', '/inventory/spoilage', {
            'request_id': 'spoil-req-001',
            'inventory_id': 2,
            'quantity': 5.0,
            'reason': 'Temperature Fluctuation'
        }, token)
        with self.db.transaction() as q:
            stock_after_dup = Decimal(str(q.one('SELECT quantity FROM Inventory WHERE inventory_id=2')['quantity']))
        self.assertEqual(stock_after_dup, Decimal('75.0'))

    def test_04_rbac_security_enforcement(self):
        """Verify Role-Based Access Control: FOH Staff cannot create POs or log spoilage."""
        foh_login = self.svc.login({'pin': '3456'}, '127.0.0.1')
        foh_token = foh_login['token']
        self.assertEqual(foh_login['user']['role'], 'FOH Staff')

        # FOH cannot create PO
        with self.assertRaises(APIError) as cm:
            self.svc.request('POST', '/purchase-orders', {'supplier_id': 1, 'items': []}, foh_token)
        self.assertEqual(cm.exception.status, 403)

        # FOH cannot log spoilage
        with self.assertRaises(APIError) as cm:
            self.svc.request('POST', '/inventory/spoilage', {'request_id': 'foh-1', 'inventory_id': 1, 'quantity': 1, 'reason': 'x'}, foh_token)
        self.assertEqual(cm.exception.status, 403)

    def test_05_job_applicants_and_customer_service(self):
        """Test UC-10 (Job Applicants) and UC-12 (Customer Service issues)."""
        admin_login = self.svc.login({'pin': '1234'}, '127.0.0.1')
        token = admin_login['token']

        # Add Applicant (UC-10)
        app_res = self.svc.request('POST', '/applicants', {
            'full_name': 'Marcus Vance',
            'email': 'marcus.v@email.com',
            'phone_number': '404-555-7733',
            'applied_position': 'Line Cook',
            'availability': 'Full Time',
            'years_experience': 4
        }, token)
        self.assertEqual(app_res['full_name'], 'Marcus Vance')
        self.assertEqual(app_res['application_status'], 'New')

        # Create Customer Service Issue (UC-12)
        issue_res = self.svc.request('POST', '/service-issues', {
            'category': 'Seating Delay',
            'description': 'Party of 6 waited 25 minutes past reservation time.',
            'customer_contact': 'Mrs. Davis (404-555-9090)'
        }, token)
        self.assertEqual(issue_res['status'], 'Open')

        # Resolve Customer Service Issue
        resolved = self.svc.request('POST', f"/service-issues/{issue_res['issue_id']}/resolve", {
            'status': 'Resolved',
            'resolution_notes': 'Offered complimentary dessert and manager apology.'
        }, token)
        self.assertEqual(resolved['status'], 'Resolved')
        self.assertIn('complimentary dessert', resolved['resolution_notes'])

if __name__ == '__main__':
    unittest.main()
