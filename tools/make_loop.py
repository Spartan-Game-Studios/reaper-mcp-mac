#!/usr/bin/env python3
"""make_loop.py: turn a REAPER render into a seamless, level-normalised game loop (wav + ogg).

  <python with numpy> tools/make_loop.py render.wav out/menu_loop [--xfade 1.5] [--rms -22] [--ceil -1] [--no-ogg]

- Prints the render's peak, RMS and RMS per 8 s block (a quick shape check).
- Normalises to a fixed RMS (peak-capped), so the deliverable doesn't depend on where REAPER's master
  fader happened to sit when it was rendered.
- Bakes an equal-power crossfade of the last `xfade` seconds into the head and drops that tail, so
  sample N-1 flows into sample 0. The output is `xfade` seconds shorter than the render.
- Writes <out>.wav (16-bit) and <out>.ogg. Homebrew's ffmpeg has no libvorbis, so it uses ffmpeg's
  native `vorbis` encoder (-strict -2, stereo only). Godot imports .ogg; set loop=true in its .import.

Needs numpy (the system python3 doesn't have it; the ComfyUI env at
/Users/atticus/ComfyUI-Installs/Atticus/standalone-env/bin/python does).
"""
import argparse, subprocess, wave
import numpy as np

FFMPEG = "/opt/homebrew/bin/ffmpeg"


def load(path):
    w = wave.open(path)
    sr, ch, sw, n = w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getnframes()
    raw = w.readframes(n)
    if sw == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        a = b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16)
        a = np.where(a >= 1 << 23, a - (1 << 24), a) / float(1 << 23)
    elif sw == 2:
        a = np.frombuffer(raw, dtype="<i2") / 32768.0
    else:
        raise SystemExit(f"unsupported sample width {sw}")
    return a.reshape(-1, ch), sr, ch


def db(x):
    return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst", help="output path without extension")
    ap.add_argument("--xfade", type=float, default=1.5, help="tail->head crossfade, seconds")
    ap.add_argument("--rms", type=float, default=-22.0, help="target RMS, dB")
    ap.add_argument("--ceil", type=float, default=-1.0, help="peak ceiling, dBFS")
    ap.add_argument("--no-ogg", action="store_true")
    a = ap.parse_args()

    x, sr, ch = load(a.src)
    m = x.mean(1)
    print(f"peak {20*np.log10(np.abs(x).max()+1e-9):.1f} dBFS  rms {db(m):.1f} dB  dB/8s:",
          " ".join(f"{db(m[i:i+sr*8]):.0f}" for i in range(0, len(m), sr * 8)))
    g = min(10 ** ((a.rms - db(m)) / 20), 10 ** (a.ceil / 20) / max(np.abs(x).max(), 1e-9))
    x = x * g
    print(f"normalised by {20*np.log10(g):+.1f} dB -> rms {db(x.mean(1)):.1f} dB, peak {20*np.log10(np.abs(x).max()):.1f} dBFS")

    n = len(x)
    xf = int(a.xfade * sr)
    t = np.linspace(0, 1, xf)[:, None]
    loop = x[:n - xf].copy()
    loop[:xf] = x[:xf] * np.sqrt(t) + x[n - xf:] * np.sqrt(1 - t)   # equal power: tail fades into head
    o = wave.open(a.dst + ".wav", "wb")
    o.setnchannels(ch); o.setsampwidth(2); o.setframerate(sr)
    o.writeframes((np.clip(loop, -1, 1) * 32767).astype("<i2").tobytes()); o.close()
    if not a.no_ogg:
        subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", a.dst + ".wav", "-c:a", "vorbis",
                        "-strict", "-2", "-ac", "2", "-q:a", "6", a.dst + ".ogg"], check=True)
    print(f"loop {len(loop)/sr:.2f}s, seam jump {np.abs(loop[-1]-loop[0]).max():.4f} -> {a.dst}.wav"
          + ("" if a.no_ogg else "/.ogg"))


if __name__ == "__main__":
    main()
