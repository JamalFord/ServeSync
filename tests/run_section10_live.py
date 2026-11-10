#!/usr/bin/env python3
"""Run the Sprint 4 Section 10 backend test cases over HTTP.

By default this talks to the live ServeSync API on Railway. It covers the
test cases of UC-01, UC-05, UC-08 and UC-11 (the UC-02 cases are done on the
application screens). Only the Python standard library is needed.

    python3 tests/run_section10_live.py                 # live Railway API
    python3 tests/run_section10_live.py --check         # reachability only, no login
    python3 tests/run_section10_live.py --base-url http://127.0.0.1:8000

The script asks for the Administrator PIN (or reads SERVESYNC_ADMIN_PIN). It
never prints or stores a PIN.

What it changes in the database it runs against:
  * creates three test accounts and deactivates them at the end
    (the API has no way to delete an account);
  * creates one test purchase order and receives it;
  * records two test spoilage entries;
  * adds one short shift record for its own test account;
  * puts the two stock quantities it touched back to their starting values,
    which adds one more purchase order and one more spoilage entry.
Real employee accounts are never changed: every test that changes an account,
a PIN or a shift uses an account the script created itself.
"""
import argparse
import getpass
import json
import os
import secrets
import socket
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from decimal import Decimal

DEFAULT_URL = 'https://servesync-production-d1da.up.railway.app'
HERE = os.path.dirname(os.path.abspath(__file__))
JOURNAL = os.path.join(HERE, '.section10_run.json')
DEFAULT_REPORT = os.path.normpath(os.path.join(HERE, '..', 'docs', 'sprint4', 'section10-live-results.md'))

TITLES = {
    '1.1': 'Log in with a valid PIN',
    '1.2': 'Log in with an unknown PIN',
    '1.3': 'Log in with a badly formatted PIN',
    '1.4': 'Log in to a deactivated account',
    '1.5': 'Second login while a session is active',
    '1.6': 'Lockout after five failed attempts',
    '1.7': 'Clock in, and duplicate clock-in',
    '1.8': 'Logging out does not end the shift',
    '1.9': 'Clock out, and clock out with no open shift',
    '5.1': 'Create a purchase order',
    '5.2': 'Purchase order with no lines',
    '5.3': 'Unknown supplier or inventory item',
    '5.4': 'Invalid quantity or unit cost',
    '5.5': 'FOH Staff cannot create or receive purchase orders',
    '5.6': 'Receive a partial delivery',
    '5.7': 'The same delivery submitted twice',
    '5.8': 'Receive more than was ordered',
    '5.9': 'Receive the remaining balance',
    '5.10': 'Invalid receiving requests',
    '8.1': 'Create an employee account',
    '8.2': 'Name length limits',
    '8.3': 'Invalid role or PIN format',
    '8.4': 'PIN already assigned to another employee',
    '8.5': 'A manager or FOH Staff cannot manage accounts',
    '8.6': 'Deactivate and reactivate an account',
    '8.7': 'An administrator cannot deactivate or demote their own account',
    '8.8': "Reset an employee's PIN",
    '8.9': "End another employee's session",
    '8.10': 'Account that does not exist',
    '11.1': 'Record spoilage',
    '11.2': 'Zero or negative quantity',
    '11.3': 'Quantity greater than the stock on hand',
    '11.4': 'Blank reason',
    '11.5': 'Inventory item that does not exist',
    '11.6': 'The same spoilage record submitted twice',
    '11.7': 'FOH Staff cannot record spoilage',
    '11.8': 'Missing request ID',
    '11.9': 'Quantity equal to all remaining stock',
}
USE_CASES = [
    ('UC-01', '1', 'User Authentication & Shift Time Tracking'),
    ('UC-05', '5', 'Procure Supplies & Manage Supplier Purchase Orders'),
    ('UC-08', '8', 'Administer User Accounts & Security Settings'),
    ('UC-11', '11', 'Record Inventory Spoilage'),
]

MSG_PIN = 'PIN must contain exactly four digits.'
MSG_SESSION = ('Employee already has an active session. Log out on that device '
               'or ask an administrator to end the session.')
MSG_LOCKED = 'Too many failed attempts. Wait five minutes.'
MSG_ROLE = 'Manager or Administrator access required.'
MSG_ADMIN = 'Administrator access is required.'
MSG_SPOIL = 'Inventory item ID, positive quantity, and reason are required.'


class Abort(Exception):
    """The run cannot continue (wrong PIN, server unreachable, ...)."""


def D(value):
    return Decimal(str(value))


def num(value):
    """Decimal -> JSON number (whole numbers as int so messages read '9', not '9.0')."""
    value = D(value)
    return int(value) if value == value.to_integral_value() else float(value)


def tc_key(tc):
    a, b = tc.split('.')
    return int(a), int(b)


def new_pin():
    return '%04d' % secrets.randbelow(10000)


class Api:
    def __init__(self, base):
        self.base = base.rstrip('/')
        self.calls = 0

    def call(self, method, path, body=None, token=None):
        """Send one request. Returns (status, parsed JSON or text)."""
        data = None if body is None else json.dumps(body).encode()
        headers = {'Accept': 'application/json', 'User-Agent': 'ServeSync-Section10-Tests/1.0'}
        if data is not None:
            headers['Content-Type'] = 'application/json'
        if token:
            headers['Authorization'] = 'Bearer ' + token
        for attempt in range(6):
            request = urllib.request.Request(self.base + path, data=data, method=method, headers=headers)
            try:
                with urllib.request.urlopen(request, timeout=45) as response:
                    status, raw = response.status, response.read()
            except urllib.error.HTTPError as err:
                status, raw = err.code, err.read()
            except (urllib.error.URLError, socket.timeout, ConnectionError) as err:
                # Only a read is safe to repeat blindly: a write may have been applied.
                if method == 'GET' and attempt < 5:
                    time.sleep(3)
                    continue
                raise Abort('Could not reach %s%s (%s).' % (self.base, path, err))
            if status == 503 and attempt < 5:
                # The API answers 503 while the database is waking up; nothing was done.
                time.sleep(3)
                continue
            self.calls += 1
            try:
                return status, json.loads(raw.decode() or 'null')
            except ValueError:
                return status, raw.decode(errors='replace')[:200]
        raise Abort('The server kept answering 503 for %s.' % path)


class Run:
    def __init__(self, api, run_id):
        self.api, self.run_id = api, run_id
        self.checks = []          # {'tc', 'text', 'ok', 'got'}
        self.skipped = {}         # tc -> reason
        self.notes = []           # things worth telling the reader
        self.left = []            # what the run left in the database
        self.admin = self.mgr = self.foh = None
        self.admin_user = self.mgr_user = self.foh_user = None
        self.foh_pin = None
        self.unknown_pin = None
        self.temp_users = []      # ids of accounts created by this run
        self.orig_stock = {}      # inventory_id -> Decimal before the run
        self.item_names = {}
        self.env = {}
        self.ready = False        # True once the administrator is logged in and the tests can start

    # ---- recording -------------------------------------------------------
    def ok(self, tc, text, cond, got=None):
        self.checks.append({'tc': tc, 'text': text, 'ok': bool(cond), 'got': '' if got is None else str(got)})
        return bool(cond)

    def expect(self, tc, text, response, status, msg=None, starts=None):
        got_status, body = response
        err = body.get('error') if isinstance(body, dict) else None
        cond = got_status == status
        if msg is not None:
            cond = cond and err == msg
        if starts is not None:
            cond = cond and (err or '').startswith(starts)
        got = 'status %s' % got_status + (', "%s"' % err if err else '')
        return self.ok(tc, text, cond, got)

    def section(self, tc, fn):
        """Run one group of steps; a script error becomes a failed check, not a crash."""
        try:
            fn()
        except Abort:
            raise
        except Exception as err:  # noqa: BLE001 - report and carry on with the next group
            self.ok(tc, 'steps could be completed', False, 'script error: %r' % (err,))

    # ---- small API helpers -----------------------------------------------
    def call(self, method, path, body=None, token=None):
        return self.api.call(method, path, body, token)

    def login(self, pin):
        return self.call('POST', '/login', {'pin': pin})

    def alive(self, token):
        return bool(token) and self.call('GET', '/me', token=token)[0] == 200

    def inventory(self, token):
        status, rows = self.call('GET', '/inventory', token=token)
        if status != 200 or not isinstance(rows, list):
            raise RuntimeError('GET /inventory answered %s' % status)
        return {int(r['inventory_id']): r for r in rows}

    def stock(self, token, inv_id):
        return D(self.inventory(token)[inv_id]['quantity'])

    def orders(self, token):
        status, rows = self.call('GET', '/purchase-orders', token=token)
        if status != 200 or not isinstance(rows, list):
            raise RuntimeError('GET /purchase-orders answered %s' % status)
        return rows

    def order(self, token, order_id):
        return next(o for o in self.orders(token) if int(o['order_id']) == order_id)

    def spoilage(self, token):
        status, rows = self.call('GET', '/inventory/spoilage', token=token)
        if status != 200 or not isinstance(rows, list):
            raise RuntimeError('GET /inventory/spoilage answered %s' % status)
        return rows

    def users(self):
        status, body = self.call('GET', '/users', token=self.admin)
        if status != 200:
            raise RuntimeError('GET /users answered %s' % status)
        return body['users']

    def payroll(self, user_id):
        status, body = self.call('GET', '/payroll', token=self.admin)
        if status != 200:
            raise RuntimeError('GET /payroll answered %s' % status)
        return [r for r in body['records'] if int(r['user_id']) == int(user_id)]

    def create_user(self, name, role):
        """Create an account with a PIN nobody uses. Returns (status, body, pin)."""
        for _ in range(40):
            pin = new_pin()
            status, body = self.call('POST', '/users', {'full_name': name, 'role': role, 'pin': pin}, self.admin)
            if status == 409:
                continue
            if status == 200:
                self.temp_users.append(int(body['user']['user_id']))
                self.save_journal()
            return status, body, pin
        return 409, {'error': 'no free PIN found'}, None

    @staticmethod
    def absent(ids, preferred):
        ids = set(ids)
        return preferred if preferred not in ids else max(ids) + 1000

    def rid(self, label):
        return 's10-%s-%s' % (self.run_id, label)

    # ---- journal: lets the next run clean up if this one is killed ---------
    def save_journal(self):
        data = {'base': self.api.base, 'admin_token': self.admin, 'temp_users': self.temp_users,
                'stock': {str(k): str(v) for k, v in self.orig_stock.items()}}
        fd = os.open(JOURNAL, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as handle:
            json.dump(data, handle)

    def recover_before_login(self):
        try:
            with open(JOURNAL) as handle:
                previous = json.load(handle)
        except (OSError, ValueError):
            return None
        if previous.get('base') != self.api.base:
            return None
        print('A previous run did not finish. Cleaning up after it first.')
        if previous.get('admin_token'):
            self.call('POST', '/logout', {}, previous['admin_token'])
        return previous

    def recover_after_login(self, previous):
        for uid in previous.get('temp_users', []):
            self.call('DELETE', '/users/%d' % uid, token=self.admin)
        for key, value in previous.get('stock', {}).items():
            self.orig_stock[int(key)] = D(value)
        self.notes.append('A previous run had stopped early. Its test accounts were deactivated and its '
                          'starting stock values were used as the values to restore.')

    # ---- UC-01, part 1 -----------------------------------------------------
    def uc01_before_login(self):
        # 1.2 Unknown PIN. 9999 is the documented value; if it is in use, pick another.
        candidates = ['9999'] + [new_pin() for _ in range(8)]
        for pin in candidates:
            status, body = self.login(pin)
            if status == 401:
                self.unknown_pin = pin
                self.expect('1.2', 'unknown PIN is rejected with 401 "Invalid Code"', (status, body), 401, 'Invalid Code')
                break
            if status == 429:
                raise Abort('This device is locked out after too many failed logins. Wait five minutes and run again.')
            if status == 200:   # the PIN belongs to somebody: close that session again at once
                self.call('POST', '/logout', {}, body.get('token'))
        else:
            self.ok('1.2', 'an unassigned PIN could be found for the test', False)
        self.expect('1.2', 'no session is created: a request without a token is refused',
                    self.call('GET', '/me'), 401, 'Please log in.')

        # 1.3 Badly formatted PINs
        for label, pin in (('three digits', '123'), ('five digits', '12345'), ('a letter', '12a4'), ('empty text', '')):
            self.expect('1.3', 'PIN with %s is rejected with 400' % label, self.login(pin), 400, MSG_PIN)

    def admin_login(self, pin):
        status, body = self.login(pin)
        if status == 409:
            raise Abort('The Administrator is still logged in somewhere else, so the script cannot log in.\n'
                        '  Log out of the ServeSync app on that device (or wait for the session to expire) and run again.')
        if status == 401:
            raise Abort('That PIN was not accepted.')
        if status == 429:
            raise Abort('This device is locked out after too many failed logins. Wait five minutes and run again.')
        if status != 200:
            raise Abort('Login answered status %s: %s' % (status, body))
        self.admin, self.admin_user = body.get('token'), body.get('user', {})
        self.save_journal()
        if self.admin_user.get('role') != 'Administrator':
            raise Abort('That PIN belongs to %s (%s). The Administrator PIN is needed.'
                        % (self.admin_user.get('full_name'), self.admin_user.get('role')))

        # 1.1 Valid login
        self.ok('1.1', 'login succeeds with status 200', status == 200, 'status %s' % status)
        self.ok('1.1', 'response contains a session token', bool(self.admin))
        self.ok('1.1', 'response contains the user with role Administrator',
                self.admin_user.get('role') == 'Administrator' and bool(self.admin_user.get('full_name')),
                '%s, %s' % (self.admin_user.get('full_name'), self.admin_user.get('role')))
        self.ok('1.1', 'response contains a shift status', isinstance(body.get('shift_status'), dict)
                and 'is_clocked_in' in body['shift_status'], body.get('shift_status'))
        self.expect('1.1', 'the token is accepted (a session exists)', self.call('GET', '/me', token=self.admin), 200)
        if body.get('shift_status', {}).get('is_clocked_in'):
            self.notes.append('The Administrator already had an open shift before the run. It was left as it was. '
                              'That a login does not create a shift is checked with the new account in 8.1.')

        # 1.5 Second login while the first session is active
        self.expect('1.5', 'second login with the same PIN is rejected with 409', self.login(pin), 409, MSG_SESSION)
        self.expect('1.5', 'the first session is still valid', self.call('GET', '/me', token=self.admin), 200)

    # ---- set-up data -------------------------------------------------------
    def read_baseline(self):
        inv = self.inventory(self.admin)
        status, suppliers = self.call('GET', '/suppliers', token=self.admin)
        if len(inv) < 2 or status != 200 or not suppliers:
            raise Abort('The database needs at least two inventory items and one supplier for these tests.')
        self.item_a, self.item_b = sorted(inv)[:2]
        self.supplier = min(int(s['supplier_id']) for s in suppliers)
        self.supplier_name = next(s['supplier_name'] for s in suppliers if int(s['supplier_id']) == self.supplier)
        for inv_id in (self.item_a, self.item_b):
            self.item_names[inv_id] = '%s (%s)' % (inv[inv_id]['item_name'], inv[inv_id]['unit'])
            self.orig_stock.setdefault(inv_id, D(inv[inv_id]['quantity']))
        self.no_item = self.absent(inv, 999)
        self.no_supplier = self.absent([int(s['supplier_id']) for s in suppliers], 999)
        self.no_order = self.absent([int(o['order_id']) for o in self.orders(self.admin)] or [0], 999)
        self.no_user = self.absent([int(u['user_id']) for u in self.users()], 9999)
        self.save_journal()
        self.ready = True

    # ---- UC-08, part 1 -----------------------------------------------------
    def uc08_create(self):
        before = len(self.users())

        # 8.1 Create an account
        name = 'Test Server %s' % self.run_id
        status, body, pin = self.create_user(name, 'FOH Staff')
        self.expect('8.1', 'account is created (status 200)', (status, body), 200)
        user = body.get('user', {}) if isinstance(body, dict) else {}
        self.foh_user, self.foh_pin = user, pin
        self.ok('8.1', 'response has the ID, name, role FOH Staff and status Active',
                bool(user.get('user_id')) and user.get('full_name') == name and user.get('role') == 'FOH Staff'
                and user.get('account_status') == 'Active', user)
        self.ok('8.1', 'response does not contain the PIN or its hash',
                not any(k in user for k in ('pin', 'access_code', 'pin_lookup')) and pin not in json.dumps(body),
                'fields: %s' % ', '.join(sorted(user)))
        status, body = self.login(pin)
        self.expect('8.1', 'the new employee can log in with the PIN', (status, body), 200)
        self.foh = body.get('token') if status == 200 else None
        if status == 200:
            self.ok('1.1', 'a login does not create a shift: the new account is "not clocked in"',
                    body['shift_status']['is_clocked_in'] is False, body['shift_status'])
            rows = self.payroll(user['user_id'])
            self.ok('1.1', 'a login does not create a Payroll record (new account has none)', len(rows) == 0,
                    '%d record(s)' % len(rows))

        # 8.2 Name length limits
        body_for = lambda n: {'full_name': n, 'role': 'FOH Staff', 'pin': new_pin()}  # noqa: E731
        msg = 'Name is required and must be at most 100 characters.'
        self.expect('8.2', 'blank name is rejected with 400', self.call('POST', '/users', body_for('   '), self.admin), 400, msg)
        self.expect('8.2', '101-character name is rejected with 400',
                    self.call('POST', '/users', body_for('X' * 101), self.admin), 400, msg)
        long_name = ('Test Name Limit %s ' % self.run_id).ljust(100, 'x')
        status, body, _ = self.create_user(long_name, 'FOH Staff')
        self.expect('8.2', '100-character name is accepted', (status, body), 200)
        if status == 200:
            self.ok('8.2', 'the stored name has all 100 characters', len(body['user']['full_name']) == 100,
                    '%d characters' % len(body['user']['full_name']))

        # 8.3 Invalid role or PIN format
        count = len(self.users())
        self.expect('8.3', 'role "Chef" is rejected with 400', self.call(
            'POST', '/users', {'full_name': 'Test Chef', 'role': 'Chef', 'pin': new_pin()}, self.admin), 400, 'Invalid role.')
        self.expect('8.3', 'PIN "12" is rejected with 400', self.call(
            'POST', '/users', {'full_name': 'Test Short Pin', 'role': 'FOH Staff', 'pin': '12'}, self.admin), 400, MSG_PIN)
        self.ok('8.3', 'no account was added', len(self.users()) == count)

        # 8.4 PIN already assigned
        self.expect('8.4', 'a PIN that is already in use is rejected with 409', self.call(
            'POST', '/users', {'full_name': 'Second User', 'role': 'FOH Staff', 'pin': self.foh_pin}, self.admin),
            409, 'PIN is already assigned. Choose another PIN.')
        self.ok('8.4', 'no account was added', len(self.users()) == count)
        self.ok('8.2', 'exactly two accounts were created by 8.1 and 8.2', count == before + 2,
                '%d before, %d after' % (before, count))

    def setup_manager(self):
        status, body, pin = self.create_user('Test Manager %s' % self.run_id, 'Manager')
        if status == 200:
            self.mgr_user = body['user']
            status, body = self.login(pin)
            self.mgr = body.get('token') if status == 200 else None
        if not self.mgr:
            self.notes.append('The test Manager account could not be created, so the Manager steps were run '
                              'with the Administrator session.')

    def uc08_roles(self):
        # 8.5 Manager and FOH Staff cannot manage accounts
        count = len(self.users())
        for who, token in (('Manager', self.mgr), ('FOH Staff', self.foh)):
            if not token:
                self.ok('8.5', '%s session available for the test' % who, False)
                continue
            self.expect('8.5', '%s cannot list users (403)' % who, self.call('GET', '/users', token=token), 403, MSG_ADMIN)
            self.expect('8.5', '%s cannot create a user (403)' % who, self.call(
                'POST', '/users', {'full_name': 'Not Allowed', 'role': 'FOH Staff', 'pin': new_pin()}, token), 403, MSG_ADMIN)
        self.ok('8.5', 'no account was added', len(self.users()) == count)

    # ---- UC-01, part 2: shifts (uses the account created in 8.1) -----------
    def uc01_shifts(self):
        uid = self.foh_user['user_id']
        # 1.7 Clock in, duplicate clock-in
        status, body = self.call('POST', '/clock-in', {}, self.foh)
        self.expect('1.7', 'clock-in succeeds', (status, body), 200)
        self.ok('1.7', 'response says "clocked in" with a clock-in time',
                status == 200 and body.get('is_clocked_in') is True and bool(body.get('clock_in_time')), body)
        rows = self.payroll(uid)
        self.ok('1.7', 'one Payroll record exists, with no clock-out time and status Pending',
                len(rows) == 1 and rows[0].get('clock_out') is None and rows[0].get('payment_status') == 'Pending',
                '%d record(s)' % len(rows))
        self.expect('1.7', 'second clock-in is rejected with 409', self.call('POST', '/clock-in', {}, self.foh), 409,
                    'Employee already has an active shift. Duplicate clock-in is prohibited.')
        self.ok('1.7', 'still only one Payroll record', len(self.payroll(uid)) == 1)

        # 1.8 Logging out does not end the shift
        old = self.foh
        status, body = self.call('POST', '/logout', {}, old)
        self.expect('1.8', 'logout succeeds', (status, body), 200)
        self.ok('1.8', 'message says the shift remains open',
                isinstance(body, dict) and body.get('message') == 'Logged out of session. Active shifts remain open.', body)
        rows = self.payroll(uid)
        self.ok('1.8', 'the Payroll record still has no clock-out time', len(rows) == 1 and rows[0].get('clock_out') is None)
        self.expect('1.8', 'the old token is rejected with 401', self.call('GET', '/me', token=old), 401, 'Please log in.')
        status, body = self.login(self.foh_pin)
        self.foh = body.get('token') if status == 200 else None
        self.ok('1.8', 'after logging in again the shift status is "clocked in"',
                status == 200 and body['shift_status']['is_clocked_in'] is True,
                body.get('shift_status') if status == 200 else 'status %s' % status)

        # 1.9 Clock out, and clock out again
        time.sleep(1)
        status, body = self.call('POST', '/clock-out', {}, self.foh)
        self.expect('1.9', 'clock-out succeeds', (status, body), 200)
        self.ok('1.9', 'response says "not clocked in"', status == 200 and body.get('is_clocked_in') is False, body)
        rows = self.payroll(uid)
        row = rows[0] if rows else {}
        filled = all(row.get(k) is not None for k in ('clock_out', 'hours_worked', 'gross_pay'))
        self.ok('1.9', 'the Payroll record has a clock-out time, hours worked and gross pay; status Pending',
                len(rows) == 1 and filled and row.get('payment_status') == 'Pending',
                {k: str(row.get(k)) for k in ('hours_worked', 'hourly_rate', 'gross_pay', 'payment_status')})
        if filled:
            # gross pay is calculated before hours are rounded to 2 places, so allow that rounding
            limit = D('0.005') * D(row['hourly_rate']) + D('0.01')
            self.ok('1.9', 'gross pay equals hours worked x hourly rate',
                    abs(D(row['gross_pay']) - D(row['hours_worked']) * D(row['hourly_rate'])) <= limit,
                    '%s x %s -> %s' % (row['hours_worked'], row['hourly_rate'], row['gross_pay']))
        self.expect('1.9', 'second clock-out is rejected with 400', self.call('POST', '/clock-out', {}, self.foh), 400,
                    'Employee does not have an active shift to clock out from.')
        self.left.append('One closed shift record (a few seconds long) for the test account "%s".' % self.foh_user['full_name'])

    # ---- UC-05 ---------------------------------------------------------------
    def uc05(self):
        boss, a, b, sup = self.mgr or self.admin, self.item_a, self.item_b, self.supplier
        a0, b0 = self.stock(boss, a), self.stock(boss, b)
        lines = [{'inventory_id': a, 'quantity_ordered': 20, 'unit_cost': 2.50},
                 {'inventory_id': b, 'quantity_ordered': 10, 'unit_cost': 4.00}]

        # 5.1 Create
        status, body = self.call('POST', '/purchase-orders', {'supplier_id': sup, 'items': lines}, boss)
        self.expect('5.1', 'purchase order is created', (status, body), 200)
        po = body.get('order', body) if isinstance(body, dict) else {}
        po_id = int(po.get('order_id', 0))
        self.ok('5.1', 'status is Pending', po.get('status') == 'Pending', po.get('status'))
        self.ok('5.1', 'total is 90.00', po_id and D(po.get('total_amount', 0)) == D('90.00'), po.get('total_amount'))
        self.ok('5.1', 'the order has two lines', len(po.get('items', [])) == 2, '%d line(s)' % len(po.get('items', [])))
        self.ok('5.1', 'stock is not changed by creating the order',
                self.stock(boss, a) == a0 and self.stock(boss, b) == b0)
        if not po_id:
            raise RuntimeError('no purchase order to continue with')
        self.left.append('Purchase order #%d (supplier "%s"), fully received.' % (po_id, self.supplier_name))
        line_a = next(int(i['item_id']) for i in po['items'] if int(i['inventory_id']) == a)
        line_b = next(int(i['item_id']) for i in po['items'] if int(i['inventory_id']) == b)
        count = len(self.orders(boss))

        # 5.2 No lines
        self.expect('5.2', 'order with no lines is rejected with 400', self.call(
            'POST', '/purchase-orders', {'supplier_id': sup, 'items': []}, boss), 400,
            'Supplier ID and at least one order line are required.')

        # 5.3 Unknown supplier / item
        self.expect('5.3', 'unknown supplier is rejected with 404', self.call(
            'POST', '/purchase-orders', {'supplier_id': self.no_supplier, 'items': lines}, boss), 404, 'Supplier not found.')
        self.expect('5.3', 'unknown inventory item is rejected with 404', self.call(
            'POST', '/purchase-orders',
            {'supplier_id': sup, 'items': [{'inventory_id': self.no_item, 'quantity_ordered': 5, 'unit_cost': 1.00}]},
            boss), 404, 'Inventory item %d not found.' % self.no_item)

        # 5.4 Invalid quantity or cost
        for label, qty, cost in (('quantity 0', 0, 2.50), ('quantity -5', -5, 2.50), ('unit cost -1.00', 10, -1.00)):
            self.expect('5.4', '%s is rejected with 400' % label, self.call(
                'POST', '/purchase-orders',
                {'supplier_id': sup, 'items': [{'inventory_id': a, 'quantity_ordered': qty, 'unit_cost': cost}]},
                boss), 400, 'Invalid quantity or unit cost.')
        self.ok('5.2', 'no order was created by the rejected requests of 5.2 to 5.4', len(self.orders(boss)) == count)

        # 5.5 FOH Staff
        if self.foh:
            self.expect('5.5', 'FOH Staff cannot create a purchase order (403)', self.call(
                'POST', '/purchase-orders', {'supplier_id': sup, 'items': lines}, self.foh), 403, MSG_ROLE)
            self.expect('5.5', 'FOH Staff cannot receive a delivery (403)', self.call(
                'POST', '/purchase-orders/%d/receive' % po_id,
                {'request_id': self.rid('rcv-foh'), 'received_items': [{'item_id': line_a, 'quantity_received': 1}]},
                self.foh), 403, MSG_ROLE)
            self.ok('5.5', 'no order was created and stock is unchanged',
                    len(self.orders(boss)) == count and self.stock(boss, a) == a0)
        else:
            self.ok('5.5', 'FOH Staff session available for the test', False)

        # 5.6 Partial delivery
        partial = {'request_id': self.rid('rcv-1'), 'received_items': [{'item_id': line_a, 'quantity_received': 12}],
                   'notes': 'Section 10 automated test run %s' % self.run_id}
        receive = '/purchase-orders/%d/receive' % po_id
        status, body = self.call('POST', receive, partial, boss)
        self.expect('5.6', 'partial delivery is accepted', (status, body), 200)
        po = self.order(boss, po_id)
        received = lambda o, line: D(next(i for i in o['items'] if int(i['item_id']) == line)['quantity_received'])  # noqa: E731
        self.ok('5.6', 'order status changes to Partial', po['status'] == 'Partial', po['status'])
        self.ok('5.6', 'the line shows 12 received', received(po, line_a) == 12, received(po, line_a))
        self.ok('5.6', 'stock of the first item goes up by exactly 12', self.stock(boss, a) == a0 + 12,
                '%s -> %s' % (a0, self.stock(boss, a)))

        # 5.7 Same delivery again
        self.expect('5.7', 'the repeated request is accepted', self.call('POST', receive, partial, boss), 200)
        po = self.order(boss, po_id)
        self.ok('5.7', 'stock is unchanged', self.stock(boss, a) == a0 + 12, self.stock(boss, a))
        self.ok('5.7', 'the line still shows 12 received', received(po, line_a) == 12, received(po, line_a))

        # 5.8 More than outstanding
        self.expect('5.8', '9 units against 8 outstanding is rejected with 400', self.call(
            'POST', receive, {'request_id': self.rid('rcv-over'),
                              'received_items': [{'item_id': line_a, 'quantity_received': 9}]}, boss),
            400, starts='Received quantity (9) exceeds outstanding balance')
        self.ok('5.8', 'stock is unchanged and the order is still Partial',
                self.stock(boss, a) == a0 + 12 and self.order(boss, po_id)['status'] == 'Partial')

        # 5.10 b and d need an order that is still open, so they are done here, before 5.9 closes it.
        self.expect('5.10', 'b) request with no request ID is rejected with 400', self.call(
            'POST', receive, {'received_items': [{'item_id': line_a, 'quantity_received': 1}]}, boss),
            400, 'Request ID is required for idempotent delivery processing.')
        self.expect('5.10', 'd) empty list of received items is rejected with 400', self.call(
            'POST', receive, {'request_id': self.rid('rcv-empty'), 'received_items': []}, boss),
            400, 'No received items specified.')
        self.ok('5.10', 'b, d) stock is unchanged', self.stock(boss, a) == a0 + 12)

        # 5.9 Remaining balance
        status, body = self.call('POST', receive, {
            'request_id': self.rid('rcv-2'),
            'received_items': [{'item_id': line_a, 'quantity_received': 8}, {'item_id': line_b, 'quantity_received': 10}],
            'notes': 'Section 10 automated test run %s' % self.run_id}, boss)
        self.expect('5.9', 'the remaining balance is accepted', (status, body), 200)
        self.ok('5.9', 'order status changes to Received', self.order(boss, po_id)['status'] == 'Received')
        self.ok('5.9', 'stock of the first item is up by 20 in total', self.stock(boss, a) == a0 + 20,
                '%s -> %s' % (a0, self.stock(boss, a)))
        self.ok('5.9', 'stock of the second item is up by 10', self.stock(boss, b) == b0 + 10,
                '%s -> %s' % (b0, self.stock(boss, b)))

        # 5.10 a and c
        self.expect('5.10', 'a) delivery against a Received order is rejected with 400', self.call(
            'POST', receive, {'request_id': self.rid('rcv-3'),
                              'received_items': [{'item_id': line_a, 'quantity_received': 1}]}, boss),
            400, "Cannot receive items on an order with status 'Received'.")
        self.expect('5.10', 'c) order that does not exist is rejected with 404', self.call(
            'POST', '/purchase-orders/%d/receive' % self.no_order,
            {'request_id': self.rid('rcv-4'), 'received_items': [{'item_id': line_a, 'quantity_received': 1}]}, boss),
            404, 'Purchase order not found.')
        self.ok('5.10', 'a, c) stock is unchanged',
                self.stock(boss, a) == a0 + 20 and self.stock(boss, b) == b0 + 10)

    # ---- UC-11 ---------------------------------------------------------------
    def uc11(self):
        boss, a = self.mgr or self.admin, self.item_a
        s0 = self.stock(boss, a)
        if s0 < 6:
            raise RuntimeError('stock of the first item is %s; at least 6 is needed' % s0)
        note = 'Section 10 automated test run %s' % self.run_id
        first = {'request_id': self.rid('spl-1'), 'inventory_id': a, 'quantity': 5, 'reason': 'Expired', 'notes': note}
        record = lambda body: body.get('spoilage', body.get('record', body))  # noqa: E731

        # 11.1 Record spoilage
        status, body = self.call('POST', '/inventory/spoilage', first, boss)
        self.expect('11.1', 'spoilage of 5 is accepted', (status, body), 200)
        rec = record(body) if status == 200 else {}
        s1 = s0 - 5
        self.ok('11.1', 'stock goes down by exactly 5', self.stock(boss, a) == s1, '%s -> %s' % (s0, self.stock(boss, a)))
        self.ok('11.1', 'the record shows the stock before and after',
                rec and D(rec.get('stock_before', -1)) == s0 and D(rec.get('stock_after', -1)) == s1,
                'before %s, after %s' % (rec.get('stock_before'), rec.get('stock_after')))
        log = self.spoilage(boss)
        self.ok('11.1', 'the record appears in the spoilage log with the reason "Expired"',
                any(r['spoilage_id'] == rec.get('spoilage_id') and r['reason'] == 'Expired' for r in log))
        count = len(log)
        if rec:
            self.left.append('Spoilage record #%s (5 of %s, reason "Expired").' % (rec.get('spoilage_id'), self.item_names[a]))

        def post(label, **changes):
            body = {'request_id': self.rid(label), 'inventory_id': a, 'quantity': 1, 'reason': 'Expired', 'notes': note}
            body.update(changes)
            return self.call('POST', '/inventory/spoilage', {k: v for k, v in body.items() if v is not None}, boss)

        # 11.2 Zero or negative
        self.expect('11.2', 'quantity 0 is rejected with 400', post('spl-zero', quantity=0), 400, MSG_SPOIL)
        self.expect('11.2', 'quantity -3 is rejected with 400', post('spl-neg', quantity=-3), 400, MSG_SPOIL)
        self.ok('11.2', 'stock is unchanged', self.stock(boss, a) == s1)

        # 11.3 More than the stock on hand
        over = s1 + D('0.01')
        self.expect('11.3', 'stock + 0.01 (%s) is rejected with 400' % over,
                    post('spl-over', quantity=num(over), reason='Damaged'), 400,
                    starts='Spoiled quantity (%s) exceeds available stock' % num(over))
        self.ok('11.3', 'stock is unchanged and no record was created',
                self.stock(boss, a) == s1 and len(self.spoilage(boss)) == count)

        # 11.4 Blank reason
        self.expect('11.4', 'blank reason is rejected with 400', post('spl-blank', quantity=2, reason=''), 400, MSG_SPOIL)
        self.ok('11.4', 'stock is unchanged', self.stock(boss, a) == s1)

        # 11.5 Unknown item
        self.expect('11.5', 'unknown inventory item is rejected with 404',
                    post('spl-noitem', inventory_id=self.no_item), 404, 'Inventory item not found.')

        # 11.6 Same request again
        status, body = self.call('POST', '/inventory/spoilage', first, boss)
        self.expect('11.6', 'the repeated request is accepted', (status, body), 200)
        again = record(body) if status == 200 else {}
        self.ok('11.6', 'the original record is returned', bool(rec) and again.get('spoilage_id') == rec.get('spoilage_id'))
        self.ok('11.6', 'stock is not reduced a second time', self.stock(boss, a) == s1, self.stock(boss, a))
        self.ok('11.6', 'no second record was created', len(self.spoilage(boss)) == count)

        # 11.7 FOH Staff
        if self.foh:
            self.expect('11.7', 'FOH Staff cannot record spoilage (403)', self.call(
                'POST', '/inventory/spoilage',
                {'request_id': self.rid('spl-foh'), 'inventory_id': a, 'quantity': 1, 'reason': 'Expired'}, self.foh),
                403, MSG_ROLE)
            self.ok('11.7', 'stock is unchanged', self.stock(boss, a) == s1)
        else:
            self.ok('11.7', 'FOH Staff session available for the test', False)

        # 11.8 Missing request ID
        self.expect('11.8', 'request with no request ID is rejected with 400', self.call(
            'POST', '/inventory/spoilage', {'inventory_id': a, 'quantity': 1, 'reason': 'Expired'}, boss),
            400, 'Request ID is required for idempotent spoilage processing.')
        self.ok('11.8', 'stock is unchanged', self.stock(boss, a) == s1)

        # 11.9 Exactly all remaining stock
        status, body = post('spl-all', quantity=num(s1), reason='Contaminated')
        self.expect('11.9', 'quantity equal to the stock on hand (%s) is accepted' % s1, (status, body), 200)
        rec = record(body) if status == 200 else {}
        self.ok('11.9', 'stock becomes 0', self.stock(boss, a) == 0, self.stock(boss, a))
        self.ok('11.9', 'the record shows stock before %s and after 0' % s1,
                rec and D(rec.get('stock_before', -1)) == s1 and D(rec.get('stock_after', -1)) == 0,
                'before %s, after %s' % (rec.get('stock_before'), rec.get('stock_after')))
        if rec:
            self.left.append('Spoilage record #%s (%s of %s, reason "Contaminated").'
                             % (rec.get('spoilage_id'), num(s1), self.item_names[a]))

    # ---- UC-08, part 2 (uses the account created in 8.1) ----------------------
    def uc08_changes(self):
        uid, own = int(self.foh_user['user_id']), int(self.admin_user['user_id'])
        path = '/users/%d' % uid
        mine = '/users/%d' % own
        msg = 'You cannot deactivate or demote your own administrator account.'

        # 8.7 Own account
        self.expect('8.7', 'administrator cannot deactivate their own account (409)',
                    self.call('DELETE', mine, token=self.admin), 409, msg)
        self.expect('8.7', 'administrator cannot demote their own account (409)',
                    self.call('PATCH', mine, {'role': 'Manager'}, self.admin), 409, msg)
        status, body = self.call('GET', '/me', token=self.admin)
        self.ok('8.7', 'the account is still Active with the role Administrator',
                status == 200 and body['user']['role'] == 'Administrator' and body['user']['account_status'] == 'Active')

        # 8.9 End another employee's session
        if not self.alive(self.foh):
            status, body = self.login(self.foh_pin)
            self.foh = body.get('token') if status == 200 else None
        old = self.foh
        status, body = self.call('POST', path + '/end-session', {}, self.admin)
        self.expect('8.9', 'ending the session succeeds', (status, body), 200)
        self.ok('8.9', 'message is "Session revoked."', isinstance(body, dict) and body.get('message') == 'Session revoked.', body)
        self.expect('8.9', "the employee's token is rejected with 401", self.call('GET', '/me', token=old), 401, 'Please log in.')
        status, body = self.login(self.foh_pin)
        self.expect('8.9', 'the employee can log in again with the same PIN', (status, body), 200)
        self.foh = body.get('token') if status == 200 else None

        # 8.8 Reset the PIN
        old, old_pin, new = self.foh, self.foh_pin, None
        for _ in range(40):
            candidate = new_pin()
            status, body = self.call('PATCH', path, {'pin': candidate}, self.admin)
            if status != 409:
                new = candidate if status == 200 else None
                break
        self.expect('8.8', 'PIN reset is accepted', (status, body), 200)
        self.expect('8.8', 'the existing session is ended (old token 401)', self.call('GET', '/me', token=old), 401, 'Please log in.')
        self.expect('8.8', 'the old PIN is rejected with 401', self.login(old_pin), 401, 'Invalid Code')
        if new:
            self.foh_pin = new
            status, body = self.login(new)
            self.expect('8.8', 'the new PIN logs in', (status, body), 200)
            self.foh = body.get('token') if status == 200 else None

        # 8.6 Deactivate and reactivate (and 1.4: login to a deactivated account)
        old = self.foh
        status, body = self.call('DELETE', path, token=self.admin)
        self.expect('8.6', 'deactivation is accepted', (status, body), 200)
        row = next((u for u in self.users() if int(u['user_id']) == uid), None)
        self.ok('8.6', 'the account still exists and its status is Inactive',
                bool(row) and row['account_status'] == 'Inactive', row)
        self.expect('8.6', "the employee's token is rejected with 401", self.call('GET', '/me', token=old), 401, 'Please log in.')
        self.expect('8.6', "the employee's PIN is rejected with 401", self.login(self.foh_pin), 401, 'Invalid Code')
        response = self.login(self.foh_pin)
        self.expect('1.4', 'PIN of a deactivated account is rejected with 401 "Invalid Code"', response, 401, 'Invalid Code')
        unknown = self.login(self.unknown_pin) if self.unknown_pin else (0, {})
        self.ok('1.4', 'the answer is identical to the one for an unknown PIN (does not reveal the account)',
                response == unknown, 'deactivated: %s / unknown: %s' % (response, unknown))
        status, body = self.call('PATCH', path, {'account_status': 'Active'}, self.admin)
        self.expect('8.6', 'reactivation is accepted', (status, body), 200)
        status, body = self.login(self.foh_pin)
        self.expect('8.6', 'after reactivation the employee can log in again', (status, body), 200)
        self.foh = body.get('token') if status == 200 else None

        # 8.10 Unknown account
        self.expect('8.10', 'user ID %d is rejected with 404' % self.no_user,
                    self.call('PATCH', '/users/%d' % self.no_user, {'role': 'Manager'}, self.admin), 404, 'User not found.')

    # ---- tear down ---------------------------------------------------------
    def restore_stock(self):
        token = self.mgr if self.alive(self.mgr) else self.admin
        note = 'Section 10 automated test run %s: tear down, puts stock back to its starting value' % self.run_id
        current = self.inventory(token)
        for inv_id, original in sorted(self.orig_stock.items()):
            if inv_id not in current:
                continue
            delta = D(current[inv_id]['quantity']) - original
            name = self.item_names.get(inv_id, 'item %d' % inv_id)
            if delta > 0:
                status, _ = self.call('POST', '/inventory/spoilage', {
                    'request_id': self.rid('restore-%d' % inv_id), 'inventory_id': inv_id, 'quantity': num(delta),
                    'reason': 'Test tear down', 'notes': note}, token)
                if status == 200:
                    self.left.append('Spoilage record of %s %s with the reason "Test tear down" (removes the stock '
                                     'the test delivery added).' % (num(delta), name))
            elif delta < 0:
                status, body = self.call('POST', '/purchase-orders', {'supplier_id': self.supplier, 'items': [
                    {'inventory_id': inv_id, 'quantity_ordered': num(-delta), 'unit_cost': 0}]}, token)
                if status == 200:
                    po = body.get('order', body)
                    self.call('POST', '/purchase-orders/%d/receive' % int(po['order_id']), {
                        'request_id': self.rid('restore-%d' % inv_id), 'notes': note,
                        'received_items': [{'item_id': int(po['items'][0]['item_id']), 'quantity_received': num(-delta)}]}, token)
                    self.left.append('Purchase order #%s for %s %s at $0.00, fully received (puts back the stock '
                                     'the spoilage tests removed).' % (po['order_id'], num(-delta), name))
        after = self.inventory(token)
        wrong = ['%s is %s, was %s' % (self.item_names.get(i, i), after[i]['quantity'], q)
                 for i, q in self.orig_stock.items() if i in after and D(after[i]['quantity']) != q]
        return wrong

    def teardown(self):
        if not self.admin or not self.alive(self.admin):
            return ['The Administrator session was not available, so nothing could be cleaned up automatically.'] \
                if (self.temp_users or self.orig_stock) and self.admin else []
        problems = []
        try:
            if self.orig_stock:
                wrong = self.restore_stock()
                if wrong:
                    problems.append('Stock could not be put back: ' + '; '.join(wrong))
        except Exception as err:  # noqa: BLE001
            problems.append('Stock could not be checked or put back (%r).' % (err,))
        for uid in self.temp_users:
            try:
                status, _ = self.call('DELETE', '/users/%d' % uid, token=self.admin)
                if status != 200:
                    problems.append('Test account %d could not be deactivated (status %s).' % (uid, status))
            except Abort as err:
                problems.append('Test account %d could not be deactivated (%s).' % (uid, err))
        if self.temp_users:
            self.left.append('%d test accounts, all deactivated (IDs %s). Their names start with "Test".'
                             % (len(self.temp_users), ', '.join(str(u) for u in self.temp_users)))
        try:
            self.call('POST', '/logout', {}, self.admin)
            self.admin = None
        except Abort as err:
            problems.append('The Administrator session could not be logged out (%s).' % err)
        if not problems:
            try:
                os.remove(JOURNAL)
            except OSError:
                pass
        return problems

    # ---- 1.6 (optional, last) ----------------------------------------------
    def lockout(self, admin_pin):
        pin = self.unknown_pin or '9999'
        for attempt in range(1, 6):
            self.expect('1.6', 'failed attempt %d is rejected with 401' % attempt, self.login(pin), 401, 'Invalid Code')
        status, body = self.login(admin_pin)
        self.expect('1.6', 'the sixth attempt, with a valid PIN, is rejected with 429', (status, body), 429, MSG_LOCKED)
        if status == 200:
            self.call('POST', '/logout', {}, body.get('token'))
        self.notes.append('1.6: only the "same device" part was run. The login from a second device cannot be '
                          'simulated by one script. After this test the device that ran the script cannot log in '
                          'for five minutes.')


# ---- output ------------------------------------------------------------------
def summarise(run):
    by_tc = {}
    for check in run.checks:
        by_tc.setdefault(check['tc'], []).append(check)
    rows = []
    for tc in sorted(TITLES, key=tc_key):
        if tc in by_tc:
            checks = by_tc[tc]
            rows.append((tc, 'Pass' if all(c['ok'] for c in checks) else 'FAIL', checks))
        else:
            rows.append((tc, 'Not run', []))
    return rows


def print_console(run, rows):
    print()
    for tc, result, checks in rows:
        print('%-8s %-5s %s' % (result.upper(), tc, TITLES[tc]))
        for check in checks:
            if not check['ok']:
                print('           x %s  [got: %s]' % (check['text'], check['got'] or 'no'))
        if result == 'Not run' and tc in run.skipped:
            print('           (%s)' % run.skipped[tc])


def write_report(run, rows, path, started, problems, live):
    passed = sum(1 for r in rows if r[1] == 'Pass')
    failed = sum(1 for r in rows if r[1] == 'FAIL')
    not_run = sum(1 for r in rows if r[1] == 'Not run')
    total_checks = len(run.checks)
    good_checks = sum(1 for c in run.checks if c['ok'])
    date = started.strftime('%-d %b %Y')
    where = 'the live REST API on Railway (MySQL database)' if live else 'a ServeSync REST API server'
    out = []
    add = out.append
    add('# Section 10 test run — results')
    add('')
    add('Produced by `tests/run_section10_live.py`. The script sends real HTTP requests to the API and compares '
        'each answer with the expected result of the test case.')
    add('')
    add('| Item | Value |')
    add('| :--- | :--- |')
    add('| Date and time | %s |' % started.strftime('%-d %B %Y, %H:%M'))
    add('| API under test | %s |' % run.api.base)
    for key, value in run.env.items():
        add('| %s | %s |' % (key, value))
    add('| Requests sent | %d |' % run.api.calls)
    add('| Test cases | %d passed, %d failed, %d not run |' % (passed, failed, not_run))
    add('| Individual checks | %d of %d matched |' % (good_checks, total_checks))
    add('')
    add('## Results by test case')
    add('')
    add('| Test Case ID | Test case | Result | Checks matched |')
    add('| :--- | :--- | :--- | :--- |')
    for tc, result, checks in rows:
        matched = '%d of %d' % (sum(1 for c in checks if c['ok']), len(checks)) if checks else '—'
        add('| %s | %s | %s | %s |' % (tc, TITLES[tc], result, matched))
    add('')
    if failed:
        add('## Checks that did not match')
        add('')
        add('| Test Case ID | Expected | Observed |')
        add('| :--- | :--- | :--- |')
        for check in run.checks:
            if not check['ok']:
                add('| %s | %s | %s |' % (check['tc'], check['text'], (check['got'] or 'not observed').replace('|', '/')))
        add('')
    if run.skipped:
        add('## Test cases not run')
        add('')
        for tc in sorted(run.skipped, key=tc_key):
            add('- **%s %s:** %s' % (tc, TITLES[tc], run.skipped[tc]))
        add('')
    add('## Rows for the table in 10.1.9')
    add('')
    add('| Use Case | Test cases | How they were run | Date | Result |')
    add('| :--- | :--- | :--- | :--- | :--- |')
    for uc, prefix, _ in USE_CASES:
        mine = [r for r in rows if r[0].split('.')[0] == prefix]
        ran = [r for r in mine if r[1] != 'Not run']
        if not ran:
            continue
        bad = [r[0] for r in ran if r[1] == 'FAIL']
        skipped = [r[0] for r in mine if r[1] == 'Not run']
        ids = '%s – %s' % (mine[0][0], mine[-1][0]) + (' (except %s)' % ', '.join(skipped) if skipped else '')
        result = 'Pass' if not bad else 'Fail: %s' % ', '.join(bad)
        add('| %s | %s | Automated script sending HTTP requests to %s | %s | %s |' % (uc, ids, where, date, result))
    add('')
    add('## How the live run differs from the written test cases')
    add('')
    add('- The written test cases start from a new seeded test database. This run used the database as it was, so '
        'stock quantities are compared with the value read just before each step, not with fixed numbers.')
    add('- Tests that change an account, a PIN or a shift (1.4, 1.7 to 1.9, 8.6, 8.8, 8.9) used the account that '
        'test case 8.1 creates, not a real employee. The Manager and FOH Staff steps used test accounts as well.')
    add('- Items used: first item %s, second item %s, supplier "%s".' % (
        run.item_names.get(getattr(run, 'item_a', None), '—'), run.item_names.get(getattr(run, 'item_b', None), '—'),
        getattr(run, 'supplier_name', '—')))
    add('- The API does not expose the Sessions, Delivery_Receipts and Inventory_Transactions tables or the stored '
        'PIN hash, so those parts of the expected results (in 1.1, 1.2, 5.6, 5.7, 8.1 and 11.1) were checked through '
        'their visible effect: whether a token is accepted, the quantity received on the order line, the stock '
        'quantity, and the absence of the PIN in the response.')
    for note in run.notes:
        add('- %s' % note)
    add('')
    add('## What the run left in the database')
    add('')
    if run.left:
        for item in run.left:
            add('- %s' % item)
    else:
        add('- Nothing.')
    add('')
    if problems:
        add('**Clean-up problems (fix these by hand):**')
        add('')
        for problem in problems:
            add('- %s' % problem)
    else:
        add('Stock quantities were checked after the run and are back at their starting values. '
            'All sessions opened by the script were closed.')
    add('')
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, 'w') as handle:
        handle.write('\n'.join(out))


def reachability(api, run=None):
    status, body = api.call('GET', '/health')
    print('GET /health   -> %s %s' % (status, body.get('status') if isinstance(body, dict) else body))
    if status != 200:
        raise Abort('The API did not answer the health check.')
    status, body = api.call('GET', '/db-test')
    if status == 200 and isinstance(body, dict):
        print('GET /db-test  -> 200, %s user accounts, %s tables' % (body.get('users_count'), len(body.get('tables', []))))
        if run:
            run.env['Database check before the run'] = '%s user accounts, %s tables' % (
                body.get('users_count'), len(body.get('tables', [])))
    else:
        print('GET /db-test  -> %s (not available on this server)' % status)
    status, body = api.call('GET', '/inventory')
    print('GET /inventory without a login -> %s %s' % (status, body.get('error') if isinstance(body, dict) else ''))


def main():
    parser = argparse.ArgumentParser(description='Run the Section 10 backend test cases over HTTP.')
    parser.add_argument('--base-url', default=os.environ.get('SERVESYNC_API_URL', DEFAULT_URL))
    parser.add_argument('--report', default=DEFAULT_REPORT, help='where to write the results (Markdown)')
    parser.add_argument('--check', action='store_true', help='only check that the API and database answer; no login')
    parser.add_argument('--lockout', action='store_true',
                        help='also run test case 1.6 (blocks logins from this device for five minutes)')
    parser.add_argument('--yes', action='store_true', help='do not ask for confirmation')
    args = parser.parse_args()

    api = Api(args.base_url)
    live = not any(h in api.base for h in ('://127.0.0.1', '://localhost', '://[::1]'))
    started = datetime.now()
    run = Run(api, started.strftime('%m%d-%H%M%S'))
    print('ServeSync Section 10 test run against %s' % api.base)
    try:
        reachability(api, run)
    except Abort as err:
        print('\nStopped: %s' % err)
        return 2
    if args.check:
        return 0

    print('\nThis run changes data in that database: it creates three test accounts (deactivated at the end),\n'
          'one test purchase order, two test spoilage entries and one short shift for a test account, and then\n'
          'puts stock back to its starting values. Real employee accounts are not changed.')
    if args.lockout:
        print('Test case 1.6 is included: afterwards this device cannot log in for five minutes.\n'
              'On a hosted server the lock may also apply to other devices that reach it through the same proxy.')
    if not args.yes and input('Type RUN to continue: ').strip().upper() != 'RUN':
        print('Nothing was done.')
        return 0
    pin = os.environ.get('SERVESYNC_ADMIN_PIN') or getpass.getpass('Administrator PIN (not shown): ')
    pin = pin.strip()

    problems, stopped = [], None
    try:
        previous = run.recover_before_login()
        run.section('1.2', run.uc01_before_login)
        run.admin_login(pin)
        if previous:
            run.recover_after_login(previous)
        run.read_baseline()
        run.section('8.1', run.uc08_create)
        if not run.foh:
            raise Abort('The test account of 8.1 could not be created or logged in, so the other tests cannot run.')
        run.setup_manager()
        run.section('8.5', run.uc08_roles)
        run.section('1.7', run.uc01_shifts)
        run.section('5.1', run.uc05)
        run.section('11.1', run.uc11)
        run.section('8.6', run.uc08_changes)
    except Abort as err:
        stopped = str(err)
    except KeyboardInterrupt:
        stopped = 'Interrupted from the keyboard.'
    finally:
        try:
            problems = run.teardown()
        except Exception as err:  # noqa: BLE001
            problems = ['Clean-up did not finish (%r). Run the script again; it cleans up after an unfinished run.' % (err,)]

    if args.lockout and not stopped:
        try:
            run.section('1.6', lambda: run.lockout(pin))
        except Abort as err:
            stopped = str(err)
    else:
        run.skipped['1.6'] = ('Left out of the normal run: it blocks logins for five minutes, and its "second '
                              'device" step needs two devices. Run it with --lockout or by hand.')
    if stopped:
        run.notes.append('The run stopped early: %s' % stopped)

    rows = summarise(run)
    print_console(run, rows)
    if run.ready:
        write_report(run, rows, args.report, started, problems, live)
    passed = sum(1 for r in rows if r[1] == 'Pass')
    failed = sum(1 for r in rows if r[1] == 'FAIL')
    not_run = sum(1 for r in rows if r[1] == 'Not run')
    print('\n%d test cases passed, %d failed, %d not run (%d of %d checks matched).'
          % (passed, failed, not_run, sum(1 for c in run.checks if c['ok']), len(run.checks)))
    if stopped:
        print('Stopped early: %s' % stopped)
    for problem in problems:
        print('CLEAN-UP PROBLEM: %s' % problem)
    print('Results written to %s' % args.report if run.ready else 'No results file was written.')
    return 1 if (failed or stopped or problems) else 0


if __name__ == '__main__':
    sys.exit(main())
