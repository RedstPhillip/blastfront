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


# --- Weapons -------------------------------------------------------------------------------------------
# Every report is built from the same parts so the family stays coherent: a bright transient, a noise
# blast, a sub thump for weight and an outdoor tail with a slap-back echo. The proportions give each
# barrel its character.

def _decay_noise(seconds, tau, lo, hi, seed):
    rng = np.random.default_rng(seed)
    t = t_axis(seconds)
    return bandpass(rng.standard_normal(len(t)), lo, hi) * np.exp(-t / tau)


def _gun_report(length, crack, blast_tau, blast_band, body, tail_tau, echo_gain, seed, drive=1.6):
    t = t_axis(length)
    n = len(t)
    rng = np.random.default_rng(seed)
    out = np.zeros(n)
    click = highpass(rng.standard_normal(n), 2500.0) * np.exp(-t / 0.0025) * crack
    blast = bandpass(rng.standard_normal(n), blast_band[0], blast_band[1]) * np.exp(-t / blast_tau)
    blast *= np.clip(t / 0.0015, 0, 1)
    out += click + blast
    if body is not None:
        start_hz, end_hz, decay, gain = body
        thud = thump(min(length, decay * 6.0), start_hz, end_hz, decay) * gain
        out[: len(thud)] += thud
    tail = lowpass(rng.standard_normal(n), 1400.0) * np.exp(-t / tail_tau) * 0.22
    tail *= np.clip((t - 0.01) / 0.03, 0, 1)
    out += tail
    out = np.tanh(out * drive) / np.tanh(drive)
    echo = np.zeros(n)
    for delay_s, gain in ((0.13, echo_gain), (0.31, echo_gain * 0.45)):
        d = int(delay_s * SR)
        if d < n:
            echo[d:] += lowpass(out[: n - d], 1800.0) * gain
    mono = out + echo
    fade = np.clip((length - t) / 0.08, 0, 1)
    return mono * fade


def render_shot_carbine():
    """The base carbine: a tight, mid-heavy crack with a short outdoor tail."""
    mono = _gun_report(0.7, 0.9, 0.022, (300.0, 7000.0), (150.0, 55.0, 0.05, 0.7), 0.12, 0.22, 301)
    return limit_peak(normalize_rms(stereoize(mono, 0.18), -15.0))


def render_shot_shotgun():
    """A shotgun: a wide, heavy boom with a lot of low end and a long rolling tail."""
    mono = _gun_report(1.2, 0.8, 0.07, (120.0, 5200.0), (120.0, 38.0, 0.12, 1.5), 0.32, 0.38, 311, drive=2.2)
    return limit_peak(normalize_rms(stereoize(mono, 0.3), -13.0))


def render_shotgun_pump():
    """The pump: slide back (scrape and clack), slide forward (clack), both a little metallic."""
    total = np.zeros(int(0.42 * SR))
    for start, gain, band in ((0.0, 0.8, (900.0, 4200.0)), (0.17, 1.0, (700.0, 3600.0))):
        scrape = _decay_noise(0.07, 0.02, band[0], band[1], int(start * 1000) + 5)
        clack = _decay_noise(0.03, 0.004, 1500.0, 7000.0, int(start * 1000) + 9) * 2.2
        ring = metal_ring(0.12, [(2350.0, 0.25), (3720.0, 0.18), (5110.0, 0.1)], 0.03)
        offset = int(start * SR)
        total[offset: offset + len(scrape)] += scrape * gain
        c_off = offset + int(0.045 * SR)
        total[c_off: c_off + len(clack)] += clack * gain
        total[c_off: c_off + len(ring)] += ring * gain
    return limit_peak(normalize_rms(stereoize(total, 0.15), -19.0))


def render_shot_sniper():
    """A rifle: a very sharp supersonic crack, a solid body and a long, echoing roll down the valley."""
    mono = _gun_report(1.8, 1.6, 0.03, (500.0, 9000.0), (170.0, 50.0, 0.07, 1.0), 0.55, 0.55, 321, drive=2.0)
    return limit_peak(normalize_rms(stereoize(mono, 0.25), -13.5))


def render_sniper_bolt():
    """Bolt cycle: lift, pull, push, lock."""
    total = np.zeros(int(0.5 * SR))
    for start, gain in ((0.0, 0.6), (0.11, 0.9), (0.27, 0.9), (0.37, 0.7)):
        clack = _decay_noise(0.04, 0.005, 1200.0, 6500.0, int(start * 1000) + 21) * 2.0
        ring = metal_ring(0.08, [(1900.0, 0.2), (3100.0, 0.14)], 0.02)
        offset = int(start * SR)
        total[offset: offset + len(clack)] += clack * gain
        total[offset: offset + len(ring)] += ring * gain
    return limit_peak(normalize_rms(stereoize(total, 0.15), -20.0))


def render_shot_heavy():
    """Heavy barrel: lower, chestier report with a deep thump."""
    mono = _gun_report(1.0, 0.7, 0.04, (160.0, 4200.0), (110.0, 42.0, 0.1, 1.4), 0.22, 0.3, 331, drive=2.0)
    return limit_peak(normalize_rms(stereoize(mono, 0.2), -14.0))


def render_shot_light():
    """Lighter barrel: a snappy, high, short pop."""
    mono = _gun_report(0.5, 1.0, 0.012, (700.0, 9000.0), (200.0, 80.0, 0.03, 0.4), 0.07, 0.15, 341)
    return limit_peak(normalize_rms(stereoize(mono, 0.15), -16.5))


def render_shot_launcher():
    """Grenade/explosive rounds: a hollow tube "thoomp" with a soft, airy whoosh after it."""
    seconds = 0.9
    t = t_axis(seconds)
    tube = bandpass(RNG.standard_normal(len(t)), 220.0, 720.0) * np.exp(-t / 0.05) * 1.4
    thud = thump(0.5, 95.0, 42.0, 0.09) * 1.6
    whoosh = bandpass(RNG.standard_normal(len(t)), 900.0, 3800.0) * np.exp(-((t - 0.12) / 0.09) ** 2) * 0.35
    mono = tube + whoosh
    mono[: len(thud)] += thud
    mono = np.tanh(mono * 1.8) / np.tanh(1.8)
    return limit_peak(normalize_rms(stereoize(mono, 0.25), -15.0))


def render_storm_loop(seconds):
    """Inside a Martian dust storm: a dense roar, gusting howls and sand grains rattling past."""
    t = t_axis(seconds)
    rng = np.random.default_rng(131)
    roar = lowpass(rng.standard_normal(len(t)), 260.0) * 2.4
    body = bandpass(rng.standard_normal(len(t)), 300.0, 1800.0) * 0.55
    hiss = highpass(rng.standard_normal(len(t)), 2600.0) * 0.16
    gust = 0.62 + 0.38 * np.clip(
        np.sin(2 * np.pi * 0.23 * t) * 0.6 + np.sin(2 * np.pi * 0.41 * t + 1.3) * 0.4 + np.sin(2 * np.pi * 0.087 * t + 0.4) * 0.7,
        -1, 1)
    howl_l = resonant_wind(seconds, 480.0, 110.0, 0.19, 41) * 0.5
    howl_r = resonant_wind(seconds, 540.0, 110.0, 0.17, 43) * 0.5
    whistle = resonant_wind(seconds, 1300.0, 80.0, 0.23, 47) * 0.18
    # Sand grains: sparse bright ticks, denser in the gusts.
    grains = np.zeros(len(t))
    density = (gust - 0.5) * 0.004
    hits = rng.random(len(t)) < np.clip(density, 0.0002, 0.003)
    grains[hits] = rng.uniform(-1.0, 1.0, int(hits.sum()))
    grains = highpass(grains, 3000.0) * 1.4
    mono = roar * (0.7 + 0.3 * gust) + (body + hiss) * gust + whistle * gust
    left = mono + howl_l * gust + grains * 0.9
    right = mono + howl_r * gust + np.roll(grains, 377) * 0.9
    return np.stack([left, right], axis=1)


def render_storm_warning():
    """The storm front arriving: a deep swell that rises in pitch with a far-off rumble under it."""
    seconds = 4.6
    t = t_axis(seconds)
    rise = np.clip(t / (seconds * 0.82), 0, 1) ** 1.6
    fade = np.clip((seconds - t) / 0.6, 0, 1)
    howl = np.zeros(len(t))
    block = 2048
    raw = RNG.standard_normal(len(t) + block)
    for start in range(0, len(t), block):
        mid = min((start + block * 0.5) / SR / seconds, 1.0)
        c = 260.0 + 520.0 * mid ** 1.4
        seg = bandpass(raw[start:start + block * 2], c - 70.0, c + 90.0)[:block]
        end = min(start + block, len(t))
        howl[start:end] = seg[: end - start]
    rumble = lowpass(RNG.standard_normal(len(t)), 110.0) * 2.2
    hiss = bandpass(RNG.standard_normal(len(t)), 1800.0, 6500.0) * 0.3
    mono = (howl * 1.2 + rumble * (0.4 + 0.6 * rise) + hiss * rise) * rise * fade
    return limit_peak(normalize_rms(stereoize(mono, 0.35), -16.0))


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
        "storm_warning.wav": render_storm_warning,
        "shot_carbine.wav": render_shot_carbine,
        "shot_shotgun.wav": render_shot_shotgun,
        "shotgun_pump.wav": render_shotgun_pump,
        "shot_sniper.wav": render_shot_sniper,
        "sniper_bolt.wav": render_sniper_bolt,
        "shot_heavy.wav": render_shot_heavy,
        "shot_light.wav": render_shot_light,
        "shot_launcher.wav": render_shot_launcher,
    }
    only = sys.argv[1:]
    for name, render in renders.items():
        if only and name not in only:
            continue
        write_wav(render(), os.path.join(OUT_DIR, name))
        print("rendered", name)
    if not only or "storm_loop.ogg" in only:
        loop = make_seamless(render_storm_loop, 30.0)
        write_ogg(normalize_rms(loop, -19.0), os.path.join(MUSIC_DIR, "storm_loop.ogg"))
        print("rendered storm_loop.ogg")
    if not only or "ambience_mars.ogg" in only:
        loop = make_seamless(render_mars_ambience, 40.0)
        write_ogg(normalize_rms(loop, -24.0), os.path.join(MUSIC_DIR, "ambience_mars.ogg"))
        print("rendered ambience_mars.ogg")


if __name__ == "__main__":
    main()
