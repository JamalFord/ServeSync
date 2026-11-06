import argparse, os, json, logging, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from datetime import date, datetime, timedelta
from decimal import Decimal
from service import Service, Database, APIError, hash_pin

DEFAULT_SECRET = 'servesync-super-secret-lookup-key-2026-sprint3'

def encode(value):
    if isinstance(value, (datetime, date)): return value.isoformat()
    if isinstance(value, (Decimal, timedelta)): return str(value)
    raise TypeError(type(value).__name__)

def auto_init_database(service):
    """Automatically seeds tables and staff logins on first launch with retry support."""
    for attempt in range(1, 4):
        try:
            print(f"[Init] Checking cloud database (attempt {attempt}/3)...")
            with service.db.transaction() as q:
                table_check = q.one(
                    "SELECT COUNT(*) AS c FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'Users'"
                )
                if table_check and table_check['c'] > 0:
                    user_check = q.one("SELECT COUNT(*) AS c FROM Users")
                    if user_check and user_check['c'] > 0:
                        print(f"[Init] Cloud database already seeded with {user_check['c']} staff members.")
                        return

            # If Users table is empty or missing, load railway_full_schema.sql
            schema_path = os.path.join(os.path.dirname(__file__), 'railway_full_schema.sql')
            if not os.path.exists(schema_path):
                schema_path = os.path.join(os.path.dirname(__file__), '..', 'database', 'railway_full_schema.sql')

            if os.path.exists(schema_path):
                print(f"[Init] Executing initial cloud schema from {schema_path}...")
                with open(schema_path, 'r', encoding='utf-8') as f:
                    sql_text = f.read()

                statements = [s.strip() for s in sql_text.split(';') if s.strip()]
                with service.db.transaction() as q:
                    for stmt in statements:
                        if stmt.startswith('--'): continue
                        try:
                            q.run(stmt)
                        except Exception:
                            pass

                # Seed default users
                users = [
                    ('Salem Marye', '1234', 'Administrator'),
                    ('Kristian Napier', '2345', 'Manager'),
                    ('Jamal Ford', '3456', 'FOH Staff'),
                    ('Sneha Patel', '4567', 'FOH Staff'),
                ]
                with service.db.transaction() as q:
                    for name, pin, role in users:
                        q.run(
                            '''INSERT INTO Users (full_name, access_code, pin_lookup, role, account_status)
                               VALUES (%s, %s, %s, %s, %s)
                               ON DUPLICATE KEY UPDATE full_name=VALUES(full_name)''',
                            (name, hash_pin(pin), service.lookup(pin), role, 'Active')
                        )
                print("[Init] ServeSync Cloud Database successfully seeded with default users, tables, and inventory!")
                return
        except Exception as e:
            print(f"[Init] Connection attempt {attempt} failed: {e}")
            if attempt < 3:
                time.sleep(2)
    print("[Init] Notice: Cloud database will be initialized lazily upon first request.")

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

    # Run auto-initialization safely in background/startup
    try:
        auto_init_database(service)
    except Exception as e:
        print(f"[Warning] Auto-init skipped on startup: {e}")

    class Handler(BaseHTTPRequestHandler):
        def handle_api(self):
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 <= size <= 8192: raise APIError(413, 'Request is too large.')
                data = json.loads(self.rfile.read(size)) if size else {}
                if not isinstance(data, dict): raise APIError(400, 'JSON object required.')
                auth = self.headers.get('Authorization', '')
                token = auth[7:] if auth.startswith('Bearer ') else ''
                result = service.request(self.command, self.path.split('?')[0], data, token, self.client_address[0])
                self.reply(200, result)
            except APIError as e: self.reply(e.status, {'error': e.message})
            except (ValueError, json.JSONDecodeError): self.reply(400, {'error': 'Invalid request.'})
            except Exception:
                logging.exception('API request failed')
                self.reply(500, {'error': 'Database or server error. Please retry.'})

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
