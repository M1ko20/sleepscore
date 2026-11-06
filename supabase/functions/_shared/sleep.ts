// Čistá logika spánku: výběr hlavního spánku, metriky a sleep score.
// Bez závislostí na Supabase, aby šla testovat (`deno test`).

export type Stage = "awake" | "core" | "deep" | "rem" | "asleep";

/** Vzorek spánku z HealthKitu (HKCategoryValueSleepAnalysis). */
export interface SleepSample {
  uuid: string;
  start: string; // ISO 8601
  end: string;
  stage: Stage; // "asleep" = asleepUnspecified (starší zařízení bez fází)
  source: string; // název zdroje, např. "Garmin Connect"
  userEntered?: boolean; // HKMetadataKeyWasUserEntered
}

export interface HrSample {
  t: string; // ISO 8601
  bpm: number;
}

export interface Segment {
  start: number; // ms
  end: number;
  stage: Stage;
  uuid: string;
}

export interface Session {
  source: string;
  segments: Segment[]; // oříznuté na [sleepStart, sleepEnd]
  sleepStart: number;
  sleepEnd: number;
  asleepMin: number;
}

export interface NightMetrics {
  sleepStart: number;
  sleepEnd: number;
  totalSleepMin: number;
  awakeMin: number;
  coreMin: number;
  deepMin: number;
  remMin: number;
  wakeCount: number;
  hrAvg: number | null;
  hrMin: number | null;
}

export interface Baseline {
  /** Usnutí posledních nocí jako minuty od poledne (místní čas). */
  startMinutesFromNoon: number[];
  /** Průměrný tep posledních nocí. */
  hrAvgs: number[];
}

export type ComponentKey = "duration" | "stages" | "interruptions" | "regularity" | "heart_rate";
export type Breakdown = Record<ComponentKey, number | null>;

export const SCORE_VERSION = 2;
export const DAY_CUTOFF_MIN = 14 * 60; // spánek patří ke dni, kdy skončil, pokud skončil do 14:00
export const STREAK_MIN_SLEEP_MIN = 6 * 60; // minimální délka pro sérii
export const REGULARITY_HISTORY_NIGHTS = 14;
export const HR_HISTORY_NIGHTS = 30;
const MIN_HISTORY = 3; // méně nocí v historii = neutrální body za pravidelnost/tep
const NEUTRAL = 85; // „normál“ – plných 100 jen za nadprůměr
const SESSION_GAP_MS = 60 * 60 * 1000; // mezera > 60 min = nová session
const WAKE_MIN_LEN_MS = 60 * 1000; // probuzení kratší než minuta se nepočítá

export const WEIGHTS: Record<ComponentKey, number> = {
  duration: 0.35,
  stages: 0.25,
  interruptions: 0.15,
  regularity: 0.15,
  heart_rate: 0.10,
};

const ASLEEP = new Set<Stage>(["core", "deep", "rem", "asleep"]);
const STAGES = new Set<Stage>(["awake", "core", "deep", "rem", "asleep"]);

// ---------------------------------------------------------------------
// Čas
// ---------------------------------------------------------------------

export function localParts(ms: number, tz: string) {
  const f = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  const p = Object.fromEntries(f.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, minutes: Number(p.hour) * 60 + Number(p.minute) };
}

export function isValidTimeZone(tz: unknown): tz is string {
  if (typeof tz !== "string" || tz.length === 0) return false;
  try {
    new Intl.DateTimeFormat("en", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/** Minuty od poledne (12:00 = 0, 23:00 = 660, 01:00 = 780) – bez skoku přes půlnoc. */
export function minutesFromNoon(ms: number, tz: string): number {
  return (localParts(ms, tz).minutes - 720 + 1440) % 1440;
}

// ---------------------------------------------------------------------
// Sessions a hlavní spánek
// ---------------------------------------------------------------------

/** Rozdělí vzorky na souvislé spánky, zvlášť pro každý zdroj. Ruční záznamy zahazuje. */
export function buildSessions(samples: SleepSample[]): Session[] {
  const bySource = new Map<string, Segment[]>();
  for (const s of samples) {
    if (s.userEntered || !STAGES.has(s.stage)) continue;
    const start = Date.parse(s.start);
    const end = Date.parse(s.end);
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) continue;
    const list = bySource.get(s.source) ?? [];
    list.push({ start, end, stage: s.stage, uuid: s.uuid });
    bySource.set(s.source, list);
  }

  const sessions: Session[] = [];
  for (const [source, segs] of bySource) {
    segs.sort((a, b) => a.start - b.start || a.end - b.end);
    let current: Segment[] = [];
    let currentEnd = -Infinity;
    const flush = () => {
      const s = finishSession(source, current);
      if (s) sessions.push(s);
      current = [];
    };
    for (const seg of segs) {
      if (seg.start - currentEnd > SESSION_GAP_MS) {
        flush();
        currentEnd = -Infinity;
      }
      // překryv v rámci jednoho zdroje: oříznout
      const start = Math.max(seg.start, currentEnd);
      if (seg.end <= start) continue;
      current.push({ ...seg, start });
      currentEnd = Math.max(currentEnd, seg.end);
    }
    flush();
  }
  return sessions;
}

function finishSession(source: string, segs: Segment[]): Session | null {
  const asleep = segs.filter((s) => ASLEEP.has(s.stage));
  if (asleep.length === 0) return null;
  const sleepStart = asleep[0].start;
  const sleepEnd = Math.max(...asleep.map((s) => s.end));
  const segments = segs
    .map((s) => ({ ...s, start: Math.max(s.start, sleepStart), end: Math.min(s.end, sleepEnd) }))
    .filter((s) => s.end > s.start);
  const asleepMin = Math.round(
    segments.filter((s) => ASLEEP.has(s.stage)).reduce((a, s) => a + (s.end - s.start), 0) / 60000,
  );
  return { source, segments, sleepStart, sleepEnd, asleepMin };
}

/**
 * Pro každý den vybere hlavní spánek: nejdelší session (napříč zdroji),
 * která skončila v daný den do 14:00 místního času. Šlofíky a spánky
 * končící po 14:00 vypadnou.
 */
export function assignMainSleep(sessions: Session[], tz: string): Map<string, Session> {
  const byDay = new Map<string, Session>();
  for (const s of sessions) {
    const end = localParts(s.sleepEnd, tz);
    if (end.minutes > DAY_CUTOFF_MIN) continue;
    const prev = byDay.get(end.date);
    if (!prev || s.asleepMin > prev.asleepMin) byDay.set(end.date, s);
  }
  return byDay;
}

// ---------------------------------------------------------------------
// Metriky a skóre
// ---------------------------------------------------------------------

export function computeMetrics(session: Session, hr: HrSample[]): NightMetrics {
  const mins = (stage: Stage) =>
    Math.round(
      session.segments.filter((s) => s.stage === stage).reduce((a, s) => a + (s.end - s.start), 0) / 60000,
    );
  const wakes = session.segments.filter((s) => s.stage === "awake" && s.end - s.start >= WAKE_MIN_LEN_MS);

  const bpms = hr
    .filter((h) => {
      const t = Date.parse(h.t);
      return t >= session.sleepStart && t <= session.sleepEnd && h.bpm > 20 && h.bpm < 250;
    })
    .map((h) => h.bpm);

  return {
    sleepStart: session.sleepStart,
    sleepEnd: session.sleepEnd,
    totalSleepMin: session.asleepMin,
    awakeMin: mins("awake"),
    coreMin: mins("core"),
    deepMin: mins("deep"),
    remMin: mins("rem"),
    wakeCount: wakes.length,
    hrAvg: bpms.length ? Math.round((bpms.reduce((a, b) => a + b, 0) / bpms.length) * 10) / 10 : null,
    hrMin: bpms.length ? Math.min(...bpms) : null,
  };
}

const clamp = (x: number) => Math.max(0, Math.min(100, x));
const mean = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;

/** Lineární interpolace mezi body [x, y] (seřazené podle x), mimo rozsah krajní hodnota. */
function piecewise(x: number, pts: [number, number][]): number {
  if (x <= pts[0][0]) return pts[0][1];
  for (let i = 1; i < pts.length; i++) {
    const [x1, y1] = pts[i];
    if (x <= x1) {
      const [x0, y0] = pts[i - 1];
      return y0 + ((x - x0) / (x1 - x0)) * (y1 - y0);
    }
  }
  return pts[pts.length - 1][1];
}

/**
 * Délka (v2): 100 jen za 8–9 h. 7 h = 80, 6 h = 55, 5 h = 30, 4 h = 0.
 * Dlouhý spánek mírně klesá (10 h = 85, 11 h = 65, 12 h+ = 50).
 */
export function durationScore(totalMin: number): number {
  return piecewise(totalMin / 60, [[4, 0], [5, 30], [6, 55], [7, 80], [8, 100], [9, 100], [10, 85], [11, 65], [12, 50]]);
}

/**
 * Fáze (v2): deep a REM zvlášť, každý polovinou. Podíl na spánku s fázemi:
 * deep 4 % = 0 → 16 % = 100, REM 8 % = 0 → 22 % = 100 (běžný dospělý: deep 13–23 %, REM 20–25 %).
 * Bez fází = null.
 */
export function stagesScore(m: NightMetrics): number | null {
  const staged = m.coreMin + m.deepMin + m.remMin;
  if (staged < m.totalSleepMin * 0.5 || staged === 0) return null;
  const deep = clamp(((m.deepMin / staged - 0.04) / 0.12) * 100);
  const rem = clamp(((m.remMin / staged - 0.08) / 0.14) * 100);
  return (deep + rem) / 2;
}

/** Přerušovanost (v2): −7 za každé probuzení, −1,2 za každou minutu vzhůru. */
export function interruptionsScore(m: NightMetrics): number {
  return clamp(100 - m.wakeCount * 7 - m.awakeMin * 1.2);
}

/** Pravidelnost (v2): odchylka usnutí od průměru; do 10 min = 100, 90 min a víc = 0. Bez historie neutrálně. */
export function regularityScore(startFromNoon: number, history: number[]): number {
  if (history.length < MIN_HISTORY) return NEUTRAL;
  const d = Math.abs(startFromNoon - mean(history));
  if (d <= 10) return 100;
  return clamp(100 - ((d - 10) / 80) * 100);
}

/** Tep (v2): průměr ve spánku vs. osobní normál; normál = 85, −2 tepy = 100, +10 tepů = 5. Bez historie neutrálně. */
export function heartRateScore(hrAvg: number | null, history: number[]): number | null {
  if (hrAvg === null) return null;
  if (history.length < MIN_HISTORY) return NEUTRAL;
  const diff = hrAvg - mean(history);
  return clamp(NEUTRAL - diff * 8);
}

/** Vážené skóre 0–100. Chybějící složky (null) se vynechají a váhy se přepočítají. */
export function computeScore(
  m: NightMetrics,
  baseline: Baseline,
  tz: string,
): { score: number; breakdown: Breakdown } {
  const breakdown: Breakdown = {
    duration: durationScore(m.totalSleepMin),
    stages: stagesScore(m),
    interruptions: interruptionsScore(m),
    regularity: regularityScore(minutesFromNoon(m.sleepStart, tz), baseline.startMinutesFromNoon),
    heart_rate: heartRateScore(m.hrAvg, baseline.hrAvgs),
  };
  let sum = 0;
  let weight = 0;
  for (const k of Object.keys(WEIGHTS) as ComponentKey[]) {
    const v = breakdown[k];
    if (v === null) continue;
    sum += v * WEIGHTS[k];
    weight += WEIGHTS[k];
  }
  for (const k of Object.keys(breakdown) as ComponentKey[]) {
    const v = breakdown[k];
    if (v !== null) breakdown[k] = Math.round(v);
  }
  const cap = durationCap(m.totalSleepMin);
  return { score: Math.min(cap, Math.round(sum / weight)), breakdown };
}

/** Strop podle délky: krátká noc nemůže mít vysoké skóre, i když je klidná. */
export function durationCap(totalMin: number): number {
  if (totalMin < 5 * 60) return 45;
  if (totalMin < 6 * 60) return 65;
  return 100;
}
