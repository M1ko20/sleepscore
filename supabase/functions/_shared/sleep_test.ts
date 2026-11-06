import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  assignMainSleep,
  buildSessions,
  computeMetrics,
  computeScore,
  durationScore,
  minutesFromNoon,
  regularityScore,
  type SleepSample,
  type Stage,
} from "./sleep.ts";

const TZ = "Europe/Prague";
let n = 0;
const s = (start: string, end: string, stage: Stage, source = "Garmin Connect", userEntered = false): SleepSample => ({
  uuid: `u${n++}`,
  start,
  end,
  stage,
  source,
  userEntered,
});

// Typická noc 23:00–07:00 (Praha, UTC+1 v listopadu)
const night = (): SleepSample[] => [
  s("2026-11-05T22:00:00Z", "2026-11-05T23:30:00Z", "core"),
  s("2026-11-05T23:30:00Z", "2026-11-06T00:30:00Z", "deep"),
  s("2026-11-06T00:30:00Z", "2026-11-06T00:40:00Z", "awake"),
  s("2026-11-06T00:40:00Z", "2026-11-06T02:40:00Z", "core"),
  s("2026-11-06T02:40:00Z", "2026-11-06T04:10:00Z", "rem"),
  s("2026-11-06T04:10:00Z", "2026-11-06T06:00:00Z", "core"),
];

Deno.test("hlavní spánek patří ke dni, kdy skončil", () => {
  const days = assignMainSleep(buildSessions(night()), TZ);
  assertEquals([...days.keys()], ["2026-11-06"]);
  const sess = days.get("2026-11-06")!;
  assertEquals(sess.asleepMin, 470); // 8 h − 10 min vzhůru
});

Deno.test("šlofík se nepočítá, vyhrává nejdelší spánek", () => {
  const samples = [...night(), s("2026-11-06T11:00:00Z", "2026-11-06T11:40:00Z", "core")]; // 12:00–12:40
  const days = assignMainSleep(buildSessions(samples), TZ);
  assertEquals(days.get("2026-11-06")!.asleepMin, 470);
});

Deno.test("spánek končící po 14:00 se nepočítá", () => {
  const samples = [s("2026-11-06T06:00:00Z", "2026-11-06T13:30:00Z", "core")]; // 7:00–14:30
  assertEquals(assignMainSleep(buildSessions(samples), TZ).size, 0);
});

Deno.test("ruční záznamy se zahazují", () => {
  const samples = night().map((x) => ({ ...x, userEntered: true }));
  assertEquals(buildSessions(samples).length, 0);
});

Deno.test("dva zdroje: bere se ten s delším spánkem, nesčítají se", () => {
  const watch = [s("2026-11-05T22:30:00Z", "2026-11-06T04:00:00Z", "core", "Apple Watch")];
  const day = assignMainSleep(buildSessions([...night(), ...watch]), TZ).get("2026-11-06")!;
  assertEquals(day.source, "Garmin Connect");
  assertEquals(day.asleepMin, 470);
});

Deno.test("úvodní a koncové awake se ořízne", () => {
  const samples = [
    s("2026-11-05T21:30:00Z", "2026-11-05T22:00:00Z", "awake"),
    ...night(),
    s("2026-11-06T06:00:00Z", "2026-11-06T06:20:00Z", "awake"),
  ];
  const sess = assignMainSleep(buildSessions(samples), TZ).get("2026-11-06")!;
  assertEquals(new Date(sess.sleepStart).toISOString(), "2026-11-05T22:00:00.000Z");
  assertEquals(new Date(sess.sleepEnd).toISOString(), "2026-11-06T06:00:00.000Z");
});

Deno.test("metriky: fáze, probuzení, tep", () => {
  const sess = assignMainSleep(buildSessions(night()), TZ).get("2026-11-06")!;
  const m = computeMetrics(sess, [
    { t: "2026-11-05T21:00:00Z", bpm: 90 }, // před spánkem – ignorovat
    { t: "2026-11-06T01:00:00Z", bpm: 50 },
    { t: "2026-11-06T03:00:00Z", bpm: 56 },
  ]);
  assertEquals([m.coreMin, m.deepMin, m.remMin, m.awakeMin], [320, 60, 90, 10]);
  assertEquals(m.wakeCount, 1);
  assertEquals(m.hrAvg, 53);
  assertEquals(m.hrMin, 50);
});

Deno.test("délka: 7–9 h plný počet, 4 h nula, dlouhý spánek max −50", () => {
  assertEquals(durationScore(8 * 60), 100);
  assertEquals(durationScore(4 * 60), 0);
  assertEquals(Math.round(durationScore(5.5 * 60)), 50);
  assertEquals(durationScore(14 * 60), 50);
});

Deno.test("pravidelnost: bez historie plné body, 2 h vedle nula", () => {
  assertEquals(regularityScore(660, []), 100);
  assertEquals(regularityScore(660, [660, 660, 660]), 100);
  assertEquals(regularityScore(780, [660, 660, 660]), 0);
});

Deno.test("minuty od poledne nepřeskočí přes půlnoc", () => {
  assertEquals(minutesFromNoon(Date.parse("2026-11-05T22:00:00Z"), TZ), 660); // 23:00
  assertEquals(minutesFromNoon(Date.parse("2026-11-06T00:00:00Z"), TZ), 780); // 01:00
});

Deno.test("skóre dobré noci je vysoké, bez fází se váhy přepočítají", () => {
  const sess = assignMainSleep(buildSessions(night()), TZ).get("2026-11-06")!;
  const m = computeMetrics(sess, []);
  const { score, breakdown } = computeScore(m, { startMinutesFromNoon: [], hrAvgs: [] }, TZ);
  assertEquals(breakdown.heart_rate, null);
  assert(score >= 85 && score <= 100, `score ${score}`);

  const unstaged = { ...m, coreMin: 0, deepMin: 0, remMin: 0 };
  const r = computeScore(unstaged, { startMinutesFromNoon: [], hrAvgs: [] }, TZ);
  assertEquals(r.breakdown.stages, null);
  assert(r.score > 0 && r.score <= 100);
});

Deno.test("krátká rozbitá noc má nízké skóre", () => {
  const samples: SleepSample[] = [];
  // 4,5 h spánku s 8 probuzeními po 5 min
  let t = Date.parse("2026-11-06T01:00:00Z");
  for (let i = 0; i < 8; i++) {
    samples.push(s(new Date(t).toISOString(), new Date(t + 30 * 60000).toISOString(), "core"));
    samples.push(s(new Date(t + 30 * 60000).toISOString(), new Date(t + 35 * 60000).toISOString(), "awake"));
    t += 35 * 60000;
  }
  samples.push(s(new Date(t).toISOString(), new Date(t + 30 * 60000).toISOString(), "core"));
  const sess = assignMainSleep(buildSessions(samples), TZ).values().next().value!;
  const { score } = computeScore(computeMetrics(sess, []), { startMinutesFromNoon: [660, 660, 660], hrAvgs: [] }, TZ);
  assert(score < 40, `score ${score}`);
});
