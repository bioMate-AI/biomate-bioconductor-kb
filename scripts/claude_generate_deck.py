#!/usr/bin/env python3
"""Give Claude the v6 PPTX + v7 content and ask it to generate v7 from scratch."""
import anthropic, pathlib, subprocess, sys, re, os, base64

api_key = open('frontend/.env').read()
api_key = next(l.split('=',1)[1].strip() for l in api_key.splitlines() if l.startswith('ANTHROPIC_API_KEY='))
client = anthropic.Anthropic(api_key=api_key)

# Send v6 as PDF so Claude can see the design
v6_pdf = open('/tmp/BioMate_Intro_Deck_v6.pdf', 'rb').read()
v6_b64 = base64.standard_b64encode(v6_pdf).decode()

v7_md = pathlib.Path('business/BioMate_Intro_Deck_v7.md').read_text()

print("Calling Claude with v6 PDF + v7 content...")
r = client.messages.create(
    model="claude-opus-4-7",
    max_tokens=8096,
    messages=[{"role": "user", "content": [
        {
            "type": "document",
            "source": {"type": "base64", "media_type": "application/pdf", "data": v6_b64},
            "title": "BioMate_Intro_Deck_v6.pdf"
        },
        {
            "type": "text",
            "text": f"""This PDF is the v6 BioMate deck. Study its visual design carefully — layouts, colors, section structures, font hierarchy.

Now write a complete python-pptx script that creates business/BioMate_Intro_Deck_v7.pptx from scratch, matching v6's visual design exactly but with this v7 content:

{v7_md[:6000]}

Requirements:
- Match v6 slide layouts, color scheme, font sizes exactly
- 13 slides with correct v7 content
- Use helper functions to avoid repetition
- Save to: business/BioMate_Intro_Deck_v7.pptx
- Print confirmation when done

Output ONLY the Python code, no explanation."""
        }
    ]}]
)

script = r.content[0].text.strip()
if '```' in script:
    m = re.search(r'```(?:python)?\n(.*?)```', script, re.DOTALL)
    if m: script = m.group(1)
# strip any leading ``` if still there
script = re.sub(r'^`+\w*\n?', '', script)

pathlib.Path('scripts/fix_deck_v7_visual.py').write_text(script)
print(f"Script: {len(script)} chars. Running...")

result = subprocess.run([sys.executable, 'scripts/fix_deck_v7_visual.py'],
    capture_output=True, text=True, cwd='/home/yzhang/biomate')
if result.stdout: print(result.stdout[-600:])
if result.stderr: print("ERR:", result.stderr[-400:])

size = os.path.getsize('business/BioMate_Intro_Deck_v7.pptx')
print(f"\nDone: {size//1024} KB")
