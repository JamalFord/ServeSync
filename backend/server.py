import argparse, os, json, logging, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from datetime import date, datetime, timedelta
from decimal import Decimal
from urllib.parse import urlsplit, parse_qsl
from service import Service, Database, APIError, hash_pin
from migrations import ensure_schema

DEFAULT_SECRET = 'servesync-super-secret-lookup-key-2026-sprint3'

def encode(value):
    if isinstance(value, (datetime, date)): return value.isoformat()
    if isinstance(value, (Decimal, timedelta)): return str(value)
    raise TypeError(type(value).__name__)

# Every table the API touches. If any is missing the schema is (re)loaded.
REQUIRED_TABLES = (
    'User_Management_Lock', 'Users', 'Payroll', 'Sessions', 'Login_Attempts',
    'Dining_Tables', 'Reservations', 'Menu_Items', 'Customer_Orders', 'Order_Items',
    'Inventory', 'Inventory_Transactions', 'Inventory_Spoilage', 'Suppliers',
    'Supplier_Orders', 'Supplier_Order_Items', 'Delivery_Receipts',
    'Job_Applicants', 'Customer_Service_Issues',
)

DEMO_USERS = [
    ('Salem Marye', '1234', 'Administrator'),
    ('Kristian Napier', '2345', 'Manager'),
    ('Jamal Ford', '3456', 'Administrator'),
    ('Sneha Patel', '4567', 'FOH Staff'),
    ('Mason Mathias', '5678', 'FOH Staff'),
]

_init_lock = threading.Lock()

def _missing_tables(q):
    rows = q.all("SELECT table_name AS t FROM information_schema.tables WHERE table_schema = DATABASE()")
    present = {str(list(r.values())[0]).lower() for r in rows}
    return [t for t in REQUIRED_TABLES if t.lower() not in present]

def _seed_demo_users(service, q):
    for name, pin, role in DEMO_USERS:
        q.run(
            '''INSERT INTO Users (full_name, access_code, pin_lookup, role, account_status)
               VALUES (%s, %s, %s, %s, %s)
               ON DUPLICATE KEY UPDATE full_name=VALUES(full_name)''',
            (name, hash_pin(pin), service.lookup(pin), role, 'Active')
        )

def auto_init_database(service, attempts=10, delay=3):
    """Create the schema and demo data, then apply the Sprint 4 additions."""
    ready = _init_base_schema(service, attempts, delay)
    if ready:
        try:
            ensure_schema(service.db)
        except Exception as e:
            print(f"[Migrate] Sprint 4 schema update failed: {e}")
    return ready

def _init_base_schema(service, attempts=10, delay=3):
    """Create the MySQL schema and demo staff on first launch.

    Safe to call repeatedly: it only loads the schema when a required table is
    missing, and only seeds staff when the Users table is empty. Retries while
    MySQL is still starting up. SQLite (local dev) is seeded by
    database/seed_database.py instead, so it is skipped here.
    """
    if service.db.sqlite_path:
        return True
    if not _init_lock.acquire(blocking=False):
        return False  # another thread is already initializing
    try:
        for attempt in range(1, attempts + 1):
            try:
                print(f"[Init] Checking cloud database (attempt {attempt}/{attempts})...")
                with service.db.transaction() as q:
                    missing = _missing_tables(q)
                    if not missing:
                        users = q.one("SELECT COUNT(*) AS c FROM Users")['c']
                        if users:
                            print(f"[Init] Cloud database ready: all tables present, {users} staff members.")
                            return True
                        _seed_demo_users(service, q)
                        print("[Init] Tables present but no staff: seeded demo staff accounts.")
                        return True
                print(f"[Init] Missing tables: {', '.join(missing)}. Loading full schema...")
                if _load_schema(service):
                    with service.db.transaction() as q:
                        _seed_demo_users(service, q)
                    print("[Init] ServeSync Cloud Database successfully seeded with default users, tables, and inventory!")
                    return True
                return False
            except Exception as e:
                print(f"[Init] Attempt {attempt} failed: {e}")
                if attempt < attempts:
                    time.sleep(delay)
        print("[Init] Giving up for now; will retry on the next request that hits a missing table.")
        return False
    finally:
        _init_lock.release()

def _load_schema(service):
    """Run railway_full_schema.sql (drops and recreates every table).

    Only called when a required table is missing, i.e. on a fresh or broken
    database. Returns False if the schema file can't be found.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [os.path.join(here, 'railway_full_schema.sql'),
                  os.path.join(here, '..', 'database', 'railway_full_schema.sql')]
    schema_path = next((c for c in candidates if os.path.exists(c)), None)
    if not schema_path:
        print('[Init] ERROR: railway_full_schema.sql not found; cannot create tables.')
        return False

    print(f"[Init] Executing cloud schema from {schema_path}...")
    with open(schema_path, 'r', encoding='utf-8') as f:
        sql_text = f.read()

    # Split on ';' and drop whole-line comments. (The schema has no ';' inside
    # string literals, and MySQL accepts the remaining inline '-- ' comments.)
    statements = []
    for chunk in sql_text.split(';'):
        lines = [line for line in chunk.splitlines() if not line.strip().startswith('--')]
        cleaned = '\n'.join(lines).strip()
        if cleaned:
            statements.append(cleaned)

    failures = 0
    with service.db.transaction() as q:
        for stmt in statements:
            try:
                q.run(stmt)
            except Exception as err:
                failures += 1
                print(f"[Init Warning] {err} -- in: {stmt[:80]!r}")
    print(f"[Init] Schema executed: {len(statements)} statements, {failures} warnings.")
    return True

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bootstrap', action='store_true')
    parser.add_argument('--name', default='ServeSync Administrator')
    args = parser.parse_args()

    secret = os.environ.get('PIN_LOOKUP_SECRET') or DEFAULT_SECRET
    service = Service(Database(), secret)

    if args.bootstrap:
        import getpass
        user = service.bootstrap(args.name, getpass.getpass('New four-digit admin PIN: '))
        print('Created administrator', user['user_id'])
        return

    # Initialize the cloud database in the background so the HTTP server starts
    # (and passes Railway's health check) even while MySQL is still booting.
    def init_in_background():
        threading.Thread(target=auto_init_database, args=(service,), daemon=True).start()
    init_in_background()

    class Handler(BaseHTTPRequestHandler):
        def handle_api(self):
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 <= size <= 16384: raise APIError(413, 'Request is too large.')
                data = json.loads(self.rfile.read(size)) if size else {}
                if not isinstance(data, dict): raise APIError(400, 'JSON object required.')
                url = urlsplit(self.path)
                if self.command == 'GET' and url.query:
                    # Query-string filters (for example /reservations?date=2026-11-10)
                    data = dict(parse_qsl(url.query), **data)
                auth = self.headers.get('Authorization', '')
                token = auth[7:] if auth.startswith('Bearer ') else ''
                result = service.request(self.command, url.path, data, token, self.client_address[0])
                self.reply(200, result)
            except APIError as e: self.reply(e.status, {'error': e.message})
            except (ValueError, json.JSONDecodeError): self.reply(400, {'error': 'Invalid request.'})
            except Exception as e:
                import traceback
                traceback.print_exc()
                # MySQL error 1146 = table doesn't exist: the schema was never
                # loaded (or was lost). Re-run setup and ask the client to retry.
                if getattr(e, 'args', None) and e.args[0] == 1146:
                    init_in_background()
                    self.reply(503, {'error': 'Database is being initialized. Please retry in a few seconds.'})
                    return
                self.reply(500, {'error': f'Database or server error: {e}'})

        def do_OPTIONS(self):
            self.send_response(204)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
            self.end_headers()

        def reply(self, code, value):
            payload = json.dumps(value, default=encode).encode()
            self.send_response(code); self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(payload))); self.send_header('Cache-Control', 'no-store')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
            self.end_headers(); self.wfile.write(payload)

        do_GET = do_POST = do_PATCH = do_DELETE = handle_api

    host = os.environ.get('API_HOST', '0.0.0.0')
    port = int(os.environ.get('PORT', '8000'))
    print(f'ServeSync REST API listening on {host}:{port} (PORT env={os.environ.get("PORT")})')
    server = ThreadingHTTPServer((host, port), Handler)
    server.serve_forever()

if __name__ == '__main__':
    main()
