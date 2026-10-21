import json, wave, os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TL = json.load(open(os.path.join(HERE, "timeline.json"), encoding="utf-8"))
SC, TY, EV = TL["scenes"], TL["type"], TL["events"]
sr = 44100
dur = TL["dur"]
N = int(dur * sr)
rng = np.random.default_rng(11)

music = [np.zeros(N), np.zeros(N)]
fx = [np.zeros(N), np.zeros(N)]

BPM = 108
beat = 60 / BPM
hz = lambda m: 440.0 * 2 ** ((m - 69) / 12)

def put(bus, sig, t0, pan=0.0, gain=1.0):
    i = int(t0 * sr)
    if i >= N or i < 0:
        return
    n = min(len(sig), N - i)
    l = np.sqrt(0.5 * (1 - pan)) * 1.414
    r = np.sqrt(0.5 * (1 + pan)) * 1.414
    bus[0][i:i + n] += sig[:n] * gain * l
    bus[1][i:i + n] += sig[:n] * gain * r

def tvec(d):
    return np.arange(int(d * sr)) / sr

def lp(x, a):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y

# ---------------------------------------------------------------- harmony: A minor
Am = ([57, 60, 64], 45); F = ([53, 57, 60], 41); C = ([55, 60, 64], 48); G = ([55, 59, 62], 43)
blk = beat * 8
n_blk = int(np.ceil(dur / blk)) + 1
seq = ([Am, F, C, G] * 8)[:n_blk - 3] + [F, G, Am]
seq = (seq + [Am] * 4)[:n_blk]
chords = seq

active = lambda t, names: any(SC[n][0] - 0.05 <= t < SC[n][1] for n in names)
hot = ["s1", "s4", "s5", "s6", "s7"]        # scenes with drums
calm = ["intro", "s2", "s3", "outro"]

# pad
for k, (notes, root) in enumerate(chords):
    t0 = k * blk
    if t0 >= dur:
        break
    d = blk + 0.6
    t = tvec(d)
    env = np.minimum(t / 0.7, 1.0) * np.clip((d - t) / 0.6, 0, 1)
    sig = np.zeros_like(t)
    for m in notes:
        for det in (-0.07, 0.0, 0.07):
            f = hz(m) * 2 ** (det / 12)
            for h, w in ((1, 1.0), (2, 0.45), (3, 0.2), (4, 0.1)):
                sig += w * np.sin(2 * np.pi * f * h * t + rng.uniform(0, 6.28))
    sig *= env * 0.012
    sig = lp(sig, 0.18)
    put(music, sig, t0, pan=-0.25)
    put(music, sig * 0.8, t0, pan=0.25)

# bass during drum scenes
for k, (notes, root) in enumerate(chords):
    for j in range(4):
        t0 = k * blk + j * 2 * beat
        if t0 >= dur or not active(t0, hot):
            continue
        t = tvec(beat * 1.7)
        env = np.minimum(t / 0.01, 1) * np.exp(-t * 2.6)
        sig = (np.sin(2 * np.pi * hz(root) * t) + 0.25 * np.sin(2 * np.pi * hz(root) * 2 * t)) * env * 0.15
        put(music, sig, t0)

# arp with echo (quieter in calm scenes)
arp = [np.zeros(N), np.zeros(N)]
pattern = [0, 1, 2, 1, 2, 1, 2, 1]
step = beat / 2
for s_i in range(int(dur / step)):
    t0 = s_i * step
    if t0 < 1.5 or t0 > dur - 1.5:
        continue
    k = min(int(t0 // blk), len(chords) - 1)
    m = chords[k][0][pattern[s_i % len(pattern)]] + 24
    t = tvec(0.55)
    env = np.exp(-t * 8.5) * np.minimum(t / 0.004, 1)
    f = hz(m)
    g = 0.05 if active(t0, hot) else 0.032
    sig = (np.sin(2 * np.pi * f * t) + 0.38 * np.sin(2 * np.pi * f * 2 * t) + 0.16 * np.sin(2 * np.pi * f * 3 * t)) * env * g
    put(arp, sig, t0, pan=-0.35 if s_i % 2 == 0 else 0.35)
echo = beat * 0.75
for rep, g in ((1, 0.36), (2, 0.15)):
    off = int(echo * sr * rep)
    for c in (0, 1):
        arp[c][off:] += arp[c][:N - off] * g
for c in (0, 1):
    music[c] += arp[c]

def kick(t0, g=0.32):
    t = tvec(0.35)
    f = 48 + 90 * np.exp(-t * 28)
    sig = np.sin(2 * np.pi * np.cumsum(f) / sr) * np.exp(-t * 9) * np.minimum(t / 0.003, 1) * g
    put(music, sig, t0)

def hat(t0, g=0.03):
    t = tvec(0.07)
    n = np.diff(rng.standard_normal(len(t)), prepend=0)
    put(music, n * np.exp(-t * 70) * g, t0, pan=0.2)

tt = 0.0
while tt < dur - 4:
    if active(tt, hot):
        kick(tt)
    tt += beat
tt = beat / 2
while tt < dur - 4:
    if active(tt, ["s4", "s5", "s6", "s7"]):
        hat(tt)
    tt += beat

# ---------------------------------------------------------------- effects (same key)
pent = [81, 84, 86, 88, 91, 93]

def blip(t0, idx, g=0.02):
    t = tvec(0.045)
    f = hz(pent[idx % len(pent)])
    put(fx, np.sin(2 * np.pi * f * t) * np.exp(-t * 90) * g, t0)

def typing(key, seed=0):
    s = TY[key]
    for i, ch in enumerate(s["text"]):
        if ch == " ":
            continue
        blip(s["t"] + i / s["cps"], (i * 3 + seed) % 6)

for k, sd in (("s1_clone", 0), ("s1_cd", 1), ("s1_ls", 2), ("s2_url", 3), ("s3_mail", 0), ("s3_pass", 4),
              ("s4_name", 2), ("s6_id", 1), ("s6_secret", 4), ("s7_cd", 0), ("s7_run", 2)):
    typing(k, sd)

def whoosh(t0, d=0.5, g=0.045):
    t = tvec(d)
    n = np.diff(lp(rng.standard_normal(len(t)), 0.06), prepend=0) * 14
    put(fx, n * np.sin(np.pi * np.clip(t / d, 0, 1)) ** 2 * g, t0)

for name in ("intro", "s1", "s2", "s3", "s4", "s5", "s6", "s7"):
    whoosh(SC[name][1] - 0.25)

def bell(t0, notes, g=0.05, d=1.6):
    t = tvec(d)
    for m, w in notes:
        f = hz(m)
        sig = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 4)) * np.exp(-t * 2.8) * np.minimum(t / 0.004, 1) * g * w
        put(fx, sig, t0, pan=0.1)

# step-start chimes climb the scale
for i, name in enumerate(("s1", "s2", "s3", "s4", "s5", "s6", "s7")):
    bell(SC[name][0] + 0.05, [(pent[min(i, 5)] - 12, 1.0), (pent[min(i, 5)], 0.5)], g=0.045, d=1.2)

for t0 in EV["s1_out"][:2]:
    bell(t0, [(88, 0.5)], g=0.04, d=0.7)
bell(EV["s2_page"], [(91, 0.7)], g=0.04, d=0.9)
bell(EV["s3_ok"], [(88, 0.8), (93, 0.6)], g=0.05, d=1.2)
bell(EV["s4_modal"], [(84, 0.6)], g=0.04, d=0.8)
bell(EV["s4_creds"], [(93, 1.0), (88, 0.7), (81, 0.6)], g=0.055, d=1.8)
bell(EV["s5_win"], [(84, 0.7)], g=0.045, d=0.9)
bell(EV["s5_lin"], [(88, 0.7)], g=0.045, d=0.9)
bell(EV["s6_labels"], [(91, 0.7)], g=0.04, d=0.9)
bell(EV["s7_out"][1], [(93, 1.0), (88, 0.7), (81, 0.6)], g=0.055, d=1.8)
bell(EV["s7_out"][2], [(91, 0.6)], g=0.045, d=1.0)

# outro: two soft hits, chime, resolve
for t0, m in zip(EV["outro"][:2], (57, 64)):
    kick(t0, g=0.4)
    t = tvec(0.7)
    f = hz(m)
    put(fx, (np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 2 * t)) * np.exp(-t * 4.5) * np.minimum(t / 0.004, 1) * 0.08, t0)
bell(EV["outro"][2], [(93, 1.0), (88, 0.8), (81, 0.7), (76, 0.5)], g=0.06, d=2.6)

# ---------------------------------------------------------------- mix
mix = np.stack(music) * 0.9 + np.stack(fx) * 0.8
for dly, g in ((int(0.037 * sr), 0.22), (int(0.071 * sr), 0.16), (int(0.113 * sr), 0.1)):
    for c in (0, 1):
        mix[c][dly:] += mix[c][:-dly] * g
mix *= np.minimum(np.arange(N) / (0.15 * sr), 1.0) * np.clip((N - np.arange(N)) / (1.2 * sr), 0, 1)
mix = np.tanh(mix * 1.3) / 1.3
mix = mix / np.abs(mix).max() * 0.89

pcm = (np.clip(mix.T, -1, 1) * 32767).astype("<i2")
with wave.open(os.path.join(HERE, "audio.wav"), "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(pcm.tobytes())
print("audio ok", round(dur, 2), "s")
