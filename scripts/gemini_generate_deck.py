#!/usr/bin/env python3
"""Use Gemini to generate v7 PPTX from v6 reference PDF + v7 content."""
import pathlib, subprocess, sys, re, os
from google import genai
from google.genai import types

api_key = open('frontend/.env').read()
api_key = next(l.split('=',1)[1].strip() for l in api_key.splitlines() if l.startswith('GEMINI_API_KEY='))
client = genai.Client(api_key=api_key)

v6_pdf_bytes = open('/tmp/BioMate_Intro_Deck_v6.pdf', 'rb').read()
v7_md = pathlib.Path('business/BioMate_Intro_Deck_v7.md').read_text()

print("Uploading v6 PDF to Gemini...")
# Upload file via Files API
import tempfile
with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as f:
    f.write(v6_pdf_bytes)
    tmp_pdf = f.name

uploaded = client.files.upload(file=tmp_pdf, config={'mime_type': 'application/pdf'})
print(f"Uploaded: {uploaded.name}")

print("Calling Gemini to generate v7 deck script...")
response = client.models.generate_content(
    model='gemini-2.5-pro',
    contents=[
        types.Part.from_uri(file_uri=uploaded.uri, mime_type='application/pdf'),
        f"""This PDF is the BioMate v6 investor deck. Study its visual design:
- Colors: navy #14283a, green #2D8659, cream/light background, gold accents
- Layout: title at top (26pt bold navy), section labels (12-14pt bold green), body text (11-12pt dark gray)
- Footer bar at bottom: dark navy rectangle with white bold text
- Three-column layouts for key slides
- Slide size: 10" x 5.625" (widescreen 16:9)

Write a complete python-pptx script that creates business/BioMate_Intro_Deck_v7.pptx.
Match v6 visual design EXACTLY. Use this v7 content for all 13 slides:

{v7_md}

Requirements:
- Use helper functions: add_text(), add_footer(), add_title(), three_col()
- All 13 slides with correct v7 content matching the v7.md document above
- Save to: business/BioMate_Intro_Deck_v7.pptx
- Print success message

Output ONLY the Python code, no explanation, no markdown fences."""
    ],
    config=types.GenerateContentConfig(max_output_tokens=16384)
)

script = response.text.strip()
if '```' in script:
    m = re.search(r'```(?:python)?\n(.*?)```', script, re.DOTALL)
    if m: script = m.group(1)
script = re.sub(r'^`+\w*\n?', '', script)

pathlib.Path('scripts/fix_deck_v7_gemini.py').write_text(script)
print(f"Script: {len(script)} chars. Running...")

result = subprocess.run([sys.executable, 'scripts/fix_deck_v7_gemini.py'],
    capture_output=True, text=True, cwd='/home/yzhang/biomate')
if result.stdout: print(result.stdout[-800:])
if result.stderr: print("ERR:", result.stderr[-500:])

if os.path.exists('business/BioMate_Intro_Deck_v7.pptx'):
    size = os.path.getsize('business/BioMate_Intro_Deck_v7.pptx')
    print(f"\nDone: business/BioMate_Intro_Deck_v7.pptx ({size//1024} KB)")
else:
    print("\nFAILED - file not created")

os.unlink(tmp_pdf)
