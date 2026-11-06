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

export const SCORE_VERSION = 1;
export const DAY_CUTOFF_MIN = 14 * 60; // spánek patří ke dni, kdy skončil, pokud skončil do 14:00
export const STREAK_MIN_SLEEP_MIN = 6 * 60; // minimální délka pro sérii
export const REGULARITY_HISTORY_NIGHTS = 14;
export const HR_HISTORY_NIGHTS = 30;
const MIN_HISTORY = 3; // méně nocí v historii = plné body za pravidelnost/tep
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

/** Délka: 7–9 h = 100; pod 7 h klesá na 0 ve 4 h; nad 9 h klesá na 50 ve 11,5 h. */
export function durationScore(totalMin: number): number {
  const h = totalMin / 60;
  if (h < 7) return clamp(100 - (7 - h) * (100 / 3));
  if (h > 9) return Math.max(50, 100 - (h - 9) * 20);
  return 100;
}

/** Fáze: podíl deep + REM na spánku s fázemi; 40 % a víc = 100. Bez fází = null. */
export function stagesScore(m: NightMetrics): number | null {
  const staged = m.coreMin + m.deepMin + m.remMin;
  if (staged < m.totalSleepMin * 0.5 || staged === 0) return null;
  return clamp(((m.deepMin + m.remMin) / staged / 0.4) * 100);
}

/** Přerušovanost: −5 za každé probuzení, −1 za každou minutu vzhůru. */
export function interruptionsScore(m: NightMetrics): number {
  return clamp(100 - m.wakeCount * 5 - m.awakeMin);
}

/** Pravidelnost: odchylka usnutí od průměru; do 15 min = 100, 120 min a víc = 0. */
export function regularityScore(startFromNoon: number, history: number[]): number {
  if (history.length < MIN_HISTORY) return 100;
  const d = Math.abs(startFromNoon - mean(history));
  if (d <= 15) return 100;
  return clamp(100 - ((d - 15) / 105) * 100);
}

/** Tep: průměr ve spánku vs. osobní normál; normál a níž = 100, +10 tepů = 0. */
export function heartRateScore(hrAvg: number | null, history: number[]): number | null {
  if (hrAvg === null) return null;
  if (history.length < MIN_HISTORY) return 100;
  const diff = hrAvg - mean(history);
  return clamp(100 - diff * 10);
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
  return { score: Math.round(sum / weight), breakdown };
}
