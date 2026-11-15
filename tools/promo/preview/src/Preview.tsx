import React from "react";
import {
  AbsoluteFill,
  Audio,
  Easing,
  Img,
  interpolate,
  OffthreadVideo,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

// Barvy z docs/design.md. Žádné gradienty, glow ani stíny – vrstvy dělí tón a tenká linka.
const C = {
  bg: "#0B0D12",
  surface: "#14171F",
  text: "#F2F1EC",
  text2: "#9AA0AB",
  accent: "#F5C542",
  hairline: "#262B36",
};
const W = 886;
const H = 1920;
const FPS = 30;
const BAR = 60; // 120 BPM: doba = 15 snímků, takt = 60 (hudba v music.py sedí na stejnou mřížku)
export const TOTAL = 14 * BAR;

// Obrazovka telefonu (záznam simulátoru 1320 × 2868) pod titulky.
const SW = 700;
const SH = Math.round((SW * 2868) / 1320);
const SX = (W - SW) / 2;
const SY = 372;
const FOCUS_TO = { x: W / 2, y: 1150 }; // kam se při přiblížení stáhne ohnisko
const BAND = 352; // horní pás s titulkem

const display: React.CSSProperties = {
  fontFamily: "system-ui, -apple-system",
  fontWeight: 900,
  fontStretch: "condensed",
  letterSpacing: "-0.01em",
  lineHeight: 0.92,
};
const label: React.CSSProperties = {
  fontFamily: "system-ui, -apple-system",
  fontWeight: 600,
  textTransform: "uppercase",
  letterSpacing: "0.16em",
};
const ease = Easing.bezier(0.16, 1, 0.3, 1);

// --- kamera nad záznamem --------------------------------------------------------
type Cam = { f: number; s: number; x: number; y: number }; // snímek ve scéně, zoom, ohnisko (0–1 v obrazovce)

function camAt(cams: Cam[], f: number) {
  if (f <= cams[0].f) return cams[0];
  for (let i = 1; i < cams.length; i++) {
    const a = cams[i - 1];
    const b = cams[i];
    if (f <= b.f) {
      const t = ease((f - a.f) / Math.max(1, b.f - a.f));
      return { f, s: a.s + (b.s - a.s) * t, x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
    }
  }
  return cams[cams.length - 1];
}

type Clip = { src: string; at: number; from: number; len: number; rate?: number };

const Screen: React.FC<{
  clips: Clip[]; // úseky záznamu za sebou (at = snímek ve scéně)
  cams: Cam[];
  dur: number;
  enter?: "slam" | "whip" | "cut";
  exit?: "whip" | "cut";
}> = ({ clips, cams, dur, enter = "whip", exit = "whip" }) => {
  const f = useCurrentFrame();
  const c = camAt(cams, f);
  const pull = Math.min(1, Math.max(0, (c.s - 1) / 0.5));
  const fx = SX + c.x * SW;
  const fy = SY + c.y * SH;
  const tx = fx + (FOCUS_TO.x - fx) * pull;
  const ty = fy + (FOCUS_TO.y - fy) * pull;
  // transform-origin je v ohnisku → ohnisko zůstane na (left + x·SW, top + y·SH)
  let left = tx - c.x * SW;
  const top = ty - c.y * SH;

  // přechody: švih do strany se směrovým rozmazáním (jen po dobu pohybu)
  let dx = 0;
  let blur = 0;
  let extra = 1;
  if (enter === "whip" && f < 7) {
    const t = ease(f / 7);
    dx = (1 - t) * 760;
    blur = (1 - t) * 14;
  }
  if (enter === "slam" && f < 9) {
    extra = interpolate(f, [0, 9], [1.22, 1], { easing: ease });
  }
  if (exit === "whip" && f > dur - 7) {
    const t = Easing.in(Easing.cubic)((f - (dur - 7)) / 7);
    dx = -t * 760;
    blur = t * 14;
  }
  left += dx;

  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      <div
        style={{
          position: "absolute",
          left,
          top,
          width: SW,
          height: SH,
          transformOrigin: `${c.x * 100}% ${c.y * 100}%`,
          transform: `scale(${c.s * extra})`,
          borderRadius: 54 / c.s,
          overflow: "hidden",
          outline: `${2 / c.s}px solid ${C.hairline}`,
          filter: blur > 0.3 ? `blur(${blur}px)` : undefined,
          background: C.bg,
        }}
      >
        {clips.map((cl, i) => (
          <Sequence key={i} from={cl.at} durationInFrames={cl.len} layout="none">
            <OffthreadVideo
              src={staticFile(cl.src)}
              startFrom={Math.round(cl.from * FPS)}
              playbackRate={cl.rate ?? 1}
              muted
              style={{ width: SW, height: SH, display: "block" }}
            />
          </Sequence>
        ))}
      </div>
    </AbsoluteFill>
  );
};

// --- titulky ----------------------------------------------------------------------
type Line = { t: string; accent?: string[] }; // slova ve žluté (jen „tvoje / vyhrál jsi“)

const Word: React.FC<{ w: string; delay: number; color: string; size: number }> = ({ w, delay, color, size }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f - delay, fps, config: { damping: 14, stiffness: 180, mass: 0.6 } });
  return (
    <span
      style={{
        display: "inline-block",
        transform: `translateY(${(1 - p) * 70}px)`,
        opacity: Math.min(1, p * 1.6),
        color,
        marginRight: size * 0.22,
      }}
    >
      {w}
    </span>
  );
};

const Caption: React.FC<{ lines: Line[]; dur: number; size?: number; lineDelay?: number }> = ({
  lines,
  dur,
  size = 112,
  lineDelay = 7,
}) => {
  const f = useCurrentFrame();
  const out = interpolate(f, [dur - 5, dur], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <div
      style={{
        position: "absolute",
        left: 54,
        right: 30,
        bottom: H - BAND + 34,
        ...display,
        fontSize: size,
        opacity: out,
        transform: `translateY(${(1 - out) * -20}px)`,
      }}
    >
      {lines.map((l, li) => (
        <div key={li} style={{ whiteSpace: "nowrap" }}>
          {l.t.split(" ").map((w, wi) => (
            <Word
              key={wi}
              w={w}
              delay={li * lineDelay + wi * 3}
              size={size}
              color={l.accent?.some((a) => w.startsWith(a)) ? C.accent : C.text}
            />
          ))}
        </div>
      ))}
    </div>
  );
};

// Horní pás: plná barva pozadí s tenkou linkou, zoom obrazovky jde pod něj.
const Band: React.FC = () => (
  <div style={{ position: "absolute", left: 0, top: 0, width: W, height: BAND, background: C.bg, borderBottom: `2px solid ${C.hairline}` }} />
);

// Počítadlo taktů vlevo nahoře – sportovní „časomíra“ místo dekorací.
const Ticker: React.FC<{ idx: number; of: number; name: string }> = ({ idx, of, name }) => {
  const f = useCurrentFrame();
  const p = interpolate(f, [0, 8], [0, 1], { extrapolateRight: "clamp", easing: ease });
  return (
    <div style={{ position: "absolute", left: 56, top: 64, ...label, fontSize: 24, color: C.text2, opacity: p }}>
      <span style={{ color: C.accent }}>{String(idx).padStart(2, "0")}</span>
      <span> / {String(of).padStart(2, "0")} · {name}</span>
    </div>
  );
};

const Flash: React.FC<{ at: number; strength?: number }> = ({ at, strength = 0.35 }) => {
  const f = useCurrentFrame();
  const o = interpolate(f, [at, at + 1, at + 6], [0, strength, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return <AbsoluteFill style={{ background: C.text, opacity: o, pointerEvents: "none" }} />;
};

// --- intro a outro ---------------------------------------------------------------
const Moon: React.FC<{ size: number; delay?: number }> = ({ size, delay = 0 }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f - delay, fps, config: { damping: 16, stiffness: 120 } });
  return (
    <Img
      src={staticFile("logo.png")}
      style={{ width: size, height: size, transform: `scale(${0.6 + 0.4 * p}) rotate(${(1 - p) * -25}deg)`, opacity: p }}
    />
  );
};

const Intro: React.FC = () => {
  const f = useCurrentFrame();
  const zoom = interpolate(f, [44, 60], [1, 1.12], { extrapolateLeft: "clamp", easing: Easing.in(Easing.cubic) });
  const fade = interpolate(f, [52, 60], [1, 0], { extrapolateLeft: "clamp" });
  return (
    <AbsoluteFill style={{ background: C.bg, alignItems: "center", justifyContent: "center", transform: `scale(${zoom})`, opacity: fade }}>
      <div style={{ position: "absolute", top: 560 }}>
        <Moon size={220} />
      </div>
      <div style={{ position: "absolute", top: 880, left: 0, right: 0, textAlign: "center", ...display, fontSize: 150 }}>
        <div>
          <Word w="Spíš" delay={10} color={C.text} size={150} />
          <Word w="líp" delay={14} color={C.text} size={150} />
        </div>
        <div>
          <Word w="než" delay={30} color={C.text} size={150} />
          <Word w="kámoši?" delay={34} color={C.text} size={150} />
        </div>
      </div>
    </AbsoluteFill>
  );
};

const Outro: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const letters = "BEDRIVAL".split("");
  const sub = interpolate(f, [26, 36], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });
  const tag = interpolate(f, [44, 54], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });
  return (
    <AbsoluteFill style={{ background: C.bg, alignItems: "center" }}>
      <div style={{ position: "absolute", top: 500 }}>
        <Moon size={200} delay={2} />
      </div>
      <div style={{ position: "absolute", top: 780, ...display, fontSize: 196, display: "flex" }}>
        {letters.map((l, i) => {
          const p = spring({ frame: f - 6 - i * 2, fps, config: { damping: 12, stiffness: 220, mass: 0.5 } });
          return (
            <span key={i} style={{ display: "inline-block", transform: `translateY(${(1 - p) * 90}px) scale(${0.8 + 0.2 * p})`, opacity: Math.min(1, p * 2), color: C.text }}>
              {l}
            </span>
          );
        })}
      </div>
      <div style={{ position: "absolute", top: 1010, fontFamily: "system-ui", fontWeight: 600, fontSize: 52, color: C.text2, opacity: sub, transform: `translateY(${(1 - sub) * 20}px)` }}>
        Spánek jako sport.
      </div>
      <div style={{ position: "absolute", top: 1420, ...label, fontSize: 34, color: C.accent, opacity: tag, transform: `translateY(${(1 - tag) * 20}px)` }}>
        Jen na pozvánku
      </div>
    </AbsoluteFill>
  );
};

// --- scény -----------------------------------------------------------------------
const Scene: React.FC<{
  from: number;
  dur: number;
  children: React.ReactNode;
}> = ({ from, dur, children }) => (
  <Sequence from={from} durationInFrames={dur}>
    {children}
  </Sequence>
);

const Cap: React.FC<{ from: number; dur: number; lines: Line[]; size?: number; idx: number; name: string }> = ({ from, dur, lines, size, idx, name }) => (
  <Sequence from={from} durationInFrames={dur}>
    <Band />
    <Ticker idx={idx} of={6} name={name} />
    <Caption lines={lines} dur={dur} size={size} />
  </Sequence>
);

export const Preview: React.FC = () => {
  const b = (n: number) => n * BAR;
  return (
    <AbsoluteFill style={{ background: C.bg }}>
      <Audio src={staticFile("music.wav")} />

      {/* 0: otázka */}
      <Scene from={0} dur={b(1)}>
        <Intro />
      </Scene>

      {/* 1–2: ranní karta – skóre naskočí, pak feed kamarádů */}
      <Scene from={b(1)} dur={b(2)}>
        <Screen
          dur={b(2)}
          enter="slam"
          clips={[
            { src: "testFeed.mp4", at: 0, from: 22.55, len: b(1) },
            { src: "testFeed.mp4", at: b(1), from: 27.4, len: b(1) },
          ]}
          cams={[
            { f: 0, s: 1, x: 0.5, y: 0.3 },
            { f: 12, s: 1.6, x: 0.4, y: 0.3 },
            { f: 50, s: 1.65, x: 0.4, y: 0.3 },
            { f: 60, s: 1, x: 0.5, y: 0.4 },
            { f: 120, s: 1.06, x: 0.5, y: 0.5 },
          ]}
        />
      </Scene>
      <Cap from={b(1)} dur={b(1)} idx={1} name="Ráno" lines={[{ t: "Každé ráno" }, { t: "tvoje noc.", accent: ["tvoje"] }]} />
      <Cap from={b(2)} dur={b(1)} idx={1} name="Feed" lines={[{ t: "Kámoši" }, { t: "ji uvidí." }]} />

      {/* 3: reakce */}
      <Scene from={b(3)} dur={b(1)}>
        <Screen
          dur={b(1)}
          clips={[{ src: "testReact.mp4", at: 0, from: 19.3, len: b(1), rate: 1.05 }]}
          cams={[
            { f: 0, s: 1.05, x: 0.5, y: 0.35 },
            { f: 30, s: 1.08, x: 0.5, y: 0.6 },
            { f: 44, s: 1.85, x: 0.75, y: 0.82 },
            { f: 60, s: 1.9, x: 0.78, y: 0.82 },
          ]}
        />
      </Scene>
      <Cap from={b(3)} dur={b(1)} idx={2} name="Reakce" lines={[{ t: "Reaguj." }, { t: "Rýpni si." }]} />

      {/* 4–6: souboj */}
      <Scene from={b(4)} dur={b(3)}>
        <Screen
          dur={b(3)}
          clips={[{ src: "testDuel.mp4", at: 0, from: 12.35, len: b(3) }]}
          cams={[
            { f: 0, s: 1, x: 0.5, y: 0.4 },
            { f: 22, s: 1.3, x: 0.5, y: 0.5 },
            { f: 54, s: 1.33, x: 0.5, y: 0.5 },
            { f: 64, s: 1.0, x: 0.5, y: 0.4 },
            { f: 76, s: 1.32, x: 0.5, y: 0.25 },
            { f: 118, s: 1.36, x: 0.5, y: 0.25 },
            { f: 132, s: 1.38, x: 0.45, y: 0.5 },
            { f: 180, s: 1.42, x: 0.45, y: 0.5 },
          ]}
        />
      </Scene>
      <Cap from={b(4)} dur={b(1)} idx={3} name="Výzvy" lines={[{ t: "Vyzvi je" }, { t: "na souboj." }]} />
      <Cap from={b(5)} dur={b(1)} idx={3} name="Souboj" lines={[{ t: "Rozhoduje" }, { t: "jen skóre." }]} />
      <Cap from={b(6)} dur={b(1)} idx={3} name="Sázka" lines={[{ t: "Sázku si" }, { t: "napíšete sami." }]} />

      {/* 7: výsledek – náraz v hudbě */}
      <Scene from={b(7)} dur={b(1)}>
        <Screen
          dur={b(1)}
          enter="slam"
          clips={[{ src: "result.mp4", at: 0, from: 3.2, len: b(1) }]}
          cams={[
            { f: 0, s: 1, x: 0.4, y: 0.4 },
            { f: 10, s: 1.6, x: 0.3, y: 0.37 },
            { f: 60, s: 1.68, x: 0.3, y: 0.38 },
          ]}
        />
      </Scene>
      <Cap from={b(7)} dur={b(1)} idx={4} name="Konec výzvy" lines={[{ t: "Vyhraješ?" }, { t: "Bereš ovečku.", accent: ["ovečku"] }]} />

      {/* 8–9: profil */}
      <Scene from={b(8)} dur={b(2)}>
        <Screen
          dur={b(2)}
          clips={[
            { src: "testProfile.mp4", at: 0, from: 7.75, len: b(1) },
            { src: "testProfile.mp4", at: b(1), from: 13.3, len: b(1) },
          ]}
          cams={[
            { f: 0, s: 1, x: 0.5, y: 0.3 },
            { f: 12, s: 1.95, x: 0.28, y: 0.25 },
            { f: 52, s: 2.0, x: 0.3, y: 0.25 },
            { f: 62, s: 1.15, x: 0.5, y: 0.62 },
            { f: 120, s: 1.25, x: 0.5, y: 0.72 },
          ]}
        />
      </Scene>
      <Cap from={b(8)} dur={b(1)} idx={5} name="Profil" lines={[{ t: "Bilance" }, { t: "jako v MMA." }]} />
      <Cap from={b(9)} dur={b(1)} idx={5} name="Stádo" lines={[{ t: "Ovečky" }, { t: "a odznaky." }]} />

      {/* 10: týden a rok – rychlé střihy na doby */}
      {[
        { src: "testRecapWrapped.mp4", from: 11.5, x: 0.28, y: 0.25 },
        { src: "testRecapWrapped.mp4", from: 24.0, x: 0.22, y: 0.38 },
        { src: "testRecapWrapped.mp4", from: 36.9, x: 0.3, y: 0.38 },
        { src: "testRecapWrapped.mp4", from: 41.3, x: 0.22, y: 0.38 },
      ].map((c, i) => (
        <Scene key={i} from={b(10) + i * 15} dur={15}>
          <Screen
            dur={15}
            enter={i === 0 ? "whip" : "cut"}
            exit="cut"
            clips={[{ src: c.src, at: 0, from: c.from, len: 15 }]}
            cams={[
              { f: 0, s: 1.75, x: c.x, y: c.y },
              { f: 15, s: 1.62, x: c.x, y: c.y },
            ]}
          />
        </Scene>
      ))}
      <Cap from={b(10)} dur={b(1)} idx={6} name="Recap" lines={[{ t: "Týden." }, { t: "Celý rok." }]} />

      {/* 11: zjištění z tagů */}
      <Scene from={b(11)} dur={b(1)}>
        <Screen
          dur={b(1)}
          enter="cut"
          clips={[{ src: "testProfile.mp4", at: 0, from: 10.0, len: b(1) }]}
          cams={[
            { f: 0, s: 1.12, x: 0.5, y: 0.46 },
            { f: 60, s: 1.2, x: 0.5, y: 0.46 },
          ]}
        />
      </Scene>
      <Cap from={b(11)} dur={b(1)} idx={6} name="Zjištění" size={100} lines={[{ t: "Zjistíš, co ti" }, { t: "kazí spánek." }]} />

      {/* 12–13: logo */}
      <Scene from={b(12)} dur={b(2)}>
        <Outro />
      </Scene>
    </AbsoluteFill>
  );
};
