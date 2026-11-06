// POST /functions/v1/ingest-sleep
// Telefon posílá surová data z HealthKitu (úseky spánku + tep) za okno
// několika dní. Server vybere hlavní spánek pro každý den, spočítá skóre,
// zapíše noc, vytvoří kartu do feedu a doplní skóre do běžících výzev.
//
// Body:
// {
//   "timezone": "Europe/Prague",
//   "samples":    [{ "uuid", "start", "end", "stage", "source", "userEntered" }],
//   "heart_rate": [{ "t", "bpm" }]
// }

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  assignMainSleep,
  buildSessions,
  computeMetrics,
  computeScore,
  HR_HISTORY_NIGHTS,
  type HrSample,
  isValidTimeZone,
  minutesFromNoon,
  REGULARITY_HISTORY_NIGHTS,
  SCORE_VERSION,
  type Session,
  type SleepSample,
} from "../_shared/sleep.ts";

const MAX_SLEEP_SAMPLES = 5000;
const MAX_HR_SAMPLES = 60000;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  // --- kdo volá -------------------------------------------------------
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth } = await admin.auth.getUser(jwt);
  const userId = auth.user?.id;
  if (!userId) return json({ error: "unauthorized" }, 401);

  const { data: profile } = await admin.from("profiles").select("id, timezone").eq("id", userId).maybeSingle();
  if (!profile) return json({ error: "not a member" }, 403);

  // --- vstup ----------------------------------------------------------
  let body: { timezone?: unknown; samples?: unknown; heart_rate?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }
  const samples = Array.isArray(body.samples) ? (body.samples as SleepSample[]) : null;
  const hr = Array.isArray(body.heart_rate) ? (body.heart_rate as HrSample[]) : [];
  if (!samples) return json({ error: "samples must be an array" }, 400);
  if (samples.length > MAX_SLEEP_SAMPLES || hr.length > MAX_HR_SAMPLES) {
    return json({ error: "payload too large" }, 413);
  }

  const tz = isValidTimeZone(body.timezone) ? body.timezone : profile.timezone;
  if (tz !== profile.timezone) {
    await admin.from("profiles").update({ timezone: tz }).eq("id", userId);
  }

  // --- zpracování -----------------------------------------------------
  const nights = assignMainSleep(buildSessions(samples), tz);
  const results: { date: string; score: number | null; status: string; [k: string]: unknown }[] = [];

  // chronologicky, aby se baseline dalších nocí počítala z už uložených
  for (const date of [...nights.keys()].sort()) {
    try {
      results.push(await saveNight(admin, userId, tz, date, nights.get(date)!, hr));
    } catch (e) {
      console.error("ingest failed", { userId, date, error: String(e) });
      results.push({ date, score: null, status: "error" });
    }
  }

  return json({ nights: results });
});

// deno-lint-ignore no-explicit-any
type Admin = any;

async function saveNight(
  admin: Admin,
  userId: string,
  tz: string,
  date: string,
  session: Session,
  hr: HrSample[],
) {
  // Ochrana zpětného nahrávání: neuložit kratší spánek přes delší,
  // pokud se časově nepřekrývají (např. dorazil jen šlofík).
  const { data: existing } = await admin
    .from("nights")
    .select("id, sleep_start, sleep_end, total_sleep_min")
    .eq("user_id", userId)
    .eq("night_date", date)
    .maybeSingle();
  if (existing) {
    const overlaps = session.sleepStart < Date.parse(existing.sleep_end) &&
      session.sleepEnd > Date.parse(existing.sleep_start);
    if (!overlaps && session.asleepMin < existing.total_sleep_min) {
      return { date, score: null, status: "kept_existing" };
    }
  }

  // Baseline z předchozích nocí
  const { data: history } = await admin
    .from("nights")
    .select("sleep_start, hr_avg")
    .eq("user_id", userId)
    .lt("night_date", date)
    .order("night_date", { ascending: false })
    .limit(Math.max(REGULARITY_HISTORY_NIGHTS, HR_HISTORY_NIGHTS));
  const rows = (history ?? []) as { sleep_start: string; hr_avg: number | null }[];
  const baseline = {
    startMinutesFromNoon: rows.slice(0, REGULARITY_HISTORY_NIGHTS).map((r) =>
      minutesFromNoon(Date.parse(r.sleep_start), tz)
    ),
    hrAvgs: rows.slice(0, HR_HISTORY_NIGHTS).map((r) => r.hr_avg).filter((x): x is number => x !== null)
      .map(Number),
  };

  const m = computeMetrics(session, hr);
  const { score, breakdown } = computeScore(m, baseline, tz);

  // Noc
  const { data: night, error: nightErr } = await admin
    .from("nights")
    .upsert({
      user_id: userId,
      night_date: date,
      sleep_start: new Date(m.sleepStart).toISOString(),
      sleep_end: new Date(m.sleepEnd).toISOString(),
      total_sleep_min: m.totalSleepMin,
      awake_min: m.awakeMin,
      core_min: m.coreMin,
      deep_min: m.deepMin,
      rem_min: m.remMin,
      wake_count: m.wakeCount,
      hr_avg: m.hrAvg,
      hr_min: m.hrMin,
      score,
      score_breakdown: breakdown,
      score_version: SCORE_VERSION,
      source_name: session.source,
    }, { onConflict: "user_id,night_date" })
    .select("id")
    .single();
  if (nightErr) throw nightErr;

  // Surová data jen v okně spánku (hypnogram + přepočet)
  const hrInWindow = hr
    .filter((h) => {
      const t = Date.parse(h.t);
      return t >= m.sleepStart && t <= m.sleepEnd;
    })
    .map((h) => [h.t, h.bpm]);
  const { error: rawErr } = await admin.from("night_raw").upsert({
    night_id: night.id,
    segments: session.segments.map((s) => ({
      start: new Date(s.start).toISOString(),
      end: new Date(s.end).toISOString(),
      stage: s.stage,
      hk_uuid: s.uuid,
    })),
    heart_rate: hrInWindow,
    received_at: new Date().toISOString(),
  });
  if (rawErr) throw rawErr;

  // Karta do feedu (zveřejní se automaticky; jen jednou)
  const { data: post, error: postErr } = await admin
    .from("posts")
    .upsert({ kind: "night", user_id: userId, night_id: night.id }, {
      onConflict: "night_id",
      ignoreDuplicates: true,
    })
    .select("id");
  if (postErr) throw postErr;
  const isNewPost = (post ?? []).length > 0;

  // Skóre do běžících výzev (uzavřené se nemění)
  const { data: parts, error: partErr } = await admin
    .from("challenge_participants")
    .select("challenge_id, challenges!inner(status, start_date, end_date)")
    .eq("user_id", userId)
    .eq("status", "accepted")
    .eq("challenges.status", "active")
    .lte("challenges.start_date", date)
    .gte("challenges.end_date", date);
  if (partErr) throw partErr;
  if (parts?.length) {
    const { error } = await admin.from("challenge_day_scores").upsert(
      parts.map((p: { challenge_id: string }) => ({
        challenge_id: p.challenge_id,
        user_id: userId,
        day: date,
        score,
        night_id: night.id,
      })),
      { onConflict: "challenge_id,user_id,day" },
    );
    if (error) throw error;
  }

  // Achievementy za noc + přepočet série (v DB, jeden dotaz)
  const { data: after, error: afterErr } = await admin.rpc("after_night_ingest", { p_night: night.id });
  if (afterErr) throw afterErr;

  // TODO: push „tvoje noc je tady, doplň komentář“ (až bude APNs)
  return {
    date,
    score,
    status: isNewPost ? "created" : "updated",
    streak: after?.current_streak ?? null,
    new_achievements: after?.new_achievements ?? [],
  };
}
