"""Renders Blastfront's synthesized one-shot sound effects into assets/audio/sfx/.

python tools/music/render_sfx.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from synth import SR, lowpass, normalize_rms, perc_env, t_axis, write_ogg

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


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    write_ogg(render_heartbeat(), os.path.join(OUT_DIR, "heartbeat.ogg"))
    print("rendered heartbeat.ogg")


if __name__ == "__main__":
    main()
