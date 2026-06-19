const UPSTREAM_URL = "https://api.football-data.org/v4/competitions/WC/matches";
const CACHE_SECONDS = 60;

function json(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...extraHeaders,
    },
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method !== "GET") {
      return json({ error: "Method not allowed" }, 405, { allow: "GET" });
    }

    if (url.pathname === "/health") {
      return json({ ok: true, service: "worldcup-widget-api" });
    }

    if (url.pathname !== "/v1/matches") {
      return json({ error: "Not found" }, 404);
    }

    if (!env.FOOTBALL_DATA_API_TOKEN) {
      return json({ error: "Server is not configured" }, 503);
    }

    const cache = caches.default;
    const cacheKey = new Request("https://cache.worldcup-widget.local/v1/matches");
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    const upstream = await fetch(UPSTREAM_URL, {
      headers: {
        accept: "application/json",
        "x-auth-token": env.FOOTBALL_DATA_API_TOKEN,
      },
      cf: {
        cacheTtl: CACHE_SECONDS,
        cacheEverything: true,
      },
    });

    if (!upstream.ok) {
      return json(
        { error: "Upstream data service unavailable", status: upstream.status },
        upstream.status === 429 ? 429 : 502,
      );
    }

    const response = new Response(upstream.body, {
      status: 200,
      headers: {
        "content-type": "application/json; charset=utf-8",
        "cache-control": `public, max-age=${CACHE_SECONDS}`,
        "x-content-type-options": "nosniff",
      },
    });

    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};
