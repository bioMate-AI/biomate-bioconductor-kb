#!/usr/bin/env python3
"""
Record the BioMate website walkthrough:
  biomate.ai homepage → pricing → register → login → platform chat → query → results

Usage:
  python3 scripts/recording/record-website-demo.py \
    --timing recording/audio/website-demo/timing.json \
    --out recording/video/website-demo-raw.webm \
    [--email demo@example.com --password secret]

Auth: tries E2E bypass first, falls back to --email/--password form login,
      falls back to showing the login form without logging in.

Environment variables (alternative to CLI flags):
  BIOMATE_DEMO_EMAIL
  BIOMATE_DEMO_PASS
"""

import json, argparse, pathlib, os
from playwright.sync_api import sync_playwright

MARKETING_URL    = 'https://biomate.ai'
PLATFORM_URL     = 'https://dev-public.biomate.ai'
E2E_TOKEN        = 'biomate-e2e-bypass-token-dev-only'

STEP_BUFFER_MS   = 500
FINAL_HOLD_MS    = 2000

# What each step does (1-indexed, matching timing.json step numbers)
STEP_ACTIONS = {
    1:  ('goto',   MARKETING_URL,                    None),
    2:  ('scroll', None,                             800),    # scroll down to app cards
    3:  ('scroll', None,                             1600),   # scroll to pipeline section
    4:  ('goto',   f'{MARKETING_URL}/pricing.html',  None),
    5:  ('goto',   f'{PLATFORM_URL}/register',       None),
    6:  ('goto',   f'{PLATFORM_URL}/login',          None),
    7:  ('login',  None,                             None),   # auth + navigate to chat
    8:  ('type',   None,                             'Run ADMET profiling on this compound — SMILES: CC(C)CC1=CC=C(C=C1)C(C)C(=O)O'),
    9:  ('wait',   None,                             None),   # wait for workflow card
    10: ('panel',  None,                             None),   # open workflow panel
    11: ('run',    None,                             None),   # confirm & run
    12: ('wait',   None,                             None),   # show results
}


def try_e2e_auth(page) -> bool:
    """Attempt to auth via E2E bypass token. Returns True on success."""
    try:
        resp = page.request.post(
            f'{PLATFORM_URL}/api/auth/login',
            headers={'X-E2E-Test-Token': E2E_TOKEN, 'Content-Type': 'application/json'},
            data=json.dumps({'email': 'cryo_demo@biomate.test'}),
        )
        if resp.ok:
            print('  [auth] E2E bypass succeeded')
            return True
    except Exception as e:
        print(f'  [auth] E2E bypass failed: {e}')
    return False


def try_form_login(page, email: str, password: str) -> bool:
    """Fill login form and submit. Returns True on success."""
    if not email or not password:
        return False
    try:
        page.goto(f'{PLATFORM_URL}/login', wait_until='networkidle', timeout=15000)
        page.fill('input[type="email"], input[name="email"]', email, timeout=5000)
        page.fill('input[type="password"], input[name="password"]', password, timeout=5000)
        page.click('button[type="submit"]', timeout=5000)
        page.wait_for_url(f'{PLATFORM_URL}/**', timeout=10000)
        print(f'  [auth] Form login succeeded for {email}')
        return True
    except Exception as e:
        print(f'  [auth] Form login failed: {e}')
        return False


def perform_step(page, step_num: int, email: str, password: str, authenticated: list):
    """Execute the action for the given step number."""
    action, target, payload = STEP_ACTIONS.get(step_num, ('wait', None, None))

    if action == 'goto':
        page.goto(target, wait_until='domcontentloaded', timeout=20000)
        page.wait_for_timeout(800)

    elif action == 'scroll':
        page.evaluate(f'window.scrollTo({{top: {payload}, behavior: "smooth"}})')
        page.wait_for_timeout(600)

    elif action == 'login':
        if not authenticated[0]:
            # Try E2E bypass
            if not try_e2e_auth(page):
                # Try form login
                try_form_login(page, email, password)
            page.goto(PLATFORM_URL, wait_until='domcontentloaded', timeout=15000)
            page.wait_for_timeout(1200)
            authenticated[0] = True

    elif action == 'type':
        # Find chat textarea and type the query
        try:
            box = page.locator('textarea, [contenteditable="true"], input[type="text"]').first
            box.wait_for(state='visible', timeout=5000)
            box.click()
            page.wait_for_timeout(400)
            page.keyboard.type(str(payload), delay=30)
            page.wait_for_timeout(800)
        except Exception as e:
            print(f'  [type] Could not find chat input: {e}')

    elif action == 'panel':
        # Try to click the workflow card to open the panel
        try:
            card = page.locator('[data-testid="workflow-card"], .workflow-card, .wf-chip').first
            card.wait_for(state='visible', timeout=8000)
            card.click()
            page.wait_for_timeout(800)
        except Exception as e:
            print(f'  [panel] Could not click workflow card: {e}')

    elif action == 'run':
        # Click Confirm & Run button
        try:
            btn = page.locator('button:has-text("Confirm"), button:has-text("Run workflow")').first
            btn.wait_for(state='visible', timeout=8000)
            btn.click()
            page.wait_for_timeout(800)
        except Exception as e:
            print(f'  [run] Could not click run button: {e}')

    # 'wait' action: just hold for the narration duration (handled by caller)


def main():
    parser = argparse.ArgumentParser(description='Record BioMate website demo')
    parser.add_argument('--timing',   required=True, help='Path to timing.json')
    parser.add_argument('--out',      required=True, help='Output .webm path')
    parser.add_argument('--email',    default=os.environ.get('BIOMATE_DEMO_EMAIL', ''))
    parser.add_argument('--password', default=os.environ.get('BIOMATE_DEMO_PASS', ''))
    parser.add_argument('--width',    type=int, default=1920)
    parser.add_argument('--height',   type=int, default=1080)
    args = parser.parse_args()

    timing   = json.loads(pathlib.Path(args.timing).read_text())
    out_path = pathlib.Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    total_s = sum(t['duration_ms'] for t in timing) / 1000
    print(f'Website demo  |  {len(timing)} steps  |  ~{total_s:.0f}s')
    print(f'Output: {out_path}\n')

    authenticated = [False]   # mutable flag shared with perform_step

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=['--no-sandbox', '--disable-setuid-sandbox',
                  '--disable-dev-shm-usage', '--disable-gpu'],
        )
        context = browser.new_context(
            viewport={'width': args.width, 'height': args.height},
            record_video_dir=str(out_path.parent),
            record_video_size={'width': args.width, 'height': args.height},
        )
        page = context.new_page()

        # Start on marketing site
        print('Opening biomate.ai...')
        page.goto(MARKETING_URL, wait_until='domcontentloaded', timeout=20000)
        page.wait_for_timeout(2000)

        for i, step in enumerate(timing):
            hold = step['duration_ms'] + STEP_BUFFER_MS
            title = step['title'][:50]
            print(f'  [{step["step"]:02d}/{len(timing)}] {title}  ({hold}ms)')

            # Perform the action for this step
            perform_step(page, step['step'], args.email, args.password, authenticated)

            # Hold for narration duration
            page.wait_for_timeout(hold)

        page.wait_for_timeout(FINAL_HOLD_MS)

        print('\nSaving video...')
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
            print('WARNING: no video found')


if __name__ == '__main__':
    main()
