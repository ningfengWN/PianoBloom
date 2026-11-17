# SPDX-License-Identifier: GPL-3.0-or-later
"""Adapter for the official O&V checkpoint. No training and no heuristic fallback."""
from __future__ import annotations

import hashlib
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from torchaudio.transforms import AmplitudeToDB, MelSpectrogram

UPSTREAM_COMMIT = "629ff11aceadf01ecc456b1c7f26a104f7e1e571"
CHECKPOINT_NAME = "OnsetsAndVelocities_2023_03_04_09_53_53.289step=43500_f1=0.9675__0.9480.torch"
RATE, HOP, FFT = 16000, 384, 2048


@dataclass(frozen=True)
class Window:
    left: int = 100
    body: int = 8
    right: int = 20


class Engine:
    def __init__(self, source: Path, checkpoint_sha256: str, threads: int = 2):
        sys.path.insert(0, str(source))
        from ov_piano.models.ov import OnsetsAndVelocities
        from ov_piano.inference import OnsetVelocityNmsDecoder

        checkpoint = source / "assets" / CHECKPOINT_NAME
        actual = hashlib.sha256(checkpoint.read_bytes()).hexdigest()
        if actual != checkpoint_sha256:
            raise ValueError("Official checkpoint checksum mismatch")
        torch.set_num_threads(threads)
        self.model = OnsetsAndVelocities(2, 229, 88, conv1x1head=(200, 200),
                                         bn_momentum=0, dropout_drop_p=0).eval()
        self.model.load_state_dict(torch.load(checkpoint, map_location="cpu", weights_only=True))
        # Same FFT/mel/power settings as the official demo; explicit center=False
        # lets this adapter place every frame on one persistent streaming grid.
        self.mel = MelSpectrogram(RATE, FFT, hop_length=HOP, f_min=50,
                                  f_max=8000, n_mels=229, power=2, center=False)
        self.db = AmplitudeToDB(stype="power", top_db=80)
        self.decoder = OnsetVelocityNmsDecoder(88, nms_pool_ksize=3,
            gauss_conv_stddev=1, gauss_conv_ksize=11, vel_pad_left=1, vel_pad_right=1)
        self.checkpoint_sha256 = actual

    def infer(self, audio: np.ndarray, db_offset: float, threshold: float):
        begin = time.perf_counter()
        with torch.inference_mode():
            logmel = self.db(self.mel(torch.from_numpy(audio.copy()))) + db_offset
            stages, velocities = self.model(logmel.unsqueeze(0), trainable_onsets=False)
            probabilities = F.pad(torch.sigmoid(stages[-1]), (1, 0))
            velocities = F.pad(torch.sigmoid(velocities), (1, 0))
            events = self.decoder(probabilities, velocities, threshold)
        return events, (time.perf_counter() - begin) * 1000


class Stream:
    """Bounded waveform history; only stable central frames are emitted once."""
    def __init__(self, engine: Engine, window: Window = Window(),
                 threshold: float = 0.75, db_offset: float = -12):
        self.engine, self.window = engine, window
        self.threshold, self.db_offset = threshold, db_offset
        self.audio = np.empty(0, dtype=np.float32)
        self.base = self.total = self.next_frame = 0
        self.pending: list[dict] = []
        self.last_onset: dict[int, float] = {}

    def append(self, data: bytes):
        if len(data) % 4 or not 0 < len(data) <= RATE * 4:
            raise ValueError("Expected <=1 second of float32 little-endian mono audio")
        chunk = np.frombuffer(data, dtype="<f4")
        if not np.isfinite(chunk).all() or np.max(np.abs(chunk)) > 4:
            raise ValueError("Invalid audio samples")
        self.audio = np.concatenate((self.audio, chunk))
        self.total += len(chunk)
        # Refuse to silently drop/compress captured time if the host cannot keep up.
        lag = self.total - self.next_frame * HOP
        if lag > RATE * 12:
            raise ValueError("Inference host cannot keep up; choose a larger batch or a faster host")

    def ready(self):
        return self.total >= (self.next_frame + self.window.body + self.window.right) * HOP + FFT // 2

    def step(self):
        w = self.window
        begin_frame = self.next_frame - w.left
        begin = begin_frame * HOP - FFT // 2
        length = (w.left + w.body + w.right) * HOP + FFT
        audio = np.zeros(length, dtype=np.float32)
        lo, hi = max(0, begin), min(self.total, begin + length)
        if lo < self.base:
            raise ValueError("Streaming history lost")
        audio[lo - begin:hi - begin] = self.audio[lo - self.base:hi - self.base]
        events, elapsed_ms = self.engine.infer(audio, self.db_offset, self.threshold)
        for row in events.itertuples():
            frame = float(row.t_idx)
            if w.left <= frame < w.left + w.body:
                onset = max(0.0, (begin_frame + frame) * HOP / RATE - 0.01)
                note = int(row.key) + 21
                if onset - self.last_onset.get(note, -100) >= 0.08:
                    self.last_onset[note] = onset
                    self.pending.append({"note": note, "time": onset,
                                         "velocity": int(np.clip(float(row.vel) * 127, 1, 127))})
        self.next_frame += w.body
        # Hold a small guard interval so chords straddling two inference chunks
        # are returned as one event. Future hints are never read from the score.
        watermark = max(0.0, self.next_frame * HOP / RATE - 0.055)
        self.pending.sort(key=lambda x: (x["time"], x["note"]))
        groups = []
        while self.pending and self.pending[0]["time"] + 0.045 <= watermark:
            first = self.pending.pop(0)
            chord = [first]
            while self.pending and self.pending[0]["time"] <= first["time"] + 0.045:
                chord.append(self.pending.pop(0))
            groups.append({"time": first["time"], "notes": sorted({x["note"] for x in chord}),
                           "velocities": {str(x["note"]): x["velocity"] for x in chord}})
        # Unemitted chord times must not be marked as missed by the client.
        if self.pending:
            watermark = min(watermark, self.pending[0]["time"])
        keep = max(0, (self.next_frame - w.left) * HOP - FFT // 2)
        drop = max(0, keep - self.base)
        self.audio = self.audio[drop:].copy(); self.base += drop
        return {"type": "events", "events": groups, "processed_through": watermark,
                "inference_ms": elapsed_ms, "captured_through": self.total / RATE}
