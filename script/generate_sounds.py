"""Original synthesized effects: no third-party recordings or downloads."""
import math, random, wave, struct
from pathlib import Path
random.seed(31)
root = Path(__file__).resolve().parents[1] / 'Sources/HalloweenApp/Resources/Sounds'
root.mkdir(parents=True, exist_ok=True)
rate = 22050

def save(name, duration, fn):
    values = [fn(i / rate) for i in range(int(duration * rate))]
    peak = max(max(abs(v) for v in values), .001)
    with wave.open(str(root / (name + '.wav')), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v / peak * .72)) * 32767)) for v in values))

def heartbeat(t):
    p = t % 1.05
    return sum(math.sin(2 * math.pi * 58 * max(0, p - d)) * math.exp(-max(0, p - d) * 25) * gain if p >= d else 0 for d, gain in [(0, 1), (.2, .72)])
def knocks(t):
    return sum((random.uniform(-1, 1) * .5 + math.sin(2 * math.pi * 160 * (t - d))) * math.exp(-(t - d) * 28) if 0 <= t - d < .35 else 0 for d in [.4, 1.1, 1.8, 3.3])
last = 0

def storm(t):
    global last
    last = .985 * last + .015 * random.uniform(-1, 1)
    envelope = sum(math.exp(-max(0, t - d) * .7) if t >= d else 0 for d in [.25, 3.2, 6.2])
    return last * envelope + random.uniform(-1, 1) * .014

def ghost(t):
    fade = min(1, t / 1.2, (8 - t) / 1.3)
    return fade * sum(math.sin(2 * math.pi * (freq * t + math.sin(t * 2 + i) * 2)) * (.6 + .4 * math.sin(t * 3 + i)) for i, freq in enumerate([173, 221, 293, 349])) / 4

def laugh(t):
    envelope = max(0, math.sin(2 * math.pi * 3.8 * t)) ** 3 * min(1, t * 4, (4.5 - t) * 2)
    phase = 2 * math.pi * (340 * t + 8 * math.sin(t * 5))
    return envelope * (math.sin(phase) + .32 * math.sin(phase * 2) + .2 * math.sin(phase * 3))

def creak(t):
    envelope = max(0, math.sin(math.pi * t / 5)) ** .5
    phase = 2 * math.pi * (120 * t + 25 * t * t + 3 * math.sin(17 * t))
    return envelope * (math.sin(phase) + .4 * math.sin(phase * 3)) * (.7 + .3 * math.sin(t * 22))
save('heartbeat', 8, heartbeat); save('knocks', 4.5, knocks); save('storm', 9, storm); save('ghost', 8, ghost); save('laugh', 4.5, laugh); save('creak', 5, creak)
print('6 original sound effects generated')
