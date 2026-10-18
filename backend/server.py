import argparse, os, json, logging
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from datetime import date, datetime, timedelta
from decimal import Decimal
from service import Service, Database, APIError

def encode(value):
    if isinstance(value, (datetime, date)): return value.isoformat()
    if isinstance(value, (Decimal, timedelta)): return str(value)
    raise TypeError(type(value).__name__)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bootstrap', action='store_true')
    parser.add_argument('--name', default='ServeSync Administrator')
    args = parser.parse_args()
    service = Service(Database(), os.environ.get('PIN_LOOKUP_SECRET', ''))
    if args.bootstrap:
        import getpass
        user = service.bootstrap(args.name, getpass.getpass('New four-digit admin PIN: '))
        print('Created administrator', user['user_id']); return
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
        def reply(self, code, value):
            payload = json.dumps(value, default=encode).encode()
            self.send_response(code); self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(payload))); self.send_header('Cache-Control', 'no-store')
            self.end_headers(); self.wfile.write(payload)
        do_GET = do_POST = do_PATCH = do_DELETE = handle_api
    port = int(os.environ.get('PORT', '8000'))
    print(f'ServeSync development API listening on port {port}')
    ThreadingHTTPServer((os.environ.get('API_HOST', '127.0.0.1'), port), Handler).serve_forever()
if __name__ == '__main__': main()
