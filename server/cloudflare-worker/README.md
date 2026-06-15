# Movie Metadata Proxies

Cloudflare Worker proxy examples for movie metadata.

## TMDB Proxy

`tmdb-proxy.js` is for phones that cannot reach TMDB directly.

Required secret:

```text
TMDB_API_KEY
```

After deployment, configure the iOS app in `Local.xcconfig`:

```text
TMDB_API_BASE_URL = https://your-worker.workers.dev/3
TMDB_IMAGE_BASE_URL = https://your-worker.workers.dev/t/p/w500
```

The app will then request the Worker instead of calling TMDB directly.

## Douban Metadata Proxy

`douban-metadata-proxy.js` exposes the App-facing endpoint:

```text
GET /movie/search?query=片名
Authorization: Bearer {MOVIE_PROXY_TOKEN}
```

It returns the shape expected by the iOS app:

```json
{
  "results": [
    {
      "title": "电影名",
      "original_title": "Original Title",
      "release_date": "2025-09-04",
      "directors": ["导演"],
      "runtime_minutes": 105,
      "douban_rating": "8.2",
      "poster_url": "https://..."
    }
  ]
}
```

Recommended Worker bindings:

```text
MOVIE_PROXY_TOKEN = your_private_token
METADATA_CACHE    = KV namespace for movie metadata cache
RATE_LIMIT_KV     = KV namespace for per-IP rate limiting
```

Deployment sketch:

```bash
cd server/cloudflare-worker
cp douban-wrangler.example.toml wrangler.toml
wrangler kv namespace create METADATA_CACHE
wrangler kv namespace create RATE_LIMIT_KV
wrangler secret put MOVIE_PROXY_TOKEN
wrangler deploy --config wrangler.toml
```

After deployment, configure the iOS app in `Local.xcconfig`:

```text
URL_SLASH = /
DOUBAN_API_BASE_URL = https:$(URL_SLASH)$(URL_SLASH)your-worker.workers.dev
DOUBAN_API_KEY = your_private_token
```

Important boundaries:

- The iOS app does not call Douban pages directly.
- The Worker caches successful results for 30 days and empty results for 6 hours.
- The Worker limits each IP to 10 requests per minute when `RATE_LIMIT_KV` is configured.
- If Douban returns `403`, `418`, or `429`, the Worker does not retry or attempt to bypass protection. It returns `503`, and the app can fall back to TMDB or block saving until required movie metadata is available.
- For production, prefer a licensed data provider or a pre-warmed/cache-first metadata store. Treat this Worker as a minimal reference implementation, not a high-volume crawler.

## Local Dev Proxy

`server/local-dev-proxy/app.py` can forward both TMDB and Douban metadata requests while testing on a phone or simulator:

```bash
SANCHANGJI_DOUBAN_PROXY_UPSTREAM=https://your-worker.workers.dev \
SANCHANGJI_DOUBAN_PROXY_TOKEN=your_private_token \
python3 server/local-dev-proxy/app.py
```

Then configure:

```text
DOUBAN_API_BASE_URL = http:$(URL_SLASH)$(URL_SLASH)你的电脑局域网IP:8787
DOUBAN_API_KEY =
```
