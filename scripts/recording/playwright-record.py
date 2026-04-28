#!/usr/bin/env python3
"""
Record the BioMate tutorial UX advancing through a demo, timed to per-step
audio durations produced by gemini-tts.py.

Usage:
  python3 scripts/recording/playwright-record.py \
    --demo cryosparc-main \
    --timing recording/audio/cryosparc/timing.json \
    --out recording/video/cryosparc-raw.webm

Modelled on the working demo-ref-helpers.ts approach:
  1. Pre-set biomate-tweaks localStorage before page load
  2. Click .tut-btn to open the TourPicker
  3. Filter .tour-picker-item by label text and click it
  4. Advance with .tour-callout .btn.primary
"""

import json, argparse, pathlib
from playwright.sync_api import sync_playwright

TOUR_URL = 'http://localhost:7779/biomate/Workflow%20Panel%20Redesign.html'

# Maps demo IDs (used in CLI / shell script) to Tour.jsx label strings (shown in picker)
# and the initial scenario tweaks to pre-set in localStorage.
DEMO_CONFIG = {
    'cryosparc-main': {
        'label':    '09d — CryoSPARC SPA · full walkthrough',
        'scenario': 'cryosparc',
        'runState': 'running',
    },
    'outputs-findings': {
        # The Tour.jsx ID is outputs-findings-report; the shell script uses outputs-findings
        'label':    '09f — Outputs, Findings & Reports',
        'scenario': 'cryosparc',
        'runState': 'completed',
    },
    'outputs-findings-report': {
        'label':    '09f — Outputs, Findings & Reports',
        'scenario': 'cryosparc',
        'runState': 'completed',
    },
    'website-quickstart': {
        'label':    '00 — Workflow Panel · first-time orientation',
        'scenario': 'nfcore',
        'runState': 'running',
    },
    'nfcore-normal': {
        'label':    '09a — nfcore normal run',
        'scenario': 'nfcore',
        'runState': 'running',
    },
    'nfcore-qcloop': {
        'label':    '09b — nfcore QC autoloop',
        'scenario': 'nfcore',
        'runState': 'running',
    },
}

# Extra hold after the narration ends before advancing (ms)
STEP_BUFFER_MS  = 300
# Final hold on last frame before stopping
FINAL_HOLD_MS   = 1500
# Settle time after clicking Next
STEP_SETTLE_MS  = 400


def start_tour(page, demo_id: str):
    """Open the TourPicker and select the given demo by its label."""
    cfg = DEMO_CONFIG.get(demo_id)
    if not cfg:
        raise ValueError(f"Unknown demo '{demo_id}'. Known: {list(DEMO_CONFIG)}")

    label = cfg['label']

    # Pre-set tweaks in localStorage (page already loaded, update + reload)
    tweaks = {
        'scenario':       cfg['scenario'],
        'runState':       cfg['runState'],
        'speed':          900,
        'panelWidth':     510,
        'sidebarMode':    'auto',
        'qcHalt':         False,
        'licenseGate':    False,
        'blocked':        False,
        'disambig':       False,
        'watcherAttached': True,
    }
    page.evaluate(f'''() => {{
        try {{ localStorage.setItem('biomate-tweaks', JSON.stringify({json.dumps(tweaks)})); }} catch(e) {{}}
        try {{ localStorage.removeItem('biomate_wf_tour_seen'); }} catch(e) {{}}
    }}''')
    page.reload(wait_until='networkidle')
    page.wait_for_timeout(1500)

    # Click the Tutorial (▶ Tutorial) button
    tut_btn = page.locator('.tut-btn').first
    tut_btn.wait_for(state='visible', timeout=15000)
    tut_btn.click()
    page.wait_for_timeout(500)

    # Wait for picker, click the matching item by label text
    page.locator('.tour-picker').first.wait_for(state='visible', timeout=10000)
    item = page.locator('.tour-picker-item').filter(has_text=label).first
    item.wait_for(state='visible', timeout=8000)
    item.click()
    page.wait_for_timeout(600)


def click_next(page):
    """Advance to the next tour step using the proven .tour-callout .btn.primary selector."""
    try:
        btn = page.locator('.tour-callout .btn.primary').first
        btn.wait_for(state='visible', timeout=3000)
        btn.click()
        return True
    except Exception:
        pass
    # Keyboard fallback
    page.keyboard.press('ArrowRight')
    return True


def main():
    parser = argparse.ArgumentParser(description='Record BioMate tutorial video')
    parser.add_argument('--demo',   required=True, help='Demo ID (e.g. cryosparc-main)')
    parser.add_argument('--timing', required=True, help='Path to timing.json from gemini-tts.py')
    parser.add_argument('--out',    required=True, help='Output .webm path')
    parser.add_argument('--url',    default=TOUR_URL, help='URL of the design UX')
    parser.add_argument('--width',  type=int, default=1920)
    parser.add_argument('--height', type=int, default=1080)
    args = parser.parse_args()

    timing = json.loads(pathlib.Path(args.timing).read_text())
    out_path = pathlib.Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    total_s = sum(t['duration_ms'] for t in timing) / 1000
    print(f'Demo: {args.demo}  |  {len(timing)} steps  |  ~{total_s:.0f}s narration')
    print(f'Output: {out_path}\n')

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=[
                '--no-sandbox',
                '--disable-setuid-sandbox',
                '--disable-dev-shm-usage',
                '--disable-gpu',
            ],
        )
        context = browser.new_context(
            viewport={'width': args.width, 'height': args.height},
            record_video_dir=str(out_path.parent),
            record_video_size={'width': args.width, 'height': args.height},
        )

        # Pre-set tweaks in localStorage via initScript so it's there on first load
        cfg = DEMO_CONFIG.get(args.demo, {})
        tweaks_init = {
            'scenario':       cfg.get('scenario', 'nfcore'),
            'runState':       cfg.get('runState', 'running'),
            'speed':          900,
            'panelWidth':     510,
            'sidebarMode':    'auto',
            'qcHalt':         False,
            'licenseGate':    False,
            'blocked':        False,
            'disambig':       False,
            'watcherAttached': True,
        }
        context.add_init_script(f'''() => {{
            try {{ localStorage.setItem('biomate-tweaks', JSON.stringify({json.dumps(tweaks_init)})); }} catch(e) {{}}
            try {{ localStorage.removeItem('biomate_wf_tour_seen'); }} catch(e) {{}}
        }}''')

        page = context.new_page()

        print('Opening design UX...')
        page.goto(args.url, wait_until='networkidle', timeout=30000)
        page.wait_for_timeout(1000)

        print(f'Starting tour: {args.demo}')
        start_tour(page, args.demo)

        for i, step in enumerate(timing):
            hold = step['duration_ms'] + STEP_BUFFER_MS
            title = step['title'][:55]
            print(f'  [{step["step"]:02d}/{len(timing)}] {title}  ({hold}ms)')

            page.wait_for_timeout(hold)

            if i < len(timing) - 1:
                click_next(page)
                page.wait_for_timeout(STEP_SETTLE_MS)

        page.wait_for_timeout(FINAL_HOLD_MS)

        print('\nClosing browser and saving video...')
        video_path = page.video.path() if page.video else None
        context.close()
        browser.close()

    if video_path and pathlib.Path(video_path).exists():
        pathlib.Path(video_path).rename(out_path)
        print(f'Video saved: {out_path}')
    else:
        candidates = sorted(out_path.parent.glob('*.webm'), key=lambda f: f.stat().st_mtime)
        if candidates:
            candidates[-1].rename(out_path)
            print(f'Video saved: {out_path}')
        else:
            print('WARNING: could not locate output video file')


if __name__ == '__main__':
    main()
