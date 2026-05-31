# TMDB Proxy

Cloudflare Worker proxy for phones that cannot reach TMDB directly.

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
