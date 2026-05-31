"use strict";

const http = require("http");
const { URL } = require("url");

const TMDB_API_ORIGIN = "https://api.themoviedb.org";
const TMDB_IMAGE_ORIGIN = "https://image.tmdb.org";
const PORT = Number(process.env.PORT || 9000);

const server = http.createServer(async (request, response) => {
  if (request.method === "OPTIONS") {
    send(response, 204, "", "text/plain");
    return;
  }

  if (request.method !== "GET") {
    send(response, 405, JSON.stringify({ error: "Method not allowed" }), "application/json; charset=utf-8");
    return;
  }

  try {
    const sourceURL = new URL(request.url, `http://${request.headers.host || "localhost"}`);

    if (sourceURL.pathname.startsWith("/3/")) {
      await proxyAPI(sourceURL, response);
      return;
    }

    if (sourceURL.pathname.startsWith("/t/")) {
      await proxyImage(sourceURL, response);
      return;
    }

    send(response, 404, JSON.stringify({ error: "Not found" }), "application/json; charset=utf-8");
  } catch (error) {
    console.error("TMDB proxy error:", error);
    send(response, 502, JSON.stringify({ error: "TMDB proxy failed" }), "application/json; charset=utf-8");
  }
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`TMDB proxy listening on ${PORT}`);
});

async function proxyAPI(sourceURL, response) {
  const apiKey = process.env.TMDB_API_KEY;
  if (!apiKey) {
    send(response, 500, JSON.stringify({ error: "Missing TMDB_API_KEY" }), "application/json; charset=utf-8");
    return;
  }

  const upstreamURL = new URL(TMDB_API_ORIGIN + sourceURL.pathname);
  for (const [key, value] of sourceURL.searchParams.entries()) {
    if (key !== "api_key") {
      upstreamURL.searchParams.set(key, value);
    }
  }
  upstreamURL.searchParams.set("api_key", apiKey);

  const upstreamResponse = await fetch(upstreamURL, {
    headers: { "Accept": "application/json" }
  });
  const body = await upstreamResponse.text();
  send(
    response,
    upstreamResponse.status,
    body,
    upstreamResponse.headers.get("content-type") || "application/json; charset=utf-8"
  );
}

async function proxyImage(sourceURL, response) {
  const upstreamURL = new URL(TMDB_IMAGE_ORIGIN + sourceURL.pathname);
  upstreamURL.search = sourceURL.search;

  const upstreamResponse = await fetch(upstreamURL);
  const body = Buffer.from(await upstreamResponse.arrayBuffer());
  send(
    response,
    upstreamResponse.status,
    body,
    upstreamResponse.headers.get("content-type") || "image/jpeg"
  );
}

function send(response, statusCode, body, contentType) {
  response.writeHead(statusCode, {
    "Content-Type": contentType,
    "Cache-Control": "public, max-age=86400",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  });
  response.end(body);
}
