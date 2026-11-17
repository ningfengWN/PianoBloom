# SPDX-License-Identifier: GPL-3.0-or-later
"""Local-network O&V inference service. Audio stays in RAM, never written to disk."""
import argparse
import asyncio
import hmac
import json
import secrets
from pathlib import Path

from aiohttp import WSMsgType, web
from engine import Engine, Stream, Window, RATE, HOP, FFT, UPSTREAM_COMMIT


def make_app(engine, token, window=Window()):
    app = web.Application(client_max_size=1024 * 1024)
    lock = asyncio.Lock()

    async def health(request):
        return web.json_response({"status": "ok", "model": "Onsets & Velocities", "protocol": 1})

    async def recognize(request):
        ws = web.WebSocketResponse(max_msg_size=RATE * 4 + 1024, heartbeat=10)
        await ws.prepare(request)
        stream = None
        try:
            first = await asyncio.wait_for(ws.receive(), 10)
            if first.type != WSMsgType.TEXT:
                raise ValueError("Start message required")
            start = json.loads(first.data)
            if not hmac.compare_digest(str(start.get("token", "")), token):
                raise ValueError("连接码不正确")
            if start.get("protocol") != 1 or start.get("sample_rate") != RATE:
                raise ValueError("Unsupported audio protocol")
            stream = Stream(engine, window)
            await ws.send_json({"type": "ready", "model": "Onsets & Velocities",
                "protocol": 1, "source_commit": UPSTREAM_COMMIT,
                "checkpoint_sha256": engine.checkpoint_sha256,
                "minimum_delay": (window.body + window.right) * HOP / RATE + FFT / 2 / RATE})
            async for message in ws:
                if message.type == WSMsgType.BINARY:
                    stream.append(message.data)
                    while stream.ready():
                        async with lock:
                            response = await asyncio.to_thread(stream.step)
                        await ws.send_json(response)
                elif message.type == WSMsgType.ERROR:
                    break
                else:
                    raise ValueError("Expected binary PCM audio")
        except Exception as error:
            if not ws.closed:
                await ws.send_json({"type": "error", "message": str(error)})
                await ws.close(code=1008)
        finally:
            stream = None  # Release waveform history at disconnect.
        return ws

    app.router.add_get("/health", health)
    app.router.add_get("/recognize", recognize)
    return app


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--token-file", type=Path, default=Path(".connection-token"))
    parser.add_argument("--official-window", action="store_true")
    args = parser.parse_args()
    if args.token_file.exists():
        token = args.token_file.read_text().strip()
    else:
        token = secrets.token_urlsafe(18)
        args.token_file.write_text(token); args.token_file.chmod(0o600)
    if not token:
        parser.error("Empty connection token")
    engine = Engine(args.source, args.sha256)
    window = Window(100, 30, 100) if args.official_window else Window()
    print("iPad 地址：ws://这台Mac的局域网IP:8765/recognize", flush=True)
    print("连接码：" + token, flush=True)
    print("仅在内存处理声音，不保存录音。关闭此终端会停止模型。", flush=True)
    web.run_app(make_app(engine, token, window), host=args.host, port=args.port,
                access_log=None)
