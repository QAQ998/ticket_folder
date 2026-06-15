import os
import ssl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse, urlunparse
from urllib.request import Request, urlopen


DEFAULT_UPSTREAM_ORIGIN = "https://sanchandb-proxy-vpzlnywcvj.cn-hongkong.fcapp.run"
DEFAULT_DOUBAN_UPSTREAM_ORIGIN = ""
DEV_SSL_CONTEXT = ssl._create_unverified_context()


class LocalDevProxyHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_common_headers("text/plain", 0)
        self.end_headers()

    def do_GET(self):
        try:
            parsed = urlparse(self.path)
            if parsed.path == "/movie/search":
                upstream_origin = os.getenv("SANCHANGJI_DOUBAN_PROXY_UPSTREAM", DEFAULT_DOUBAN_UPSTREAM_ORIGIN)
                if not upstream_origin:
                    self.send_text(503, "Missing SANCHANGJI_DOUBAN_PROXY_UPSTREAM")
                    return
                self.proxy_request(self.upstream_url(upstream_origin, parsed.path, parsed.query))
                return

            if not (parsed.path.startswith("/3/") or parsed.path.startswith("/t/")):
                self.send_text(404, "Not found")
                return

            upstream_origin = os.getenv("SANCHANGJI_PROXY_UPSTREAM", DEFAULT_UPSTREAM_ORIGIN)
            self.proxy_request(self.upstream_url(upstream_origin, parsed.path, parsed.query))
        except Exception as error:
            self.send_text(502, f"Local proxy failed: {error.__class__.__name__}: {error}")

    def upstream_url(self, upstream_origin, path, query):
        upstream = urlparse(upstream_origin)
        return urlunparse((
            upstream.scheme,
            upstream.netloc,
            path,
            "",
            query,
            ""
        ))

    def proxy_request(self, upstream_url):
        headers = {"Accept": "*/*"}
        token = os.getenv("SANCHANGJI_DOUBAN_PROXY_TOKEN")
        if token and "/movie/search" in upstream_url:
            headers["Authorization"] = f"Bearer {token}"
        request = Request(upstream_url, headers=headers)
        try:
            with urlopen(request, timeout=30, context=DEV_SSL_CONTEXT) as response:
                body = response.read()
                status = response.status
                content_type = response.headers.get("Content-Type", "application/octet-stream")
        except HTTPError as error:
            body = error.read()
            status = error.code
            content_type = error.headers.get("Content-Type", "application/octet-stream")
        except URLError as error:
            raise RuntimeError(str(error.reason))

        self.send_response(status)
        self.send_common_headers(content_type, len(body))
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, status, message):
        body = message.encode("utf-8")
        self.send_response(status)
        self.send_common_headers("text/plain; charset=utf-8", len(body))
        self.end_headers()
        self.wfile.write(body)

    def send_common_headers(self, content_type, content_length):
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(content_length))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def log_message(self, format, *args):
        return


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8787"))
    server = ThreadingHTTPServer(("0.0.0.0", port), LocalDevProxyHandler)
    print(f"散场记 local dev proxy listening on http://0.0.0.0:{port}")
    server.serve_forever()
