"""Генерирует assets/sounds/drop.wav: тихий «плюх» капли (44,1 кГц, mono, 16 бит, ~0,35 с).
Запуск: python3 tool/make_drop_sound.py"""
import math
import struct
import wave
from pathlib import Path

RATE = 44100
DUR = 0.35
AMP = 0.28  # тихо


def tone(t, t0, f0, f1, decay, length):
    """Затухающий синус с понижением частоты f0 -> f1; начинается в t0."""
    x = t - t0
    if x < 0 or x > length:
        return 0.0
    k = (f1 - f0) / length
    phase = 2 * math.pi * (f0 * x + 0.5 * k * x * x)
    env = math.exp(-decay * x) * min(1.0, x / 0.004)  # мягкая атака 4 мс
    return math.sin(phase) * env


def main():
    n = int(RATE * DUR)
    frames = bytearray()
    for i in range(n):
        t = i / RATE
        v = tone(t, 0.0, 900, 300, 14, 0.30)
        v += 0.45 * tone(t, 0.09, 700, 380, 18, 0.22)  # второй лёгкий «бульк»
        fade = min(1.0, (DUR - t) / 0.03)  # без щелчка в конце
        v = max(-1.0, min(1.0, v * AMP * fade))
        frames += struct.pack('<h', int(v * 32767))
    out = Path(__file__).resolve().parent.parent / 'assets' / 'sounds' / 'drop.wav'
    out.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(out), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))
    print(out)


if __name__ == '__main__':
    main()
