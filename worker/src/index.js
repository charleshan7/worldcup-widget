const UPSTREAM_URL = "https://api.football-data.org/v4/competitions/WC/matches";
const ESPN_URL = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard";
const TSDB_DAY = "https://www.thesportsdb.com/api/v1/json/3/eventsday.php";
const TSDB_TL = "https://www.thesportsdb.com/api/v1/json/3/lookuptimeline.php";
const CACHE_SECONDS = 45;

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

// 队名归一化（跨数据源对齐）
const ALIAS = {
  unitedstates: "usa", us: "usa",
  korearepublic: "southkorea", republicofkorea: "southkorea", korea: "southkorea",
  czechrepublic: "czechia",
  turkiye: "turkey",
  drcongo: "congodr", democraticrepublicofthecongo: "congodr",
  capeverdeislands: "capeverde",
  bosniaandherzegovina: "bosnia", bosniaherzegovina: "bosnia",
  cotedivoire: "ivorycoast",
};
function norm(s) {
  if (!s) return "";
  const x = String(s).toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z]/g, "");
  return ALIAS[x] || x;
}
function pairKey(a, b) {
  return [norm(a), norm(b)].sort().join("|");
}

// 昨天 / 今天 / 明天（UTC）的日期串
function windowDates() {
  const out = [];
  const now = Date.now();
  const p = (n) => String(n).padStart(2, "0");
  for (let off = -1; off <= 1; off++) {
    const d = new Date(now + off * 86400000);
    const y = d.getUTCFullYear(), m = d.getUTCMonth() + 1, day = d.getUTCDate();
    out.push({ ymd: `${y}${p(m)}${p(day)}`, dash: `${y}-${p(m)}-${p(day)}` });
  }
  return out;
}

// 源 1：ESPN（覆盖好，一天一调即拿到当天全部进球）
async function espnGoals(dates) {
  const map = {};
  for (const d of dates) {
    try {
      const r = await fetch(`${ESPN_URL}?dates=${d.ymd}`, { cf: { cacheTtl: 30 } });
      if (!r.ok) continue;
      const data = await r.json();
      for (const ev of data.events || []) {
        const comp = (ev.competitions || [])[0];
        if (!comp) continue;
        const competitors = comp.competitors || [];
        if (competitors.length < 2) continue;
        const nameById = {};
        for (const c of competitors) nameById[c.id] = c.team?.displayName || c.team?.name || "";
        const goals = [];
        for (const det of comp.details || []) {
          const t = (det.type?.text || "").toLowerCase();
          if (!det.scoringPlay && !t.includes("goal")) continue;
          if (t.includes("shootout")) continue; // 跳过点球大战
          const ath = (det.athletesInvolved || [])[0];
          const minute = parseInt(String(det.clock?.displayValue || ""), 10) || null; // "45'+3'" -> 45
          goals.push({
            player: ath?.displayName || "Goal",
            minute,
            teamNorm: norm(nameById[det.team?.id] || ""),
            ownGoal: t.includes("own"),
          });
        }
        const st = ev.status || comp.status || {};
        map[pairKey(competitors[0].team?.displayName, competitors[1].team?.displayName)] = {
          goals,
          minute: parseInt(String(st.displayClock || ""), 10) || null, // 直播分钟
          state: st.type?.state || "",   // in / pre / post
          name: st.type?.name || "",     // STATUS_HALFTIME / STATUS_FIRST_HALF / ...
        };
      }
    } catch (_) { /* 单源失败不影响整体 */ }
  }
  return map;
}

// 源 2：TheSportsDB（兜底 ESPN 未覆盖的场次）
async function tsdbGoals(dates, needed) {
  const map = {};
  const H = { "User-Agent": "Mozilla/5.0" };
  for (const d of dates) {
    try {
      const r = await fetch(`${TSDB_DAY}?d=${d.dash}&l=4429`, { headers: H, cf: { cacheTtl: 60 } });
      if (!r.ok) continue;
      const data = await r.json();
      for (const e of data.events || []) {
        const pk = pairKey(e.strHomeTeam, e.strAwayTeam);
        if (!needed.has(pk) || map[pk]) continue;
        const tr = await fetch(`${TSDB_TL}?id=${e.idEvent}`, { headers: H, cf: { cacheTtl: 30 } });
        if (!tr.ok) continue;
        const td = await tr.json();
        const goals = [];
        for (const t of td.timeline || []) {
          if ((t.strTimeline || "").toLowerCase() !== "goal" || !t.strPlayer) continue;
          goals.push({
            player: t.strPlayer,
            minute: parseInt(t.intTime) || null,
            teamNorm: (t.strHome || "").toLowerCase() === "yes" ? norm(e.strHomeTeam) : norm(e.strAwayTeam),
            ownGoal: (t.strTimelineDetail || "").toLowerCase().includes("own"),
          });
        }
        if (goals.length) map[pk] = goals;
      }
    } catch (_) { /* 忽略 */ }
  }
  return map;
}

async function enrich(matches) {
  const now = Date.now();
  // 只给最近(±2天内)有比分/进行中的比赛补进球
  const relevant = matches.filter((m) => {
    if (!["IN_PLAY", "PAUSED", "FINISHED", "SUSPENDED", "AWARDED"].includes(m.status)) return false;
    const t = Date.parse(m.utcDate);
    return !isNaN(t) && t > now - 2 * 86400000 && t < now + 86400000;
  });
  if (!relevant.length) return matches;

  const dates = windowDates();
  const espn = await espnGoals(dates);

  const missing = new Set();
  for (const m of relevant) {
    const pk = pairKey(m.homeTeam?.name, m.awayTeam?.name);
    if (!(espn[pk]?.goals?.length)) missing.add(pk);
  }
  const tsdb = missing.size ? await tsdbGoals(dates, missing) : {};

  for (const m of matches) {
    const pk = pairKey(m.homeTeam?.name, m.awayTeam?.name);
    const e = espn[pk];
    const hNorm = norm(m.homeTeam?.name);
    const goals = (e?.goals?.length ? e.goals : tsdb[pk]) || null;
    if (goals) {
      m.goals = goals.map((g) => ({
        player: g.player,
        minute: g.minute,
        isHome: g.teamNorm === hNorm,
        ownGoal: g.ownGoal,
      }));
    }
    // 直播分钟/阶段（ESPN 报告进行中时）：供"正在进行"显示进程时间/中场休息
    if (e && e.state === "in") {
      m.minute = e.minute;
      m.phase = e.name;
    }
  }
  return matches;
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
      headers: { accept: "application/json", "x-auth-token": env.FOOTBALL_DATA_API_TOKEN },
      cf: { cacheTtl: CACHE_SECONDS, cacheEverything: true },
    });
    if (!upstream.ok) {
      return json(
        { error: "Upstream data service unavailable", status: upstream.status },
        upstream.status === 429 ? 429 : 502,
      );
    }

    const data = await upstream.json();
    try {
      if (Array.isArray(data.matches)) data.matches = await enrich(data.matches);
    } catch (_) { /* 补全失败则原样返回比分 */ }

    const response = json(data, 200, { "cache-control": `public, max-age=${CACHE_SECONDS}` });
    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};
