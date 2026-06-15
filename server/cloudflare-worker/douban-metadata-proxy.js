const DOUBAN_ORIGIN = "https://movie.douban.com";
const CACHE_TTL_SECONDS = 60 * 60 * 24 * 30;
const NEGATIVE_CACHE_TTL_SECONDS = 60 * 60 * 6;
const RATE_LIMIT_WINDOW_SECONDS = 60;
const RATE_LIMIT_MAX_REQUESTS = 10;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname !== "/movie/search") {
      return json({ error: "not_found" }, 404);
    }

    if (request.method !== "GET") {
      return json({ error: "method_not_allowed" }, 405);
    }

    const authError = validateAuthorization(request, env);
    if (authError) {
      return authError;
    }

    const rateLimitError = await enforceRateLimit(request, env);
    if (rateLimitError) {
      return rateLimitError;
    }

    const query = normalizeQuery(url.searchParams.get("query") ?? "");
    if (!query) {
      return json({ error: "missing_query" }, 400);
    }

    const cacheKey = `douban:movie:${query}`;
    const cached = await readCache(env, cacheKey);
    if (cached) {
      return json(cached.body, cached.status, { "x-metadata-cache": "hit" });
    }

    try {
      const movie = await fetchDoubanMovie(query);
      if (!movie) {
        const body = { results: [] };
        ctx.waitUntil(writeCache(env, cacheKey, body, 200, NEGATIVE_CACHE_TTL_SECONDS));
        return json(body, 200, { "x-metadata-cache": "miss" });
      }

      const body = { results: [movie] };
      ctx.waitUntil(writeCache(env, cacheKey, body, 200, CACHE_TTL_SECONDS));
      return json(body, 200, { "x-metadata-cache": "miss" });
    } catch (error) {
      const message = error instanceof Error ? error.message : "upstream_error";
      return json({ error: "douban_unavailable", message }, 503);
    }
  }
};

function validateAuthorization(request, env) {
  if (!env.MOVIE_PROXY_TOKEN) {
    return null;
  }

  const expected = `Bearer ${env.MOVIE_PROXY_TOKEN}`;
  if (request.headers.get("authorization") !== expected) {
    return json({ error: "unauthorized" }, 401);
  }

  return null;
}

async function enforceRateLimit(request, env) {
  if (!env.RATE_LIMIT_KV) {
    return null;
  }

  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const bucket = Math.floor(Date.now() / 1000 / RATE_LIMIT_WINDOW_SECONDS);
  const key = `ratelimit:${ip}:${bucket}`;
  const count = Number(await env.RATE_LIMIT_KV.get(key) ?? "0") + 1;
  await env.RATE_LIMIT_KV.put(key, String(count), {
    expirationTtl: RATE_LIMIT_WINDOW_SECONDS * 2
  });

  if (count > RATE_LIMIT_MAX_REQUESTS) {
    return json({ error: "rate_limited" }, 429, {
      "retry-after": String(RATE_LIMIT_WINDOW_SECONDS)
    });
  }

  return null;
}

async function fetchDoubanMovie(query) {
  const suggestions = await fetchSuggestions(query);
  const movieSuggestion = suggestions.find((item) => item.type === "movie" && item.id) ?? suggestions.find((item) => item.id);
  if (!movieSuggestion) {
    return null;
  }

  const subject = await fetchSubject(movieSuggestion.id);
  return {
    title: subject.title || movieSuggestion.title || query,
    original_title: subject.originalTitle || "",
    release_date: subject.releaseDate || "",
    directors: subject.directors,
    runtime_minutes: subject.runtimeMinutes,
    douban_rating: subject.rating || "",
    poster_url: subject.posterURL || movieSuggestion.img || ""
  };
}

async function fetchSuggestions(query) {
  const url = new URL(`${DOUBAN_ORIGIN}/j/subject_suggest`);
  url.searchParams.set("q", query);

  const response = await fetchDouban(url);
  const data = await response.json();
  return Array.isArray(data) ? data : [];
}

async function fetchSubject(id) {
  const url = new URL(`${DOUBAN_ORIGIN}/subject/${encodeURIComponent(id)}/`);
  const response = await fetchDouban(url);
  const html = await response.text();
  const jsonLD = parseJSONLD(html);

  return {
    title: stringValue(jsonLD.name),
    originalTitle: parseOriginalTitle(html),
    releaseDate: stringValue(jsonLD.datePublished) || parseFirstMatch(html, /上映日期:<\/span>\s*([^<]+)/),
    directors: parsePeople(jsonLD.director),
    runtimeMinutes: parseDurationMinutes(jsonLD.duration) ?? parseRuntimeFromHTML(html),
    rating: stringValue(jsonLD.aggregateRating?.ratingValue) || parseFirstMatch(html, /property="v:average">([^<]+)</),
    posterURL: stringValue(jsonLD.image) || parseFirstMatch(html, /rel="v:image"\s+src="([^"]+)"/)
  };
}

async function fetchDouban(url) {
  const response = await fetch(url, {
    headers: {
      "accept": "application/json,text/html;q=0.9,*/*;q=0.8",
      "accept-language": "zh-CN,zh;q=0.9,en;q=0.6",
      "user-agent": "TicketWalletAppMetadataProxy/1.0"
    }
  });

  if ([403, 418, 429].includes(response.status)) {
    throw new Error(`douban_blocked_${response.status}`);
  }

  if (!response.ok) {
    throw new Error(`douban_http_${response.status}`);
  }

  return response;
}

function parseJSONLD(html) {
  const match = html.match(/<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/i);
  if (!match) {
    return {};
  }

  try {
    return JSON.parse(unescapeHTML(match[1].trim()));
  } catch {
    return {};
  }
}

function parseOriginalTitle(html) {
  const title = parseFirstMatch(html, /<span property="v:itemreviewed">([^<]+)<\/span>/);
  if (!title) {
    return "";
  }
  const parts = title.split(" ");
  return parts.length > 1 ? parts.slice(1).join(" ").trim() : "";
}

function parsePeople(value) {
  if (!value) {
    return [];
  }

  const people = Array.isArray(value) ? value : [value];
  return people
    .map((person) => typeof person === "string" ? person : person?.name)
    .filter(Boolean);
}

function parseDurationMinutes(value) {
  const text = stringValue(value);
  if (!text) {
    return null;
  }

  const isoMatch = text.match(/PT(?:(\d+)H)?(?:(\d+)M)?/i);
  if (isoMatch) {
    return Number(isoMatch[1] ?? 0) * 60 + Number(isoMatch[2] ?? 0);
  }

  const minuteMatch = text.match(/(\d+)/);
  return minuteMatch ? Number(minuteMatch[1]) : null;
}

function parseRuntimeFromHTML(html) {
  const runtime = parseFirstMatch(html, /片长:<\/span>\s*([^<]+)/);
  if (!runtime) {
    return null;
  }
  const match = runtime.match(/(\d+)/);
  return match ? Number(match[1]) : null;
}

function parseFirstMatch(text, pattern) {
  const match = text.match(pattern);
  return match ? unescapeHTML(match[1]).trim() : "";
}

function stringValue(value) {
  if (value === null || value === undefined) {
    return "";
  }
  return String(value).trim();
}

function normalizeQuery(value) {
  return value
    .trim()
    .replace(/\s+/g, " ")
    .slice(0, 64);
}

async function readCache(env, key) {
  if (!env.METADATA_CACHE) {
    return null;
  }

  const raw = await env.METADATA_CACHE.get(key);
  return raw ? JSON.parse(raw) : null;
}

async function writeCache(env, key, body, status, ttl) {
  if (!env.METADATA_CACHE) {
    return;
  }

  await env.METADATA_CACHE.put(
    key,
    JSON.stringify({ body, status }),
    { expirationTtl: ttl }
  );
}

function json(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": status === 200 ? `public, max-age=${CACHE_TTL_SECONDS}` : "no-store",
      ...extraHeaders
    }
  });
}

function unescapeHTML(value) {
  return value
    .replace(/&quot;/g, '"')
    .replace(/&#34;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}
