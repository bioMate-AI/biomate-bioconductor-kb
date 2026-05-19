#!/usr/bin/env python3
"""
Record the BioMate website quick-start v2 walkthrough.

Beats (must match the 14-step narration in
  reference/claude_design/biomate/website-quickstart-v2.en.short.md):

  1  Home (biomate.ai)
  2  Hover Services dropdown
  3  Click "All Services" → services.html
  4  Pricing
  5  Newsroom (Scientific Articles)
  6  About → How it works (jump to anchor)
  7  Click "Start free" → /register
  8  Register form (visual, no submit)
  9  Login form (visual, no submit) — then E2E bypass auth
 10  Platform landing (chat UI)
 11  Type the first prompt (SMILES ADMET query)
 12  Workflow card appears → click to open panel
 13  Confirm and run → SSE running
 14  Results land in panel

Usage:
  python3 scripts/recording/record-website-v2.py \
    --timing recording/audio/website-quickstart-v2/timing.json \
    --out    recording/video/website-quickstart-v2-raw.webm
"""
import json, argparse, pathlib, os
from playwright.sync_api import sync_playwright

MARKETING_URL = 'https://biomate.ai'
PLATFORM_URL  = 'https://dev-public.biomate.ai'
E2E_TOKEN     = os.environ.get('BIOMATE_E2E_TOKEN', 'biomate-e2e-bypass-token-dev-only')

STEP_BUFFER_MS = 400
FINAL_HOLD_MS  = 1500

DEMO_PROMPT = ('Run ADMET profiling on this compound. SMILES: '
               'CC(C)CC1=CC=C(C=C1)C(C)C(=O)O')

# (action, payload)
STEPS = {
    1:  ('goto',     f'{MARKETING_URL}/'),
    2:  ('hover',    'a:has-text("Services")'),
    3:  ('goto',     f'{MARKETING_URL}/services.html'),
    4:  ('goto',     f'{MARKETING_URL}/pricing.html'),
    5:  ('goto',     f'{MARKETING_URL}/blog.html'),
    6:  ('goto',     f'{MARKETING_URL}/index.html#how-it-works'),
    7:  ('click',    'a[href*="register"], a.bm-nav-cta'),
    8:  ('settle',   None),                       # let register page render
    9:  ('goto',     f'{PLATFORM_URL}/login'),    # show login form
    10: ('auth',     None),                       # E2E bypass + navigate to platform
    11: ('type',     DEMO_PROMPT),
    12: ('panel',    None),
    13: ('run',      None),
    14: ('settle',   None),
}


def try_e2e_auth(page):
    try:
        resp = page.request.post(
            f'{PLATFORM_URL}/api/auth/login',
            headers={'X-E2E-Test-Token': E2E_TOKEN, 'Content-Type': 'application/json'},
            data=json.dumps({'email': 'demo@biomate.test'}),
        )
        return resp.ok
    except Exception as e:
        print(f'  [auth] E2E bypass error: {e}')
        return False


def perform(page, step_num, authed):
    action, payload = STEPS.get(step_num, ('wait', None))
    try:
        if action == 'goto':
            page.goto(payload, wait_until='domcontentloaded', timeout=20000)
            page.wait_for_timeout(800)
        elif action == 'hover':
            el = page.locator(payload).first
            el.wait_for(state='visible', timeout=5000)
            el.hover()
            page.wait_for_timeout(800)
        elif action == 'click':
            el = page.locator(payload).first
            el.wait_for(state='visible', timeout=8000)
            el.click()
            page.wait_for_timeout(1500)
        elif action == 'auth':
            if not authed[0]:
                if try_e2e_auth(page):
                    print('  [auth] E2E bypass OK')
                page.goto(PLATFORM_URL, wait_until='domcontentloaded', timeout=15000)
                page.wait_for_timeout(1500)
                authed[0] = True
        elif action == 'type':
            box = page.locator('textarea, [contenteditable="true"]').first
            box.wait_for(state='visible', timeout=8000)
            box.click()
            page.wait_for_timeout(400)
            page.keyboard.type(str(payload), delay=20)
            page.keyboard.press('Enter')
            page.wait_for_timeout(800)
        elif action == 'panel':
            card = page.locator(
                '[data-testid="workflow-card"], .workflow-card, .wf-chip, '
                'button:has-text("Open in panel")'
            ).first
            card.wait_for(state='visible', timeout=15000)
            card.click()
            page.wait_for_timeout(1000)
        elif action == 'run':
            btn = page.locator(
                'button:has-text("Confirm and run"), button:has-text("Run workflow"), '
                'button:has-text("Confirm & Run")'
            ).first
            btn.wait_for(state='visible', timeout=10000)
            btn.click()
            page.wait_for_timeout(1500)
        elif action == 'settle':
            page.wait_for_timeout(800)
    except Exception as e:
        print(f'  [step {step_num} {action}] FAILED: {e}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--timing', required=True)
    ap.add_argument('--out',    required=True)
    ap.add_argument('--width',  type=int, default=1920)
    ap.add_argument('--height', type=int, default=1080)
    args = ap.parse_args()

    timing = json.loads(pathlib.Path(args.timing).read_text())
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    total_s = sum(t['duration_ms'] for t in timing) / 1000
    print(f'Website v2  |  {len(timing)} steps  |  ~{total_s:.0f}s')

    authed = [False]
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=['--no-sandbox', '--disable-setuid-sandbox',
                  '--disable-dev-shm-usage', '--disable-gpu'],
        )
        context = browser.new_context(
            viewport={'width': args.width, 'height': args.height},
            record_video_dir=str(out.parent),
            record_video_size={'width': args.width, 'height': args.height},
        )
        page = context.new_page()
        page.goto(MARKETING_URL, wait_until='domcontentloaded', timeout=20000)
        page.wait_for_timeout(1500)

        for step in timing:
            hold = step['duration_ms'] + STEP_BUFFER_MS
            print(f'  [{step["step"]:02d}/{len(timing)}] {step["title"][:50]}  ({hold}ms)')
            perform(page, step['step'], authed)
            page.wait_for_timeout(hold)

        page.wait_for_timeout(FINAL_HOLD_MS)
        vp = page.video.path() if page.video else None
        context.close()
        browser.close()

    if vp and pathlib.Path(vp).exists():
        pathlib.Path(vp).rename(out)
    else:
        cands = sorted(out.parent.glob('*.webm'), key=lambda f: f.stat().st_mtime)
        if cands:
            cands[-1].rename(out)
    print(f'Saved: {out}')


if __name__ == '__main__':
    main()
