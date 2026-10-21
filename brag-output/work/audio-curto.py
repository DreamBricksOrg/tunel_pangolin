import json, wave, os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TL = json.load(open(os.path.join(HERE, "timeline.json")))
sr = 44100
dur = TL["dur"]
N = int(dur * sr)
rng = np.random.default_rng(7)

L = np.zeros(N)
R = np.zeros(N)
music = [np.zeros(N), np.zeros(N)]   # pad/bass/arp/drums
fx = [np.zeros(N), np.zeros(N)]      # typing, whoosh, chimes

BPM = 112
beat = 60 / BPM
hz = lambda m: 440.0 * 2 ** ((m - 69) / 12)

def put(bus, sig, t0, pan=0.0, gain=1.0):
    i = int(t0 * sr)
    if i >= N or i < 0:
        return
    n = min(len(sig), N - i)
    l = np.sqrt(0.5 * (1 - pan)) * 1.0
    r = np.sqrt(0.5 * (1 + pan)) * 1.0
    bus[0][i:i + n] += sig[:n] * gain * l * 1.414
    bus[1][i:i + n] += sig[:n] * gain * r * 1.414

def tvec(d):
    return np.arange(int(d * sr)) / sr

def lp(x, a):  # one-pole lowpass, a in (0,1): smaller = darker
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y

# ---------------------------------------------------------------- harmony (A minor)
# A minor -> F -> C -> G -> F -> A minor, 2 bars (8 beats) each
chords = [
    ([57, 60, 64], 45),  # Am: A3 C4 E4, root A2
    ([53, 57, 60], 41),  # F
    ([55, 60, 64], 48),  # C
    ([55, 59, 62], 43),  # G
    ([53, 57, 60], 41),  # F
    ([57, 60, 64], 45),  # Am
]
blk = beat * 8

# pad
for k, (notes, root) in enumerate(chords):
    t0 = k * blk
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
    put(music, sig, t0, pan=-0.25, gain=1.0)
    put(music, sig * 0.8, t0, pan=0.25, gain=1.0)

# bass: one note per 2 beats from 3.8s
for k, (notes, root) in enumerate(chords):
    for j in range(4):
        t0 = k * blk + j * 2 * beat
        if t0 < 3.6:
            continue
        t = tvec(beat * 1.7)
        env = np.minimum(t / 0.01, 1) * np.exp(-t * 2.6)
        sig = (np.sin(2 * np.pi * hz(root) * t) + 0.25 * np.sin(2 * np.pi * hz(root) * 2 * t)) * env * 0.16
        put(music, sig, t0, pan=0.0)

# arp (8th notes) from 1.7s, with dotted-8th echo
arp_bus = [np.zeros(N), np.zeros(N)]
pattern = [0, 1, 2, 1, 2, 1, 2, 1]
step = beat / 2
n_steps = int(dur / step)
for s_i in range(n_steps):
    t0 = s_i * step
    if t0 < 1.7 or t0 > dur - 1.2:
        continue
    k = min(int(t0 // blk), len(chords) - 1)
    notes = chords[k][0]
    m = notes[pattern[s_i % len(pattern)]] + 24
    t = tvec(0.55)
    env = np.exp(-t * 8.5) * np.minimum(t / 0.004, 1)
    f = hz(m)
    sig = (np.sin(2 * np.pi * f * t) + 0.38 * np.sin(2 * np.pi * f * 2 * t) + 0.16 * np.sin(2 * np.pi * f * 3 * t)) * env * 0.05
    put(arp_bus, sig, t0, pan=-0.35 if s_i % 2 == 0 else 0.35)
echo = beat * 0.75
for rep, g in ((1, 0.38), (2, 0.16)):
    off = int(echo * sr * rep)
    for c in (0, 1):
        arp_bus[c][off:] += arp_bus[c][:N - off] * g * (1 if c == 0 else 1)
    # cross-channel feel
    arp_bus[0][off:], arp_bus[1][off:] = arp_bus[0][off:] * 0.9 + arp_bus[1][:N - off] * 0.0, arp_bus[1][off:] * 0.9
for c in (0, 1):
    music[c] += arp_bus[c]

# drums: soft kick on beats 3.8 -> 20.4 and on S5 hits
def kick(t0, g=0.34):
    t = tvec(0.35)
    f = 48 + 90 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / sr
    sig = np.sin(ph) * np.exp(-t * 9) * np.minimum(t / 0.003, 1) * g
    put(music, sig, t0)

def hat(t0, g=0.035):
    t = tvec(0.07)
    n = rng.standard_normal(len(t))
    n = np.diff(n, prepend=0)  # crude highpass
    sig = n * np.exp(-t * 70) * g
    put(music, sig, t0, pan=0.2)

tt = 3.8
while tt < 20.4:
    kick(tt)
    tt += beat
tt = 9.2 + beat / 2
while tt < 20.3:
    hat(tt)
    tt += beat

# ---------------------------------------------------------------- effects (A minor pentatonic, same key)
pent = [81, 84, 86, 88, 91, 93]  # A5 C6 D6 E6 G6 A6

def blip(t0, idx, g=0.02):
    t = tvec(0.045)
    f = hz(pent[idx % len(pent)])
    sig = np.sin(2 * np.pi * f * t) * np.exp(-t * 90) * g
    put(fx, sig, t0, pan=0.0)

def typing(text, t0, cps, seed=0):
    for i, ch in enumerate(text):
        if ch == " ":
            continue
        blip(t0 + i / cps, (i * 3 + seed) % 6)

typing("tunel 8001 meuapp", TL["s2_type"], TL["s2_cps"])
for c in TL["s4_cmds"]:
    typing(c["text"], c["t"], TL["s4_cps"], seed=2)

def whoosh(t0, d=0.55, g=0.05):
    t = tvec(d)
    n = rng.standard_normal(len(t))
    n = lp(n, 0.06)
    n = np.diff(n, prepend=0) * 14
    env = np.sin(np.pi * np.clip(t / d, 0, 1)) ** 2
    sig = n * env * g
    put(fx, sig, t0, pan=0.0)

for e in (TL["s1"][1] - 0.25, TL["s2"][1] - 0.25, TL["s3"][1] - 0.25, TL["s4"][1] - 0.25):
    whoosh(e)

def bell(t0, notes, g=0.05, d=1.6):
    t = tvec(d)
    for m, w in notes:
        f = hz(m)
        sig = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 4)) * np.exp(-t * 2.8) * np.minimum(t / 0.004, 1) * g * w
        put(fx, sig, t0, pan=0.1)

bell(TL["s2_out"][1], [(93, 1.0), (88, 0.7), (81, 0.6)])         # link reveal
bell(TL["s2_out"][2], [(91, 0.6)], d=1.0)                         # "pronto"
for t0, m in zip(TL["s3_cards"], (84, 88, 91)):                  # cards pop
    bell(t0, [(m, 1.0), (m - 12, 0.5)], g=0.06, d=0.9)
bell(TL["s4_cmds"][2]["out"], [(88, 0.8)], d=0.9)                 # list
bell(TL["s4_list2"], [(91, 0.8)], d=0.9)

# S5: three soft hits (sub + stab), then final chime
for t0, m in zip(TL["s5_words"], (57, 60, 64)):
    kick(t0, g=0.42)
    t = tvec(0.7)
    f = hz(m)
    sig = (np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 2 * t)) * np.exp(-t * 4.5) * np.minimum(t / 0.004, 1) * 0.08
    put(fx, sig, t0, pan=0.0)
bell(TL["s5_cmd"], [(93, 1.0), (88, 0.8), (81, 0.7), (76, 0.5)], g=0.06, d=2.4)

# ---------------------------------------------------------------- mix
mus = np.stack(music)
fxs = np.stack(fx)
mix = mus * 0.9 + fxs * 0.8
# small glue reverb: short feedback comb on the sum
for dly, g in ((int(0.037 * sr), 0.22), (int(0.071 * sr), 0.16), (int(0.113 * sr), 0.1)):
    for c in (0, 1):
        mix[c][dly:] += mix[c][:-dly] * g
# fades
fi = np.minimum(np.arange(N) / (0.15 * sr), 1.0)
fo = np.clip((N - np.arange(N)) / (0.9 * sr), 0, 1)
mix *= fi * fo
mix = np.tanh(mix * 1.3) / 1.3
peak = np.abs(mix).max()
mix = mix / peak * 0.89

pcm = (np.clip(mix.T, -1, 1) * 32767).astype("<i2")
with wave.open(os.path.join(HERE, "audio.wav"), "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(sr)
    w.writeframes(pcm.tobytes())
print("audio ok", round(dur, 2), "s")
