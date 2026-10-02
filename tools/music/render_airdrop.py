"""Renders the supply drop's sound set into assets/audio/sfx/.

uv run --no-project --with numpy --with scipy --with soundfile python tools/music/render_airdrop.py

The drop is one event told in sound: a radio double-chirp and a transport passing high overhead
(anticipation), the canopy snapping open and fluttering down (arrival), a heavy crate landing in dirt
(impact), latches springing open one by one while it is captured (interaction), a pressure release and
the lid coming off (opening) and a warm three-note chime with ticks for each research point (reward).
Everything is built from noise, oscillators, filters and a convolution reverb, so it is owned outright.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from synth import SR, bandpass, highpass, lowpass, normalize_rms, perc_env, reverb, t_axis, write_ogg

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")
RNG = np.random.default_rng(4401)


def noise(n):
    return RNG.standard_normal(n)


def env_ar(n, attack, release_tau):
    t = np.arange(n) / SR
    return np.clip(t / max(attack, 1e-4), 0, 1) * np.exp(-np.maximum(t - attack, 0) / release_tau)


def thump(seconds, start_hz, end_hz, decay, glide=0.05):
    t = t_axis(seconds)
    freq = end_hz + (start_hz - end_hz) * np.exp(-t / glide)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * perc_env(len(t), decay)


def metal(seconds, partials, decay, seed=0):
    """Inharmonic partials with their own decays and a little random phase: struck steel."""
    rng = np.random.default_rng(seed)
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for index, (freq, amp) in enumerate(partials):
        tau = decay * (1.0 - 0.13 * index)
        out += np.sin(2 * np.pi * freq * t + rng.random() * 6.28) * amp * np.exp(-t / max(tau, 0.005))
    return out


def fm_bell(freq, seconds, index=2.2, ratio=1.4, decay=0.6):
    """Soft FM bell: the modulation index falls faster than the tone, so it starts glassy and ends pure."""
    t = t_axis(seconds)
    mod = np.sin(2 * np.pi * freq * ratio * t) * index * np.exp(-t / (decay * 0.35))
    tone = np.sin(2 * np.pi * freq * t + mod) * np.exp(-t / decay)
    return tone * np.clip(t / 0.004, 0, 1)


def stereo_width(mono, width=0.15, delay_ms=0.6):
    d = max(1, int(delay_ms * 0.001 * SR))
    right = np.concatenate([np.zeros(d), mono[:-d]])
    left = mono * (1.0 + width) - right * width
    return np.stack([left, right], axis=1)


def place(track, clip, at_seconds, gain=1.0):
    start = int(at_seconds * SR)
    end = min(start + len(clip), len(track))
    if start < len(track):
        track[start:end] += clip[: end - start] * gain


def fade_tail(x, seconds=0.05):
    n = int(seconds * SR)
    ramp = np.linspace(1.0, 0.0, n)
    if x.ndim == 2:
        ramp = ramp[:, None]
    x[-n:] *= ramp
    return x


def finish(stereo, rms_db, peak=0.8):
    out = normalize_rms(stereo, rms_db)
    current = np.max(np.abs(out))
    return fade_tail(out * min(1.0, peak / max(current, 1e-9)))


# --- Anticipation ---------------------------------------------------------------------------------

def render_alert():
    """Radio double-chirp: key-up click and hiss, two clean tones through a radio band, squelch tail."""
    seconds = 0.95
    total = np.zeros(int(seconds * SR))
    key = bandpass(noise(int(0.05 * SR)), 900.0, 4500.0) * env_ar(int(0.05 * SR), 0.001, 0.012)
    place(total, key, 0.0, 0.5)
    hiss = bandpass(noise(int(0.09 * SR)), 1200.0, 5000.0) * 0.06
    place(total, hiss, 0.01)
    for at, freq in ((0.07, 1046.5), (0.21, 1568.0)):
        n = int(0.11 * SR)
        t = t_axis(0.11)
        tone = np.sin(2 * np.pi * freq * t) + 0.18 * np.sin(2 * np.pi * freq * 3 * t) + 0.06 * np.sin(2 * np.pi * freq * 5 * t)
        shape = np.clip(t / 0.008, 0, 1) * np.clip((0.11 - t) / 0.035, 0, 1) ** 1.5
        place(total, tone * shape, at, 0.4)
    squelch = bandpass(noise(int(0.16 * SR)), 1500.0, 6000.0) * env_ar(int(0.16 * SR), 0.004, 0.05)
    place(total, squelch, 0.34, 0.35)
    radio = np.tanh(bandpass(total, 420.0, 3600.0) * 1.15)
    return finish(reverb(radio, wet=0.12, seconds=0.9, damping=5000.0), -20.0)


def render_flyover():
    """A transport passing high overhead: two slightly detuned engines with propeller beat, far away
    (dull), sweeping left to right with a small Doppler drop and an outdoor tail."""
    seconds = 5.2
    t = t_axis(seconds)
    progress = t / seconds
    pitch = 1.0 - 0.05 * (1.0 / (1.0 + np.exp(-(progress - 0.5) * 9.0)))
    engines = np.zeros_like(t)
    for detune, gain in ((1.0, 1.0), (1.013, 0.8)):
        f0 = 41.0 * detune * pitch
        phase = 2 * np.pi * np.cumsum(f0) / SR
        for harmonic, amp in ((1, 1.0), (2, 0.7), (3, 0.45), (4, 0.3), (6, 0.18), (8, 0.1)):
            engines += np.sin(phase * harmonic + harmonic) * amp * gain
    beat = 0.65 + 0.35 * np.sin(2 * np.pi * np.cumsum(17.5 * pitch) / SR) ** 2
    rumble = bandpass(noise(len(t)), 60.0, 420.0) * 1.6
    body = (engines * 0.5 + rumble) * beat
    distance = np.exp(-((progress - 0.48) ** 2) / 0.06)
    # Air absorption: the closest moment is the brightest.
    near = lowpass(body, 700.0)
    far = lowpass(body, 260.0)
    mono = (far * (1.0 - distance) + near * distance) * (0.15 + 0.85 * distance)
    mono *= np.clip(t / 0.6, 0, 1)
    pan_position = np.clip((progress - 0.5) * 1.6, -0.8, 0.8)
    angle = (pan_position + 1) * np.pi / 4
    stereo = np.stack([mono * np.cos(angle), mono * np.sin(angle)], axis=1)
    wet = reverb(mono, wet=0.35, seconds=2.6, damping=1800.0) - np.stack([mono, mono], axis=1) * (1 - 0.35 * 0.5)
    return finish(stereo + wet * 0.8, -22.0)


# --- Arrival --------------------------------------------------------------------------------------

def render_chute():
    """Canopy snapping open: a sharp cloth crack, a low whump of air and a short flutter."""
    seconds = 0.9
    n = int(seconds * SR)
    t = t_axis(seconds)
    total = np.zeros(n)
    crack = bandpass(noise(int(0.08 * SR)), 350.0, 3200.0) * env_ar(int(0.08 * SR), 0.0015, 0.018)
    place(total, crack, 0.0, 1.0)
    crack2 = bandpass(noise(int(0.06 * SR)), 500.0, 2600.0) * env_ar(int(0.06 * SR), 0.001, 0.012)
    place(total, crack2, 0.035, 0.55)
    whump = lowpass(noise(n), 260.0) * env_ar(n, 0.012, 0.11) * 2.2
    total += whump
    flutter_rate = 22.0 + 6.0 * np.sin(2 * np.pi * 3.0 * t)
    flutter = 0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(flutter_rate) / SR)
    total += bandpass(noise(n), 250.0, 1600.0) * flutter * env_ar(n, 0.04, 0.22) * 0.5
    return finish(stereo_width(total, 0.2), -17.0)


def render_descent():
    """Wind across the canopy while it sinks: band-limited air with an irregular flutter, growing as it
    comes closer. Short fades so the landing can cut it."""
    seconds = 4.4
    n = int(seconds * SR)
    t = t_axis(seconds)
    rate = 11.0 + 5.0 * np.sin(2 * np.pi * 0.7 * t) + 3.0 * np.sin(2 * np.pi * 1.9 * t + 1.3)
    flutter = 0.72 + 0.28 * np.sin(2 * np.pi * np.cumsum(rate) / SR)
    air = bandpass(noise(n), 180.0, 950.0) * flutter
    whistle = bandpass(noise(n), 1100.0, 1500.0) * 0.18 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.4 * t))
    swell = 0.35 + 0.65 * (t / seconds) ** 1.4
    mono = lowpass(lowpass((air + whistle) * swell, 1100.0), 1600.0)
    mono *= np.clip(t / 0.25, 0, 1) * np.clip((seconds - t) / 0.12, 0, 1)
    return finish(stereo_width(mono, 0.35, 1.1), -24.0)


# --- Impact ---------------------------------------------------------------------------------------

def render_impact():
    """A heavy crate into dirt: sub thump, a burst of earth, the steel frame ringing and rattling as it
    settles, a scatter of pebbles and a slow dust exhale."""
    seconds = 1.8
    total = np.zeros(int(seconds * SR))
    place(total, thump(0.6, 82.0, 36.0, 0.21, 0.04), 0.0, 1.5)
    earth = lowpass(noise(int(0.4 * SR)), 380.0) * env_ar(int(0.4 * SR), 0.002, 0.07) * 2.0
    place(total, earth, 0.0)
    crunch = bandpass(noise(int(0.12 * SR)), 900.0, 4200.0) * env_ar(int(0.12 * SR), 0.001, 0.025)
    place(total, crunch, 0.004, 0.6)
    frame = metal(0.6, [(176.0, 0.7), (411.0, 0.5), (689.0, 0.35), (1127.0, 0.22), (1730.0, 0.12)], 0.16, 3)
    place(total, frame, 0.006, 0.55)
    settle = metal(0.4, [(203.0, 0.5), (466.0, 0.35), (771.0, 0.22)], 0.09, 5)
    place(total, settle, 0.11, 0.35)
    place(total, thump(0.2, 120.0, 60.0, 0.05), 0.11, 0.5)
    rng = np.random.default_rng(9)
    for _ in range(9):
        at = 0.06 + rng.random() * 0.5
        tick = highpass(noise(int(0.012 * SR)), 2200.0) * env_ar(int(0.012 * SR), 0.0005, 0.003)
        place(total, tick, at, 0.12 + rng.random() * 0.12)
    dust_n = int(1.3 * SR)
    dust = bandpass(noise(dust_n), 300.0, 1700.0) * env_ar(dust_n, 0.03, 0.42) * 0.42
    place(total, dust, 0.02)
    wet = reverb(total, wet=0.16, seconds=1.4, damping=2400.0)
    return finish(wet, -14.0, 0.9)


# --- Capture and opening --------------------------------------------------------------------------

def render_latch():
    """One latch springing open: a click, a spring tink and a small thunk of the clasp."""
    seconds = 0.26
    total = np.zeros(int(seconds * SR))
    click = highpass(noise(int(0.004 * SR)), 2800.0) * np.linspace(1.0, 0.0, int(0.004 * SR))
    place(total, click, 0.0, 0.9)
    place(total, metal(0.22, [(2110.0, 0.5), (3380.0, 0.32), (4925.0, 0.16)], 0.035, 7), 0.002, 0.45)
    place(total, thump(0.06, 330.0, 160.0, 0.018, 0.01), 0.012, 0.6)
    clack = bandpass(noise(int(0.02 * SR)), 1400.0, 5200.0) * env_ar(int(0.02 * SR), 0.0006, 0.004)
    place(total, clack, 0.024, 0.5)
    return finish(stereo_width(total, 0.12), -19.0)


def render_open():
    """The crate opens: a pressure seal hisses out, the lid pops with a steel clank, and lands beside it."""
    seconds = 1.4
    total = np.zeros(int(seconds * SR))
    hiss_n = int(0.6 * SR)
    hiss = bandpass(noise(hiss_n), 2200.0, 9000.0) * env_ar(hiss_n, 0.004, 0.16)
    place(total, hiss, 0.0, 0.5)
    place(total, thump(0.25, 140.0, 62.0, 0.07), 0.01, 0.9)
    place(total, metal(0.6, [(248.0, 0.6), (523.0, 0.42), (871.0, 0.3), (1402.0, 0.18), (2210.0, 0.1)], 0.2, 11), 0.012, 0.5)
    place(total, metal(0.35, [(301.0, 0.5), (640.0, 0.3), (1050.0, 0.2)], 0.08, 13), 0.56, 0.3)
    place(total, lowpass(noise(int(0.12 * SR)), 500.0) * env_ar(int(0.12 * SR), 0.002, 0.03), 0.56, 0.6)
    wet = reverb(total, wet=0.14, seconds=1.2, damping=3000.0)
    return finish(wet, -16.0)


# --- Reward ---------------------------------------------------------------------------------------

def render_reward():
    """Research secured: three soft FM bells rising a fifth and an octave, with a faint glassy shimmer."""
    seconds = 1.8
    total = np.zeros(int(seconds * SR))
    for at, freq, gain in ((0.0, 659.25, 0.8), (0.085, 987.77, 0.7), (0.17, 1318.5, 0.62)):
        place(total, fm_bell(freq, 1.4, index=1.6, ratio=1.41, decay=0.55), at, gain)
        place(total, fm_bell(freq * 2.0, 0.6, index=0.8, ratio=2.0, decay=0.18), at, gain * 0.18)
    t = t_axis(seconds)
    shimmer = sum(np.sin(2 * np.pi * f * t + i) for i, f in enumerate((2637.0, 2649.0, 3951.0))) * 0.04
    total += shimmer * np.clip(t / 0.2, 0, 1) * np.exp(-t / 0.5)
    wet = reverb(lowpass(total, 7000.0), wet=0.3, seconds=1.6, damping=6000.0)
    return finish(wet, -21.0)


def render_tick():
    """One research point arriving: a short glassy tick, pitched up by the game for each token."""
    seconds = 0.32
    total = fm_bell(1567.98, seconds, index=1.2, ratio=2.76, decay=0.07)
    total += fm_bell(3135.96, seconds, index=0.4, ratio=1.0, decay=0.03) * 0.25
    return finish(stereo_width(total, 0.1), -24.0)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    renders = {
        "airdrop_alert.ogg": render_alert,
        "airdrop_flyover.ogg": render_flyover,
        "airdrop_chute.ogg": render_chute,
        "airdrop_descent.ogg": render_descent,
        "airdrop_impact.ogg": render_impact,
        "airdrop_latch.ogg": render_latch,
        "airdrop_open.ogg": render_open,
        "research_reward.ogg": render_reward,
        "research_tick.ogg": render_tick,
    }
    only = set(sys.argv[1:])
    for name, render in renders.items():
        if only and name not in only:
            continue
        path = os.path.join(OUT_DIR, name)
        write_ogg(render(), path)
        print("wrote", os.path.relpath(path))


if __name__ == "__main__":
    main()
