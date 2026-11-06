"""ServeSync: Cloud MySQL Seeder Script for Railway / Aiven / Remote MySQL.
Executes database/railway_full_schema.sql and creates initial staff accounts with working PINs.

Usage:
  python database/seed_cloud_mysql.py [OPTIONAL_CONNECTION_URL]
Or via environment variables:
  export MYSQL_URL="mysql://root:password@host:port/railway"
  python database/seed_cloud_mysql.py
"""
import os, sys, urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend'))
import pymysql
from service import hash_pin

SECRET = os.environ.get('PIN_LOOKUP_SECRET', 'servesync-super-secret-lookup-key-2026-sprint3')
import hmac, hashlib

def lookup(pin):
    return hmac.new(SECRET.encode(), pin.encode(), hashlib.sha256).hexdigest()

def get_connection():
    url = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('MYSQL_URL') or os.environ.get('DATABASE_URL')
    if url:
        p = urllib.parse.urlparse(url)
        return pymysql.connect(
            host=p.hostname,
            port=p.port or 3306,
            user=p.username,
            password=p.password or '',
            database=p.path.lstrip('/') or 'railway',
            charset='utf8mb4',
            cursorclass=pymysql.cursors.DictCursor,
            autocommit=True
        )
    return pymysql.connect(
        host=os.environ.get('DB_HOST') or os.environ.get('MYSQLHOST') or '127.0.0.1',
        port=int(os.environ.get('DB_PORT') or os.environ.get('MYSQLPORT') or 3306),
        user=os.environ.get('DB_USER') or os.environ.get('MYSQLUSER') or 'root',
        password=os.environ.get('DB_PASSWORD') or os.environ.get('MYSQLPASSWORD') or '',
        database=os.environ.get('DB_NAME') or os.environ.get('MYSQLDATABASE') or 'servesync',
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True
    )

def main():
    print('Connecting to Cloud MySQL database...')
    conn = get_connection()
    cur = conn.cursor()
    print('Connected successfully!')

    schema_file = os.path.join(os.path.dirname(__file__), 'railway_full_schema.sql')
    with open(schema_file, 'r', encoding='utf-8') as f:
        sql_content = f.read()

    # Split and execute statements
    statements = [stmt.strip() for stmt in sql_content.split(';') if stmt.strip()]
    print(f'Executing {len(statements)} schema statements...')
    for stmt in statements:
        if stmt.startswith('--'):
            continue
        try:
            cur.execute(stmt)
        except Exception as e:
            # Skip harmless set or drop notices
            if 'DROP TABLE' not in stmt and 'FOREIGN_KEY_CHECKS' not in stmt:
                print(f'Notice on statement: {e}')

    # Seed Users with salted PINs
    users = [
        ('Salem Marye', '1234', 'Administrator'),
        ('Kristian Napier', '2345', 'Manager'),
        ('Jamal Ford', '3456', 'FOH Staff'),
        ('Sneha Patel', '4567', 'FOH Staff'),
    ]

    print('Seeding employee accounts with PIN hashes...')
    for name, pin, role in users:
        cur.execute(
            '''INSERT INTO Users (full_name, access_code, pin_lookup, role, account_status)
               VALUES (%s, %s, %s, %s, %s)
               ON DUPLICATE KEY UPDATE full_name=VALUES(full_name)''',
            (name, hash_pin(pin), lookup(pin), role, 'Active')
        )

    # Verification counts
    cur.execute('SELECT COUNT(*) AS count FROM Users')
    user_count = cur.fetchone()['count']
    cur.execute('SELECT COUNT(*) AS count FROM Inventory')
    inv_count = cur.fetchone()['count']
    cur.execute('SELECT COUNT(*) AS count FROM Menu_Items')
    menu_count = cur.fetchone()['count']
    cur.execute('SELECT COUNT(*) AS count FROM Dining_Tables')
    table_count = cur.fetchone()['count']
    cur.execute('SELECT COUNT(*) AS count FROM Suppliers')
    supp_count = cur.fetchone()['count']

    print('================================================================')
    print('SUCCESS! ServeSync Cloud MySQL Database is completely seeded:')
    print(f'  - Users (Staff Accounts): {user_count}')
    print(f'  - Dining Tables:          {table_count}')
    print(f'  - Menu Items:             {menu_count}')
    print(f'  - Inventory Ingredients:  {inv_count}')
    print(f'  - Approved Suppliers:     {supp_count}')
    print('================================================================')
    print('Working Login PINs:')
    print('  - Salem Marye (Admin):   PIN 1234')
    print('  - Kristian N. (Manager): PIN 2345')
    print('  - Jamal Ford  (FOH):     PIN 3456')
    print('  - Sneha Patel (FOH):     PIN 4567')
    print('================================================================')
    conn.close()

if __name__ == '__main__':
    main()
