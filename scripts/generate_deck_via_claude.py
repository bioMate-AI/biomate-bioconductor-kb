#!/usr/bin/env python3
"""Call Claude API to generate v7 PPTX script, then run it."""
import anthropic, pathlib, subprocess, sys, os, re

api_key = open('/home/yzhang/biomate/frontend/.env').read()
api_key = next(l.split('=',1)[1].strip() for l in api_key.splitlines() if l.startswith('ANTHROPIC_API_KEY='))

client = anthropic.Anthropic(api_key=api_key)
v7_md = pathlib.Path('business/BioMate_Intro_Deck_v7.md').read_text()

print("Calling Claude API to generate v7 PPTX...")
response = client.messages.create(
    model="claude-opus-4-7",
    max_tokens=8096,
    messages=[{"role": "user", "content": f"""Write a complete python-pptx script to create BioMate_Intro_Deck_v7.pptx.

Design (match v6 exactly):
- Slide size: 9144000 x 5143500 EMU (16:9)
- Title: 26pt bold color #1E3A5F, pos left=600 top=250, width=9002 height=499
- Section labels: 12-14pt bold color #2D8659 (green)
- Body text: 11-12pt color #2C2C2C or #5A5A52
- Footer bar: filled rectangle top=4850 height=450 color #1E3A5F, white 12pt bold text on top of it
- Three-column layouts: x positions ~800, ~3900, ~7000, each width ~2400

Use helper function: add_text(slide, text, left, top, width, height, size, bold=False, color='2C2C2C', align='left')

Create 13 slides using this v7 content:

{v7_md[:7000]}

Save to: business/BioMate_Intro_Deck_v7.pptx
Output ONLY the executable Python code, no explanation, no markdown fences."""}]
)

script = response.content[0].text.strip()
# Strip markdown fences if present
script = re.sub(r'^```\w*\n?', '', script, flags=re.MULTILINE)
script = re.sub(r'\n?```\s*$', '', script, flags=re.MULTILINE)

script_path = pathlib.Path('scripts/create_deck_v7_claude.py')
script_path.write_text(script)
print(f"Script written ({len(script)} chars)")

result = subprocess.run([sys.executable, str(script_path)],
    capture_output=True, text=True, cwd='/home/yzhang/biomate')
if result.stdout: print(result.stdout[-600:])
if result.stderr: print("ERR:", result.stderr[-400:])

out = pathlib.Path('business/BioMate_Intro_Deck_v7.pptx')
if out.exists():
    print(f"\nSUCCESS: {out} ({out.stat().st_size//1024} KB)")
else:
    print("\nFAILED — file not created")
