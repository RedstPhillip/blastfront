"""Small offline synthesizer used to render Blastfront's original music and ambience.

Everything here is generated from scratch (oscillators, noise, envelopes, filters, convolution reverb),
so the output is fully owned by the project. Run `python tools/music/render_all.py` to re-render.
"""
import subprocess
import wave

import numpy as np
from scipy import signal

SR = 44100
RNG = np.random.default_rng(1337)


def note_hz(name: str) -> float:
    names = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
             "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
    pitch, octave = (name[:-1], int(name[-1]))
    midi = 12 * (octave + 1) + names[pitch]
    return 440.0 * 2 ** ((midi - 69) / 12)


def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * SR)) / SR


def saw(freq, t, detune_cents=0.0):
    f = freq * 2 ** (detune_cents / 1200)
    phase = (f * t + RNG.random()) % 1.0
    return 2.0 * phase - 1.0


def supersaw(freq, t, voices=5, spread=14.0):
    out = np.zeros_like(t)
    for i in range(voices):
        cents = (i - (voices - 1) / 2) * spread / max(voices - 1, 1) * 2
        out += saw(freq, t, cents)
    return out / voices


def sine(freq, t, phase=0.0):
    return np.sin(2 * np.pi * freq * t + phase)


def tri(freq, t):
    return 2 * np.abs(2 * ((freq * t) % 1.0) - 1) - 1


def square(freq, t, duty=0.5):
    return np.where((freq * t) % 1.0 < duty, 1.0, -1.0)


def adsr(n, a=0.01, d=0.1, s=0.7, r=0.2, sustain_len=None):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    if sustain_len is None:
        sustain_len = max(n - a_n - d_n - r_n, 0)
    env = np.concatenate([
        np.linspace(0, 1, max(a_n, 1)),
        np.linspace(1, s, max(d_n, 1)),
        np.full(max(sustain_len, 0), s),
        np.linspace(s, 0, max(r_n, 1)),
    ])
    if len(env) < n:
        env = np.concatenate([env, np.zeros(n - len(env))])
    return env[:n]


def perc_env(n, decay):
    t = np.arange(n) / SR
    return np.exp(-t / decay)


def lowpass(x, cutoff, order=2):
    b, a = signal.butter(order, min(cutoff / (SR / 2), 0.99), "low")
    return signal.lfilter(b, a, x)


def highpass(x, cutoff, order=2):
    b, a = signal.butter(order, min(cutoff / (SR / 2), 0.99), "high")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], "band")
    return signal.lfilter(b, a, x)


def sweep_lowpass(x, start, end, blocks=64):
    """Time-varying lowpass by processing in blocks with interpolated cutoff."""
    out = np.zeros_like(x)
    size = int(np.ceil(len(x) / blocks))
    zi = None
    for i in range(blocks):
        seg = x[i * size:(i + 1) * size]
        if len(seg) == 0:
            break
        cutoff = start * (end / start) ** (i / max(blocks - 1, 1))
        b, a = signal.butter(2, min(cutoff / (SR / 2), 0.99), "low")
        if zi is None:
            zi = signal.lfilter_zi(b, a) * seg[0]
        seg_out, zi = signal.lfilter(b, a, seg, zi=zi)
        out[i * size:i * size + len(seg)] = seg_out
    return out


def reverb_ir(seconds=2.4, damping=4000.0, stereo_seed=0):
    rng = np.random.default_rng(stereo_seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    noise = lowpass(noise, damping)
    ir = noise * np.exp(-t * (6.9 / seconds))
    ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
    return ir / np.sqrt(np.sum(ir ** 2))


def reverb(x, wet=0.25, seconds=2.4, damping=4000.0):
    left = signal.fftconvolve(x, reverb_ir(seconds, damping, 1))[: len(x)]
    right = signal.fftconvolve(x, reverb_ir(seconds, damping, 2))[: len(x)]
    dry = np.stack([x, x], axis=1)
    return dry * (1 - wet * 0.5) + np.stack([left, right], axis=1) * wet


def delay(x, seconds, feedback=0.35, mix=0.3, taps=6):
    out = x.copy()
    d = int(seconds * SR)
    gain = mix
    for i in range(1, taps + 1):
        shifted = np.zeros_like(x)
        shifted[d * i:] = x[: len(x) - d * i] if d * i < len(x) else 0
        out += shifted * gain
        gain *= feedback
    return out


def pan(mono, position):
    angle = (position + 1) * np.pi / 4
    return np.stack([mono * np.cos(angle), mono * np.sin(angle)], axis=1)


def place(track, clip, start_sample):
    end = min(start_sample + len(clip), len(track))
    if start_sample >= len(track):
        return
    track[start_sample:end] += clip[: end - start_sample]


def soft_limit(stereo, drive=1.2):
    return np.tanh(stereo * drive) / np.tanh(drive)


def normalize_rms(stereo, target_db=-16.0):
    rms = np.sqrt(np.mean(stereo ** 2))
    gain = 10 ** (target_db / 20) / max(rms, 1e-9)
    out = stereo * gain
    peak = np.max(np.abs(out))
    if peak > 0.97:
        out *= 0.97 / peak
    return out


def make_seamless(render_fn, loop_seconds):
    """Render two cycles and keep the second, so reverb/delay tails wrap around the loop point."""
    full = render_fn(loop_seconds * 2)
    n = int(loop_seconds * SR)
    loop = full[n:2 * n].copy()
    fade = int(0.03 * SR)
    ramp = np.linspace(0.0, 1.0, fade)[:, None] if loop.ndim == 2 else np.linspace(0.0, 1.0, fade)
    # The audio that originally led into loop[0] is full[n - fade:n]; blend the loop end into it.
    loop[-fade:] = loop[-fade:] * (1.0 - ramp) + full[n - fade:n] * ramp
    return loop


def write_ogg(stereo, path, quality=6):
    import shutil
    if shutil.which("ffmpeg") is None:
        # No ffmpeg on this machine: libsndfile (via soundfile) writes Ogg Vorbis directly.
        import soundfile
        soundfile.write(path, np.clip(stereo, -1, 1), SR, format="OGG", subtype="VORBIS")
        return
    wav_path = path.replace(".ogg", ".tmp.wav")
    data = np.clip(stereo, -1, 1)
    pcm = (data * 32767).astype(np.int16)
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
    import os
    os.remove(wav_path)


# --- Instruments ------------------------------------------------------------------------------

def kick(length=0.45, punch=1.0):
    t = t_axis(length)
    freq = 45 + 110 * np.exp(-t / 0.035)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    body = np.sin(phase) * perc_env(len(t), 0.16)
    click = highpass(RNG.standard_normal(len(t)), 2000) * perc_env(len(t), 0.004) * 0.25
    return (body + click) * punch


def snare(length=0.3):
    t = t_axis(length)
    tone = (sine(185, t) + 0.5 * sine(330, t)) * perc_env(len(t), 0.05) * 0.6
    noise = bandpass(RNG.standard_normal(len(t)), 900, 9000) * perc_env(len(t), 0.11)
    return tone + noise * 0.9


def clap(length=0.3):
    t = t_axis(length)
    env = np.zeros(len(t))
    for offset in (0.0, 0.011, 0.022):
        o = int(offset * SR)
        env[o:] += perc_env(len(t) - o, 0.012 if offset < 0.02 else 0.09)
    return bandpass(RNG.standard_normal(len(t)), 1100, 6000) * env * 0.8


def hat(length=0.08, open_hat=False):
    t = t_axis(0.35 if open_hat else length)
    noise = highpass(RNG.standard_normal(len(t)), 7000)
    return noise * perc_env(len(t), 0.12 if open_hat else 0.022) * 0.5


def bass_note(freq, length, cutoff=700.0):
    t = t_axis(length)
    raw = saw(freq, t) * 0.6 + square(freq * 0.5, t) * 0.4
    filt = sweep_lowpass(raw, cutoff * 2.2, cutoff, blocks=16)
    return filt * adsr(len(t), 0.005, 0.12, 0.75, 0.06)


def pluck(freq, length, brightness=3200.0):
    t = t_axis(length)
    raw = saw(freq, t) * 0.5 + tri(freq * 2, t) * 0.3
    filt = sweep_lowpass(raw, brightness, 400, blocks=12)
    return filt * perc_env(len(t), length * 0.35)


def pad_chord(freqs, length, cutoff=1800.0, attack=0.6, release=0.8):
    t = t_axis(length)
    out = np.zeros(len(t))
    for f in freqs:
        out += supersaw(f, t, voices=5, spread=10.0)
    out /= max(len(freqs), 1)
    out = lowpass(out, cutoff)
    return out * adsr(len(t), attack, 0.4, 0.85, release)


def keys_chord(freqs, length):
    """Soft electric-piano-like tone (sine + bell harmonic, slow decay)."""
    t = t_axis(length)
    out = np.zeros(len(t))
    for f in freqs:
        out += sine(f, t) * 0.7 + sine(f * 2, t) * 0.18 * np.exp(-t / 0.25) + sine(f * 3.01, t) * 0.06 * np.exp(-t / 0.12)
    out /= max(len(freqs), 1)
    trem = 1 + 0.08 * np.sin(2 * np.pi * 4.5 * t)
    return out * trem * adsr(len(t), 0.004, 0.6, 0.5, 0.5)
