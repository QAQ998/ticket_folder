# Aliyun FC TMDB Proxy

Use Alibaba Cloud Function Compute to proxy TMDB requests when phones cannot reach TMDB directly.

Function settings:

```text
Runtime: Node.js 20
Handler: index.handler
Memory: 128 MB
Timeout: 15 seconds
Environment variable: TMDB_API_KEY
HTTP trigger auth: anonymous/no authentication for development
Allowed methods: GET, OPTIONS
Internet access: enabled
```

After deployment, configure the iOS app in `Local.xcconfig`:

```text
TMDB_API_BASE_URL = https://your-fc-domain.fcapp.run/3
TMDB_IMAGE_BASE_URL = https://your-fc-domain.fcapp.run/t/p/w500
```
