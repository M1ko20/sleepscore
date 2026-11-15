#!/usr/bin/env python3
"""Hudba k app preview: 120 BPM, A moll, 28 s. Jen numpy, výstup public/music.wav (48 kHz stereo).

Takty po 2 s (= 60 snímků při 30 fps), střih v src/Preview.tsx sedí na stejnou mřížku:
  0     klid (zvonky, pad), na konci riser
  1–5   drop: kick, clap, hi-hat, basa se sidechainem, stab akordy, zvonková melodie
  6     build (snare roll, filtr) → 7 náraz (VÝHRA)
  7–11  groove naplno
  12–13 závěrečný akord a dozvuk se zvonky (logo)
"""
import sys
import wave

import numpy as np

SR = 48000
BPM = 120
BEAT = 60 / BPM
BAR = 4 * BEAT
LEN = 28.0
N = int(SR * LEN)
rng = np.random.default_rng(7)


def t_of(n):
    return np.arange(n) / SR


def add(buf, sig, at):
    i = int(at * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i]


def fft_filter(x, lo=None, hi=None, slope=4.0):
    """Statický filtr přes FFT (měkké hrany)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if hi:
        g *= 1 / (1 + (f / hi) ** slope)
    if lo:
        g *= 1 / (1 + (lo / np.maximum(f, 1)) ** slope)
    return np.fft.irfft(X * g, len(x))


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def saw(freq, dur, max_h=40, detune=0.0, phase=0.0):
    t = t_of(int(dur * SR))
    out = np.zeros_like(t)
    f = freq * (1 + detune)
    for h in range(1, max_h + 1):
        if f * h > 9000:
            break
        out += np.sin(2 * np.pi * f * h * t + phase * h) / h
    return out


def env_adsr(n, a=0.005, d=0.1, s=0.6, r=0.1):
    e = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = max(1, min(na, n)); e[:na] = np.linspace(0, 1, na)
    nd = max(1, min(nd, n - na)); e[na:na + nd] = np.linspace(1, s, nd)
    if nr < n:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


# --- nástroje -----------------------------------------------------------------
def kick(vel=1.0):
    n = int(0.45 * SR); t = t_of(n)
    f = 45 + 110 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * 7.5)
    click = fft_filter(rng.standard_normal(n), lo=2000) * np.exp(-t * 400) * 0.25
    return np.tanh((body + click) * 1.6) * vel


def clap(vel=1.0):
    n = int(0.35 * SR); t = t_of(n)
    noise = fft_filter(rng.standard_normal(n), lo=900, hi=5000)
    e = np.exp(-t * 18)
    for off in (0.0, 0.011, 0.022):
        i = int(off * SR)
        e[i:i + int(0.006 * SR)] += 0.8
    return noise * e * 0.5 * vel


def hat(open_=False, vel=1.0):
    n = int((0.25 if open_ else 0.06) * SR); t = t_of(n)
    noise = fft_filter(rng.standard_normal(n), lo=7000)
    return noise * np.exp(-t * (14 if open_ else 70)) * 0.32 * vel


def bell(m, dur=0.9, vel=1.0):
    n = int(dur * SR); t = t_of(n)
    f = midi(m)
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 2.2 * np.exp(-t * 6)
    sig = np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 4.2)
    sig += 0.35 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 7)
    return sig * vel * 0.32


def bass(m, dur):
    s = saw(midi(m), dur, max_h=14) * 0.55 + np.sin(2 * np.pi * midi(m) * t_of(int(dur * SR))) * 0.7
    return s * env_adsr(len(s), 0.004, 0.12, 0.75, 0.04) * 0.55


def supersaw(notes, dur, vel=1.0, max_h=30):
    n = int(dur * SR)
    out = np.zeros(n)
    for m in notes:
        for d in (-0.012, -0.005, 0.0, 0.006, 0.013):
            out += saw(midi(m), dur, max_h=max_h, detune=d, phase=rng.uniform(0, 6.28))[:n]
    return out / (len(notes) * 4) * vel


def riser(dur):
    n = int(dur * SR); t = t_of(n)
    noise = rng.standard_normal(n)
    parts = np.array_split(np.arange(n), 16)
    out = np.zeros(n)
    for k, idx in enumerate(parts):   # filtr se otevírá po kouscích
        seg = fft_filter(noise[idx], lo=400 + k * 350, hi=1500 + k * 900)
        out[idx] = seg
    sweep = np.sin(2 * np.pi * np.cumsum(200 + 1400 * (t / dur) ** 2) / SR) * 0.15
    return (out * 0.35 + sweep) * (t / dur) ** 2


def impact():
    n = int(2.6 * SR); t = t_of(n)
    f = 30 + 60 * np.exp(-t * 6)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 2.2)
    crash = fft_filter(rng.standard_normal(n), lo=3500) * np.exp(-t * 2.4) * 0.35
    return np.tanh(boom * 1.4) * 0.9 + crash


def whoosh(dur=0.35):
    n = int(dur * SR); t = t_of(n)
    e = np.sin(np.pi * t / dur) ** 2
    return fft_filter(rng.standard_normal(n), lo=600, hi=6000) * e * 0.18


# --- aranž --------------------------------------------------------------------
CHORDS = [  # Am, F, C, G (kořen basy, tóny akordu)
    (45, [57, 60, 64]),
    (41, [57, 60, 65]),
    (48, [55, 60, 64]),
    (43, [55, 59, 62]),
]
# melodie: (doba v taktu, midi, délka v dobách)
HOOK = [
    [(0, 76, 1), (1.5, 74, .5), (2, 72, 1), (3, 69, 1)],
    [(0, 72, 1), (1.5, 69, .5), (2, 72, .5), (2.5, 74, 1.5)],
    [(0, 76, 1), (1.5, 79, .5), (2, 76, 1), (3, 74, 1)],
    [(0, 74, 1), (1.5, 71, .5), (2, 67, 1), (3, 71, 1)],
]

drums = np.zeros(N); bassbus = np.zeros(N); padbus = np.zeros(N); lead = np.zeros(N); fx = np.zeros(N)
sidechain = np.ones(N)


def bar_start(b):
    return b * BAR


# takt 0: klid – zvonky a tichý pad, riser do dropu
for i, (beat, m, _) in enumerate(HOOK[0]):
    add(lead, bell(m + 12, 1.4, 0.55), bar_start(0) + beat * BEAT)
add(padbus, fft_filter(supersaw([57, 60, 64], BAR), hi=900) * env_adsr(int(BAR * SR), 0.8, 0.2, 1, 0.3) * 0.5, 0)
add(fx, riser(1.0), 1.0)

for b in range(1, 12):
    ch = CHORDS[(b - 1) % 4]
    s = bar_start(b)
    build = b == 6
    # bicí
    for k in range(4):
        if not build or k < 2:
            add(drums, kick(), s + k * BEAT)
            i = int((s + k * BEAT) * SR)
            dip = 1 - 0.65 * np.exp(-t_of(int(BEAT * SR)) * 9)
            sidechain[i:i + len(dip)] = np.minimum(sidechain[i:i + len(dip)], dip)
        if k in (1, 3) and not build:
            add(drums, clap(), s + k * BEAT)
        add(drums, hat(open_=True, vel=0.7), s + k * BEAT + BEAT / 2)
        for sx in (0.25, 0.75):
            add(drums, hat(vel=0.45 + 0.25 * rng.random()), s + k * BEAT + sx * BEAT)
    if build:   # snare roll se zrychluje
        steps = [2, 2.5, 3, 3.25, 3.5, 3.625, 3.75, 3.8125, 3.875, 3.9375]
        for j, st in enumerate(steps):
            add(drums, clap(0.35 + 0.06 * j), s + st * BEAT)
        add(fx, riser(BAR), s)
    # basa: osminy, kořen + oktáva
    for k in range(8):
        m = ch[0] + (12 if k % 4 == 3 else 0)
        add(bassbus, bass(m, BEAT / 2 * 0.92), s + k * BEAT / 2)
    # stab akordy na „a“ (offbeat), v buildu držený pad
    if build:
        add(padbus, fft_filter(supersaw(ch[1], BAR), hi=2500) * np.linspace(0.2, 1, int(BAR * SR)), s)
    else:
        for k in range(4):
            st = supersaw(ch[1], BEAT * 0.45, vel=0.9)
            add(padbus, st * env_adsr(len(st), 0.003, 0.08, 0.5, 0.05), s + k * BEAT + BEAT / 2)
    # melodie od taktu 3 (po prvním refrénu nastoupí)
    if b >= 3 and not build:
        for beat, m, ln in HOOK[(b - 1) % 4]:
            add(lead, bell(m, ln * BEAT + 0.5, 0.8), s + beat * BEAT)
            add(lead, bell(m + 12, ln * BEAT + 0.3, 0.25), s + beat * BEAT)

# přechody (whoosh) na hranách scén
for b in (3, 4, 5, 8, 9, 10, 11):
    add(fx, whoosh(), bar_start(b) - 0.2)
# náraz VÝHRA (takt 7)
add(fx, impact(), bar_start(7))
# konec: velký akord + boom + zvonky v dozvuku
end = bar_start(12)
add(fx, impact() * 0.8, end)
add(drums, kick(1.1), end)
fin = supersaw([45, 57, 60, 64, 69], 4.0, vel=1.2)
add(padbus, fft_filter(fin, hi=3000) * np.exp(-t_of(len(fin)) * 0.9), end)
for i, (beat, m, _) in enumerate(HOOK[0]):
    add(lead, bell(m + 12, 1.6, 0.5), end + 0.5 + beat * BEAT * 0.75)


# --- mix ----------------------------------------------------------------------
def reverb(x, secs=2.2, seed=1):
    r = np.random.default_rng(seed)
    n = int(secs * SR)
    ir = r.standard_normal(n) * np.exp(-t_of(n) * 3.2)
    ir = fft_filter(ir, hi=6000)
    ir /= np.sqrt(np.sum(ir ** 2))
    L = len(x) + n
    y = np.fft.irfft(np.fft.rfft(x, L) * np.fft.rfft(ir, L), L)[: len(x)]
    return y


padbus = fft_filter(padbus, lo=180, hi=7000) * sidechain
bassbus = fft_filter(bassbus, hi=1800) * (0.35 + 0.65 * sidechain)
dry = drums * 0.9 + bassbus * 0.85 + padbus * 0.55 + lead * 0.5 + fx * 0.6
wetsrc = padbus * 0.5 + lead * 0.6 + fx * 0.3 + drums * 0.05
L = dry + reverb(wetsrc, seed=1) * 0.45
R = dry + reverb(wetsrc, seed=2) * 0.45
# šířka: zvonky a pad trochu do stran
L += lead * 0.08; R -= lead * 0.08
stereo = np.stack([L, R], axis=1)
stereo = np.tanh(stereo / np.max(np.abs(stereo)) * 1.8)
stereo *= 0.89 / np.max(np.abs(stereo))
fade = int(0.8 * SR)
stereo[-fade:] *= np.linspace(1, 0, fade)[:, None]

out = sys.argv[1] if len(sys.argv) > 1 else "public/music.wav"
with wave.open(out, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((stereo * 32767).astype(np.int16).tobytes())
print(out, f"{LEN:.1f} s")
