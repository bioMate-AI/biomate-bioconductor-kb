#!/usr/bin/env python3
"""Record the auto-playing m2-rnaseq-differential-expression walkthrough (window.__timeline / __done).
Adapted from record-walkthrough-t0.py for T1 (unique port 7788).
Outputs a webm + a JSON with t_scene0_ms and the page's __timeline."""
import json, time, pathlib
from playwright.sync_api import sync_playwright

URL = 'http://localhost:7793/tutorials/m3-accession-to-workflow-walkthrough.html'
OUT = pathlib.Path('/Users/kky/biomate-review/recording/video')
OUT.mkdir(parents=True, exist_ok=True)
META = pathlib.Path('/Users/kky/biomate-review/recording/audio/m3-shared')
META.mkdir(parents=True, exist_ok=True)
W, H = 1920, 1080

def now_ms(t0): return int((time.monotonic() - t0) * 1000)

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, args=[
        '--no-sandbox','--disable-setuid-sandbox','--disable-dev-shm-usage','--disable-gpu'])
    t0 = time.monotonic()
    ctx = browser.new_context(viewport={'width':W,'height':H},
        record_video_dir=str(OUT), record_video_size={'width':W,'height':H})
    page = ctx.new_page()
    page.goto(URL, wait_until='networkidle', timeout=30000)
    t_scene0 = None
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        st = page.evaluate("""() => {
            const a = document.querySelector('.scene.active');
            const scenes = Array.prototype.slice.call(document.querySelectorAll('.scene'));
            return {
              hasTL: Array.isArray(window.__timeline),
              activeIsFirst: !!a && scenes.indexOf(a) === 0,
              timeline: window.__timeline || null,
              total: window.__totalSeconds || null
            };
        }""")
        if st['hasTL'] and st['activeIsFirst']:
            t_scene0 = now_ms(t0)
            timeline = st['timeline']; total = st['total']
            break
        time.sleep(0.012)
    if t_scene0 is None:
        raise SystemExit('scene 0 never became active')
    print(f'scene0 active at t={t_scene0}ms; timeline={timeline}; total={total}s')
    deadline = time.monotonic() + total + 60
    while time.monotonic() < deadline:
        if page.evaluate('() => window.__done === true'):
            break
        time.sleep(0.1)
    t_done = now_ms(t0)
    print(f'__done at t={t_done}ms ({(t_done-t_scene0)/1000:.1f}s after scene0)')
    page.wait_for_timeout(900)
    vid = page.video.path() if page.video else None
    ctx.close(); browser.close()

dst = OUT / 'm3-accession-to-workflow-raw.webm'
if vid and pathlib.Path(vid).exists():
    pathlib.Path(vid).rename(dst)
else:
    cands = sorted(OUT.glob('*.webm'), key=lambda f: f.stat().st_mtime)
    cands[-1].rename(dst)
(META / 'record_meta.json').write_text(json.dumps(
    {'t_scene0_ms': t_scene0, 't_done_ms': t_done, 'timeline': timeline,
     'total_seconds': total, 'video': str(dst)}, indent=2))
print('video ->', dst)
print('meta  ->', META / 'record_meta.json')
