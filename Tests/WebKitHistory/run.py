"""Compile the product runtime and exercise history using an isolated local page."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import threading

root = Path(__file__).resolve().parents[2]
sources = sorted(str(path) for path in (root / 'Sources').rglob('*.swift')
                 if path.name != 'JenaWebMain.swift' and 'cef' not in path.parts)

class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(b'<html><head><title>History test</title></head><body>SPA fixture</body></html>')

    def log_message(self, *args):
        pass

with tempfile.TemporaryDirectory(prefix='jena-history-test-') as directory:
    executable = str(Path(directory) / 'HistoryProbe')
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', *sources,
                    str(Path(__file__).with_name('HistoryProbe.swift')),
                    '-framework', 'AppKit', '-framework', 'WebKit', '-framework', 'AVFoundation',
                    '-framework', 'CoreLocation', '-lsqlite3', '-o', executable], check=True)
    server = ThreadingHTTPServer(('127.0.0.1', 18793), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        subprocess.run([executable], check=True, timeout=30)
    finally:
        server.shutdown()
        server.server_close()
