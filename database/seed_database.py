"""ServeSync Sprint 3: Database Seeder Script.
Populates initial sample data for Development, Test, and Demonstration environments:
- 1 Admin, 1 Manager, 1 FOH Staff
- 3 Approved Suppliers (UC-05)
- 6 Realistic Restaurant Inventory Items (UC-04, UC-11)
- 1 Pending Supplier Purchase Order (UC-05)
- 1 Sample Logged Spoilage Incident (UC-11)
- 2 Job Applicants (UC-10)
- 2 Customer Service Issues (UC-12)
"""
import os, sys, sqlite3
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend'))
from service import hash_pin, now, stamp

SQLITE_PATH = os.path.join(os.path.dirname(__file__), 'servesync_dev.db')
SECRET = b'servesync-super-secret-lookup-key-2026-sprint3'

import hmac, hashlib
def lookup(pin):
    return hmac.new(SECRET, pin.encode(), hashlib.sha256).hexdigest()

def seed_sqlite(db_path):
    print(f'Seeding database at: {db_path}')
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    
    # Read schema 01 and 02
    schema1 = '''
    CREATE TABLE IF NOT EXISTS User_Management_Lock(lock_id INTEGER PRIMARY KEY);
    CREATE TABLE IF NOT EXISTS Users(user_id INTEGER PRIMARY KEY AUTOINCREMENT,full_name TEXT NOT NULL,access_code TEXT NOT NULL,pin_lookup TEXT UNIQUE NOT NULL,role TEXT NOT NULL,account_status TEXT NOT NULL,created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS Payroll(payroll_id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL,clock_in TEXT NOT NULL,clock_out TEXT,hours_worked TEXT,hourly_rate TEXT NOT NULL,gross_pay TEXT,payment_status TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS Sessions(token_hash TEXT PRIMARY KEY,user_id INTEGER NOT NULL,payroll_id INTEGER,expires_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS Login_Attempts(client_key TEXT PRIMARY KEY,window_start INTEGER NOT NULL,failures INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS Inventory(inventory_id INTEGER PRIMARY KEY AUTOINCREMENT,item_name TEXT NOT NULL,category TEXT NOT NULL,quantity REAL NOT NULL,unit TEXT NOT NULL,reorder_level REAL NOT NULL,last_updated TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS Inventory_Transactions(transaction_id INTEGER PRIMARY KEY AUTOINCREMENT,inventory_id INTEGER NOT NULL,user_id INTEGER NOT NULL,quantity_change REAL NOT NULL,reason TEXT NOT NULL,timestamp TEXT NOT NULL);
    '''
    
    schema2 = '''
    CREATE TABLE IF NOT EXISTS Suppliers(supplier_id INTEGER PRIMARY KEY AUTOINCREMENT,supplier_name TEXT NOT NULL,contact_person TEXT NOT NULL,phone_number TEXT NOT NULL,email TEXT NOT NULL,product_category TEXT NOT NULL,created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS Supplier_Orders(order_id INTEGER PRIMARY KEY AUTOINCREMENT,supplier_id INTEGER NOT NULL,created_by INTEGER NOT NULL,order_date TEXT NOT NULL,total_amount REAL NOT NULL,status TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS Supplier_Order_Items(item_id INTEGER PRIMARY KEY AUTOINCREMENT,order_id INTEGER NOT NULL,inventory_id INTEGER NOT NULL,quantity_ordered REAL NOT NULL,quantity_received REAL NOT NULL,unit_cost REAL NOT NULL);
    CREATE TABLE IF NOT EXISTS Delivery_Receipts(receipt_id INTEGER PRIMARY KEY AUTOINCREMENT,order_id INTEGER NOT NULL,received_by INTEGER NOT NULL,receipt_date TEXT NOT NULL,request_id TEXT UNIQUE NOT NULL,notes TEXT);
    CREATE TABLE IF NOT EXISTS Inventory_Spoilage(spoilage_id INTEGER PRIMARY KEY AUTOINCREMENT,inventory_id INTEGER NOT NULL,quantity_spoiled REAL NOT NULL,reason TEXT NOT NULL,notes TEXT,recorded_by INTEGER NOT NULL,occurred_at TEXT NOT NULL,stock_before REAL NOT NULL,stock_after REAL NOT NULL,request_id TEXT UNIQUE NOT NULL);
    CREATE TABLE IF NOT EXISTS Job_Applicants(applicant_id INTEGER PRIMARY KEY AUTOINCREMENT,full_name TEXT NOT NULL,email TEXT NOT NULL,phone_number TEXT NOT NULL,applied_position TEXT NOT NULL,availability TEXT NOT NULL,years_experience INTEGER NOT NULL,resume_path TEXT,application_status TEXT NOT NULL,created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS Customer_Service_Issues(issue_id INTEGER PRIMARY KEY AUTOINCREMENT,category TEXT NOT NULL,description TEXT NOT NULL,customer_contact TEXT,status TEXT NOT NULL,reported_at TEXT NOT NULL,assigned_to INTEGER,resolution_notes TEXT,resolved_at TEXT);
    '''
    
    cur.executescript(schema1)
    cur.executescript(schema2)
    cur.execute('INSERT OR IGNORE INTO User_Management_Lock VALUES (1)')
    
    # Seed Employees if empty
    cur.execute('SELECT COUNT(*) FROM Users')
    if cur.fetchone()[0] == 0:
        users = [
            ('Salem Marye (Admin)', '1234', 'Administrator'),
            ('Kristian Napier (Manager)', '2345', 'Manager'),
            ('Jamal Ford (FOH)', '3456', 'FOH Staff'),
            ('Sneha Patel (FOH)', '4567', 'FOH Staff')
        ]
        for name, pin, role in users:
            cur.execute(
                'INSERT INTO Users (full_name,access_code,pin_lookup,role,account_status,created_at) VALUES (?,?,?,?,?,?)',
                (name, hash_pin(pin), lookup(pin), role, 'Active', stamp(now()))
            )
        print('Seeded 4 users (Admin PIN: 1234, Manager PIN: 2345, FOH PIN: 3456)')

    # Seed Inventory if empty
    cur.execute('SELECT COUNT(*) FROM Inventory')
    if cur.fetchone()[0] == 0:
        items = [
            ('Vine Tomatoes', 'Produce', 45.0, 'lbs', 15.0),
            ('Angus Beef Patties', 'Meat', 80.0, 'units', 25.0),
            ('Brioche Buns', 'Bakery', 120.0, 'units', 30.0),
            ('Romaine Lettuce', 'Produce', 30.0, 'heads', 10.0),
            ('Sharp Cheddar Cheese', 'Dairy', 25.0, 'lbs', 8.0),
            ('Whole Milk', 'Dairy', 18.0, 'gallons', 5.0)
        ]
        for name, cat, qty, unit, reorder in items:
            cur.execute(
                'INSERT INTO Inventory (item_name,category,quantity,unit,reorder_level,last_updated) VALUES (?,?,?,?,?,?)',
                (name, cat, qty, unit, reorder, stamp(now()))
            )
        print('Seeded 6 inventory items.')

    # Seed Suppliers if empty
    cur.execute('SELECT COUNT(*) FROM Suppliers')
    if cur.fetchone()[0] == 0:
        suppliers = [
            ('Metro Farm Produce Co.', 'Dave Miller', '404-555-0199', 'orders@metrofarm.com', 'Produce & Herbs'),
            ('Prime Cut Meats & Poultry', 'Sarah Jenkins', '404-555-0244', 'sales@primecutmeats.com', 'Fresh Meats & Poultry'),
            ('Golden Crust Artisan Bakery', 'Marco Rossi', '404-555-0377', 'deliveries@goldencrust.com', 'Breads & Buns')
        ]
        for name, contact, phone, email, cat in suppliers:
            cur.execute(
                'INSERT INTO Suppliers (supplier_name,contact_person,phone_number,email,product_category,created_at) VALUES (?,?,?,?,?,?)',
                (name, contact, phone, email, cat, stamp(now()))
            )
        print('Seeded 3 approved suppliers.')

    # Seed Sample Purchase Order
    cur.execute('SELECT COUNT(*) FROM Supplier_Orders')
    if cur.fetchone()[0] == 0:
        cur.execute(
            'INSERT INTO Supplier_Orders (supplier_id,created_by,order_date,total_amount,status) VALUES (1, 1, ?, 125.00, ?)',
            (stamp(now()), 'Pending')
        )
        po_id = cur.lastrowid
        cur.execute(
            'INSERT INTO Supplier_Order_Items (order_id,inventory_id,quantity_ordered,quantity_received,unit_cost) VALUES (?, 1, 50.0, 0.0, 2.50)',
            (po_id,)
        )
        print('Seeded sample pending Purchase Order #1.')

    conn.commit()
    conn.close()
    print('Seeding completed successfully.')

if __name__ == '__main__':
    seed_sqlite(SQLITE_PATH)
