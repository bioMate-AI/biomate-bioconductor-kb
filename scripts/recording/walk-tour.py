#!/usr/bin/env python3
"""
OBSERVE a tour playing at its native pace. Don't disable autoAdvance, don't
mutate speed, don't call __tourReset/__tourFFTo. Just watch the .tour-callout
title change; when it changes, take 3 screenshots across the next ~5s.

This produces an honest "ground truth" of what the design intends.

Usage:
  python3 walk-tour.py --demo ra-drugscreen --out /tmp/walk_drugscreen/
"""
import json, time, argparse, pathlib, sys
import importlib.util
spec = importlib.util.spec_from_file_location(
    "pr", str(pathlib.Path(__file__).parent / "playwright-record.py"))
pr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pr)
from playwright.sync_api import sync_playwright


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--demo', required=True)
    ap.add_argument('--out',  required=True)
    ap.add_argument('--max-seconds', type=int, default=240,
                    help='Maximum wall time to wait for tour to finish')
    args = ap.parse_args()

    out = pathlib.Path(args.out); out.mkdir(parents=True, exist_ok=True)
    cfg = pr.DEMO_CONFIG.get(args.demo)
    if not cfg:
        sys.exit(f'unknown demo {args.demo}')

    target_url = cfg.get('url') or pr.TOUR_URL
    # Use design-default tweaks (speed=1, panel width default). Set scenario only.
    tweaks_init = {
        'scenario':       cfg.get('scenario', 'nfcore'),
        'runState':       cfg.get('runState', 'running'),
        'speed':          1.0,
        'panelWidth':     760,
        'sidebarMode':    'auto',
        'qcHalt': False, 'licenseGate': False, 'blocked': False,
        'disambig': False, 'watcherAttached': True,
    }

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=['--no-sandbox','--disable-setuid-sandbox',
                  '--disable-dev-shm-usage','--disable-gpu'],
        )
        context = browser.new_context(viewport={'width': 1920, 'height': 1080})
        context.add_init_script(f'''() => {{
            try {{ localStorage.setItem('biomate-tweaks',          JSON.stringify({json.dumps(tweaks_init)})); }} catch(e) {{}}
            try {{ localStorage.setItem('biomate-research-tweaks', JSON.stringify({json.dumps(tweaks_init)})); }} catch(e) {{}}
            try {{ localStorage.removeItem('biomate_wf_tour_seen'); }} catch(e) {{}}
        }}''')
        page = context.new_page()
        page.goto(target_url, wait_until='networkidle', timeout=30000)
        page.wait_for_timeout(2000)

        # NOTE: rewind-aware tourFFTo is patched directly in
        # reference/claude_design/research_agents/src/ResearchApp.jsx
        # so we don't need to monkey-patch from here.

        # Start the tour the normal way.
        label = cfg.get('label')
        if label is None:
            page.locator('.tut-btn').first.click()
        else:
            page.locator('.tut-btn').first.click()
            page.locator('.tour-picker').first.wait_for(state='visible', timeout=10000)
            page.locator('.tour-picker-item').filter(has_text=label).first.click()
        page.locator('.tour-callout').first.wait_for(state='visible', timeout=15000)

        # Observe: poll callout title every 250ms. On change, snapshot.
        def callout_signature():
            try:
                return page.locator('.tour-callout').first.inner_text()[:120]
            except Exception:
                return None

        beats = []
        start = time.monotonic()
        prev_sig = None
        beat_idx = 0
        while time.monotonic() - start < args.max_seconds:
            sig = callout_signature()
            if sig is None:
                # Callout gone — tour finished
                break
            if sig != prev_sig:
                beat_idx += 1
                first_line = (sig.split('\n')[0] or '')[:80]
                print(f'  beat {beat_idx:>2}: {first_line}')
                # Scroll spotlight target into view
                page.evaluate('''() => {
                    const ring = document.querySelector('.tour-overlay rect');
                    if (!ring) return;
                    const r = ring.getBoundingClientRect();
                    const el = document.elementFromPoint(r.left + r.width/2, r.top + r.height/2);
                    if (el) el.scrollIntoView({behavior:'instant', block:'center', inline:'center'});
                }''')
                page.wait_for_timeout(200)
                # 3 screenshots across the next ~5s (or until the callout changes)
                for tag, dt_ms in [('a_start', 0), ('b_mid', 2500), ('c_end', 5000)]:
                    shot = out / f'beat{beat_idx:02d}{tag}.png'
                    page.screenshot(path=str(shot), full_page=False)
                    if tag == 'c_end':
                        break
                    # Wait dt; bail if callout changed (tour auto-advanced)
                    deadline = time.monotonic() + (dt_ms / 1000.0)
                    while time.monotonic() < deadline:
                        if callout_signature() != sig:
                            break
                        page.wait_for_timeout(150)
                beats.append({
                    'step': beat_idx,
                    'callout_text_first_line': first_line,
                })
                prev_sig = sig
            page.wait_for_timeout(250)

        (out / 'beats.json').write_text(json.dumps(beats, indent=2))
        print(f'[walk] captured {beat_idx} beats over {time.monotonic()-start:.0f}s')
        browser.close()


if __name__ == '__main__':
    main()
