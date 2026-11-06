#!/usr/bin/env python3
"""
Record the Grounded Standards Assistant auto-play walkthrough to MP4.

Serves this directory over HTTP (so the page can fetch the real demo_data.json),
drives the auto-play page with headless Chromium, records to webm, and transcodes
to mp4 with ffmpeg. Mirrors scripts/recording/record-walkthrough.py.

Run (after gen_demo_data.py):  python3 grounded-prototype/demo/record-grounded-demo.py
"""
import functools
import http.server
import pathlib
import socketserver
import threading
import time

from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).resolve().parent
PORT = 7794
URL = f"http://localhost:{PORT}/grounded-standards-walkthrough.html"
OUT = HERE / "out"
OUT.mkdir(exist_ok=True)
W, H = 1920, 1080


def serve():
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(HERE))
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("127.0.0.1", PORT), handler)
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    return httpd


def now_ms(t0):
    return int((time.monotonic() - t0) * 1000)


def main():
    httpd = serve()
    time.sleep(0.4)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=[
            "--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage", "--disable-gpu"])
        ctx = browser.new_context(viewport={"width": W, "height": H},
                                  record_video_dir=str(OUT),
                                  record_video_size={"width": W, "height": H})
        page = ctx.new_page()
        t0 = time.monotonic()
        page.goto(URL, wait_until="networkidle", timeout=30000)

        # wait for timeline + scene 0 active
        t_scene0 = None
        deadline = time.monotonic() + 30
        total = None
        while time.monotonic() < deadline:
            st = page.evaluate("""() => {
                const a = document.querySelector('.scene.active');
                const scenes = Array.prototype.slice.call(document.querySelectorAll('.scene'));
                return { hasTL: Array.isArray(window.__timeline),
                         activeIsFirst: !!a && scenes.indexOf(a) === 0,
                         total: window.__totalSeconds || null };
            }""")
            if st["hasTL"] and st["activeIsFirst"]:
                t_scene0 = now_ms(t0); total = st["total"]; break
            time.sleep(0.02)
        if t_scene0 is None:
            raise SystemExit("scene 0 never became active")
        print(f"scene0 at {t_scene0}ms; total={total}s")

        # poll until done
        deadline = time.monotonic() + (total or 60) + 60
        while time.monotonic() < deadline:
            if page.evaluate("() => window.__done === true"):
                break
            time.sleep(0.1)
        page.wait_for_timeout(900)  # hold last frame
        vid = page.video.path() if page.video else None
        ctx.close(); browser.close()

    httpd.shutdown()
    raw = OUT / "grounded-demo-raw.webm"
    if vid and pathlib.Path(vid).exists():
        pathlib.Path(vid).rename(raw)
    else:
        cands = sorted(OUT.glob("*.webm"), key=lambda f: f.stat().st_mtime)
        if not cands:
            raise SystemExit("no webm produced")
        cands[-1].rename(raw)
    print("raw webm ->", raw)

    # transcode to mp4 (H.264, faststart) for easy sharing
    mp4 = OUT / "grounded-standards-demo.mp4"
    import subprocess
    # anaconda ffmpeg 4.3 ships libopenh264 (not libx264); use it for portable H.264 mp4.
    r = subprocess.run([
        "ffmpeg", "-y", "-i", str(raw), "-vf", "fps=30,format=yuv420p",
        "-c:v", "libopenh264", "-profile:v", "high", "-b:v", "6000k", "-movflags", "+faststart",
        str(mp4)], capture_output=True, text=True)
    if r.returncode != 0:
        print("ffmpeg failed:\n", r.stderr[-2000:])
        raise SystemExit(1)
    print("mp4 ->", mp4)


if __name__ == "__main__":
    main()
