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


def _sparse_events(n, rate_hz, rng):
    """Sample indices of a Poisson stream of events (rate per second) across n samples."""
    count = rng.poisson(rate_hz * n / SR)
    return np.sort(rng.integers(0, n, count))


def render_tidewater_ambience(seconds):
    """A drowned temple at night in the rain: steady downpour, waves washing through the ruins in slow
    swells, water dripping off stone and thunder rolling far away."""
    t = t_axis(seconds)
    n = len(t)
    rng = np.random.default_rng(211)
    rain = bandpass(rng.standard_normal(n), 1400.0, 9000.0) * 0.32
    rain *= 0.85 + 0.15 * np.sin(2 * np.pi * 0.07 * t)
    patter = np.zeros(n)
    for start in _sparse_events(n, 55.0, rng):
        length = int(SR * rng.uniform(0.004, 0.012))
        end = min(start + length, n)
        patter[start:end] += rng.uniform(-1, 1) * np.exp(-np.arange(end - start) / (length * 0.3))
    patter = bandpass(patter, 1800.0, 6000.0) * 0.9
    # Waves: two swells of different period wash in and drain away.
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * t / 8.0) ** 3 + 0.25 * np.sin(2 * np.pi * t / 13.0 + 1.0)
    swell = np.clip(swell, 0.15, 1.4)
    wash = bandpass(rng.standard_normal(n), 180.0, 1100.0) * 0.9 * swell
    undertow = lowpass(rng.standard_normal(n), 110.0) * 1.3 * (0.6 + 0.4 * swell)
    drips = np.zeros(n)
    for start in _sparse_events(n, 0.9, rng):
        length = int(SR * 0.18)
        end = min(start + length, n)
        tt = np.arange(end - start) / SR
        freq = rng.uniform(900.0, 1700.0) * (1.0 + 0.6 * np.exp(-tt / 0.01))
        drips[start:end] += np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-tt / 0.035) * rng.uniform(0.3, 0.7)
    drips = reverb(drips, wet=0.5, seconds=1.8, damping=3000.0)
    thunder = np.zeros(n)
    for start in _sparse_events(n, 0.035, rng):
        length = int(SR * 5.0)
        end = min(start + length, n)
        tt = np.arange(end - start) / SR
        roll = 1.0 + 0.5 * np.sin(2 * np.pi * 1.3 * tt) * np.exp(-tt / 1.5)
        thunder[start:end] += np.clip(tt / 0.4, 0, 1) * np.exp(-tt / 1.8) * roll
    thunder = lowpass(rng.standard_normal(n), 140.0) * thunder * 2.6
    mono = rain + undertow + thunder
    left = mono + wash + patter * 0.8 + drips[:, 0] * 0.6
    right = mono + np.roll(wash, int(SR * 0.7)) + np.roll(patter, 911) * 0.8 + drips[:, 1] * 0.6
    return np.stack([left, right], axis=1)


def render_rimefall_ambience(seconds):
    """A glacier pass at night: thin wind whistling over the ice, a low drone off the mountain, snow
    hissing past, and now and then the glacier groaning or a crack ringing out across the frozen lake."""
    t = t_axis(seconds)
    n = len(t)
    rng = np.random.default_rng(313)
    gusts = 0.5 + 0.5 * np.clip(np.sin(2 * np.pi * 0.045 * t) * np.sin(2 * np.pi * 0.017 * t + 0.6) * 2.2, -1, 1)
    drone = lowpass(rng.standard_normal(n), 75.0) * 1.4 * (0.75 + 0.25 * gusts)
    whistle = resonant_wind(seconds, 1750.0, 45.0, 0.09, 17) * 0.3 * gusts
    howl = resonant_wind(seconds, 700.0, 80.0, 0.06, 19) * 0.32 * (0.4 + 0.6 * gusts)
    snow = highpass(rng.standard_normal(n), 4200.0) * 0.05 * (0.6 + 0.4 * gusts)
    groans = np.zeros(n)
    for start in _sparse_events(n, 0.06, rng):
        length = int(SR * 2.4)
        end = min(start + length, n)
        tt = np.arange(end - start) / SR
        freq = rng.uniform(70.0, 110.0) * (1.0 + 0.25 * np.sin(2 * np.pi * 0.35 * tt))
        phase = 2 * np.pi * np.cumsum(freq) / SR
        voice = np.sign(np.sin(phase)) * 0.4 + np.sin(phase * 2.01) * 0.3
        groans[start:end] += voice * np.sin(np.pi * np.clip(tt / 2.4, 0, 1)) ** 2
    groans = bandpass(groans, 60.0, 600.0) * 0.5
    cracks = np.zeros(n)
    for start in _sparse_events(n, 0.08, rng):
        length = int(SR * 1.6)
        end = min(start + length, n)
        tt = np.arange(end - start) / SR
        ring = sum(np.sin(2 * np.pi * f * tt) for f in rng.uniform(300.0, 1600.0, 4)) * 0.25
        snap = rng.standard_normal(end - start) * np.exp(-tt / 0.008)
        cracks[start:end] += (snap * 0.8 + ring * np.exp(-tt / 0.35)) * rng.uniform(0.25, 0.6)
    cracks = reverb(highpass(cracks, 200.0), wet=0.6, seconds=3.2, damping=5000.0)
    chimes = np.zeros(n)
    for start in _sparse_events(n, 0.5, rng):
        length = int(SR * 0.9)
        end = min(start + length, n)
        tt = np.arange(end - start) / SR
        chimes[start:end] += np.sin(2 * np.pi * rng.uniform(2800.0, 5200.0) * tt) * np.exp(-tt / 0.25) * 0.08
    chimes = reverb(chimes, wet=0.7, seconds=2.5, damping=8000.0)
    mono = drone + howl + snow + groans
    left = mono + whistle + cracks[:, 0] + chimes[:, 0]
    right = mono + np.roll(whistle, int(SR * 1.3)) + cracks[:, 1] + chimes[:, 1]
    return np.stack([left, right], axis=1)


# --- Tidewater: the tide and the water -------------------------------------------------------------------

def render_tide_horn():
    """The flood warning: a long conch blast, breathy and low, swelling and bending up at the end, with the
    echo of the ruins behind it."""
    seconds = 3.4
    t = t_axis(seconds)
    bend = 1.0 + 0.04 * np.clip((t - 2.2) / 0.8, 0, 1) ** 2
    vibrato = 1.0 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.6) / 0.8, 0, 1)
    freq = 116.0 * bend * vibrato
    phase = 2 * np.pi * np.cumsum(freq) / SR
    tone = sum(np.sin(phase * h) * a for h, a in ((1, 1.0), (2, 0.55), (3, 0.42), (4, 0.2), (5, 0.16), (6, 0.08)))
    breath = bandpass(noise(len(t)), 300.0, 2400.0) * 0.18
    env = np.clip(t / 0.35, 0, 1) ** 1.5 * (0.8 + 0.2 * np.clip((t - 0.4) / 1.5, 0, 1)) * np.clip((seconds - 0.25 - t) / 0.7, 0, 1)
    mono = lowpass((tone * 0.5 + breath) * env, 2200.0)
    return limit_peak(normalize_rms(reverb(mono, wet=0.45, seconds=2.6, damping=2500.0), -15.0))


def _water_body(seconds, lo, hi, seed):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    body = bandpass(rng.standard_normal(n), lo, hi)
    gurgle = np.zeros(n)
    for start in _sparse_events(n, 9.0, rng):
        length = int(SR * rng.uniform(0.03, 0.09))
        end = min(start + length, n)
        tt = np.arange(end - start) / SR
        f = rng.uniform(250.0, 700.0) * (1.0 + 1.2 * tt / max(tt[-1], 1e-3) if len(tt) else 1.0)
        gurgle[start:end] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / max(tt[-1], 1e-3))
    return body, gurgle


def render_tide_surge():
    """The sea pouring into the ruins: a rushing roar that builds over the rise and churns with gurgles."""
    seconds = 5.2
    t = t_axis(seconds)
    body, gurgle = _water_body(seconds, 150.0, 2600.0, 61)
    roar = lowpass(noise(len(t)), 160.0) * 1.6
    rise = np.clip(t / 1.4, 0, 1) * np.clip((seconds - t) / 1.6, 0, 1)
    churn = 0.8 + 0.2 * np.sin(2 * np.pi * 1.7 * t) * np.sin(2 * np.pi * 0.6 * t)
    mono = (body * churn + roar + gurgle * 0.35) * rise
    return limit_peak(normalize_rms(stereoize(mono, 0.4), -17.0))


def render_tide_drain():
    """The sea draining back out: a falling hiss and trickle with gurgles that thin out."""
    seconds = 5.6
    t = t_axis(seconds)
    body, gurgle = _water_body(seconds, 400.0, 3800.0, 67)
    trickle = bandpass(noise(len(t)), 2500.0, 7000.0) * 0.4
    fall = np.clip(t / 0.5, 0, 1) * np.exp(-t / 2.4)
    mono = (body * 0.8 + trickle + gurgle * 0.5) * fall
    return limit_peak(normalize_rms(stereoize(mono, 0.4), -19.0))


def render_splash(seed):
    """Something hitting the water: a sharp slap, a spray of droplets and a short bubbly tail."""
    rng = np.random.default_rng(seed)
    seconds = 0.9
    t = t_axis(seconds)
    slap = bandpass(rng.standard_normal(len(t)), 500.0, 6000.0) * np.exp(-t / 0.05)
    spray = highpass(rng.standard_normal(len(t)), 2500.0) * np.exp(-t / 0.18) * 0.5
    bubbles = np.zeros(len(t))
    for start in _sparse_events(len(t), 22.0, rng):
        length = int(SR * rng.uniform(0.02, 0.05))
        end = min(start + length, len(t))
        tt = np.arange(end - start) / SR
        f = rng.uniform(500.0, 1100.0) * (1.0 + 2.0 * tt / 0.05)
        bubbles[start:end] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.015) * 0.4
    bubbles *= np.exp(-t / 0.3)
    body = lowpass(rng.standard_normal(len(t)), 300.0) * np.exp(-t / 0.08) * 1.2
    mono = slap + spray + bubbles + body
    return limit_peak(normalize_rms(stereoize(mono, 0.25), -16.0))


def render_swim(seed):
    """One swimming stroke: a soft low swish of water."""
    rng = np.random.default_rng(seed)
    seconds = 0.45
    t = t_axis(seconds)
    swish = bandpass(rng.standard_normal(len(t)), 250.0, 1800.0) * np.sin(np.pi * np.clip(t / seconds, 0, 1)) ** 2
    return limit_peak(normalize_rms(stereoize(swish, 0.2), -24.0))


# --- Rimefall: the ice -------------------------------------------------------------------------------------

def render_ice_skid():
    """Boots skating over glare ice: a gritty bright scrape that fades as the slide slows."""
    rng = np.random.default_rng(83)
    seconds = 0.7
    t = t_axis(seconds)
    grit = np.zeros(len(t))
    hits = rng.random(len(t)) < 0.05
    grit[hits] = rng.uniform(-1.0, 1.0, int(hits.sum()))
    scrape = bandpass(rng.standard_normal(len(t)), 1800.0, 6500.0) * 0.6 + bandpass(grit, 2500.0, 9000.0) * 1.4
    scrape *= 0.75 + 0.25 * np.sin(2 * np.pi * 31.0 * t)
    env = np.clip(t / 0.02, 0, 1) * np.exp(-t / 0.28)
    return limit_peak(normalize_rms(stereoize(scrape * env, 0.2), -19.0))


def render_step_ice(seed):
    """A footstep on ice: a crisp click with a short glassy ring."""
    rng = np.random.default_rng(seed)
    seconds = 0.22
    t = t_axis(seconds)
    click = highpass(rng.standard_normal(len(t)), 1500.0) * np.exp(-t / 0.006)
    ring = sum(np.sin(2 * np.pi * f * t) for f in rng.uniform(2200.0, 4600.0, 3)) * np.exp(-t / 0.04) * 0.12
    thud = lowpass(rng.standard_normal(len(t)), 250.0) * np.exp(-t / 0.02) * 0.5
    return limit_peak(normalize_rms(stereoize(click + ring + thud, 0.1), -22.0))


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
        "tide_horn.wav": render_tide_horn,
        "tide_surge.wav": render_tide_surge,
        "tide_drain.wav": render_tide_drain,
        "ice_skid.wav": render_ice_skid,
    }
    for index in range(3):
        renders["splash_%d.wav" % index] = lambda seed=index: render_splash(500 + seed)
        renders["swim_%d.wav" % index] = lambda seed=index: render_swim(600 + seed)
        renders["step_ice_%d.wav" % index] = lambda seed=index: render_step_ice(700 + seed)
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
    for world, render in (("tidewater", render_tidewater_ambience), ("rimefall", render_rimefall_ambience)):
        name = "ambience_%s.ogg" % world
        if not only or name in only:
            loop = make_seamless(render, 40.0)
            write_ogg(normalize_rms(loop, -24.0), os.path.join(MUSIC_DIR, name))
            print("rendered", name)


if __name__ == "__main__":
    main()
