import json
import os
import re
import ssl
import time
from html import unescape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, quote, urlencode, urlparse, urlunparse
from urllib.request import Request, urlopen


DEFAULT_UPSTREAM_ORIGIN = "https://sanchandb-proxy-vpzlnywcvj.cn-hongkong.fcapp.run"
DEV_SSL_CONTEXT = ssl._create_unverified_context()
DOUBAN_ORIGIN = "https://movie.douban.com"
DOUBAN_SEARCH_ORIGIN = "https://search.douban.com"
USER_AGENT = "SanchangjiPrototype/0.1 (+https://github.com/QAQ998/ticket_folder)"

SEARCH_CACHE = {}
DETAIL_CACHE = {}
MOVIE_INDEX = {}
CACHE_TTL_SECONDS = 60 * 60 * 24


class LocalDevProxyHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_common_headers("text/plain", 0)
        self.end_headers()

    def do_GET(self):
        try:
            parsed = urlparse(self.path)
            if os.getenv("SANCHANGJI_METADATA_PROVIDER", "douban").lower() == "douban":
                if self.handle_douban_api(parsed):
                    return

            if not (parsed.path.startswith("/3/") or parsed.path.startswith("/t/")):
                self.send_text(404, "Not found")
                return

            upstream_origin = os.getenv("SANCHANGJI_PROXY_UPSTREAM", DEFAULT_UPSTREAM_ORIGIN)
            upstream = urlparse(upstream_origin)
            upstream_url = urlunparse((
                upstream.scheme,
                upstream.netloc,
                parsed.path,
                "",
                parsed.query,
                ""
            ))
            self.proxy_request(upstream_url)
        except Exception as error:
            self.send_json(502, {
                "error": "Local proxy failed",
                "detail": {
                    "name": error.__class__.__name__,
                    "message": str(error)
                }
            })

    def handle_douban_api(self, parsed):
        if parsed.path == "/3/search/movie":
            params = dict(parse_qsl(parsed.query, keep_blank_values=True))
            query = params.get("query", "").strip()
            results = search_douban_movies(query)
            if results or os.getenv("SANCHANGJI_DISABLE_UPSTREAM_FALLBACK", "").lower() == "true":
                self.send_json(200, {"results": results})
            else:
                self.proxy_to_configured_upstream(parsed)
            return True

        detail_match = re.fullmatch(r"/3/movie/(\d+)", parsed.path)
        if detail_match and detail_match.group(1) in MOVIE_INDEX:
            self.send_json(200, douban_movie_details(detail_match.group(1)))
            return True

        credits_match = re.fullmatch(r"/3/movie/(\d+)/credits", parsed.path)
        if credits_match and credits_match.group(1) in MOVIE_INDEX:
            details = douban_movie_details(credits_match.group(1))
            director = details.get("_director", "")
            crew = [{"name": name, "job": "Director"} for name in split_people(director)]
            self.send_json(200, {"crew": crew})
            return True

        return False

    def proxy_to_configured_upstream(self, parsed):
        upstream_origin = os.getenv("SANCHANGJI_PROXY_UPSTREAM", DEFAULT_UPSTREAM_ORIGIN)
        upstream = urlparse(upstream_origin)
        upstream_url = urlunparse((
            upstream.scheme,
            upstream.netloc,
            parsed.path,
            "",
            parsed.query,
            ""
        ))
        self.proxy_request(upstream_url)

    def proxy_request(self, upstream_url):
        request = Request(upstream_url, headers={"Accept": "*/*", "User-Agent": USER_AGENT})
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

    def send_json(self, status, payload):
        public_payload = strip_private_keys(payload)
        body = json.dumps(public_payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_common_headers("application/json; charset=utf-8", len(body))
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


def search_douban_movies(query):
    normalized = normalize_query(query)
    if not normalized:
        return []

    cache_key = f"search:{normalized}"
    cached = get_cache(SEARCH_CACHE, cache_key)
    if cached is not None:
        return cached

    results = []
    for candidate in search_query_candidates(query, normalized):
        results.extend(search_douban_rexxar(candidate))
        if len(results) >= 6:
            break
        results.extend(search_douban_suggest(candidate))
        if len(results) >= 6:
            break
        results.extend(search_douban_html(candidate))
        if len(results) >= 6:
            break

    deduped = rank_and_dedupe(results, normalized)
    for item in deduped:
        index_movie_result(item)
    set_cache(SEARCH_CACHE, cache_key, deduped)
    return deduped


def search_douban_rexxar(query):
    url = f"https://m.douban.com/rexxar/api/v2/search?q={quote(query)}&start=0&count=20&cat=1002"
    try:
        payload = json.loads(fetch_text(url, referer=f"https://m.douban.com/search/?q={quote(query)}"))
    except Exception:
        return []

    subjects = payload.get("subjects")
    if isinstance(subjects, dict):
        items = subjects.get("items", [])
    elif isinstance(subjects, list):
        items = subjects
    else:
        items = []
    if not isinstance(items, list):
        return []

    results = []
    for item in items:
        target = item.get("target") or item
        uri = str(target.get("uri") or "")
        id_match = re.search(r"douban://douban\.com/movie/(\d+)", uri)
        if not id_match:
            continue
        douban_id = id_match.group(1)
        title = clean_title(target.get("title") or target.get("name") or "")
        if not title:
            continue
        cover = target.get("cover") or {}
        pic = target.get("pic") or {}
        poster = (
            (cover.get("normal") or {}).get("url")
            or (cover.get("large") or {}).get("url")
            or (pic.get("normal") or "")
            or target.get("cover_url")
            or ""
        )
        results.append({
            "id": int(douban_id),
            "title": title,
            "original_title": target.get("original_title") or target.get("latin_title") or "",
            "release_date": normalize_release_date(target.get("year") or target.get("card_subtitle") or ""),
            "poster_path": clean_url(poster),
            "overview": subject_url(douban_id),
            "_director": director_from_subtitle(target.get("card_subtitle") or "")
        })
    return results


def search_douban_suggest(query):
    url = f"{DOUBAN_ORIGIN}/j/subject_suggest?q={quote(query)}"
    try:
        payload = json.loads(fetch_text(url, referer=DOUBAN_ORIGIN))
    except Exception:
        return []

    if not isinstance(payload, list):
        return []

    results = []
    for item in payload:
        douban_id = str(item.get("id") or "").strip()
        title = clean_title(item.get("title") or item.get("sub_title") or "")
        if not douban_id or not title:
            continue
        results.append({
            "id": int(douban_id),
            "title": title,
            "original_title": item.get("sub_title") or "",
            "release_date": normalize_release_date(item.get("year") or ""),
            "poster_path": item.get("cover_url") or "",
            "overview": subject_url(douban_id)
        })
    return results


def search_douban_html(query):
    url = f"{DOUBAN_SEARCH_ORIGIN}/movie/subject_search?search_text={quote(query)}&cat=1002"
    try:
        html = fetch_text(url, referer=DOUBAN_ORIGIN)
    except Exception:
        return []

    match = re.search(r"window\.__DATA__\s*=\s*({.*?});", html, flags=re.S)
    if not match:
        return []

    raw_json = re.sub(
        r"\\x([0-9A-Fa-f]{2})",
        lambda m: chr(int(m.group(1), 16)),
        match.group(1)
    )

    try:
        payload = json.loads(raw_json)
    except json.JSONDecodeError:
        return []

    if payload.get("error_info"):
        return []

    results = []
    for item in payload.get("items", []):
        douban_id = str(item.get("id") or "").strip()
        title = clean_title(item.get("title") or "")
        if not douban_id or not title:
            continue
        year = extract_year(item.get("title") or "")
        results.append({
            "id": int(douban_id),
            "title": title,
            "original_title": "",
            "release_date": normalize_release_date(year),
            "poster_path": item.get("cover_url") or "",
            "overview": item.get("url") or subject_url(douban_id)
        })
    return results


def douban_movie_details(douban_id):
    cache_key = f"detail:{douban_id}"
    cached = get_cache(DETAIL_CACHE, cache_key)
    if cached is not None:
        return cached

    url = subject_url(douban_id)
    fallback = MOVIE_INDEX.get(str(douban_id), {})
    try:
        html = fetch_text(url, referer=DOUBAN_ORIGIN)
    except Exception:
        html = ""

    title = clean_title(first_match(html, r'<span property="v:itemreviewed">(.*?)</span>')) or fallback.get("title", "")
    year = extract_year(first_match(html, r'<span class="year">\((\d{4})\)</span>')) or extract_year(fallback.get("release_date", ""))
    poster = clean_url(first_match(html, r'<img[^>]+rel="v:image"[^>]+src="([^"]+)"')) or fallback.get("poster_path", "")
    director = " / ".join(clean_title(name) for name in re.findall(r'rel="v:directedBy">(.*?)</a>', html))
    if not director:
        director = fallback.get("_director", "")

    details = {
        "id": int(douban_id),
        "title": title or f"豆瓣条目 {douban_id}",
        "original_title": "",
        "release_date": normalize_release_date(year),
        "poster_path": poster,
        "overview": url,
        "_director": director
    }
    set_cache(DETAIL_CACHE, cache_key, details)
    return details


def fetch_text(url, referer):
    request = Request(
        url,
        headers={
            "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.4",
            "Referer": referer,
            "User-Agent": USER_AGENT
        }
    )
    with urlopen(request, timeout=12, context=DEV_SSL_CONTEXT) as response:
        return response.read().decode("utf-8", "ignore")


def normalize_query(query):
    text = unescape(str(query or "")).strip()
    patterns = [
        r"\s*[（(][^）)]*(英文|英语|中文|国语|原版|中字|字幕|2D|3D|4D|IMAX|CINITY|中国巨幕|杜比|激光)[^）)]*[）)]\s*$",
        r"\s*(中文|国语|原版|英语|英文)?\s*[234]D\s*$",
        r"\s*(IMAX|CINITY|中国巨幕|杜比全景声|杜比|激光|原版|国语|中字|中文字幕)\s*$"
    ]
    for pattern in patterns:
        text = re.sub(pattern, "", text, flags=re.I)
    return text.strip()


def clean_title(value):
    text = re.sub(r"<[^>]+>", "", str(value or ""))
    text = unescape(text).strip()
    text = re.sub(r"\s*\(\d{4}\)\s*$", "", text)
    return normalize_query(text)


def clean_url(value):
    return unescape(str(value or "").strip())


def extract_year(value):
    match = re.search(r"(19|20)\d{2}", str(value or ""))
    return match.group(0) if match else ""


def normalize_release_date(year):
    year = extract_year(year)
    return f"{year}-01-01" if year else ""


def first_match(text, pattern):
    match = re.search(pattern, text, flags=re.S)
    return match.group(1).strip() if match else ""


def subject_url(douban_id):
    return f"{DOUBAN_ORIGIN}/subject/{douban_id}/"


def split_people(value):
    return [name.strip() for name in re.split(r"[/,，、]", value or "") if name.strip()]


def director_from_subtitle(value):
    parts = [part.strip() for part in re.split(r"\s*/\s*", str(value or "")) if part.strip()]
    if len(parts) >= 3:
        return clean_title(parts[2])
    return ""


def index_movie_result(item):
    douban_id = str(item.get("id") or "")
    if douban_id:
        MOVIE_INDEX[douban_id] = dict(item)


def unique_values(values):
    seen = set()
    result = []
    for value in values:
        text = normalize_query(value)
        if text and text not in seen:
            seen.add(text)
            result.append(text)
    return result


def search_query_candidates(raw_query, normalized_query):
    candidates = [raw_query, normalized_query]
    title = normalize_query(normalized_query)

    for separator in ["：", ":", "之"]:
        if separator in title:
            candidates.append(title.split(separator, 1)[0])

    chinese_chars = "".join(re.findall(r"[\u4e00-\u9fff]", title))
    if len(chinese_chars) >= 3:
        candidates.append(chinese_chars[:3])
    if len(chinese_chars) >= 2:
        candidates.append(chinese_chars[:2])

    return unique_values(candidates)[:4]


def rank_and_dedupe(results, query):
    seen = set()
    normalized_query = compact_text(query)
    scored = []
    for item in results:
        douban_id = item.get("id")
        if not douban_id or douban_id in seen:
            continue
        seen.add(douban_id)
        title = compact_text(item.get("title", ""))
        score = 0
        if title == normalized_query:
            score += 100
        elif normalized_query and normalized_query in title:
            score += 60
        elif title and title in normalized_query:
            score += 40
        if item.get("poster_path"):
            score += 5
        if item.get("release_date"):
            score += 3
        scored.append((score, item))
    scored.sort(key=lambda pair: pair[0], reverse=True)
    return [item for _, item in scored[:10]]


def compact_text(value):
    return re.sub(r"[\W_]+", "", str(value or "").lower(), flags=re.UNICODE)


def get_cache(cache, key):
    item = cache.get(key)
    if not item:
        return None
    created_at, value = item
    if time.time() - created_at > CACHE_TTL_SECONDS:
        cache.pop(key, None)
        return None
    return value


def set_cache(cache, key, value):
    cache[key] = (time.time(), value)


def strip_private_keys(payload):
    if isinstance(payload, dict):
        return {key: strip_private_keys(value) for key, value in payload.items() if not key.startswith("_")}
    if isinstance(payload, list):
        return [strip_private_keys(item) for item in payload]
    return payload


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8787"))
    server = ThreadingHTTPServer(("0.0.0.0", port), LocalDevProxyHandler)
    provider = os.getenv("SANCHANGJI_METADATA_PROVIDER", "douban")
    print(f"散场记 local dev proxy listening on http://0.0.0.0:{port} ({provider})")
    server.serve_forever()
