"""ServeSync Sprint 4 feature routes.

Adds the routes that complete the twelve original project features:
  FR-1  supplier contact management, purchase order cancellation
  FR-3  inventory item create / edit / manual stock adjustment
  FR-4  payroll review, adjustment with reason, pay rates
  FR-7  reservation management
  FR-8  customer reviews and AI review summary
  FR-9  customer orders stored in the database, with inventory usage
  FR-10 consumption analytics and stock forecast
  FR-11 customer service issue status
  FR-12 hiring pipeline and onboarding

service.Service.request() authenticates the caller and then calls dispatch().
"""
import json
import re
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

import insights
import service as S

NOT_FOUND = object()
MANAGERS = ('Manager', 'Administrator')
ADMIN = ('Administrator',)
TAX_RATE = Decimal('0.0825')
CENT = Decimal('.01')


class Deferred:
    """Work to run after the request transaction has committed (slow network calls)."""
    def __init__(self, fn):
        self.fn = fn

    def run(self, svc):
        return self.fn(svc)


# --- small validation helpers -------------------------------------------------
def need(actor, roles):
    if actor['role'] not in roles:
        raise S.APIError(403, ' or '.join(roles) + ' access required.')


def text(data, key, label, required=True, maxlen=255):
    value = data.get(key)
    value = '' if value is None else str(value).strip()
    if required and not value:
        raise S.APIError(400, f'{label} is required.')
    if len(value) > maxlen:
        raise S.APIError(400, f'{label} must be at most {maxlen} characters.')
    return value


def number(value, label, minimum=None, above=None):
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError):
        raise S.APIError(400, f'{label} must be a number.')
    if not result.is_finite():
        raise S.APIError(400, f'{label} must be a number.')
    if minimum is not None and result < minimum:
        raise S.APIError(400, f'{label} must be at least {minimum}.')
    if above is not None and result <= above:
        raise S.APIError(400, f'{label} must be greater than {above}.')
    return result


def whole(value, label, minimum=1, maximum=None):
    try:
        if isinstance(value, bool) or int(str(value)) != float(str(value)):
            raise ValueError
        result = int(str(value))
    except (ValueError, TypeError):
        raise S.APIError(400, f'{label} must be a whole number.')
    if result < minimum or (maximum is not None and result > maximum):
        limit = f'between {minimum} and {maximum}' if maximum is not None else f'at least {minimum}'
        raise S.APIError(400, f'{label} must be {limit}.')
    return result


def money(value):
    return str(Decimal(str(value)).quantize(CENT))


# --- FR-7: reservations -------------------------------------------------------
RESERVATION_STATUSES = ('Confirmed', 'Seated', 'Cancelled', 'No-Show')
DEFAULT_SEATING_MINUTES = 90


def hhmm(value):
    if isinstance(value, timedelta):  # MySQL TIME columns arrive as timedelta
        total = int(value.total_seconds())
        return '%02d:%02d' % (total // 3600, total % 3600 // 60)
    parts = str(value).split(':')
    return '%02d:%02d' % (int(parts[0]), int(parts[1]))


def reservation_row(r):
    r = dict(r)
    r['reservation_date'] = str(r['reservation_date'])[:10]
    r['reservation_time'] = hhmm(r['reservation_time'])
    r['end_time'] = hhmm(r['end_time'])
    return r


def list_reservations(q, data):
    sql, params = 'SELECT * FROM Reservations', []
    if data.get('date'):
        sql += ' WHERE reservation_date=%s'
        params.append(parse_date(data['date']))
    rows = [reservation_row(r) for r in q.all(sql, tuple(params))]
    rows.sort(key=lambda r: (r['reservation_date'], r['reservation_time'], r['reservation_id']))
    return {'records': rows}


def parse_date(value):
    try:
        return datetime.strptime(str(value), '%Y-%m-%d').strftime('%Y-%m-%d')
    except ValueError:
        raise S.APIError(400, 'Date must be in YYYY-MM-DD format.')


def parse_time(value, label):
    match = re.fullmatch(r'([01]?\d|2[0-3]):([0-5]\d)(:[0-5]\d)?', str(value or '').strip())
    if not match:
        raise S.APIError(400, f'{label} must be in HH:MM (24-hour) format.')
    return '%02d:%02d' % (int(match[1]), int(match[2]))


def reservation_fields(q, data, current=None):
    """Validate a new or edited reservation and return the column values."""
    current = current or {}
    merged = dict(current)
    merged.update({k: v for k, v in data.items() if v is not None})
    guest = text(merged, 'guest_name', 'Guest name', maxlen=100)
    phone = text(merged, 'phone_number', 'Phone number', maxlen=20)
    if not re.fullmatch(r'[0-9+()\-. ]{7,20}', phone):
        raise S.APIError(400, 'Phone number is not valid.')
    party = whole(merged.get('party_size'), 'Party size', 1, 50)
    day = parse_date(merged.get('reservation_date'))
    if day < (S.now() - timedelta(days=1)).strftime('%Y-%m-%d'):
        raise S.APIError(400, 'Reservation date cannot be in the past.')
    start = parse_time(merged.get('reservation_time'), 'Reservation time')
    if 'end_time' in data and data['end_time']:
        end = parse_time(data['end_time'], 'End time')
    elif current and 'reservation_time' not in data:
        end = hhmm(current['end_time'])
    else:
        minutes = int(start[:2]) * 60 + int(start[3:]) + DEFAULT_SEATING_MINUTES
        end = '%02d:%02d' % divmod(min(minutes, 23 * 60 + 59), 60)
    if end <= start:
        raise S.APIError(400, 'End time must be after the reservation time.')
    table_number = whole(merged.get('table_number'), 'Table number', 1)
    table = q.one('SELECT * FROM Dining_Tables WHERE table_number=%s', (table_number,))
    if not table:
        raise S.APIError(404, f'Table {table_number} does not exist.')
    if party > int(table['capacity']):
        raise S.APIError(400, f"Table {table_number} seats {table['capacity']}; the party of {party} is too large.")
    for other in q.all('SELECT * FROM Reservations WHERE table_number=%s AND reservation_date=%s', (table_number, day)):
        if other['reservation_id'] == current.get('reservation_id') or other['status'] not in ('Confirmed', 'Seated'):
            continue
        if start < hhmm(other['end_time']) and hhmm(other['reservation_time']) < end:
            raise S.APIError(409, f"Table {table_number} is already reserved from {hhmm(other['reservation_time'])} "
                                  f"to {hhmm(other['end_time'])} for {other['guest_name']}.")
    notes = text(merged, 'notes', 'Notes', required=False)
    return guest, phone, party, day, start + ':00', end + ':00', table_number, notes


def create_reservation(q, actor, data):
    fields = reservation_fields(q, data)
    cur = q.run('INSERT INTO Reservations (guest_name,phone_number,party_size,reservation_date,reservation_time,'
                'end_time,table_number,notes,status,created_by) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)',
                fields + ('Confirmed', actor['user_id']))
    return reservation_row(q.one('SELECT * FROM Reservations WHERE reservation_id=%s', (cur.lastrowid,)))


def get_reservation(q, reservation_id):
    row = q.one('SELECT * FROM Reservations WHERE reservation_id=%s' + q.lock(), (reservation_id,))
    if not row:
        raise S.APIError(404, 'Reservation not found.')
    return row


def update_reservation(q, reservation_id, data):
    current = get_reservation(q, reservation_id)
    if current['status'] != 'Confirmed':
        raise S.APIError(409, f"A reservation that is {current['status']} cannot be edited.")
    current = reservation_row(current)
    fields = reservation_fields(q, data, current)
    q.run('UPDATE Reservations SET guest_name=%s,phone_number=%s,party_size=%s,reservation_date=%s,'
          'reservation_time=%s,end_time=%s,table_number=%s,notes=%s WHERE reservation_id=%s', fields + (reservation_id,))
    return reservation_row(q.one('SELECT * FROM Reservations WHERE reservation_id=%s', (reservation_id,)))


def set_reservation_status(q, reservation_id, data):
    status = data.get('status')
    if status not in RESERVATION_STATUSES:
        raise S.APIError(400, 'Status must be one of: ' + ', '.join(RESERVATION_STATUSES) + '.')
    current = get_reservation(q, reservation_id)
    if current['status'] == status:
        return reservation_row(current)
    if current['status'] != 'Confirmed':
        raise S.APIError(409, f"A reservation that is {current['status']} cannot be changed to {status}.")
    q.run('UPDATE Reservations SET status=%s WHERE reservation_id=%s', (status, reservation_id))
    return reservation_row(q.one('SELECT * FROM Reservations WHERE reservation_id=%s', (reservation_id,)))


# --- FR-9: customer orders ----------------------------------------------------
def order_with_items(q, order):
    order = dict(order)
    order['items'] = q.all(
        'SELECT oi.order_item_id, oi.menu_item_id, m.item_name, oi.quantity, oi.unit_price, oi.modifications '
        'FROM Order_Items oi JOIN Menu_Items m ON oi.menu_item_id = m.menu_item_id WHERE oi.order_id=%s '
        'ORDER BY oi.order_item_id', (order['order_id'],))
    return order


def list_orders(q, data):
    sql, params = ('SELECT o.*, u.full_name AS server_name FROM Customer_Orders o '
                   'JOIN Users u ON o.user_id = u.user_id'), []
    if data.get('status'):
        sql += ' WHERE o.order_status=%s'
        params.append(str(data['status']))
    sql += ' ORDER BY o.order_id DESC LIMIT 100'
    return {'records': [order_with_items(q, o) for o in q.all(sql, tuple(params))]}


def create_order(q, actor, data):
    table_number = whole(data.get('table_number'), 'Table number', 1)
    if not q.one('SELECT table_number FROM Dining_Tables WHERE table_number=%s', (table_number,)):
        raise S.APIError(404, f'Table {table_number} does not exist.')
    items = data.get('items')
    if not isinstance(items, list) or not items:
        raise S.APIError(400, 'An order needs at least one item.')
    if len(items) > 60:
        raise S.APIError(400, 'An order can have at most 60 lines.')
    lines, subtotal = [], Decimal('0')
    for it in items:
        if not isinstance(it, dict):
            raise S.APIError(400, 'Each order line must be an object.')
        if it.get('menu_item_id') is not None:
            menu = q.one('SELECT * FROM Menu_Items WHERE menu_item_id=%s', (whole(it['menu_item_id'], 'Menu item'),))
        else:
            menu = q.one('SELECT * FROM Menu_Items WHERE LOWER(item_name)=LOWER(%s)', (text(it, 'name', 'Item name', maxlen=100),))
        if not menu:
            raise S.APIError(404, f"Menu item '{it.get('name') or it.get('menu_item_id')}' is not on the menu.")
        if not menu['available']:
            raise S.APIError(409, f"{menu['item_name']} is not available.")
        quantity = whole(it.get('quantity', 1), 'Quantity', 1, 99)
        mods = text(it, 'modifications', 'Modifications', required=False)
        price = Decimal(str(menu['price']))
        subtotal += price * quantity
        lines.append((menu, quantity, price, mods))
    tax = (subtotal * TAX_RATE).quantize(CENT, rounding=ROUND_HALF_UP)
    total = subtotal + tax
    current = S.stamp(S.now())
    cur = q.run('INSERT INTO Customer_Orders (user_id,table_number,order_status,total_amount,order_time) VALUES (%s,%s,%s,%s,%s)',
                (actor['user_id'], table_number, 'Active', money(total), current))
    order_id = cur.lastrowid
    usage = {}
    for menu, quantity, price, mods in lines:
        q.run('INSERT INTO Order_Items (order_id,menu_item_id,quantity,unit_price,modifications) VALUES (%s,%s,%s,%s,%s)',
              (order_id, menu['menu_item_id'], quantity, money(price), mods or None))
        for part in q.all('SELECT inventory_id, quantity_per_serving FROM Menu_Item_Ingredients WHERE menu_item_id=%s',
                          (menu['menu_item_id'],)):
            usage[part['inventory_id']] = usage.get(part['inventory_id'], Decimal('0')) + \
                Decimal(str(part['quantity_per_serving'])) * quantity
    for inventory_id, needed in sorted(usage.items()):  # sorted: always lock rows in the same order
        inv = q.one('SELECT * FROM Inventory WHERE inventory_id=%s' + q.lock(), (inventory_id,))
        if not inv:
            continue
        on_hand = Decimal(str(inv['quantity']))
        used = min(on_hand, needed).quantize(CENT)
        if used <= 0:
            continue
        q.run('UPDATE Inventory SET quantity=%s, last_updated=%s WHERE inventory_id=%s',
              (money(on_hand - used), current, inventory_id))
        q.run('INSERT INTO Inventory_Transactions (inventory_id,user_id,quantity_change,reason,timestamp) VALUES (%s,%s,%s,%s,%s)',
              (inventory_id, actor['user_id'], money(-used), f'Order #{order_id} usage', current))
    q.run('UPDATE Dining_Tables SET status=%s WHERE table_number=%s', ('Occupied', table_number))
    order = order_with_items(q, q.one(
        'SELECT o.*, u.full_name AS server_name FROM Customer_Orders o JOIN Users u ON o.user_id=u.user_id WHERE o.order_id=%s',
        (order_id,)))
    order['subtotal'], order['tax'] = money(subtotal), money(tax)
    return order


def close_order(q, order_id, new_status, data):
    order = q.one('SELECT * FROM Customer_Orders WHERE order_id=%s' + q.lock(), (order_id,))
    if not order:
        raise S.APIError(404, 'Order not found.')
    if order['order_status'] in ('Completed', 'Cancelled'):
        raise S.APIError(409, f"Order #{order_id} is already {order['order_status']}.")
    method = None
    if new_status == 'Completed':
        method = data.get('payment_method') or 'Card'
        if method not in ('Cash', 'Card', 'Other'):
            raise S.APIError(400, 'Payment method must be Cash, Card, or Other.')
    q.run('UPDATE Customer_Orders SET order_status=%s, completed_at=%s, payment_method=%s WHERE order_id=%s',
          (new_status, S.stamp(S.now()), method, order_id))
    if not q.one("SELECT order_id FROM Customer_Orders WHERE table_number=%s AND order_status IN ('Active','In Prep')",
                 (order['table_number'],)):
        q.run('UPDATE Dining_Tables SET status=%s WHERE table_number=%s', ('Available', order['table_number']))
    return order_with_items(q, q.one('SELECT * FROM Customer_Orders WHERE order_id=%s', (order_id,)))


# --- FR-1 / FR-3: suppliers, purchase orders, inventory -----------------------
def supplier_fields(data, current=None):
    merged = dict(current or {})
    merged.update({k: v for k, v in data.items() if v is not None})
    name = text(merged, 'supplier_name', 'Supplier name', maxlen=100)
    contact = text(merged, 'contact_person', 'Contact person', maxlen=100)
    phone = text(merged, 'phone_number', 'Phone number', maxlen=20)
    email = text(merged, 'email', 'Email', maxlen=100)
    if not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+', email):
        raise S.APIError(400, 'Email address is not valid.')
    category = text(merged, 'product_category', 'Product category', maxlen=100)
    return name, contact, phone, email, category


def save_supplier(q, data, supplier_id=None):
    current = None
    if supplier_id is not None:
        current = q.one('SELECT * FROM Suppliers WHERE supplier_id=%s', (supplier_id,))
        if not current:
            raise S.APIError(404, 'Supplier not found.')
    fields = supplier_fields(data, current)
    clash = q.one('SELECT supplier_id FROM Suppliers WHERE LOWER(supplier_name)=LOWER(%s)', (fields[0],))
    if clash and clash['supplier_id'] != supplier_id:
        raise S.APIError(409, 'A supplier with this name already exists.')
    if supplier_id is None:
        supplier_id = q.run('INSERT INTO Suppliers (supplier_name,contact_person,phone_number,email,product_category,created_at) '
                            'VALUES (%s,%s,%s,%s,%s,%s)', fields + (S.stamp(S.now()),)).lastrowid
    else:
        q.run('UPDATE Suppliers SET supplier_name=%s,contact_person=%s,phone_number=%s,email=%s,product_category=%s '
              'WHERE supplier_id=%s', fields + (supplier_id,))
    return q.one('SELECT * FROM Suppliers WHERE supplier_id=%s', (supplier_id,))


def cancel_purchase_order(svc, q, order_id):
    order = q.one('SELECT * FROM Supplier_Orders WHERE order_id=%s' + q.lock(), (order_id,))
    if not order:
        raise S.APIError(404, 'Purchase order not found.')
    if order['status'] != 'Pending':
        raise S.APIError(409, f"Only a Pending purchase order can be cancelled; this one is {order['status']}.")
    q.run('UPDATE Supplier_Orders SET status=%s WHERE order_id=%s', ('Cancelled', order_id))
    return [o for o in svc.get_purchase_orders(q) if o['order_id'] == order_id][0]


def create_inventory_item(q, actor, data):
    name = text(data, 'item_name', 'Item name', maxlen=100)
    if q.one('SELECT inventory_id FROM Inventory WHERE LOWER(item_name)=LOWER(%s)', (name,)):
        raise S.APIError(409, 'An inventory item with this name already exists.')
    category = text(data, 'category', 'Category', maxlen=50)
    unit = text(data, 'unit', 'Unit', maxlen=20)
    quantity = number(data.get('quantity', 0), 'Quantity', minimum=0)
    reorder = number(data.get('reorder_level', 0), 'Reorder level', minimum=0)
    cost = number(data.get('unit_cost', 0), 'Unit cost', minimum=0)
    current = S.stamp(S.now())
    inventory_id = q.run('INSERT INTO Inventory (item_name,category,quantity,unit,reorder_level,unit_cost,last_updated) '
                         'VALUES (%s,%s,%s,%s,%s,%s,%s)',
                         (name, category, money(quantity), unit, money(reorder), money(cost), current)).lastrowid
    if quantity > 0:
        q.run('INSERT INTO Inventory_Transactions (inventory_id,user_id,quantity_change,reason,timestamp) VALUES (%s,%s,%s,%s,%s)',
              (inventory_id, actor['user_id'], money(quantity), 'Manual adjustment: opening stock', current))
    return q.one('SELECT * FROM Inventory WHERE inventory_id=%s', (inventory_id,))


def update_inventory_item(q, actor, inventory_id, data):
    inv = q.one('SELECT * FROM Inventory WHERE inventory_id=%s' + q.lock(), (inventory_id,))
    if not inv:
        raise S.APIError(404, 'Inventory item not found.')
    merged = dict(inv)
    merged.update({k: v for k, v in data.items() if v is not None})
    name = text(merged, 'item_name', 'Item name', maxlen=100)
    clash = q.one('SELECT inventory_id FROM Inventory WHERE LOWER(item_name)=LOWER(%s)', (name,))
    if clash and clash['inventory_id'] != inventory_id:
        raise S.APIError(409, 'An inventory item with this name already exists.')
    category = text(merged, 'category', 'Category', maxlen=50)
    unit = text(merged, 'unit', 'Unit', maxlen=20)
    reorder = number(merged.get('reorder_level'), 'Reorder level', minimum=0)
    cost = number(merged.get('unit_cost'), 'Unit cost', minimum=0)
    current = S.stamp(S.now())
    old_qty = Decimal(str(inv['quantity']))
    new_qty = old_qty
    if data.get('quantity') is not None:
        new_qty = number(data['quantity'], 'Quantity', minimum=0).quantize(CENT)
        if new_qty != old_qty.quantize(CENT):
            reason = text(data, 'reason', 'A reason for the stock adjustment', maxlen=80)
            q.run('INSERT INTO Inventory_Transactions (inventory_id,user_id,quantity_change,reason,timestamp) VALUES (%s,%s,%s,%s,%s)',
                  (inventory_id, actor['user_id'], money(new_qty - old_qty), f'Manual adjustment: {reason}', current))
    q.run('UPDATE Inventory SET item_name=%s,category=%s,unit=%s,reorder_level=%s,unit_cost=%s,quantity=%s,last_updated=%s '
          'WHERE inventory_id=%s', (name, category, unit, money(reorder), money(cost), money(new_qty), current, inventory_id))
    return q.one('SELECT * FROM Inventory WHERE inventory_id=%s', (inventory_id,))


# --- FR-4: payroll ------------------------------------------------------------
PAYMENT_STATUSES = ('Pending', 'Paid', 'Pending Correction')


def payroll_report(q, data):
    sql, params = ('SELECT p.*, u.full_name, u.role FROM Payroll p JOIN Users u ON p.user_id = u.user_id'), []
    clauses = []
    if data.get('from'):
        clauses.append('p.clock_in >= %s')
        params.append(parse_date(data['from']) + ' 00:00:00')
    if data.get('to'):
        clauses.append('p.clock_in <= %s')
        params.append(parse_date(data['to']) + ' 23:59:59')
    if clauses:
        sql += ' WHERE ' + ' AND '.join(clauses)
    records = q.all(sql + ' ORDER BY p.payroll_id DESC', tuple(params))
    summary = {}
    for r in records:
        row = summary.setdefault(r['user_id'], {
            'user_id': r['user_id'], 'full_name': r['full_name'], 'role': r['role'], 'shifts': 0,
            'open_shifts': 0, 'hours': Decimal('0'), 'gross_pay': Decimal('0'), 'unpaid': Decimal('0')})
        row['shifts'] += 1
        if r['clock_out'] is None:
            row['open_shifts'] += 1
            continue
        gross = Decimal(str(r['gross_pay'] or 0))
        row['hours'] += Decimal(str(r['hours_worked'] or 0))
        row['gross_pay'] += gross
        if r['payment_status'] != 'Paid':
            row['unpaid'] += gross
    rows = sorted(summary.values(), key=lambda r: r['full_name'])
    for row in rows:
        row['hours'], row['gross_pay'], row['unpaid'] = money(row['hours']), money(row['gross_pay']), money(row['unpaid'])
    return {'records': records, 'summary': rows,
            'employees': q.all('SELECT user_id, full_name, role, account_status, hourly_rate FROM Users ORDER BY full_name')}


def adjust_payroll(q, actor, payroll_id, data):
    record = q.one('SELECT * FROM Payroll WHERE payroll_id=%s' + q.lock(), (payroll_id,))
    if not record:
        raise S.APIError(404, 'Payroll record not found.')
    reason = text(data, 'reason', 'A reason for the adjustment')
    if len(reason) < 3:
        raise S.APIError(400, 'A reason for the adjustment is required.')
    status = data.get('payment_status', record['payment_status'])
    if status not in PAYMENT_STATUSES:
        raise S.APIError(400, 'Payment status must be one of: ' + ', '.join(PAYMENT_STATUSES) + '.')
    changing_pay = data.get('hours_worked') is not None or data.get('hourly_rate') is not None
    if record['clock_out'] is None and (changing_pay or status == 'Paid'):
        raise S.APIError(409, 'This shift is still open. The employee must clock out before it can be adjusted or paid.')
    hours = number(data['hours_worked'], 'Hours worked', minimum=0) if data.get('hours_worked') is not None \
        else (Decimal(str(record['hours_worked'])) if record['hours_worked'] is not None else None)
    if hours is not None and hours > 24:
        raise S.APIError(400, 'Hours worked cannot be more than 24 for one shift.')
    rate = number(data['hourly_rate'], 'Hourly rate', minimum=0) if data.get('hourly_rate') is not None \
        else Decimal(str(record['hourly_rate']))
    gross = money(hours * rate) if hours is not None else None
    q.run('UPDATE Payroll SET hours_worked=%s,hourly_rate=%s,gross_pay=%s,payment_status=%s,adjustment_reason=%s,adjusted_by=%s '
          'WHERE payroll_id=%s', (money(hours) if hours is not None else None, money(rate), gross, status, reason,
                                  actor['user_id'], payroll_id))
    return q.one('SELECT p.*, u.full_name FROM Payroll p JOIN Users u ON p.user_id=u.user_id WHERE p.payroll_id=%s', (payroll_id,))


# --- FR-12: hiring and onboarding ---------------------------------------------
ONBOARDING = ('Not Started', 'In Progress', 'Complete')


def update_applicant(svc, q, applicant_id, data):
    applicant = q.one('SELECT * FROM Job_Applicants WHERE applicant_id=%s' + q.lock(), (applicant_id,))
    if not applicant:
        raise S.APIError(404, 'Applicant not found.')
    status = data.get('application_status', applicant['application_status'])
    if status != applicant['application_status']:
        if status == 'Hired':
            raise S.APIError(400, 'Use the hire action to hire an applicant; it also creates the staff account.')
        if applicant['application_status'] == 'Hired':
            raise S.APIError(409, 'A hired applicant cannot be moved back to an earlier stage.')
        svc.update_applicant_status(q, applicant_id, status)
    onboarding = data.get('onboarding_status', applicant.get('onboarding_status') or 'Not Started')
    if onboarding not in ONBOARDING:
        raise S.APIError(400, 'Onboarding status must be one of: ' + ', '.join(ONBOARDING) + '.')
    if onboarding != 'Not Started' and status != 'Hired':
        raise S.APIError(409, 'Onboarding starts after the applicant is hired.')
    notes = text(data, 'notes', 'Notes', required=False, maxlen=2000) if 'notes' in data else applicant.get('notes')
    q.run('UPDATE Job_Applicants SET onboarding_status=%s, notes=%s WHERE applicant_id=%s', (onboarding, notes, applicant_id))
    return q.one('SELECT * FROM Job_Applicants WHERE applicant_id=%s', (applicant_id,))


def hire_applicant(svc, q, applicant_id, data):
    applicant = q.one('SELECT * FROM Job_Applicants WHERE applicant_id=%s' + q.lock(), (applicant_id,))
    if not applicant:
        raise S.APIError(404, 'Applicant not found.')
    if applicant['application_status'] == 'Hired':
        raise S.APIError(409, 'This applicant has already been hired.')
    if applicant['application_status'] == 'Rejected':
        raise S.APIError(409, 'A rejected applicant cannot be hired.')
    user = svc.create(q, {'full_name': applicant['full_name'], 'role': data.get('role', 'FOH Staff'), 'pin': data.get('pin')})
    if data.get('hourly_rate') is not None:
        q.run('UPDATE Users SET hourly_rate=%s WHERE user_id=%s',
              (money(number(data['hourly_rate'], 'Hourly rate', minimum=0)), user['user_id']))
    q.run('UPDATE Job_Applicants SET application_status=%s, hired_user_id=%s, onboarding_status=%s WHERE applicant_id=%s',
          ('Hired', user['user_id'], 'In Progress', applicant_id))
    return {'applicant': q.one('SELECT * FROM Job_Applicants WHERE applicant_id=%s', (applicant_id,)),
            'user': svc.public(q.one('SELECT * FROM Users WHERE user_id=%s', (user['user_id'],)))}


# --- FR-11: customer service issues -------------------------------------------
def set_issue_status(q, actor, issue_id, data):
    issue = q.one('SELECT * FROM Customer_Service_Issues WHERE issue_id=%s' + q.lock(), (issue_id,))
    if not issue:
        raise S.APIError(404, 'Service issue not found.')
    status = data.get('status')
    if status not in ('Open', 'In Progress', 'Resolved'):
        raise S.APIError(400, 'Status must be Open, In Progress, or Resolved.')
    notes = text(data, 'resolution_notes', 'Resolution notes', required=(status == 'Resolved'), maxlen=2000)
    q.run('UPDATE Customer_Service_Issues SET status=%s, resolution_notes=%s, resolved_at=%s, assigned_to=%s WHERE issue_id=%s',
          (status, notes or issue['resolution_notes'], S.stamp(S.now()) if status == 'Resolved' else None,
           actor['user_id'], issue_id))
    return q.one('SELECT * FROM Customer_Service_Issues WHERE issue_id=%s', (issue_id,))


# --- FR-8: customer reviews ---------------------------------------------------
REVIEW_SOURCES = ('In-App', 'Comment Card', 'Phone', 'Google')


def all_reviews(q):
    return q.all('SELECT * FROM Customer_Reviews ORDER BY review_date DESC, review_id DESC')


def list_reviews(q):
    reviews = all_reviews(q)
    return dict(insights.review_statistics(reviews), reviews=reviews,
                google_connected=insights.google_configured(), ai_connected=insights.ai_configured())


def create_review(q, data):
    name = text(data, 'reviewer_name', 'Reviewer name', required=False, maxlen=100) or 'Guest'
    rating = whole(data.get('rating'), 'Rating', 1, 5)
    body = text(data, 'review_text', 'Review text', maxlen=4000)
    source = data.get('source', 'In-App')
    if source not in REVIEW_SOURCES:
        raise S.APIError(400, 'Source must be one of: ' + ', '.join(REVIEW_SOURCES) + '.')
    current = S.stamp(S.now())
    cur = q.run('INSERT INTO Customer_Reviews (source,reviewer_name,rating,review_text,review_date,created_at) '
                'VALUES (%s,%s,%s,%s,%s,%s)', (source, name, rating, body, current, current))
    return q.one('SELECT * FROM Customer_Reviews WHERE review_id=%s', (cur.lastrowid,))


def latest_summary(q):
    row = q.one('SELECT * FROM Review_Summaries ORDER BY summary_id DESC LIMIT 1')
    if not row:
        return None
    summary = json.loads(row['summary_json'])
    summary['generated_at'] = row['generated_at']
    count = q.one('SELECT COUNT(*) AS c FROM Customer_Reviews')['c']
    summary['is_out_of_date'] = count != row['review_count']
    summary['ai_connected'] = insights.ai_configured()
    return summary


def store_summary(q, summary, user_id):
    q.run('INSERT INTO Review_Summaries (generated_at,generated_by,engine,review_count,average_rating,summary_json) '
          'VALUES (%s,%s,%s,%s,%s,%s)',
          (S.stamp(S.now()), user_id, summary['engine'][:60], summary['review_count'],
           str(summary['average_rating']), json.dumps(summary)))


def generate_summary(q, actor):
    """Read the reviews now; summarise after this transaction ends (the AI call can take seconds)."""
    reviews, user_id = all_reviews(q), actor['user_id']

    def run(svc):
        summary = insights.summarize_reviews(reviews)
        with svc.db.transaction() as q2:
            store_summary(q2, summary, user_id)
            return latest_summary(q2)
    return Deferred(run)


def import_google_reviews(actor):
    def run(svc):
        try:
            found = insights.fetch_google_reviews()
        except RuntimeError as err:
            raise S.APIError(503, str(err))
        added = 0
        with svc.db.transaction() as q:
            for r in found:
                if r['external_id'] and q.one('SELECT review_id FROM Customer_Reviews WHERE external_id=%s', (r['external_id'],)):
                    continue
                q.run('INSERT INTO Customer_Reviews (source,reviewer_name,rating,review_text,review_date,external_id,created_at) '
                      'VALUES (%s,%s,%s,%s,%s,%s,%s)',
                      ('Google', r['reviewer_name'], r['rating'], r['review_text'],
                       r['review_date'] or S.stamp(S.now()), r['external_id'], S.stamp(S.now())))
                added += 1
        return {'imported': added, 'found': len(found)}
    return Deferred(run)


# --- FR-10: consumption analytics ---------------------------------------------
CATEGORY_WORDS = {'meat': ['meat', 'beef', 'poultry'], 'seafood': ['seafood', 'fish'], 'produce': ['produce'],
                  'bakery': ['bakery', 'bread', 'bun'], 'dairy': ['dairy', 'cheese']}

def consumption_report(q, data):
    days = whole(data.get('days', 14), 'Reporting period (days)', 1, 90)
    current = S.now()
    inventory = q.all('SELECT * FROM Inventory ORDER BY item_name')
    transactions = q.all('SELECT inventory_id, quantity_change, reason, timestamp FROM Inventory_Transactions '
                         'WHERE timestamp >= %s', (S.stamp(current - timedelta(days=days)),))
    for t in transactions:
        when = datetime.fromisoformat(str(t.pop('timestamp')).replace('T', ' ')[:19])
        t['age_days'] = (current - when).total_seconds() / 86400.0
    on_order = {}
    for row in q.all("SELECT poi.inventory_id, poi.quantity_ordered, poi.quantity_received FROM Supplier_Order_Items poi "
                     "JOIN Supplier_Orders po ON poi.order_id = po.order_id WHERE po.status IN ('Pending','Partial')"):
        outstanding = float(row['quantity_ordered']) - float(row['quantity_received'])
        on_order[row['inventory_id']] = on_order.get(row['inventory_id'], 0.0) + max(0.0, outstanding)
    suppliers = {}
    for row in q.all('SELECT poi.inventory_id, s.supplier_id, s.supplier_name FROM Supplier_Order_Items poi '
                     'JOIN Supplier_Orders po ON poi.order_id = po.order_id '
                     'JOIN Suppliers s ON po.supplier_id = s.supplier_id ORDER BY po.order_id'):
        suppliers[row['inventory_id']] = {'supplier_id': row['supplier_id'], 'supplier_name': row['supplier_name']}
    # No order history for an item: suggest the supplier whose product category matches it.
    all_suppliers = q.all('SELECT supplier_id, supplier_name, product_category FROM Suppliers ORDER BY supplier_id')
    for inv in inventory:
        if inv['inventory_id'] in suppliers:
            continue
        words = CATEGORY_WORDS.get(str(inv['category']).lower(), [str(inv['category']).lower()])
        match = next((s for s in all_suppliers if any(w in str(s['product_category']).lower() for w in words)), None)
        if match:
            suppliers[inv['inventory_id']] = {'supplier_id': match['supplier_id'], 'supplier_name': match['supplier_name']}
    items = insights.build_forecast(inventory, transactions, on_order, suppliers, days, current.date())
    generated = S.stamp(current)

    def run(svc):
        summary, recommendations, engine, note = insights.narrate_forecast(items, days)
        report = {'period_days': days, 'generated_at': generated, 'engine': engine, 'summary': summary,
                  'recommendations': recommendations, 'items': items, 'ai_connected': insights.ai_configured(),
                  'totals': {'critical': sum(1 for i in items if i['risk'] == 'Critical'),
                             'reorder_soon': sum(1 for i in items if i['risk'] == 'Reorder soon'),
                             'healthy': sum(1 for i in items if i['risk'] == 'Healthy'),
                             'spoilage_cost': round(sum(i['spoiled'] * i['unit_cost'] for i in items), 2)}}
        if note:
            report['engine_note'] = note
        return report
    return Deferred(run)


# --- route table ----------------------------------------------------------------
def dispatch(svc, q, actor, method, path, data):
    """Return a result, a Deferred, or NOT_FOUND when the path is not one of these routes."""
    def match(pattern):
        return re.fullmatch(pattern, path)

    # FR-7 reservations (all signed-in staff)
    if path == '/tables' and method == 'GET':
        return {'records': q.all('SELECT * FROM Dining_Tables ORDER BY table_number')}
    if path == '/reservations':
        if method == 'GET':
            return list_reservations(q, data)
        if method == 'POST':
            return create_reservation(q, actor, data)
    m = match(r'/reservations/(\d+)')
    if m and method == 'PATCH':
        return update_reservation(q, int(m[1]), data)
    m = match(r'/reservations/(\d+)/status')
    if m and method == 'POST':
        return set_reservation_status(q, int(m[1]), data)

    # FR-9 customer orders (all signed-in staff)
    if path == '/menu' and method == 'GET':
        return {'records': q.all('SELECT * FROM Menu_Items ORDER BY category, item_name')}
    if path == '/orders':
        if method == 'GET':
            return list_orders(q, data)
        if method == 'POST':
            return create_order(q, actor, data)
    m = match(r'/orders/(\d+)/(complete|cancel)')
    if m and method == 'POST':
        return close_order(q, int(m[1]), 'Completed' if m[2] == 'complete' else 'Cancelled', data)

    # FR-1 suppliers and purchase orders (managers)
    if path == '/suppliers' and method == 'POST':
        need(actor, MANAGERS)
        return save_supplier(q, data)
    m = match(r'/suppliers/(\d+)')
    if m and method == 'PATCH':
        need(actor, MANAGERS)
        return save_supplier(q, data, int(m[1]))
    m = match(r'/purchase-orders/(\d+)/cancel')
    if m and method == 'POST':
        need(actor, MANAGERS)
        return cancel_purchase_order(svc, q, int(m[1]))

    # FR-3 inventory items (managers)
    if path == '/inventory' and method == 'POST':
        need(actor, MANAGERS)
        return create_inventory_item(q, actor, data)
    m = match(r'/inventory/(\d+)')
    if m and method == 'PATCH':
        need(actor, MANAGERS)
        return update_inventory_item(q, actor, int(m[1]), data)

    # FR-4 payroll (administrators)
    if path == '/payroll' and method == 'GET':
        need(actor, ADMIN)
        return payroll_report(q, data)
    m = match(r'/payroll/(\d+)')
    if m and method == 'PATCH':
        need(actor, ADMIN)
        return adjust_payroll(q, actor, int(m[1]), data)

    # FR-12 hiring (administrators)
    m = match(r'/applicants/(\d+)')
    if m and method == 'PATCH':
        need(actor, ADMIN)
        return update_applicant(svc, q, int(m[1]), data)
    m = match(r'/applicants/(\d+)/hire')
    if m and method == 'POST':
        need(actor, ADMIN)
        return hire_applicant(svc, q, int(m[1]), data)

    # FR-11 customer service (managers change status)
    m = match(r'/service-issues/(\d+)/status')
    if m and method == 'POST':
        need(actor, MANAGERS)
        return set_issue_status(q, actor, int(m[1]), data)

    # FR-8 reviews
    if path == '/reviews':
        if method == 'GET':
            return list_reviews(q)
        if method == 'POST':
            return create_review(q, data)
    if path == '/reviews/import-google' and method == 'POST':
        need(actor, MANAGERS)
        return import_google_reviews(actor)
    if path == '/reviews/summary':
        need(actor, MANAGERS)
        if method == 'GET':
            return latest_summary(q) or generate_summary(q, actor)
        if method == 'POST':
            return generate_summary(q, actor)

    # FR-10 consumption analytics (managers)
    if path == '/analytics/consumption' and method == 'GET':
        need(actor, MANAGERS)
        return consumption_report(q, data)

    return NOT_FOUND
