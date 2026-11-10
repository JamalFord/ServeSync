"""ServeSync Sprint 4: additive schema changes and demo data.

Everything here is safe to run on every start-up:
  * tables are created only if they are missing (nothing is dropped);
  * columns are added only if they are missing;
  * sample rows are inserted only into tables that are still empty.

It works on both MySQL (Railway) and SQLite (local development and tests).
"""
import re
from datetime import timedelta

import service as S

# (table, MySQL-flavoured DDL). SQLite differences are handled in _create().
TABLES = [
    ('Dining_Tables', '''CREATE TABLE IF NOT EXISTS Dining_Tables (
        table_number INT PRIMARY KEY,
        capacity INT NOT NULL,
        status VARCHAR(20) NOT NULL DEFAULT 'Available'
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'''),
    ('Reservations', '''CREATE TABLE IF NOT EXISTS Reservations (
        reservation_id INT AUTO_INCREMENT PRIMARY KEY,
        guest_name VARCHAR(100) NOT NULL,
        phone_number VARCHAR(20) NOT NULL,
        party_size INT NOT NULL,
        reservation_date DATE NOT NULL,
        reservation_time TIME NOT NULL,
        end_time TIME NOT NULL,
        table_number INT NOT NULL,
        status VARCHAR(20) NOT NULL DEFAULT 'Confirmed',
        created_by INT NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'''),
    ('Menu_Items', '''CREATE TABLE IF NOT EXISTS Menu_Items (
        menu_item_id INT AUTO_INCREMENT PRIMARY KEY,
        item_name VARCHAR(100) NOT NULL,
        category VARCHAR(50) NOT NULL,
        price DECIMAL(10,2) NOT NULL,
        available BOOLEAN NOT NULL DEFAULT TRUE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'''),
    ('Customer_Orders', '''CREATE TABLE IF NOT EXISTS Customer_Orders (
        order_id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        table_number INT NOT NULL,
        order_status VARCHAR(20) NOT NULL DEFAULT 'Active',
        total_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
        order_time DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'''),
    ('Order_Items', '''CREATE TABLE IF NOT EXISTS Order_Items (
        order_item_id INT AUTO_INCREMENT PRIMARY KEY,
        order_id INT NOT NULL,
        menu_item_id INT NOT NULL,
        quantity INT NOT NULL,
        unit_price DECIMAL(10,2) NOT NULL,
        modifications VARCHAR(255) NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'''),
    # --- New in Sprint 4 ---
    ('Menu_Item_Ingredients', '''CREATE TABLE IF NOT EXISTS Menu_Item_Ingredients (
        menu_item_id INT NOT NULL,
        inventory_id INT NOT NULL,
        quantity_per_serving DECIMAL(10,3) NOT NULL,
        PRIMARY KEY (menu_item_id, inventory_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'''),
    ('Customer_Reviews', '''CREATE TABLE IF NOT EXISTS Customer_Reviews (
        review_id INT AUTO_INCREMENT PRIMARY KEY,
        source VARCHAR(30) NOT NULL,
        reviewer_name VARCHAR(100) NOT NULL,
        rating INT NOT NULL,
        review_text TEXT NOT NULL,
        review_date DATETIME NOT NULL,
        external_id VARCHAR(191) NULL UNIQUE,
        created_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'''),
    ('Review_Summaries', '''CREATE TABLE IF NOT EXISTS Review_Summaries (
        summary_id INT AUTO_INCREMENT PRIMARY KEY,
        generated_at DATETIME NOT NULL,
        generated_by INT NULL,
        engine VARCHAR(60) NOT NULL,
        review_count INT NOT NULL,
        average_rating DECIMAL(3,2) NOT NULL,
        summary_json TEXT NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'''),
]

# (table, column, definition)
COLUMNS = [
    ('Users', 'hourly_rate', 'DECIMAL(8,2) NOT NULL DEFAULT 16.50'),
    ('Payroll', 'adjustment_reason', 'VARCHAR(255) NULL'),
    ('Payroll', 'adjusted_by', 'INT NULL'),
    ('Inventory', 'unit_cost', 'DECIMAL(10,2) NOT NULL DEFAULT 1.00'),
    ('Job_Applicants', 'notes', 'TEXT NULL'),
    ('Job_Applicants', 'hired_user_id', 'INT NULL'),
    ('Job_Applicants', 'onboarding_status', "VARCHAR(30) NOT NULL DEFAULT 'Not Started'"),
    ('Customer_Orders', 'completed_at', 'DATETIME NULL'),
    ('Customer_Orders', 'payment_method', 'VARCHAR(30) NULL'),
    ('Customer_Orders', 'kitchen_status', "VARCHAR(20) NOT NULL DEFAULT 'New'"),
    ('Reservations', 'notes', 'VARCHAR(255) NULL'),
]

DEMO_RATES = {'Salem Marye': '28.00', 'Kristian Napier': '22.50'}

DINING_TABLES = [(1, 2), (2, 4), (3, 4), (4, 6), (5, 4), (6, 2), (7, 8), (8, 4)]

MENU = [
    ('ServeSync Smash Burger', 'Entrees', '18.00'),
    ('Pan-Roasted Atlantic Salmon', 'Entrees', '26.50'),
    ('Wild Mushroom Risotto', 'Entrees', '22.00'),
    ('Truffle Parmesan Fries', 'Appetizers', '12.00'),
    ('Crispy Calamari', 'Appetizers', '15.50'),
    ('Smoked Hibiscus Spritz', 'Beverages', '9.50'),
    ('Craft Cold Brew & Tonic', 'Beverages', '6.00'),
    ('Warm Molten Lava Cake', 'Desserts', '11.00'),
]

# menu item -> [(inventory name keyword, quantity per serving)]
RECIPES = {
    'ServeSync Smash Burger': [('Beef', '0.50'), ('Bun', '1.00'), ('Chedd', '0.15')],
    'Pan-Roasted Atlantic Salmon': [('Salmon', '0.60'), ('Tomato', '0.30')],
    'Truffle Parmesan Fries': [('Potato', '0.75')],
    'Crispy Calamari': [('Calamari', '0.50')],
}

SAMPLE_REVIEWS = [
    ('Alicia R.', 5, 'The smash burger was incredible, juicy with a perfect crust, and our server was friendly and attentive the whole night.', 2),
    ('Marcus T.', 5, 'Best salmon I have had in Atlanta. Crispy skin, fresh sides, and the hibiscus spritz was delicious.', 3),
    ('Priya S.', 4, 'Great food and a cozy atmosphere. The truffle fries are amazing. Service was a little slow when it got busy.', 5),
    ('Devon K.', 2, 'We waited over 25 minutes for the calamari on Friday night and it arrived cold. The staff apologized but the wait was too long.', 6),
    ('Hannah L.', 5, 'Lovely atmosphere and excellent service. The lava cake is a perfect dessert. Will definitely come back.', 8),
    ('Omar F.', 3, 'Food was good but a bit pricey for the portion size. The burger was tasty, the fries were overly salty.', 9),
    ('Grace W.', 5, 'Fantastic dinner. Friendly staff, quick seating with our reservation, and the mushroom risotto was rich and delicious.', 11),
    ('Tyler B.', 4, 'Really good burger and great cold brew tonic. It was loud inside, so it was hard to talk, but the food made up for it.', 13),
    ('Nia J.', 1, 'Our order was wrong twice and nobody checked on the table. Very slow service and the salmon was overcooked.', 15),
    ('Sam P.', 5, 'Amazing service from start to finish. The calamari was crispy and fresh and the drinks were excellent.', 18),
    ('Elena M.', 4, 'Clean restaurant, friendly host, and tasty food. Parking was difficult and the wait for a table was long without a reservation.', 21),
    ('Jordan C.', 5, 'The burger and truffle fries are the best in town. Fast service at lunch and fair prices.', 24),
]

SAMPLE_APPLICANTS = [
    ('Riley Chen', 'riley.chen@example.com', '404-555-0111', 'Server', 'Evenings and weekends', 2),
    ('Andre Wallace', 'andre.wallace@example.com', '404-555-0122', 'Line Cook', 'Full time', 4),
]

SAMPLE_ISSUES = [
    ('Order Accuracy', 'Guest at table 5 received the wrong entree and waited 15 minutes for the correction.', 'guest5@example.com'),
    ('Billing', 'Guest reports being charged twice for a dessert on a recent visit.', '404-555-0166'),
]


def _create(q, ddl):
    if q.sqlite:
        ddl = ddl.replace('INT AUTO_INCREMENT PRIMARY KEY', 'INTEGER PRIMARY KEY AUTOINCREMENT')
        ddl = re.sub(r'\)\s*ENGINE=[^)]*$', ')', ddl.strip())
    q.run(ddl)


def has_column(q, table, column):
    if q.sqlite:
        return any(r['name'].lower() == column.lower() for r in q.all('PRAGMA table_info(' + table + ')'))
    return bool(q.one(
        'SELECT column_name AS c FROM information_schema.columns '
        'WHERE table_schema = DATABASE() AND LOWER(table_name) = LOWER(%s) AND LOWER(column_name) = LOWER(%s)',
        (table, column)))


def _count(q, table):
    return q.one('SELECT COUNT(*) AS c FROM ' + table)['c']


def _first_user_id(q):
    row = q.one("SELECT user_id FROM Users WHERE role='Administrator' ORDER BY user_id LIMIT 1") \
        or q.one('SELECT user_id FROM Users ORDER BY user_id LIMIT 1')
    return row['user_id'] if row else None


def ensure_schema(db, log=print):
    """Create missing tables and columns, then add demo rows to empty tables."""
    problems = 0
    for table, ddl in TABLES:
        try:
            with db.transaction() as q:
                _create(q, ddl)
        except Exception as err:  # keep going: one failed step must not block start-up
            problems += 1
            log(f'[Migrate] Could not create {table}: {err}')
    added = []
    for table, column, definition in COLUMNS:
        try:
            with db.transaction() as q:
                if not has_column(q, table, column):
                    q.run(f'ALTER TABLE {table} ADD COLUMN {column} {definition}')
                    added.append(f'{table}.{column}')
        except Exception as err:
            problems += 1
            log(f'[Migrate] Could not add {table}.{column}: {err}')
    for step in (_seed_rates, _seed_tables_and_menu, _seed_recipes, _seed_reviews,
                 _seed_usage_history, _seed_applicants_and_issues):
        try:
            with db.transaction() as q:
                step(q, added)
        except Exception as err:
            problems += 1
            log(f'[Migrate] {step.__name__} skipped: {err}')
    log(f"[Migrate] Sprint 4 schema ready ({len(added)} columns added, {problems} problems).")
    return problems == 0


def _seed_rates(q, added):
    if 'Users.hourly_rate' not in added:
        return
    for name, rate in DEMO_RATES.items():
        q.run('UPDATE Users SET hourly_rate=%s WHERE full_name=%s', (rate, name))


def _seed_tables_and_menu(q, added):
    if _count(q, 'Dining_Tables') == 0:
        for number, capacity in DINING_TABLES:
            q.run('INSERT INTO Dining_Tables (table_number, capacity, status) VALUES (%s,%s,%s)',
                  (number, capacity, 'Available'))
    if _count(q, 'Menu_Items') == 0:
        for name, category, price in MENU:
            q.run('INSERT INTO Menu_Items (item_name, category, price, available) VALUES (%s,%s,%s,%s)',
                  (name, category, price, 1))


def _seed_recipes(q, added):
    if _count(q, 'Menu_Item_Ingredients') > 0:
        return
    inventory = q.all('SELECT inventory_id, item_name FROM Inventory')
    for menu_name, parts in RECIPES.items():
        menu = q.one('SELECT menu_item_id FROM Menu_Items WHERE item_name=%s', (menu_name,))
        if not menu:
            continue
        for keyword, qty in parts:
            match = next((i for i in inventory if keyword.lower() in i['item_name'].lower()), None)
            if match:
                q.run('INSERT INTO Menu_Item_Ingredients (menu_item_id, inventory_id, quantity_per_serving) VALUES (%s,%s,%s)',
                      (menu['menu_item_id'], match['inventory_id'], qty))


def _seed_reviews(q, added):
    if _count(q, 'Customer_Reviews') > 0:
        return
    current = S.now()
    for name, rating, body, days_ago in SAMPLE_REVIEWS:
        q.run('INSERT INTO Customer_Reviews (source, reviewer_name, rating, review_text, review_date, created_at) '
              'VALUES (%s,%s,%s,%s,%s,%s)',
              ('Sample', name, rating, body, S.stamp(current - timedelta(days=days_ago)), S.stamp(current)))


def _seed_usage_history(q, added):
    """Fourteen days of sample kitchen usage so the consumption forecast has history to read.

    These rows are audit-log history only; they do not change the stock on hand.
    """
    marker = 'Sample usage history'
    if q.one('SELECT transaction_id FROM Inventory_Transactions WHERE reason=%s LIMIT 1', (marker,)):
        return
    user_id = _first_user_id(q)
    if user_id is None:
        return
    current = S.now().replace(hour=21, minute=0, second=0)
    weekday_factor = [0.8, 0.8, 0.9, 1.0, 1.3, 1.5, 1.1]  # Monday .. Sunday
    for item in q.all('SELECT inventory_id, reorder_level FROM Inventory'):
        base = float(item['reorder_level']) * 0.3
        if base <= 0:
            continue
        for days_ago in range(14, 0, -1):
            day = current - timedelta(days=days_ago)
            used = round(base * weekday_factor[day.weekday()] * (1.0 + (14 - days_ago) * 0.01), 2)
            q.run('INSERT INTO Inventory_Transactions (inventory_id, user_id, quantity_change, reason, timestamp) '
                  'VALUES (%s,%s,%s,%s,%s)', (item['inventory_id'], user_id, str(-used), marker, S.stamp(day)))


def _seed_applicants_and_issues(q, added):
    if _count(q, 'Job_Applicants') == 0:
        for name, email, phone, position, availability, years in SAMPLE_APPLICANTS:
            q.run('INSERT INTO Job_Applicants (full_name,email,phone_number,applied_position,availability,'
                  'years_experience,application_status,created_at) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)',
                  (name, email, phone, position, availability, years, 'New', S.stamp(S.now())))
    if _count(q, 'Customer_Service_Issues') == 0:
        for category, description, contact in SAMPLE_ISSUES:
            q.run('INSERT INTO Customer_Service_Issues (category,description,customer_contact,status,reported_at) '
                  'VALUES (%s,%s,%s,%s,%s)', (category, description, contact, 'Open', S.stamp(S.now())))
