"""Renders Blastfront's synthesized one-shot sound effects into assets/audio/sfx/.

python tools/music/render_sfx.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from synth import SR, bandpass, highpass, lowpass, normalize_rms, perc_env, t_axis, write_ogg

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")


def thump(length, start_hz, end_hz, decay):
    t = t_axis(length)
    freq = end_hz + (start_hz - end_hz) * np.exp(-t / 0.04)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * perc_env(len(t), decay)


def render_heartbeat():
    """Low "lub-dub" for the low-health warning; dry and soft so it sits under the mix."""
    total = np.zeros(int(0.75 * SR))
    lub = thump(0.32, 95.0, 48.0, 0.09)
    dub = thump(0.28, 80.0, 42.0, 0.075) * 0.72
    total[: len(lub)] += lub
    offset = int(0.26 * SR)
    total[offset: offset + len(dub)] += dub
    total = lowpass(total, 260.0)
    fade = np.linspace(1.0, 0.0, int(0.08 * SR))
    total[-len(fade):] *= fade
    stereo = np.stack([total, total], axis=1)
    return normalize_rms(stereo, -14.0)


RNG = np.random.default_rng(2024)


def noise(n):
    return RNG.standard_normal(n)


def metal_ring(length, partials, decay):
    """Inharmonic partials with individual decays: the ring of a steel part settling into a mount."""
    t = t_axis(length)
    out = np.zeros_like(t)
    for index, (freq, amp) in enumerate(partials):
        out += np.sin(2 * np.pi * freq * t + index) * amp * np.exp(-t / (decay * (1.0 - index * 0.12)))
    return out


def limit_peak(stereo, peak=0.72):
    """Codec overshoot pushes decoded transients past the encoded peak; leave headroom."""
    current = np.max(np.abs(stereo))
    return stereo * min(1.0, peak / max(current, 1e-9))


def stereoize(mono, width=0.12):
    delay = int(0.0006 * SR)
    right = np.concatenate([np.zeros(delay), mono[:-delay]])
    left = mono * (1.0 + width) - right * width
    return np.stack([left, right], axis=1)


def render_loadout_snap():
    """Part locking into a weapon socket: sharp latch click, short steel ring, low body thunk."""
    total = np.zeros(int(0.42 * SR))
    click = highpass(noise(int(0.006 * SR)), 2500.0) * np.linspace(1.0, 0.0, int(0.006 * SR))
    total[: len(click)] += click * 0.9
    latch = bandpass(noise(int(0.03 * SR)), 1800.0, 5200.0) * perc_env(int(0.03 * SR), 0.006)
    offset = int(0.018 * SR)
    total[offset: offset + len(latch)] += latch * 0.8
    ring = metal_ring(0.36, [(1870.0, 0.5), (2640.0, 0.32), (3910.0, 0.2), (5230.0, 0.12)], 0.07)
    total[offset: offset + len(ring)] += ring * 0.35
    thunk = thump(0.16, 210.0, 90.0, 0.045)
    total[: len(thunk)] += thunk * 0.75
    fade = np.linspace(1.0, 0.0, int(0.05 * SR))
    total[-len(fade):] *= fade
    return limit_peak(normalize_rms(stereoize(total), -15.0))


def render_loadout_detach():
    """Part pulled off: soft release click and an airy upward swish."""
    length = 0.3
    n = int(length * SR)
    t = t_axis(length)
    total = np.zeros(n)
    click = bandpass(noise(int(0.012 * SR)), 1200.0, 4000.0) * perc_env(int(0.012 * SR), 0.004)
    total[: len(click)] += click * 0.7
    swish = bandpass(noise(n), 900.0, 3800.0) * np.sin(np.pi * np.clip(t / length, 0, 1)) ** 2 * 0.35
    total += swish
    ring = metal_ring(0.2, [(1320.0, 0.4), (2210.0, 0.25)], 0.04)
    total[: len(ring)] += ring * 0.25
    return limit_peak(normalize_rms(stereoize(total), -18.0))


def render_loadout_pickup():
    """Grabbing a part: tiny tick plus a short rising air swell."""
    length = 0.18
    n = int(length * SR)
    t = t_axis(length)
    total = np.zeros(n)
    tick = highpass(noise(int(0.004 * SR)), 3000.0) * np.linspace(1.0, 0.0, int(0.004 * SR))
    total[: len(tick)] += tick * 0.6
    swell = bandpass(noise(n), 1500.0, 6000.0) * (t / length) * np.exp(-((t - length * 0.7) ** 2) / 0.002) * 0.5
    total += swell
    blip = np.sin(2 * np.pi * (900.0 + 700.0 * t / length) * t) * perc_env(n, 0.03) * 0.25
    total += blip
    return limit_peak(normalize_rms(stereoize(total), -20.0))


def render_loadout_hover():
    """Very soft high tick for hovering inventory tiles."""
    n = int(0.06 * SR)
    t = t_axis(0.06)
    tone = np.sin(2 * np.pi * 2600.0 * t) * perc_env(n, 0.008)
    tick = highpass(noise(n), 4000.0) * perc_env(n, 0.002) * 0.4
    return limit_peak(normalize_rms(stereoize(tone * 0.6 + tick), -24.0))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    renders = {
        "heartbeat.ogg": render_heartbeat,
        "loadout_snap.ogg": render_loadout_snap,
        "loadout_detach.ogg": render_loadout_detach,
        "loadout_pickup.ogg": render_loadout_pickup,
        "loadout_hover.ogg": render_loadout_hover,
    }
    only = sys.argv[1:]
    for name, render in renders.items():
        if only and name not in only:
            continue
        write_ogg(render(), os.path.join(OUT_DIR, name))
        print("rendered", name)


if __name__ == "__main__":
    main()
