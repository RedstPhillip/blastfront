"""Renders Blastfront's synthesized one-shot sound effects into assets/audio/sfx/.

python tools/music/render_sfx.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from synth import SR, bandpass, highpass, lowpass, make_seamless, normalize_rms, perc_env, reverb, t_axis, write_ogg, write_wav

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


MUSIC_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "music")


def resonant_wind(seconds, center, width, sweep_rate, seed):
    """Band-limited noise whose centre slowly wanders: the thin whistle of wind over rock."""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = t_axis(seconds)
    block = 2048
    out = np.zeros(n)
    raw = rng.standard_normal(n + block)
    for start in range(0, n, block):
        mid = (start + block * 0.5) / SR
        c = center * (1.0 + 0.35 * np.sin(2 * np.pi * sweep_rate * mid + seed) + 0.15 * np.sin(2 * np.pi * sweep_rate * 2.7 * mid))
        seg = bandpass(raw[start:start + block * 2], max(c - width, 40.0), c + width)[:block]
        end = min(start + block, n)
        out[start:end] = seg[: end - start]
    return out


def render_mars_ambience(seconds):
    t = t_axis(seconds)
    rng = np.random.default_rng(77)
    rumble = lowpass(rng.standard_normal(len(t)), 90.0) * 1.6
    rumble *= 0.75 + 0.25 * np.sin(2 * np.pi * 0.05 * t)
    howl = resonant_wind(seconds, 620.0, 90.0, 0.07, 3) * 0.55
    whistle = resonant_wind(seconds, 1450.0, 60.0, 0.11, 5) * 0.22
    hiss = highpass(rng.standard_normal(len(t)), 3500.0) * 0.06
    gusts = 0.55 + 0.45 * np.clip(np.sin(2 * np.pi * 0.031 * t) * np.sin(2 * np.pi * 0.013 * t + 1.0) * 2.0, -1, 1)
    mono = rumble + (howl + whistle + hiss) * gusts
    left = mono + resonant_wind(seconds, 900.0, 120.0, 0.05, 9) * 0.18 * gusts
    right = mono + resonant_wind(seconds, 820.0, 120.0, 0.06, 11) * 0.18 * gusts
    stereo = np.stack([left, right], axis=1)
    return stereo


def render_dust_gust():
    """Rising howl before a gust: wind sweeping up in pitch and level."""
    seconds = 3.2
    t = t_axis(seconds)
    howl = resonant_wind(seconds, 520.0, 140.0, 0.25, 21)
    swell = np.sin(np.pi * np.clip(t / seconds, 0, 1)) ** 1.5
    hiss = bandpass(RNG.standard_normal(len(t)), 2000.0, 7000.0) * 0.25
    mono = (howl + hiss) * swell
    return limit_peak(normalize_rms(stereoize(mono, 0.3), -17.0))


def render_geyser_rumble():
    seconds = 1.1
    t = t_axis(seconds)
    rumble = lowpass(RNG.standard_normal(len(t)), 120.0) * 2.5
    hiss = bandpass(RNG.standard_normal(len(t)), 2500.0, 8000.0) * 0.35 * (t / seconds) ** 2
    env = np.clip(t / 0.3, 0, 1) * np.clip((seconds - t) / 0.15, 0, 1)
    return limit_peak(normalize_rms(stereoize((rumble + hiss) * env), -20.0))


def render_geyser_blast():
    seconds = 1.5
    t = t_axis(seconds)
    thumpy = thump(0.4, 140.0, 45.0, 0.12)
    blast = bandpass(RNG.standard_normal(len(t)), 600.0, 6000.0) * np.exp(-t / 0.55)
    roar = lowpass(RNG.standard_normal(len(t)), 300.0) * 1.8 * np.exp(-t / 0.7)
    mono = blast * 0.8 + roar
    mono[: len(thumpy)] += thumpy * 1.2
    mono *= np.clip(t / 0.01, 0, 1)
    return limit_peak(normalize_rms(stereoize(mono, 0.2), -15.0))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    renders = {
        "heartbeat.wav": render_heartbeat,
        "loadout_snap.wav": render_loadout_snap,
        "loadout_detach.wav": render_loadout_detach,
        "loadout_pickup.wav": render_loadout_pickup,
        "loadout_hover.wav": render_loadout_hover,
        "dust_gust.wav": render_dust_gust,
        "geyser_rumble.wav": render_geyser_rumble,
        "geyser_blast.wav": render_geyser_blast,
    }
    only = sys.argv[1:]
    for name, render in renders.items():
        if only and name not in only:
            continue
        write_wav(render(), os.path.join(OUT_DIR, name))
        print("rendered", name)
    if not only or "ambience_mars.ogg" in only:
        loop = make_seamless(render_mars_ambience, 40.0)
        write_ogg(normalize_rms(loop, -24.0), os.path.join(MUSIC_DIR, "ambience_mars.ogg"))
        print("rendered ambience_mars.ogg")


if __name__ == "__main__":
    main()
