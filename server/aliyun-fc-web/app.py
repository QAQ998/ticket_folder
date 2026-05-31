import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse
from urllib.request import Request, urlopen


TMDB_API_ORIGIN = "https://api.themoviedb.org"
TMDB_IMAGE_ORIGIN = "https://image.tmdb.org"


class TMDBProxyHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_common_headers("text/plain")
        self.end_headers()

    def do_GET(self):
        try:
            parsed = urlparse(self.path)
            if parsed.path.startswith("/3/"):
                self.proxy_api(parsed)
                return
            if parsed.path.startswith("/t/"):
                self.proxy_image(parsed)
                return
            self.send_json(404, {"error": "Not found"})
        except Exception as error:
            self.send_json(502, {
                "error": "TMDB proxy failed",
                "detail": {
                    "name": error.__class__.__name__,
                    "message": str(error)
                }
            })

    def proxy_api(self, parsed):
        api_key = os.getenv("TMDB_API_KEY")
        if not api_key:
            self.send_json(500, {"error": "Missing TMDB_API_KEY"})
            return

        query_items = [
            (key, value)
            for key, value in parse_qsl(parsed.query, keep_blank_values=True)
            if key != "api_key"
        ]
        query_items.append(("api_key", api_key))
        upstream_url = urlunparse((
            "https",
            "api.themoviedb.org",
            parsed.path,
            "",
            urlencode(query_items),
            ""
        ))
        self.proxy_request(upstream_url, "application/json; charset=utf-8")

    def proxy_image(self, parsed):
        upstream_url = TMDB_IMAGE_ORIGIN + parsed.path
        if parsed.query:
            upstream_url += "?" + parsed.query
        self.proxy_request(upstream_url, "image/jpeg")

    def proxy_request(self, upstream_url, fallback_content_type):
        request = Request(upstream_url, headers={"Accept": "*/*"})
        try:
            with urlopen(request, timeout=15) as response:
                body = response.read()
                status = response.status
                content_type = response.headers.get("Content-Type", fallback_content_type)
        except HTTPError as error:
            body = error.read()
            status = error.code
            content_type = error.headers.get("Content-Type", fallback_content_type)
        except URLError as error:
            raise RuntimeError(str(error.reason))

        self.send_response(status)
        self.send_common_headers(content_type)
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_common_headers("application/json; charset=utf-8")
        self.end_headers()
        self.wfile.write(body)

    def send_common_headers(self, content_type):
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "public, max-age=86400")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def log_message(self, format, *args):
        return


if __name__ == "__main__":
    port = int(os.getenv("PORT", "9000"))
    server = ThreadingHTTPServer(("0.0.0.0", port), TMDBProxyHandler)
    print(f"TMDB proxy listening on {port}")
    server.serve_forever()
