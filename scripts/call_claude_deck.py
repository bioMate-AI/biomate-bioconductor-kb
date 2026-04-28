#!/usr/bin/env python3
import anthropic, pathlib, subprocess, sys, re, os

api_key = open('frontend/.env').read()
api_key = next(l.split('=',1)[1].strip() for l in api_key.splitlines() if l.startswith('ANTHROPIC_API_KEY='))

client = anthropic.Anthropic(api_key=api_key)
deck_state = open('/tmp/deck_state.txt').read()
v7_md = pathlib.Path('business/BioMate_Intro_Deck_v7.md').read_text()[:5000]

print("Calling Claude API...")
r = client.messages.create(
    model="claude-opus-4-7",
    max_tokens=8096,
    messages=[{"role": "user", "content": f"""Fix business/BioMate_Intro_Deck_v7.pptx using python-pptx. Keep all visual design (colors, backgrounds, images). Fix text content only.

CURRENT SHAPE STATE (slide index, shape index sorted by top, font, current text):
{deck_state}

TARGET CONTENT from v7.md:
{v7_md}

SPECIFIC FIXES NEEDED:
1. Slide index 1 (The Problem): shape[1] title = "The Problem" only. shape[4] at top=950 = "Computationally demanding biomedical work is a bottleneck at every stage of the pipeline."
2. Slide index 4 (QC): body text under GOLD/SILVER/BRONZE needs proper newlines between sentences
3. Slide index 9 (GTM): shape[1] title = "Go-To-Market: We Grow the Way Science Grows."
4. Verify slides 11 (Team) and 12 (The Ask) match v7.md content

Write a complete python-pptx script that:
- Opens business/BioMate_Intro_Deck_v7.pptx
- Makes targeted fixes using shape indices from the state above
- Saves back to the same file
- Prints confirmation

Output ONLY executable Python code, no markdown."""}]
)

script = r.content[0].text.strip()
if script.startswith("```"):
    m = re.search(r'```(?:python)?\n(.*?)```', script, re.DOTALL)
    if m: script = m.group(1)

pathlib.Path('scripts/fix_deck_v7.py').write_text(script)
print(f"Script written ({len(script)} chars). Running...")

result = subprocess.run([sys.executable, 'scripts/fix_deck_v7.py'],
    capture_output=True, text=True, cwd='/home/yzhang/biomate')
if result.stdout: print(result.stdout[-500:])
if result.stderr: print("ERR:", result.stderr[-400:])

size = os.path.getsize('business/BioMate_Intro_Deck_v7.pptx')
print(f"\nFinal: business/BioMate_Intro_Deck_v7.pptx ({size//1024} KB)")
