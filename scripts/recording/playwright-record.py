#!/usr/bin/env python3
"""
Record the BioMate tutorial UX advancing through a demo, while logging the
wall-clock moment each tour step actually became visible. The companion
merge-audio-aligned.py uses those timestamps to start each step's narration
WAV exactly when the spotlight arrives.

Outputs:
  --out               raw .webm video
  --timestamps-out    JSON with t0 (first-step-visible ms since recording start)
                      and per-step arrival times (ms since recording start)

Usage:
  python3 playwright-record.py \
    --demo cryosparc-main \
    --timing recording/audio/cryosparc/timing.json \
    --out   recording/video/cryosparc-raw.webm \
    --timestamps-out recording/audio/cryosparc/step_timestamps.json
"""
import json, time, argparse, pathlib
from playwright.sync_api import sync_playwright

TOUR_URL = 'http://localhost:7779/biomate/Workflow%20Panel%20Redesign.html'
RA_URL   = 'http://localhost:7779/research_agents/Research%20Agent%20UI.html'
IND_URL  = 'http://localhost:7779/IND_design/BioMate%20IND%20Report.html'

# Tours whose steps carry `autoAdvance: N` ms drive themselves — DO NOT click Next.
# Just observe when each step becomes visible, line up audio to that arrival time.
AUTOADVANCE_DEMOS = {'ra-drugscreen', 'ra-variant', 'ra-rnaseq'}

DEMO_CONFIG = {
    'cryosparc-main': {
        'label':    '09d — CryoSPARC SPA · full walkthrough',
        'scenario': 'cryosparc', 'runState': 'running',
    },
    'outputs-findings': {
        'label':    '09f — Outputs, Findings & Reports',
        'scenario': 'cryosparc', 'runState': 'completed',
    },
    'outputs-findings-report': {
        'label':    '09f — Outputs, Findings & Reports',
        'scenario': 'cryosparc', 'runState': 'completed',
    },
    'website-quickstart': {
        'label':    '00 — Workflow Panel · first-time orientation',
        'scenario': 'nfcore', 'runState': 'running',
    },
    'nfcore-normal': {
        'label':    '09a — nfcore normal run',
        'scenario': 'nfcore', 'runState': 'running',
    },
    'nfcore-qcloop': {
        'label':    '09b — nfcore QC autoloop',
        'scenario': 'nfcore', 'runState': 'running',
    },
    'ra-cryo': {
        'label':    '09d — CryoSPARC SPA · 3-minute deep dive',
        'url':      RA_URL,
        'scenario': 'cryosparc', 'runState': 'running',
    },
    'ra-afterrun': {
        'label':    '09f — After run · all tabs',
        'url':      RA_URL,
        'scenario': 'cryosparc', 'runState': 'completed',
    },
    'ra-drugscreen': {
        'label':    'R02 — Drug screen · auto-loop + comparison',
        'url':      RA_URL,
        'scenario': 'drugscreen', 'runState': 'running',
    },
    'ind': {
        # IND has no picker. Click .tut-btn → tour auto-starts.
        'label':    None,
        'url':      IND_URL,
        'scenario': None, 'runState': None,
    },
}

STEP_BUFFER_MS = 250    # cushion after audio ends before clicking Next
FINAL_HOLD_MS  = 1500


def now_ms(t0):
    return int((time.monotonic() - t0) * 1000)


def start_tour(page, demo_id, rec_t0):
    """
    Start the tour. Returns wall-clock ms (relative to rec_t0) at which the
    FIRST tour callout becomes visible. We:
      1. Hide .tut-btn + .tour-picker* via CSS so the picker frames are
         invisible in the recording (no user-facing selection segment).
      2. Mutate DEMO_TOURS[*].steps[*].autoAdvance × AUTOADVANCE_MULT
         BEFORE the tour starts (so step 1's autoAdvance is also scaled).
      3. Click .tut-btn + .tour-picker-item (or just .tut-btn for IND).
      4. Wait for the first .tour-callout to be visible.
    """
    cfg = DEMO_CONFIG.get(demo_id)
    if not cfg:
        raise ValueError(f"Unknown demo '{demo_id}'. Known: {list(DEMO_CONFIG)}")
    label = cfg.get('label')

    # Step 0a: hide the tutorial button + picker UI so the recording never shows them.
    page.add_style_tag(content='''
        .tut-btn, .tour-picker, .tour-picker-backdrop {
            opacity: 0 !important;
            pointer-events: auto !important;
        }
    ''')

    # Step 0b: apply autoAdvance multiplier BEFORE any tour starts.
    mult = float(__import__('os').environ.get('AUTOADVANCE_MULT', '1.0'))
    if mult != 1.0:
        page.evaluate(f'''() => {{
            const tours = window.DEMO_TOURS || window.IND_TOUR_STEPS && {{__ind__: {{ steps: window.IND_TOUR_STEPS }}}} || {{}};
            Object.values(tours).forEach(t => {{
                if (!t || !t.steps) return;
                t.steps.forEach(s => {{
                    if (typeof s.autoAdvance === 'number') {{
                        s.autoAdvance = Math.round(s.autoAdvance * {mult});
                    }}
                }});
            }});
        }}''')

    if label is None:  # IND — no picker
        tut_btn = page.locator('.tut-btn').first
        tut_btn.wait_for(state='attached', timeout=15000)
        tut_btn.click(force=True)
    else:
        tut_btn = page.locator('.tut-btn').first
        tut_btn.wait_for(state='attached', timeout=15000)
        tut_btn.click(force=True)
        page.locator('.tour-picker').first.wait_for(state='attached', timeout=10000)
        item = page.locator('.tour-picker-item').filter(has_text=label).first
        item.wait_for(state='attached', timeout=8000)
        item.click(force=True)

    page.locator('.tour-callout').first.wait_for(state='visible', timeout=15000)
    return now_ms(rec_t0)


def click_next(page):
    try:
        btn = page.locator('.tour-callout .btn.primary').first
        btn.wait_for(state='visible', timeout=5000)
        # force=True skips the stability check — cryo tour's cartoon SVG ring
        # animation makes the callout "unstable" forever in Playwright's eyes,
        # making each click hang for ~30s and inflating the video length.
        btn.click(force=True, timeout=2000)
        return True
    except Exception:
        page.keyboard.press('ArrowRight')
        return True


def wait_for_callout_visible(page, settle_ms=300, timeout_ms=4000):
    """After click_next, just wait briefly for next callout to be visible."""
    try:
        page.locator('.tour-callout').first.wait_for(state='visible', timeout=timeout_ms)
        page.wait_for_timeout(settle_ms)
        return True
    except Exception:
        return False


def read_current_step(page):
    """Return current tour step number (1-based) from .tour-callout, or None.
    The callout's footer typically shows 'X / N'."""
    try:
        txt = page.locator('.tour-callout').first.inner_text()
        m = __import__('re').search(r'(\d+)\s*/\s*\d+', txt or '')
        return int(m.group(1)) if m else None
    except Exception:
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--demo',            required=True)
    parser.add_argument('--timing',          required=True)
    parser.add_argument('--out',             required=True)
    parser.add_argument('--timestamps-out',  required=True)
    parser.add_argument('--url',             default=None)
    parser.add_argument('--width',  type=int, default=1920)
    parser.add_argument('--height', type=int, default=1080)
    args = parser.parse_args()

    timing = json.loads(pathlib.Path(args.timing).read_text())
    out_path = pathlib.Path(args.out)
    ts_path  = pathlib.Path(args.timestamps_out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    ts_path.parent.mkdir(parents=True, exist_ok=True)

    total_s = sum(t['duration_ms'] for t in timing) / 1000
    print(f'Demo: {args.demo}  |  {len(timing)} steps  |  ~{total_s:.0f}s narration')

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=['--no-sandbox','--disable-setuid-sandbox',
                  '--disable-dev-shm-usage','--disable-gpu'],
        )

        # rec_t0 = the moment we create the context (≈ first video frame).
        rec_t0 = time.monotonic()
        context = browser.new_context(
            viewport={'width': args.width, 'height': args.height},
            record_video_dir=str(out_path.parent),
            record_video_size={'width': args.width, 'height': args.height},
        )
        cfg = DEMO_CONFIG.get(args.demo, {})
        target_url = args.url or cfg.get('url') or TOUR_URL
        tweaks_init = {
            'scenario':       cfg.get('scenario', 'nfcore'),
            'runState':       cfg.get('runState', 'running'),
            'speed':          1.0,
            'panelWidth':     int((__import__('os').environ.get('PANEL_WIDTH', '760'))),
            'sidebarMode':    'auto',
            'qcHalt': False, 'licenseGate': False, 'blocked': False,
            'disambig': False, 'watcherAttached': True,
        }
        # Note: RA UI reads 'biomate-research-tweaks', Workflow Panel reads 'biomate-tweaks'.
        # Set both so either UI picks it up.
        context.add_init_script(f'''() => {{
            try {{ localStorage.setItem('biomate-tweaks',          JSON.stringify({json.dumps(tweaks_init)})); }} catch(e) {{}}
            try {{ localStorage.setItem('biomate-research-tweaks', JSON.stringify({json.dumps(tweaks_init)})); }} catch(e) {{}}
            try {{ localStorage.removeItem('biomate_wf_tour_seen'); }} catch(e) {{}}
        }}''')
        page = context.new_page()

        print('Opening design UX...')
        page.goto(target_url, wait_until='networkidle', timeout=30000)
        page.wait_for_timeout(600)

        print(f'Starting tour: {args.demo}')
        t_first = start_tour(page, args.demo, rec_t0)
        print(f'  first callout visible at t={t_first}ms')

        # Step-arrival timestamps. Each entry: {step, t_visible_ms} (ms since rec start).
        step_arrivals = [{'step': timing[0]['step'], 't_visible_ms': t_first}]

        autoadvance = args.demo in AUTOADVANCE_DEMOS
        if autoadvance:
            print(f'  → tour has autoAdvance; observing step transitions only')

        # Loop through steps; on autoAdvance tours, just observe; otherwise, click Next.
        for i, step in enumerate(timing):
            if i == len(timing) - 1:
                # Last step: hold for narration then final hold
                hold = step['duration_ms'] + STEP_BUFFER_MS
                print(f'  [{step["step"]:02d}/{len(timing)}] (final) hold {hold}ms — {step["title"][:50]}')
                page.wait_for_timeout(hold)
                break

            if autoadvance:
                # Tour clicks Next itself; just watch for the step counter to bump.
                next_step_num = timing[i+1]['step']
                deadline = time.monotonic() + (step['duration_ms'] / 1000.0 + 15.0)
                arrived = False
                while time.monotonic() < deadline:
                    cur = read_current_step(page)
                    if cur and cur >= next_step_num:
                        arrived = True
                        break
                    page.wait_for_timeout(120)
                if not arrived:
                    print(f'  [{step["step"]:02d}/{len(timing)}] autoAdvance stuck; clicking Next')
                    click_next(page)
                    wait_for_callout_visible(page)
                t_next = now_ms(rec_t0)
                step_arrivals.append({'step': next_step_num, 't_visible_ms': t_next})
                print(f'  [{step["step"]:02d}/{len(timing)}] → step {next_step_num} at t={t_next}ms')
            else:
                # Narration-paced: hold for cue duration, click Next, settle briefly.
                hold = step['duration_ms'] + STEP_BUFFER_MS
                print(f'  [{step["step"]:02d}/{len(timing)}] hold {hold}ms — {step["title"][:50]}')
                page.wait_for_timeout(hold)
                click_next(page)
                wait_for_callout_visible(page, settle_ms=200, timeout_ms=3000)
                t_next = now_ms(rec_t0)
                step_arrivals.append({'step': timing[i+1]['step'], 't_visible_ms': t_next})

        page.wait_for_timeout(FINAL_HOLD_MS)
        t_end = now_ms(rec_t0)

        print('\nClosing browser and saving video...')
        video_path = page.video.path() if page.video else None
        context.close()
        browser.close()

    if video_path and pathlib.Path(video_path).exists():
        pathlib.Path(video_path).rename(out_path)
    else:
        cands = sorted(out_path.parent.glob('*.webm'), key=lambda f: f.stat().st_mtime)
        if cands:
            cands[-1].rename(out_path)

    ts_path.write_text(json.dumps({
        't_first_step_ms': t_first,
        't_end_ms': t_end,
        'arrivals': step_arrivals,
    }, indent=2))
    print(f'Video: {out_path}')
    print(f'Timestamps: {ts_path}')


if __name__ == '__main__':
    main()
