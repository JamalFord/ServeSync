"""ServeSync Sprint 3: API services, Firestore-compatible data models, and business logic.
All database operations use bound parameters and atomic transactions.
Supports:
- UC-01: User Authentication & Explicit Shift Clock-In/Clock-Out (per client feedback)
- UC-08: Administer User Accounts & Security Settings
- UC-05: Supplier Purchasing & Delivery Receiving (Sprint 3 Native Feature A)
- UC-11: Record Inventory Spoilage (Sprint 3 Native Feature B)
- UC-10: Job Applicants & Onboarding (Sprint 3 Database Case)
- UC-12: Customer Service Issues (Sprint 3 Database Case)
- Baseline UC-02, UC-03, UC-04, and Payroll audit logging
"""
import os, re, json, hashlib, hmac, secrets, sqlite3, time
from contextlib import contextmanager
from decimal import Decimal
from datetime import datetime, timedelta, timezone

ROLES = ('FOH Staff', 'Manager', 'Administrator')
def now(): return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)
def stamp(value): return value.strftime('%Y-%m-%d %H:%M:%S')

class APIError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message

def require_pin(pin):
    if not isinstance(pin, str) or not re.fullmatch(r'[0-9]{4}', pin):
        raise APIError(400, 'PIN must contain exactly four digits.')
    return pin

def hash_pin(pin):
    salt = secrets.token_hex(16)
    digest = hashlib.scrypt(pin.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1).hex()
    return f'scrypt${salt}${digest}'

def verify_pin(pin, value):
    _, salt, expected = value.split('$')
    actual = hashlib.scrypt(pin.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1).hex()
    return hmac.compare_digest(actual, expected)

class Database:
    def __init__(self, sqlite_path=None):
        self.sqlite_path = sqlite_path
        
    @contextmanager
    def transaction(self):
        if self.sqlite_path:
            c = sqlite3.connect(self.sqlite_path, timeout=15)
            c.row_factory = sqlite3.Row
            c.execute('PRAGMA foreign_keys = ON')
            c.execute('BEGIN IMMEDIATE')
        else:
            import pymysql
            c = pymysql.connect(
                host=os.environ.get('DB_HOST', '127.0.0.1'),
                port=int(os.environ.get('DB_PORT', '3306')),
                user=os.environ.get('DB_USER', 'root'),
                password=os.environ.get('DB_PASSWORD', ''),
                database=os.environ.get('DB_NAME', 'servesync'),
                cursorclass=pymysql.cursors.DictCursor,
                charset='utf8mb4',
                autocommit=False
            )
        try:
            yield Query(c, bool(self.sqlite_path))
            c.commit()
        except Exception:
            c.rollback()
            raise
        finally:
            c.close()

class Query:
    def __init__(self, connection, sqlite):
        self.connection, self.sqlite = connection, sqlite
        
    def run(self, sql, params=()):
        cur = self.connection.cursor()
        cur.execute(sql.replace('%s', '?') if self.sqlite else sql, params)
        return cur
        
    def one(self, sql, params=()):
        row = self.run(sql, params).fetchone()
        return dict(row) if row else None
        
    def all(self, sql, params=()):
        return [dict(r) for r in self.run(sql, params).fetchall()]
        
    def lock(self):
        return '' if self.sqlite else ' FOR UPDATE'

class Service:
    def __init__(self, db, secret):
        if len(secret) < 32:
            raise ValueError('PIN_LOOKUP_SECRET must have at least 32 characters.')
        self.db, self.secret = db, secret.encode()

    def lookup(self, pin):
        return hmac.new(self.secret, pin.encode(), hashlib.sha256).hexdigest()

    def public(self, user):
        return {k: user[k] for k in ('user_id', 'full_name', 'role', 'account_status')}

    def validate_user(self, data):
        name = data.get('full_name', '')
        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 100:
            raise APIError(400, 'Name is required and must be at most 100 characters.')
        role = data.get('role')
        if role not in ROLES:
            raise APIError(400, 'Invalid role.')
        require_pin(data.get('pin'))
        return name.strip(), role, data['pin']

    def create(self, q, data):
        name, role, pin = self.validate_user(data)
        q.one('SELECT lock_id FROM User_Management_Lock WHERE lock_id=1' + q.lock())
        if q.one('SELECT user_id FROM Users WHERE pin_lookup=%s', (self.lookup(pin),)):
            raise APIError(409, 'PIN is already assigned. Choose another PIN.')
        cur = q.run(
            'INSERT INTO Users (full_name,access_code,pin_lookup,role,account_status,created_at) VALUES (%s,%s,%s,%s,%s,%s)',
            (name, hash_pin(pin), self.lookup(pin), role, 'Active', stamp(now()))
        )
        return self.public(q.one('SELECT * FROM Users WHERE user_id=%s', (cur.lastrowid,)))

    def bootstrap(self, name, pin):
        with self.db.transaction() as q:
            q.one('SELECT lock_id FROM User_Management_Lock WHERE lock_id=1' + q.lock())
            if q.one('SELECT user_id FROM Users LIMIT 1'):
                raise APIError(409, 'Initial setup is already complete.')
            return self.create(q, {'full_name': name, 'pin': pin, 'role': 'Administrator'})

    # --- Session Management (separate from Shift Tracking) ---
    def expire_sessions(self, q):
        q.run('DELETE FROM Sessions WHERE expires_at<=%s', (stamp(now()),))

    def login(self, data, client_ip):
        pin = require_pin(data.get('pin'))
        key = hashlib.sha256(client_ip.encode()).hexdigest()
        failure = None
        result = None
        with self.db.transaction() as q:
            q.one('SELECT lock_id FROM User_Management_Lock WHERE lock_id=1' + q.lock())
            self.expire_sessions(q)
            attempt = q.one('SELECT * FROM Login_Attempts WHERE client_key=%s', (key,))
            current = int(time.time())
            if attempt and current - attempt['window_start'] < 300 and attempt['failures'] >= 5:
                failure = APIError(429, 'Too many failed attempts. Wait five minutes.')
            else:
                user = q.one('SELECT * FROM Users WHERE pin_lookup=%s', (self.lookup(pin),))
                if not user or user['account_status'] != 'Active' or not verify_pin(pin, user['access_code']):
                    count = attempt['failures'] + 1 if attempt and current - attempt['window_start'] < 300 else 1
                    start = attempt['window_start'] if count > 1 else current
                    q.run('DELETE FROM Login_Attempts WHERE client_key=%s', (key,))
                    q.run('INSERT INTO Login_Attempts VALUES (%s,%s,%s)', (key, start, count))
                    failure = APIError(401, 'Invalid Code')
                elif q.one('SELECT token_hash FROM Sessions WHERE user_id=%s', (user['user_id'],)):
                    failure = APIError(409, 'Employee already has an active session. Log out on that device or ask an administrator to end the session.')
                else:
                    q.run('DELETE FROM Login_Attempts WHERE client_key=%s', (key,))
                    token = secrets.token_urlsafe(32)
                    q.run(
                        'INSERT INTO Sessions (token_hash,user_id,payroll_id,expires_at) VALUES (%s,%s,%s,%s)',
                        (hashlib.sha256(token.encode()).hexdigest(), user['user_id'], None, stamp(now() + timedelta(hours=12)))
                    )
                    shift = q.one('SELECT * FROM Payroll WHERE user_id=%s AND clock_out IS NULL', (user['user_id'],))
                    shift_status = {
                        'is_clocked_in': bool(shift),
                        'clock_in_time': str(shift['clock_in']) if shift else None,
                        'hours_worked_today': 0.0
                    }
                    result = {'token': token, 'user': self.public(user), 'shift_status': shift_status}
        if failure:
            raise failure
        return result

    def authenticate(self, q, token):
        s = q.one('SELECT * FROM Sessions WHERE token_hash=%s', (hashlib.sha256(token.encode()).hexdigest(),))
        if not s:
            raise APIError(401, 'Please log in.')
        user = q.one('SELECT * FROM Users WHERE user_id=%s', (s['user_id'],))
        if user['account_status'] != 'Active':
            raise APIError(401, 'Account is inactive.')
        return s, user

    # --- Client-Requested Shift Actions (UC-01) ---
    def get_shift_status(self, q, user_id):
        shift = q.one('SELECT * FROM Payroll WHERE user_id=%s AND clock_out IS NULL', (user_id,))
        return {
            'is_clocked_in': bool(shift),
            'clock_in_time': str(shift['clock_in']) if shift else None,
            'hours_worked_today': 0.0
        }

    def clock_in(self, q, user_id):
        active = q.one('SELECT payroll_id FROM Payroll WHERE user_id=%s AND clock_out IS NULL', (user_id,))
        if active:
            raise APIError(409, 'Employee already has an active shift. Duplicate clock-in is prohibited.')
        current_time = stamp(now())
        q.run(
            'INSERT INTO Payroll (user_id,clock_in,hourly_rate,payment_status) VALUES (%s,%s,%s,%s)',
            (user_id, current_time, '15.00', 'Pending')
        )
        return {'is_clocked_in': True, 'clock_in_time': current_time, 'hours_worked_today': 0.0}

    def clock_out(self, q, user_id):
        shift = q.one('SELECT * FROM Payroll WHERE user_id=%s AND clock_out IS NULL', (user_id,))
        if not shift:
            raise APIError(400, 'Employee does not have an active shift to clock out from.')
        ended = now()
        start = datetime.fromisoformat(str(shift['clock_in']))
        hours = Decimal(str(max(0, (ended - start).total_seconds()) / 3600))
        gross = hours * Decimal(str(shift['hourly_rate']))
        q.run(
            'UPDATE Payroll SET clock_out=%s,hours_worked=%s,gross_pay=%s WHERE payroll_id=%s',
            (stamp(ended), str(hours.quantize(Decimal('.01'))), str(gross.quantize(Decimal('.01'))), shift['payroll_id'])
        )
        return {'is_clocked_in': False, 'clock_in_time': None, 'hours_worked_today': float(hours)}

    # --- Feature A: Supplier Purchasing & Receiving (UC-05) ---
    def get_suppliers(self, q):
        return q.all('SELECT * FROM Suppliers ORDER BY supplier_name')

    def get_purchase_orders(self, q, status=None):
        sql = '''
            SELECT po.order_id, po.supplier_id, s.supplier_name, u.full_name AS created_by_name,
                   po.order_date, po.status, po.total_amount
            FROM Supplier_Orders po
            JOIN Suppliers s ON po.supplier_id = s.supplier_id
            JOIN Users u ON po.created_by = u.user_id
        '''
        params = ()
        if status and status != 'All':
            sql += ' WHERE po.status = %s'
            params = (status,)
        sql += ' ORDER BY po.order_id DESC'
        orders = q.all(sql, params)
        for o in orders:
            o['items'] = q.all('''
                SELECT poi.item_id, poi.inventory_id, inv.item_name, poi.quantity_ordered,
                       poi.quantity_received, poi.unit_cost, inv.unit
                FROM Supplier_Order_Items poi
                JOIN Inventory inv ON poi.inventory_id = inv.inventory_id
                WHERE poi.order_id = %s
            ''', (o['order_id'],))
        return orders

    def create_purchase_order(self, q, user_id, data):
        supplier_id = data.get('supplier_id')
        items = data.get('items', [])
        if not supplier_id or not items:
            raise APIError(400, 'Supplier ID and at least one order line are required.')
        if not q.one('SELECT supplier_id FROM Suppliers WHERE supplier_id=%s', (supplier_id,)):
            raise APIError(404, 'Supplier not found.')
        
        total = Decimal('0.00')
        lines = []
        for it in items:
            inv_id = it.get('inventory_id')
            qty = Decimal(str(it.get('quantity_ordered', 0)))
            cost = Decimal(str(it.get('unit_cost', 0)))
            if qty <= 0 or cost < 0:
                raise APIError(400, 'Invalid quantity or unit cost.')
            if not q.one('SELECT inventory_id FROM Inventory WHERE inventory_id=%s', (inv_id,)):
                raise APIError(404, f'Inventory item {inv_id} not found.')
            total += (qty * cost)
            lines.append((inv_id, qty, cost))

        cur = q.run(
            'INSERT INTO Supplier_Orders (supplier_id,created_by,order_date,total_amount,status) VALUES (%s,%s,%s,%s,%s)',
            (supplier_id, user_id, stamp(now()), str(total.quantize(Decimal('.01'))), 'Pending')
        )
        order_id = cur.lastrowid
        for inv_id, qty, cost in lines:
            q.run(
                'INSERT INTO Supplier_Order_Items (order_id,inventory_id,quantity_ordered,quantity_received,unit_cost) VALUES (%s,%s,%s,%s,%s)',
                (order_id, inv_id, str(qty.quantize(Decimal('.01'))), '0.00', str(cost.quantize(Decimal('.01'))))
            )
        return self.get_purchase_orders(q)[0]

    def receive_delivery(self, q, user_id, order_id, data):
        req_id = data.get('request_id')
        if not req_id:
            raise APIError(400, 'Request ID is required for idempotent delivery processing.')
        # Idempotency check
        existing = q.one('SELECT receipt_id FROM Delivery_Receipts WHERE request_id=%s', (req_id,))
        if existing:
            return [o for o in self.get_purchase_orders(q) if o['order_id'] == order_id][0]

        order = q.one('SELECT * FROM Supplier_Orders WHERE order_id=%s' + q.lock(), (order_id,))
        if not order:
            raise APIError(404, 'Purchase order not found.')
        if order['status'] in ('Received', 'Cancelled'):
            raise APIError(400, f"Cannot receive items on an order with status '{order['status']}'.")

        received_items = data.get('received_items', [])
        if not received_items:
            raise APIError(400, 'No received items specified.')

        # Record Delivery Receipt header
        notes = data.get('notes', '')
        cur_rcpt = q.run(
            'INSERT INTO Delivery_Receipts (order_id,received_by,receipt_date,request_id,notes) VALUES (%s,%s,%s,%s,%s)',
            (order_id, user_id, stamp(now()), req_id, notes)
        )
        receipt_id = cur_rcpt.lastrowid

        for it in received_items:
            item_id = it.get('item_id')
            qty_rcv = Decimal(str(it.get('quantity_received', 0)))
            if qty_rcv <= 0:
                continue
            line = q.one('SELECT * FROM Supplier_Order_Items WHERE item_id=%s AND order_id=%s' + q.lock(), (item_id, order_id))
            if not line:
                raise APIError(404, f'Order line {item_id} not found in PO #{order_id}.')
            
            ordered = Decimal(str(line['quantity_ordered']))
            already = Decimal(str(line['quantity_received']))
            remaining = ordered - already
            if qty_rcv > remaining:
                raise APIError(400, f"Received quantity ({qty_rcv}) exceeds outstanding balance ({remaining}) for line {item_id}.")
            
            new_received = already + qty_rcv
            q.run('UPDATE Supplier_Order_Items SET quantity_received=%s WHERE item_id=%s',
                  (str(new_received.quantize(Decimal('.01'))), item_id))
            
            # Atomic inventory increment
            inv = q.one('SELECT * FROM Inventory WHERE inventory_id=%s' + q.lock(), (line['inventory_id'],))
            current_stock = Decimal(str(inv['quantity']))
            new_stock = current_stock + qty_rcv
            q.run('UPDATE Inventory SET quantity=%s, last_updated=%s WHERE inventory_id=%s',
                  (str(new_stock.quantize(Decimal('.01'))), stamp(now()), line['inventory_id']))
            
            # Audit transaction log
            q.run(
                'INSERT INTO Inventory_Transactions (inventory_id,user_id,quantity_change,reason,timestamp) VALUES (%s,%s,%s,%s,%s)',
                (line['inventory_id'], user_id, str(qty_rcv.quantize(Decimal('.01'))), f'PO #{order_id} Delivery Receipt', stamp(now()))
            )

        # Check if entire PO is now fulfilled
        all_lines = q.all('SELECT quantity_ordered, quantity_received FROM Supplier_Order_Items WHERE order_id=%s', (order_id,))
        all_fulfilled = all(Decimal(str(l['quantity_received'])) >= Decimal(str(l['quantity_ordered'])) for l in all_lines)
        any_received = any(Decimal(str(l['quantity_received'])) > 0 for l in all_lines)
        new_status = 'Received' if all_fulfilled else ('Partial' if any_received else 'Pending')
        q.run('UPDATE Supplier_Orders SET status=%s WHERE order_id=%s', (new_status, order_id))

        return [o for o in self.get_purchase_orders(q) if o['order_id'] == order_id][0]

    # --- Feature B: Spoilage Logging & Inventory (UC-11 & UC-04) ---
    def get_inventory(self, q):
        return q.all('SELECT * FROM Inventory ORDER BY item_name')

    def get_spoilage_history(self, q):
        return q.all('''
            SELECT sp.spoilage_id, sp.inventory_id, inv.item_name, sp.quantity_spoiled,
                   inv.unit, sp.reason, u.full_name AS recorded_by_name, sp.occurred_at,
                   sp.stock_before, sp.stock_after
            FROM Inventory_Spoilage sp
            JOIN Inventory inv ON sp.inventory_id = inv.inventory_id
            JOIN Users u ON sp.recorded_by = u.user_id
            ORDER BY sp.spoilage_id DESC
        ''')

    def record_spoilage(self, q, user_id, data):
        req_id = data.get('request_id')
        if not req_id:
            raise APIError(400, 'Request ID is required for idempotent spoilage processing.')
        existing = q.one('SELECT spoilage_id FROM Inventory_Spoilage WHERE request_id=%s', (req_id,))
        if existing:
            return q.one('''
                SELECT sp.spoilage_id, sp.inventory_id, inv.item_name, sp.quantity_spoiled,
                       inv.unit, sp.reason, u.full_name AS recorded_by_name, sp.occurred_at,
                       sp.stock_before, sp.stock_after
                FROM Inventory_Spoilage sp
                JOIN Inventory inv ON sp.inventory_id = inv.inventory_id
                JOIN Users u ON sp.recorded_by = u.user_id
                WHERE sp.spoilage_id=%s
            ''', (existing['spoilage_id'],))

        inv_id = data.get('inventory_id')
        qty = Decimal(str(data.get('quantity', 0)))
        reason = data.get('reason', '').strip()
        notes = data.get('notes', '').strip()
        if not inv_id or qty <= 0 or not reason:
            raise APIError(400, 'Inventory item ID, positive quantity, and reason are required.')

        inv = q.one('SELECT * FROM Inventory WHERE inventory_id=%s' + q.lock(), (inv_id,))
        if not inv:
            raise APIError(404, 'Inventory item not found.')

        current_stock = Decimal(str(inv['quantity']))
        if qty > current_stock:
            raise APIError(400, f'Spoiled quantity ({qty}) exceeds available stock ({current_stock}).')

        new_stock = current_stock - qty
        current_time = stamp(now())

        # Update inventory quantity atomically
        q.run('UPDATE Inventory SET quantity=%s, last_updated=%s WHERE inventory_id=%s',
              (str(new_stock.quantize(Decimal('.01'))), current_time, inv_id))

        # Record spoilage log
        cur = q.run(
            'INSERT INTO Inventory_Spoilage (inventory_id,quantity_spoiled,reason,notes,recorded_by,occurred_at,stock_before,stock_after,request_id) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)',
            (inv_id, str(qty.quantize(Decimal('.01'))), reason, notes, user_id, current_time,
             str(current_stock.quantize(Decimal('.01'))), str(new_stock.quantize(Decimal('.01'))), req_id)
        )
        spoilage_id = cur.lastrowid

        # Record in inventory transactions history
        q.run(
            'INSERT INTO Inventory_Transactions (inventory_id,user_id,quantity_change,reason,timestamp) VALUES (%s,%s,%s,%s,%s)',
            (inv_id, user_id, str((-qty).quantize(Decimal('.01'))), f'Spoilage: {reason}', current_time)
        )

        return q.one('''
            SELECT sp.spoilage_id, sp.inventory_id, inv.item_name, sp.quantity_spoiled,
                   inv.unit, sp.reason, u.full_name AS recorded_by_name, sp.occurred_at,
                   sp.stock_before, sp.stock_after
            FROM Inventory_Spoilage sp
            JOIN Inventory inv ON sp.inventory_id = inv.inventory_id
            JOIN Users u ON sp.recorded_by = u.user_id
            WHERE sp.spoilage_id=%s
        ''', (spoilage_id,))

    # --- UC-10: Applicants ---
    def get_applicants(self, q):
        return q.all('SELECT * FROM Job_Applicants ORDER BY applicant_id DESC')

    def create_applicant(self, q, data):
        name = data.get('full_name', '').strip()
        email = data.get('email', '').strip()
        phone = data.get('phone_number', '').strip()
        pos = data.get('applied_position', '').strip()
        avail = data.get('availability', '').strip()
        exp = int(data.get('years_experience', 0))
        if not name or not email or not pos:
            raise APIError(400, 'Full name, email, and applied position are required.')
        cur = q.run(
            'INSERT INTO Job_Applicants (full_name,email,phone_number,applied_position,availability,years_experience,application_status,created_at) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)',
            (name, email, phone, pos, avail, exp, 'New', stamp(now()))
        )
        return q.one('SELECT * FROM Job_Applicants WHERE applicant_id=%s', (cur.lastrowid,))

    def update_applicant_status(self, q, applicant_id, status):
        if status not in ('New', 'Reviewed', 'Interview', 'Rejected', 'Hired'):
            raise APIError(400, 'Invalid applicant status.')
        q.run('UPDATE Job_Applicants SET application_status=%s WHERE applicant_id=%s', (status, applicant_id))
        return q.one('SELECT * FROM Job_Applicants WHERE applicant_id=%s', (applicant_id,))

    # --- UC-12: Customer Service Issues ---
    def get_service_issues(self, q):
        return q.all('''
            SELECT s.issue_id, s.category, s.description, s.customer_contact, s.status,
                   s.reported_at, s.resolution_notes, u.full_name AS assigned_to_name
            FROM Customer_Service_Issues s
            LEFT JOIN Users u ON s.assigned_to = u.user_id
            ORDER BY s.issue_id DESC
        ''')

    def create_service_issue(self, q, user_id, data):
        cat = data.get('category', '').strip()
        desc = data.get('description', '').strip()
        contact = data.get('customer_contact', '').strip()
        if not cat or not desc:
            raise APIError(400, 'Category and description are required.')
        cur = q.run(
            'INSERT INTO Customer_Service_Issues (category,description,customer_contact,status,reported_at,assigned_to) VALUES (%s,%s,%s,%s,%s,%s)',
            (cat, desc, contact, 'Open', stamp(now()), user_id)
        )
        return q.one('SELECT * FROM Customer_Service_Issues WHERE issue_id=%s', (cur.lastrowid,))

    def resolve_service_issue(self, q, user_id, issue_id, data):
        notes = data.get('resolution_notes', '').strip()
        status = data.get('status', 'Resolved')
        if not notes:
            raise APIError(400, 'Resolution notes are required when updating customer service status.')
        q.run(
            'UPDATE Customer_Service_Issues SET status=%s, resolution_notes=%s, resolved_at=%s WHERE issue_id=%s',
            (status, notes, stamp(now()), issue_id)
        )
        return q.one('SELECT * FROM Customer_Service_Issues WHERE issue_id=%s', (issue_id,))

    # --- Master Request Dispatcher ---
    def request(self, method, path, data, token='', client_ip='local'):
        if method == 'POST' and path == '/login':
            return self.login(data, client_ip)

        with self.db.transaction() as q:
            q.one('SELECT lock_id FROM User_Management_Lock WHERE lock_id=1' + q.lock())
            self.expire_sessions(q)

        with self.db.transaction() as q:
            q.one('SELECT lock_id FROM User_Management_Lock WHERE lock_id=1' + q.lock())
            session, actor = self.authenticate(q, token)

            if path == '/me' and method == 'GET':
                return {'user': self.public(actor)}

            # Explicit shift endpoints (UC-01)
            if path == '/shift-status' and method == 'GET':
                return self.get_shift_status(q, actor['user_id'])
            if path == '/clock-in' and method == 'POST':
                return self.clock_in(q, actor['user_id'])
            if path == '/clock-out' and method == 'POST':
                return self.clock_out(q, actor['user_id'])

            # Client requirement: Logout ends session only; does NOT end shift
            if path == '/logout' and method == 'POST':
                q.run('DELETE FROM Sessions WHERE token_hash=%s', (session['token_hash'],))
                return {'message': 'Logged out of session. Active shifts remain open.'}

            # UC-08: Admin User Management
            if path.startswith('/users'):
                if actor['role'] != 'Administrator':
                    raise APIError(403, 'Administrator access is required.')
                if path == '/users' and method == 'GET':
                    return {'users': [self.public(u) for u in q.all('SELECT * FROM Users ORDER BY full_name')]}
                if path == '/users' and method == 'POST':
                    return {'user': self.create(q, data)}
                match = re.fullmatch(r'/users/(\d+)(/end-session)?', path)
                if not match:
                    raise APIError(404, 'Route not found.')
                uid = int(match[1])
                user = q.one('SELECT * FROM Users WHERE user_id=%s', (uid,))
                if not user:
                    raise APIError(404, 'User not found.')
                if match[2] and method == 'POST':
                    q.run('DELETE FROM Sessions WHERE user_id=%s', (uid,))
                    return {'message': 'Session revoked.'}
                if method not in ('PATCH', 'DELETE'):
                    raise APIError(405, 'Method not allowed.')
                status = 'Inactive' if method == 'DELETE' else data.get('account_status', user['account_status'])
                role = data.get('role', user['role'])
                name = data.get('full_name', user['full_name'])
                if status not in ('Active', 'Inactive') or role not in ROLES or not isinstance(name, str) or not 1 <= len(name.strip()) <= 100:
                    raise APIError(400, 'Invalid name, role, or account status.')
                if uid == actor['user_id'] and (status != 'Active' or role != 'Administrator'):
                    raise APIError(409, 'You cannot deactivate or demote your own administrator account.')
                if user['role'] == 'Administrator' and (role != 'Administrator' or status != 'Active'):
                    admins = q.one("SELECT COUNT(*) AS n FROM Users WHERE role='Administrator' AND account_status='Active'")['n']
                    if admins <= 1:
                        raise APIError(409, 'At least one active administrator is required.')
                if 'pin' in data:
                    pin = require_pin(data['pin'])
                    lookup = self.lookup(pin)
                    if q.one('SELECT user_id FROM Users WHERE pin_lookup=%s AND user_id<>%s', (lookup, uid)):
                        raise APIError(409, 'PIN is already assigned.')
                    q.run('UPDATE Users SET access_code=%s,pin_lookup=%s WHERE user_id=%s', (hash_pin(pin), lookup, uid))
                q.run('UPDATE Users SET full_name=%s,role=%s,account_status=%s WHERE user_id=%s', (name.strip(), role, status, uid))
                if status == 'Inactive' or 'pin' in data:
                    q.run('DELETE FROM Sessions WHERE user_id=%s', (uid,))
                return {'user': self.public(q.one('SELECT * FROM Users WHERE user_id=%s', (uid,)))}

            # UC-05: Suppliers & Purchase Orders
            if path == '/suppliers' and method == 'GET':
                return self.get_suppliers(q)
            if path == '/purchase-orders' and method == 'GET':
                return self.get_purchase_orders(q)
            if path == '/purchase-orders' and method == 'POST':
                if actor['role'] not in ('Manager', 'Administrator'):
                    raise APIError(403, 'Manager or Administrator access required.')
                return self.create_purchase_order(q, actor['user_id'], data)
            match_rcv = re.fullmatch(r'/purchase-orders/(\d+)/receive', path)
            if match_rcv and method == 'POST':
                if actor['role'] not in ('Manager', 'Administrator'):
                    raise APIError(403, 'Manager or Administrator access required.')
                return self.receive_delivery(q, actor['user_id'], int(match_rcv[1]), data)

            # UC-11 & UC-04: Inventory & Spoilage
            if path == '/inventory' and method == 'GET':
                return self.get_inventory(q)
            if path == '/inventory/spoilage' and method == 'GET':
                return self.get_spoilage_history(q)
            if path == '/inventory/spoilage' and method == 'POST':
                if actor['role'] not in ('Manager', 'Administrator'):
                    raise APIError(403, 'Manager or Administrator access required.')
                return self.record_spoilage(q, actor['user_id'], data)

            # UC-10: Applicants
            if path == '/applicants' and method == 'GET':
                if actor['role'] != 'Administrator':
                    raise APIError(403, 'Administrator access required.')
                return self.get_applicants(q)
            if path == '/applicants' and method == 'POST':
                if actor['role'] != 'Administrator':
                    raise APIError(403, 'Administrator access required.')
                return self.create_applicant(q, data)

            # UC-12: Customer Service
            if path == '/service-issues' and method == 'GET':
                return self.get_service_issues(q)
            if path == '/service-issues' and method == 'POST':
                return self.create_service_issue(q, actor['user_id'], data)
            match_cs = re.fullmatch(r'/service-issues/(\d+)/resolve', path)
            if match_cs and method == 'POST':
                if actor['role'] not in ('Manager', 'Administrator'):
                    raise APIError(403, 'Manager or Administrator access required.')
                return self.resolve_service_issue(q, actor['user_id'], int(match_cs[1]), data)

            # Read-only baseline routes
            if method == 'GET' and path in ('/orders', '/reservations'):
                tbl = {'/orders': 'Customer_Orders', '/reservations': 'Reservations'}[path]
                return {'records': q.all('SELECT * FROM ' + tbl)}
            if method == 'GET' and path == '/payroll':
                if actor['role'] != 'Administrator':
                    raise APIError(403, 'Administrator access required.')
                return {'records': q.all('SELECT * FROM Payroll')}

            raise APIError(404, 'Route not found.')
