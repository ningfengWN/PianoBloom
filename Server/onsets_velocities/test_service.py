# SPDX-License-Identifier: GPL-3.0-or-later
"""Run with the real official checkpoint; fake output is used only for seam edge cases."""
import argparse
import asyncio
import json
from pathlib import Path

import numpy as np
import pandas as pd
from aiohttp import ClientSession, web

from engine import Engine, Stream
from server import make_app

SHA = "90901ff8c7cb15c76a4da2f4aca643a10295c834ac9e549ee16097d4bbce642d"


def check_chunk_edges():
    class SeamOutput:
        calls = 0
        def infer(self, audio, db_offset, threshold):
            # Two chord notes split across the commit boundary, plus the same
            # pitch peak duplicated at the seam, then a genuinely repeated note.
            rows = [((0, 107, 39, 0.8),), ((0, 100, 39, 0.8), (0, 100, 43, 0.7)), ((0, 104, 39, 0.8),)]
            values = rows[self.calls] if self.calls < len(rows) else ()
            self.calls += 1
            return pd.DataFrame(values, columns=["batch_idx", "t_idx", "key", "vel"]), 1
    stream = Stream(SeamOutput())
    stream.append(np.zeros(16000, dtype="<f4").tobytes())
    first = stream.step(); second = stream.step()
    assert first["events"] == [], "Do not release half a chord"
    assert len(second["events"]) == 1 and second["events"][0]["notes"] == [60, 64]
    stream.append(np.zeros(16000, dtype="<f4").tobytes())
    third = stream.step(); fourth = stream.step()
    events = third["events"] + fourth["events"]
    assert any(event["notes"] == [60] for event in events), "Repeated notes must survive deduplication"
    assert all(a["processed_through"] <= b["processed_through"] for a, b in zip([first, second, third], [second, third, fourth]))
    assert stream.base + len(stream.audio) == stream.total
    try:
        stream.append(np.array([np.nan], dtype="<f4").tobytes())
        raise AssertionError("Non-finite audio accepted")
    except ValueError:
        pass


async def check_websocket(engine):
    runner = web.AppRunner(make_app(engine, "test-pairing-token"))
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", 0)
    await site.start()
    port = site._server.sockets[0].getsockname()[1]
    try:
        async with ClientSession() as client:
            address = f"http://127.0.0.1:{port}"
            async with client.get(address + "/health") as health:
                assert (await health.json())["status"] == "ok"
            async with client.ws_connect(address + "/recognize") as ws:
                await ws.send_json({"protocol": 1, "sample_rate": 16000, "token": "wrong"})
                assert (await ws.receive_json())["type"] == "error", "Invalid pairing token accepted"
            async with client.ws_connect(address + "/recognize") as ws:
                await ws.send_json({"protocol": 1, "sample_rate": 16000, "token": "test-pairing-token"})
                ready = await ws.receive_json()
                assert ready["type"] == "ready" and ready["checkpoint_sha256"] == SHA
                await ws.send_bytes(np.zeros(16000, dtype="<f4").tobytes())
                response = await asyncio.wait_for(ws.receive_json(), 15)
                assert response["type"] == "events" and response["events"] == []
                assert 0 < response["processed_through"] < response["captured_through"]
                assert response["inference_ms"] > 0
    finally:
        await runner.cleanup()


def check_audio(engine, path):
    import soundfile as sf
    from scipy.signal import resample_poly
    from math import gcd
    audio, rate = sf.read(path, dtype="float32", always_2d=True)
    audio = audio.mean(axis=1)
    factor = gcd(rate, 16000)
    audio = resample_poly(audio, 16000 // factor, rate // factor).astype(np.float32)[:16000 * 8]
    stream = Stream(engine)
    events, watermark = [], 0
    for start in range(0, len(audio), 1536):
        stream.append(audio[start:start + 1536].astype("<f4").tobytes())
        while stream.ready():
            result = stream.step()
            assert result["processed_through"] >= watermark
            watermark = result["processed_through"]
            events += result["events"]
    assert len(events) >= 3, "Piano fixture produced no usable note events"
    assert all(21 <= note <= 108 for event in events for note in event["notes"])
    print(json.dumps({"real_checkpoint_audio_smoke": {"events": len(events),
          "first_events": events[:3], "processed_seconds": watermark}}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--audio", type=Path)
    args = parser.parse_args()
    check_chunk_edges()
    engine = Engine(args.source, SHA)
    asyncio.run(check_websocket(engine))
    if args.audio:
        check_audio(engine, args.audio)
    print("PASS: official checkpoint, live WebSocket, authentication, PCM, timing watermarks and seam checks")
