# Aliyun FC Web Function TMDB Proxy

Use this version when Alibaba Cloud asks for a startup command and listening port.

Recommended settings:

```text
Runtime: Custom Runtime / Node.js 20 / Debian 11
Startup command: node server.js
Listening port: 9000
Memory: 0.5 GB or the minimum available
Timeout: 15-60 seconds
Environment variable: TMDB_API_KEY
HTTP access auth: anonymous/no authentication for development
```

After deployment, configure the iOS app in `Local.xcconfig`:

```text
TMDB_API_BASE_URL = https://your-fc-domain.fcapp.run/3
TMDB_IMAGE_BASE_URL = https://your-fc-domain.fcapp.run/t/p/w500
```
