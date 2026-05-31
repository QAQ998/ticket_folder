"use strict";

const TMDB_API_ORIGIN = "https://api.themoviedb.org";
const TMDB_IMAGE_ORIGIN = "https://image.tmdb.org";

exports.handler = async function(event) {
  const request = JSON.parse(event.toString());
  const path = request.rawPath || request?.requestContext?.http?.path || "/";
  const query = request.queryParameters || {};
  const method = request?.requestContext?.http?.method || "GET";

  if (method === "OPTIONS") {
    return response(204, "", "text/plain");
  }

  try {
    if (path.startsWith("/3/")) {
      return await proxyAPI(path, query);
    }

    if (path.startsWith("/t/")) {
      return await proxyImage(path, query);
    }

    return response(404, JSON.stringify({ error: "Not found" }), "application/json; charset=utf-8");
  } catch (error) {
    console.error("TMDB proxy error:", error);
    return response(502, JSON.stringify({ error: "TMDB proxy failed" }), "application/json; charset=utf-8");
  }
};

async function proxyAPI(path, query) {
  const apiKey = process.env.TMDB_API_KEY;
  if (!apiKey) {
    return response(500, JSON.stringify({ error: "Missing TMDB_API_KEY" }), "application/json; charset=utf-8");
  }

  const upstreamURL = new URL(TMDB_API_ORIGIN + path);
  for (const [key, value] of Object.entries(query)) {
    if (key !== "api_key" && value != null) {
      upstreamURL.searchParams.set(key, value);
    }
  }
  upstreamURL.searchParams.set("api_key", apiKey);

  const upstreamResponse = await fetch(upstreamURL, {
    method: "GET",
    headers: { "Accept": "application/json" }
  });
  const body = await upstreamResponse.text();

  return response(
    upstreamResponse.status,
    body,
    upstreamResponse.headers.get("content-type") || "application/json; charset=utf-8"
  );
}

async function proxyImage(path, query) {
  const upstreamURL = new URL(TMDB_IMAGE_ORIGIN + path);
  for (const [key, value] of Object.entries(query)) {
    if (value != null) {
      upstreamURL.searchParams.set(key, value);
    }
  }

  const upstreamResponse = await fetch(upstreamURL);
  const buffer = Buffer.from(await upstreamResponse.arrayBuffer());

  return {
    statusCode: upstreamResponse.status,
    headers: defaultHeaders(upstreamResponse.headers.get("content-type") || "image/jpeg"),
    body: buffer.toString("base64"),
    isBase64Encoded: true
  };
}

function response(statusCode, body, contentType) {
  return {
    statusCode,
    headers: defaultHeaders(contentType),
    body,
    isBase64Encoded: false
  };
}

function defaultHeaders(contentType) {
  return {
    "Content-Type": contentType,
    "Cache-Control": "public, max-age=86400",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  };
}
