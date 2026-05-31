"use strict";

const express = require("express");
const https = require("https");

const TMDB_API_ORIGIN = "https://api.themoviedb.org";
const TMDB_IMAGE_ORIGIN = "https://image.tmdb.org";

const app = express();
const port = Number(process.env.PORT || 9000);

app.options("/*", (_req, res) => {
  setCommonHeaders(res, "text/plain");
  res.status(204).send("");
});

app.get("/3/*", async (req, res) => {
  try {
    const apiKey = process.env.TMDB_API_KEY;
    if (!apiKey) {
      sendJSON(res, 500, { error: "Missing TMDB_API_KEY" });
      return;
    }

    const upstreamURL = new URL(TMDB_API_ORIGIN + req.path);
    for (const [key, value] of Object.entries(req.query)) {
      if (key !== "api_key" && value != null) {
        upstreamURL.searchParams.set(key, String(value));
      }
    }
    upstreamURL.searchParams.set("api_key", apiKey);

    const upstreamResponse = await requestUpstream(upstreamURL, {
      Accept: "application/json"
    });

    setCommonHeaders(res, upstreamResponse.headers["content-type"] || "application/json; charset=utf-8");
    res.status(upstreamResponse.statusCode).send(upstreamResponse.body);
  } catch (error) {
    console.error("TMDB API proxy error:", error);
    sendJSON(res, 502, { error: "TMDB proxy failed", detail: formatError(error) });
  }
});

app.get("/t/*", async (req, res) => {
  try {
    const upstreamURL = new URL(TMDB_IMAGE_ORIGIN + req.path);
    for (const [key, value] of Object.entries(req.query)) {
      if (value != null) {
        upstreamURL.searchParams.set(key, String(value));
      }
    }

    const upstreamResponse = await requestUpstream(upstreamURL);

    setCommonHeaders(res, upstreamResponse.headers["content-type"] || "image/jpeg");
    res.status(upstreamResponse.statusCode).send(upstreamResponse.body);
  } catch (error) {
    console.error("TMDB image proxy error:", error);
    sendJSON(res, 502, { error: "TMDB image proxy failed", detail: formatError(error) });
  }
});

app.get("/*", (_req, res) => {
  sendJSON(res, 404, { error: "Not found" });
});

app.listen(port, () => {
  console.log(`TMDB proxy listening on ${port}`);
});

function sendJSON(res, statusCode, payload) {
  setCommonHeaders(res, "application/json; charset=utf-8");
  res.status(statusCode).send(JSON.stringify(payload));
}

function requestUpstream(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const request = https.request(url, { family: 4, method: "GET", headers }, response => {
      const chunks = [];

      response.on("data", chunk => chunks.push(chunk));
      response.on("end", () => {
        resolve({
          body: Buffer.concat(chunks),
          headers: response.headers,
          statusCode: response.statusCode || 502
        });
      });
    });

    request.setTimeout(15000, () => {
      request.destroy(new Error("Upstream request timed out"));
    });
    request.on("error", reject);
    request.end();
  });
}

function formatError(error) {
  return {
    code: error && error.code,
    message: error && error.message,
    name: error && error.name,
    text: String(error)
  };
}

function setCommonHeaders(res, contentType) {
  res.setHeader("Content-Type", contentType);
  res.setHeader("Cache-Control", "public, max-age=86400");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
}
