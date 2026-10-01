"""Renders Blastfront's original soundtrack into assets/audio/music/.

python tools/music/render_all.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from synth import (SR, RNG, adsr, bass_note, bandpass, clap, delay, hat, highpass, keys_chord, kick, lowpass,
                   make_seamless, normalize_rms, note_hz, pad_chord, pan, place, pluck, reverb, sine, snare,
                   soft_limit, square, t_axis, write_ogg)

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "music")


def chord(names):
    return [note_hz(n) for n in names]


def sidechain_envelope(total, kick_times, depth=0.55, release=0.22):
    env = np.ones(total)
    rel = int(release * SR)
    curve = 1 - depth * np.exp(-np.arange(rel) / (rel * 0.35))
    for start in kick_times:
        s = int(start * SR)
        e = min(s + rel, total)
        if s < total:
            env[s:e] = np.minimum(env[s:e], curve[: e - s])
    return env


# --- Battle -------------------------------------------------------------------------------

def render_battle(seconds):
    bpm = 120.0
    beat = 60.0 / bpm
    bar = beat * 4
    total = int(seconds * SR)
    drums = np.zeros(total)
    bass = np.zeros(total)
    pads = np.zeros(total)
    arps = np.zeros(total)
    stabs = np.zeros(total)
    progression = [
        (["A2"], ["A3", "C4", "E4"]), (["F2"], ["F3", "A3", "C4"]),
        (["C3"], ["C4", "E4", "G4"]), (["G2"], ["G3", "B3", "D4"]),
        (["A2"], ["A3", "C4", "E4"]), (["F2"], ["F3", "A3", "C4"]),
        (["D3"], ["D4", "F4", "A4"]), (["E2"], ["E3", "G#3", "B3"]),
    ]
    kick_times = []
    bars = int(seconds / bar)
    for b in range(bars):
        section = b % 16
        root_names, chord_names = progression[(section // 2) % len(progression)]
        start = b * bar
        root = note_hz(root_names[0])
        # drums
        for k in (0.0, 1.5, 2.0, 2.75) if section % 4 == 3 else (0.0, 1.5, 2.0):
            place(drums, kick(punch=1.0), int((start + k * beat) * SR))
            kick_times.append(start + k * beat)
        for s in (1.0, 3.0):
            place(drums, snare() * 0.85 + clap() * 0.5, int((start + s * beat) * SR))
        for i in range(16):
            accent = 1.0 if i % 4 == 2 else 0.55
            place(drums, hat() * accent * 0.7, int((start + i * beat / 4) * SR))
        place(drums, hat(open_hat=True) * 0.45, int((start + 3.5 * beat) * SR))
        if section in (7, 15):
            for i in range(8):
                place(drums, snare() * (0.35 + i * 0.07), int((start + 2 * beat + i * beat / 4) * SR))
        # bass ostinato (eighths)
        pattern = [1, 1, 2, 1, 1, 1, 2, 1]
        for i, mult in enumerate(pattern):
            place(bass, bass_note(root * mult, beat / 2 * 0.92, cutoff=600 + 300 * (i % 2)) * 0.9, int((start + i * beat / 2) * SR))
        # pads every two bars
        if section % 2 == 0:
            place(pads, pad_chord(chord(chord_names), bar * 2, cutoff=1500.0, attack=0.25, release=0.5), int(start * SR))
            stab_t = t_axis(0.35)
            stab = np.zeros(len(stab_t))
            for f in chord(chord_names):
                stab += square(f * 2, stab_t, 0.4)
            stab = lowpass(stab / 3, 2500) * np.exp(-stab_t / 0.12)
            place(stabs, stab * 0.55, int(start * SR))
        # arps in second half
        if section >= 8:
            notes = chord(chord_names) + [chord(chord_names)[0] * 2]
            for i in range(16):
                f = notes[i % len(notes)] * 2
                place(arps, pluck(f, beat / 4 * 0.95, 4200) * 0.5, int((start + i * beat / 4) * SR))
    side = sidechain_envelope(total, kick_times, 0.6, 0.24)
    pads *= side
    bass *= 0.6 + 0.4 * side
    arps = delay(arps * side, beat * 0.75, 0.32, 0.35)
    mix = (
        pan(drums, 0.0) * 0.85
        + pan(bass, 0.0) * 0.7
        + reverb(pads * 0.55, 0.35, 2.2, 3500)
        + reverb(arps * 0.35, 0.3, 1.6, 5000) * np.array([0.8, 1.0])
        + reverb(stabs, 0.25, 1.4, 4000) * np.array([1.0, 0.85])
    )
    mix = highpass(mix.T, 28).T
    return soft_limit(mix, 1.15)


# --- Menu ---------------------------------------------------------------------------------

def render_menu(seconds):
    bpm = 84.0
    beat = 60.0 / bpm
    bar = beat * 4
    total = int(seconds * SR)
    pads = np.zeros(total)
    keys = np.zeros(total)
    sub = np.zeros(total)
    lead = np.zeros(total)
    perc = np.zeros(total)
    shimmer = np.zeros(total)
    progression = [
        (["A1"], ["A3", "B3", "C4", "E4"]),
        (["F1"], ["F3", "A3", "C4", "E4"]),
        (["C2"], ["C4", "E4", "G4", "B4"]),
        (["G1"], ["G3", "C4", "D4", "G4"]),
    ]
    melody = ["E5", None, "D5", "C5", None, "B4", "C5", None, "A4", None, None, "G4", "A4", None, "C5", "B4"]
    bars = int(seconds / bar)
    for b in range(bars):
        section = b % 16
        root_names, chord_names = progression[(section // 2) % len(progression)]
        start = b * bar
        if section % 2 == 0:
            place(pads, pad_chord(chord(chord_names), bar * 2, cutoff=1900.0, attack=1.2, release=1.5), int(start * SR))
            if section >= 8:
                place(shimmer, pad_chord([f * 4 for f in chord(chord_names)], bar * 2, cutoff=7000.0, attack=1.6, release=1.6) * 0.18, int(start * SR))
            sub_t = t_axis(bar * 2)
            place(sub, sine(note_hz(root_names[0]) * 2, sub_t) * adsr(len(sub_t), 0.4, 0.5, 0.8, 1.0) * 0.7, int(start * SR))
        freqs = chord(chord_names)
        for i, step in enumerate([0, 2, 1, 3, 2, 1, 0, 2]):
            place(keys, keys_chord([freqs[step] * 2], beat * 0.9) * 0.45, int((start + i * beat / 2) * SR))
        place(perc, kick(0.4, 0.45), int(start * SR))
        place(perc, hat(open_hat=True) * 0.18, int((start + 2 * beat) * SR))
        if section >= 8:
            for i in range(4):
                note = melody[((section - 8) * 4 + i) % len(melody)]
                if note is None:
                    continue
                t = t_axis(beat * 1.6)
                f = note_hz(note)
                vib = 1 + 0.004 * np.sin(2 * np.pi * 5.0 * t)
                tone = (sine(f * vib, t) * 0.7 + sine(f * 2, t) * 0.12) * adsr(len(t), 0.06, 0.3, 0.6, 0.5)
                place(lead, tone * 0.42, int((start + i * beat) * SR))
    keys = delay(keys, beat * 0.75, 0.42, 0.4)
    lead = delay(lead, beat * 1.5, 0.35, 0.35)
    air = bandpass(RNG.standard_normal(total), 2500, 9000) * 0.03
    mix = (
        reverb(pads * 0.6, 0.55, 3.8, 2500)
        + reverb(keys * 0.5, 0.45, 3.2, 4500) * np.array([1.0, 0.8])
        + pan(sub * 0.55, 0.0)
        + reverb(lead, 0.6, 4.0, 5000) * np.array([0.85, 1.0])
        + reverb(shimmer, 0.7, 4.5, 8000) * np.array([1.0, 0.9])
        + pan(perc * 0.6, 0.0)
        + pan(air, 0.0)
    )
    mix = highpass(mix.T, 24).T
    return soft_limit(mix, 1.05)


# --- Locker -------------------------------------------------------------------------------

def render_locker(seconds):
    bpm = 90.0
    beat = 60.0 / bpm
    bar = beat * 4
    total = int(seconds * SR)
    keys = np.zeros(total)
    drums = np.zeros(total)
    bass = np.zeros(total)
    progression = [
        (["D2"], ["D4", "F4", "A4", "C5", "E5"]),
        (["G1"], ["F4", "A4", "B4", "E5"]),
        (["C2"], ["E4", "G4", "B4", "D5"]),
        (["A1"], ["E4", "G4", "C5", "D5"]),
    ]
    swing = beat * 0.08
    bars = int(seconds / bar)
    for b in range(bars):
        root_names, chord_names = progression[b % len(progression)]
        start = b * bar
        place(keys, keys_chord(chord(chord_names), bar * 0.95) * 0.9, int(start * SR))
        place(keys, keys_chord(chord(chord_names[1:]), beat * 1.2) * 0.4, int((start + 2.5 * beat + swing) * SR))
        place(drums, kick(0.4, 0.8), int(start * SR))
        place(drums, kick(0.4, 0.6), int((start + 2.5 * beat + swing) * SR))
        place(drums, snare() * 0.6, int((start + beat) * SR))
        place(drums, snare() * 0.6, int((start + 3 * beat) * SR))
        for i in range(8):
            offset = swing if i % 2 == 1 else 0.0
            place(drums, hat() * (0.35 if i % 2 else 0.5), int((start + i * beat / 2 + offset) * SR))
        root = note_hz(root_names[0]) * 2
        for i, (pos, mult) in enumerate([(0.0, 1), (1.5, 1), (2.5, 1.5), (3.0, 1)]):
            place(bass, bass_note(root * mult, beat * 0.8, 420) * 0.8, int((start + pos * beat) * SR))
    crackle = np.zeros(total)
    pops = RNG.integers(0, total, int(seconds * 14))
    crackle[pops] = RNG.uniform(0.1, 0.4, len(pops))
    crackle = highpass(crackle, 3000) * 0.5 + lowpass(RNG.standard_normal(total), 4000) * 0.004
    keys = lowpass(keys, 3200)
    mix = (
        reverb(keys * 0.6, 0.35, 2.0, 3000)
        + pan(lowpass(drums, 6000) * 0.55, 0.0)
        + pan(bass * 0.5, 0.0)
        + pan(crackle, 0.1)
    )
    mix = highpass(mix.T, 30).T
    return soft_limit(mix, 1.1)


# --- Ambience -----------------------------------------------------------------------------

def render_wind(seconds):
    total = int(seconds * SR)
    t = np.arange(total) / SR
    white = RNG.standard_normal(total)
    low = lowpass(white, 420, 2)
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / 11.0 + 0.6) * np.sin(2 * np.pi * t / 4.3)
    whistle = bandpass(RNG.standard_normal(total), 900, 1600) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 7.0)) * 0.12
    crickets = np.zeros(total)
    for start in np.arange(0.5, seconds, 1.9):
        for chirp in range(3):
            s = int((start + chirp * 0.11 + RNG.uniform(0, 0.03)) * SR)
            ct = t_axis(0.05)
            tone = sine(4600 + RNG.uniform(-80, 80), ct) * np.sin(np.pi * np.arange(len(ct)) / len(ct)) ** 2
            place(crickets, tone * 0.05 * RNG.uniform(0.5, 1.0), s)
    left = low * gust * 0.8 + whistle
    right = np.roll(low, 2205) * gust[::-1] * 0.8 + np.roll(whistle, 4410)
    stereo = np.stack([left, right], axis=1) + pan(delay(crickets, 0.13, 0.3, 0.3), -0.3) + pan(np.roll(crickets, int(0.7 * SR)), 0.4) * 0.7
    return soft_limit(stereo, 1.0)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    tracks = [
        ("battle_theme.ogg", render_battle, 16 * 4 * 60.0 / 120.0, -15.0),
        ("menu_theme.ogg", render_menu, 16 * 4 * 60.0 / 84.0, -17.0),
        ("locker_theme.ogg", render_locker, 8 * 4 * 60.0 / 90.0, -17.0),
        ("ambience_wind.ogg", render_wind, 40.0, -24.0),
    ]
    for file_name, renderer, loop_seconds, loudness in tracks:
        audio = make_seamless(renderer, loop_seconds)
        audio = normalize_rms(audio, loudness)
        write_ogg(audio, os.path.join(OUT_DIR, file_name))
        print("rendered", file_name, round(loop_seconds, 2), "s")


if __name__ == "__main__":
    main()
