const TMDB_API_ORIGIN = "https://api.themoviedb.org";
const TMDB_IMAGE_ORIGIN = "https://image.tmdb.org";

export default {
  async fetch(request, env) {
    const sourceURL = new URL(request.url);
    const pathname = sourceURL.pathname;

    if (pathname.startsWith("/3/")) {
      return proxyAPIRequest(request, env, sourceURL);
    }

    if (pathname.startsWith("/t/")) {
      return proxyImageRequest(request, sourceURL);
    }

    return new Response("Not found", { status: 404 });
  }
};

async function proxyAPIRequest(request, env, sourceURL) {
  if (!env.TMDB_API_KEY) {
    return new Response("Missing TMDB_API_KEY", { status: 500 });
  }

  const upstreamURL = new URL(TMDB_API_ORIGIN + sourceURL.pathname);
  upstreamURL.search = sourceURL.search;
  upstreamURL.searchParams.delete("api_key");
  upstreamURL.searchParams.set("api_key", env.TMDB_API_KEY);

  const response = await fetch(upstreamURL, {
    method: request.method,
    headers: {
      "Accept": "application/json"
    }
  });

  return new Response(response.body, {
    status: response.status,
    headers: responseHeaders(response, "application/json; charset=utf-8")
  });
}

async function proxyImageRequest(request, sourceURL) {
  const upstreamURL = new URL(TMDB_IMAGE_ORIGIN + sourceURL.pathname);
  upstreamURL.search = sourceURL.search;

  const response = await fetch(upstreamURL, {
    method: request.method
  });

  return new Response(response.body, {
    status: response.status,
    headers: responseHeaders(response, response.headers.get("content-type") ?? "image/jpeg")
  });
}

function responseHeaders(response, contentType) {
  const headers = new Headers();
  headers.set("content-type", contentType);
  headers.set("cache-control", response.headers.get("cache-control") ?? "public, max-age=86400");
  return headers;
}
