import base64, json, os, re, sys, urllib.request, pathlib
# Usage: python3 frontend/scripts/gemini_ui_tune.py <screens_dir> <out.css> [prev.css]
#   env PROTO_IMAGES=a.jpg,b.jpg  TOKENS=token_sheets.css  EXTRA="reviewer notes"  SELECTORS=selectors.txt
# Pair with frontend/scripts/ui_tune_capture.mjs (renders dev with a CSS override injected).
KEY = open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
MODEL = os.environ.get("GEMINI_MODEL", "google/gemini-3.1-pro-preview")
round_dir, out_css = sys.argv[1], sys.argv[2]          # screenshots to show, file to write
prev_css = sys.argv[3] if len(sys.argv) > 3 else None   # previous override (for critique rounds)

def img(p):
    return {"type": "image_url", "image_url": {"url": "data:image/png;base64," + base64.b64encode(open(p, "rb").read()).decode()}}

BRIEF = f"""You are the visual designer tuning the appearance of BioMate, a scientific-workflow web app (React + Tailwind/shadcn + CSS custom properties).

FOUNDER DIRECTIVE (verbatim intent): "The current UI uses too much light grey, without difference among elements — boring and hard to read. The prototype's main idea is agreed, but do NOT change to purple."

You get: (A) screenshots of the LIVE app as it renders now, (B) prototype images showing the agreed direction (ignore their purple/indigo accent — only take their surface separation, contrast, type size, and hierarchy), (C) the real token sheets.

HARD CONSTRAINTS
1. Keep BioMate's brand accent: cerulean blue hsl(202 100% 37%) = #007fbd (oklch ≈ 0.55 0.14 245). You may add a darker ink and a soft tint of it. NO purple/indigo/violet anywhere.
2. Output ONE CSS file that is injected AFTER the existing sheets. It must work purely by (a) redefining existing custom properties in the same scopes (:root for index.css shadcn HSL tokens — values are bare 'H S% L%' triples; :root for --bm-* oklch tokens and the unprefixed aliases; .wf-panel for panel tokens) and (b) optionally a SMALL number of rules using selectors that certainly exist: body, [data-sidebar="sidebar"], .wf-panel, html. Do not invent class names.
3. Light mode only (do not touch .dark).
4. Goals: clear surface hierarchy (sidebar visibly tinted vs. white canvas; cards white on a slightly tinted canvas OR tinted on white — pick one and be consistent), borders that are actually visible where they separate things, primary text near-black, secondary text dark enough to read (WCAG AA ≥4.5:1 on its surface), status colors (ok/warn/err) saturated enough to read, slightly larger base text (currently 12–13px reads as tiny). Restrained, high-end (Linear/Stripe level) — contrast via surfaces and type, not via more lines.
5. Every value must be justified in a short CSS comment.

Return ONLY the CSS inside one ```css block, then after it a short bullet list of what you changed and why."""

content = [{"type": "text", "text": BRIEF}, {"type": "text", "text": "(A) LIVE APP NOW — landing, run manager, workspace with workflow panel:"}]
for p in sorted(pathlib.Path(round_dir).glob("*.png")): content.append(img(str(p)))
content.append({"type": "text", "text": "(B) PROTOTYPES (direction only — NOT the purple):"})
for p in filter(None, os.environ.get("PROTO_IMAGES", "").split(",")):
    b = base64.b64encode(open(p, "rb").read()).decode()
    content.append({"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + b}})
content.append({"type": "text", "text": "(C) CURRENT TOKEN SHEETS:\n" + open(os.environ["TOKENS"]).read()})
if prev_css:
    content.append({"type": "text", "text": "ROUND NOTE: the screenshots in (A) ALREADY have your previous override (below) injected. Critique them honestly against the directive, then return an improved COMPLETE override file (not a diff).\nPREVIOUS OVERRIDE:\n" + open(prev_css).read()})

if os.environ.get("SELECTORS"): content.append({"type": "text", "text": "REAL SELECTORS that exist in the app's CSS (you MAY target these and only these, in addition to the token scopes):\n" + open(os.environ["SELECTORS"]).read()})
if os.environ.get("EXTRA"): content.append({"type": "text", "text": "REVIEWER OBSERVATIONS on the rendered result (address each):\n" + os.environ["EXTRA"]})
req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions",
    data=json.dumps({"model": MODEL, "messages": [{"role": "user", "content": content}], "max_tokens": 16000}).encode(),
    headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
resp = json.load(urllib.request.urlopen(req, timeout=600))
choice = resp["choices"][0]
txt = choice["message"].get("content") or ""
open(out_css + ".response.md", "w").write(txt)
m = re.search(r"```css\s*(.*?)```", txt, re.S)
if not m:
    print("NO CSS BLOCK; finish_reason=", choice.get("finish_reason"), "usage=", resp.get("usage")); print(txt[:2000]); sys.exit(1)
open(out_css, "w").write(m.group(1))
print("model", resp.get("model"), "usage", resp.get("usage", {}).get("total_tokens"), "cost", resp.get("usage", {}).get("cost"))
print(txt[m.end():][:3000])
