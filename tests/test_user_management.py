"""Behavior tests using SQLite as a test double; MySQL DDL needs separate validation."""
import os, sys, tempfile, unittest, hashlib
from datetime import timedelta
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend'))
from service import Database, Service, APIError, now, stamp

SCHEMA = '''
CREATE TABLE Users(user_id INTEGER PRIMARY KEY AUTOINCREMENT,full_name TEXT NOT NULL,access_code TEXT NOT NULL,pin_lookup TEXT UNIQUE NOT NULL,role TEXT NOT NULL,account_status TEXT NOT NULL,created_at TEXT NOT NULL);
CREATE TABLE Payroll(payroll_id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL REFERENCES Users(user_id),clock_in TEXT NOT NULL,clock_out TEXT,hours_worked NUMERIC,hourly_rate NUMERIC NOT NULL,gross_pay NUMERIC,payment_status TEXT NOT NULL);
CREATE TABLE Sessions(token_hash TEXT PRIMARY KEY,user_id INTEGER UNIQUE NOT NULL REFERENCES Users(user_id),payroll_id INTEGER UNIQUE NOT NULL REFERENCES Payroll(payroll_id),expires_at TEXT NOT NULL);
CREATE TABLE Login_Attempts(client_key TEXT PRIMARY KEY,window_start INTEGER NOT NULL,failures INTEGER NOT NULL);
CREATE TABLE User_Management_Lock(lock_id INTEGER PRIMARY KEY);
INSERT INTO User_Management_Lock VALUES(1);
CREATE TABLE Customer_Orders(order_id INTEGER PRIMARY KEY,user_id INTEGER REFERENCES Users(user_id));
CREATE TABLE Reservations(reservation_id INTEGER PRIMARY KEY,created_by INTEGER REFERENCES Users(user_id));
CREATE TABLE Inventory(inventory_id INTEGER PRIMARY KEY,item_name TEXT);
'''
class UserManagementTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.db = Database(self.temp.name + '/test.db')
        with self.db.transaction() as q: q.connection.executescript(SCHEMA)
        self.service = Service(self.db, 'test-only-secret-at-least-32-characters')
        self.admin = self.service.bootstrap('Admin', '0001')
        self.token = self.service.login({'pin': '0001'}, 'admin')['token']
    def tearDown(self): self.temp.cleanup()
    def call(self, method, path, data=None, token=None):
        return self.service.request(method,path,data or {},self.token if token is None else token)
    def add(self, pin='1234', role='FOH Staff'):
        return self.call('POST','/users',{'full_name':'Employee','role':role,'pin':pin})['user']
    def fails(self, status, function):
        with self.assertRaises(APIError) as caught: function()
        self.assertEqual(caught.exception.status,status)
    def test_admin_creation_persists_hash_only(self):
        u = self.add()
        with self.db.transaction() as q:
            row=q.one('SELECT * FROM Users WHERE user_id=%s',(u['user_id'],))
            self.assertTrue(row['access_code'].startswith('scrypt$')); self.assertNotIn('pin',u)
            self.assertNotEqual(row['access_code'],'1234'); self.assertEqual(len(row['pin_lookup']),64)
    def test_login_creates_one_shift_and_session(self):
        u=self.add(); login=self.service.login({'pin':'1234'},'staff')
        self.assertEqual(self.call('GET','/me',token=login['token'])['user']['user_id'],u['user_id'])
        with self.db.transaction() as q:
            self.assertEqual(q.one('SELECT COUNT(*) AS n FROM Payroll WHERE user_id=%s',(u['user_id'],))['n'],1)
    def test_invalid_pin_does_not_clock_in(self):
        self.fails(401,lambda:self.service.login({'pin':'9999'},'bad'))
        with self.db.transaction() as q: self.assertEqual(q.one('SELECT COUNT(*) AS n FROM Payroll')['n'],1)
    def test_duplicate_pin_rejected(self):
        self.add(); self.fails(409,lambda:self.add())
    def test_pin_validation_and_leading_zero(self):
        for pin in ('123','12345','１２３４',1234): self.fails(400,lambda:self.add(pin=pin))
        self.add(pin='0012'); self.assertIn('token',self.service.login({'pin':'0012'},'staff'))
    def test_foh_cannot_manage_accounts_or_payroll(self):
        self.add(); token=self.service.login({'pin':'1234'},'staff')['token']
        self.fails(403,lambda:self.call('GET','/users',token=token))
        self.fails(403,lambda:self.call('GET','/payroll',token=token))
        self.assertIn('records',self.call('GET','/orders',token=token))
    def test_manager_cannot_manage_users(self):
        self.add(role='Manager'); token=self.service.login({'pin':'1234'},'staff')['token']
        self.fails(403,lambda:self.call('GET','/users',token=token))
    def test_logout_closes_shift_and_invalidates_token(self):
        self.call('POST','/logout'); self.fails(401,lambda:self.call('GET','/me'))
        with self.db.transaction() as q: self.assertIsNotNone(q.one('SELECT clock_out FROM Payroll')['clock_out'])
    def test_self_deactivation_and_demotion_denied(self):
        path='/users/'+str(self.admin['user_id'])
        self.fails(409,lambda:self.call('DELETE',path))
        self.fails(409,lambda:self.call('PATCH',path,{'role':'FOH Staff'}))
    def test_role_change_is_immediate(self):
        u=self.add(role='Administrator'); token=self.service.login({'pin':'1234'},'staff')['token']
        self.call('PATCH',f"/users/{u['user_id']}",{'role':'FOH Staff'})
        self.fails(403,lambda:self.call('GET','/users',token=token))
    def test_deactivation_preserves_history_and_closes_shift(self):
        u=self.add(); token=self.service.login({'pin':'1234'},'staff')['token']
        self.call('DELETE',f"/users/{u['user_id']}")
        self.fails(401,lambda:self.call('GET','/me',token=token))
        self.fails(401,lambda:self.service.login({'pin':'1234'},'staff2'))
        with self.db.transaction() as q:
            self.assertIsNotNone(q.one('SELECT user_id FROM Users WHERE user_id=%s',(u['user_id'],)))
            self.assertIsNotNone(q.one('SELECT clock_out FROM Payroll WHERE user_id=%s',(u['user_id'],))['clock_out'])
    def test_pin_reset_revokes_session(self):
        u=self.add(); token=self.service.login({'pin':'1234'},'staff')['token']
        self.call('PATCH',f"/users/{u['user_id']}",{'pin':'5678'})
        self.fails(401,lambda:self.call('GET','/me',token=token))
        self.assertIn('token',self.service.login({'pin':'5678'},'staff2'))
    def test_rate_limit_after_five_failures(self):
        for _ in range(5): self.fails(401,lambda:self.service.login({'pin':'9999'},'bad'))
        self.fails(429,lambda:self.service.login({'pin':'0001'},'bad'))
    def test_duplicate_session_is_rejected(self):
        self.fails(409,lambda:self.service.login({'pin':'0001'},'second-device'))
    def test_expiry_closes_shift_at_expiry(self):
        expired=stamp(now()-timedelta(seconds=5))
        with self.db.transaction() as q:
            q.run('UPDATE Payroll SET clock_in=%s',(stamp(now()-timedelta(hours=2)),))
            q.run('UPDATE Sessions SET expires_at=%s',(expired,))
        self.fails(401,lambda:self.call('GET','/me'))
        with self.db.transaction() as q: self.assertEqual(q.one('SELECT clock_out FROM Payroll')['clock_out'],expired)
    def test_bootstrap_cannot_run_twice(self):
        self.fails(409,lambda:self.service.bootstrap('Other','1111'))
    def test_recovery_ends_session_and_allows_new_login(self):
        u=self.add(); token=self.service.login({'pin':'1234'},'staff')['token']
        self.call('POST',f"/users/{u['user_id']}/end-session")
        self.fails(401,lambda:self.call('GET','/me',token=token))
        self.assertIn('token',self.service.login({'pin':'1234'},'staff2'))
if __name__ == '__main__': unittest.main(verbosity=2)
