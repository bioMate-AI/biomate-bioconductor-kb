#!/usr/bin/env python3
"""Send v6 and v7 slide images to Claude for visual review and fix generation."""
import anthropic, pathlib, subprocess, sys, re, os, base64, glob

api_key = open('frontend/.env').read()
api_key = next(l.split('=',1)[1].strip() for l in api_key.splitlines() if l.startswith('ANTHROPIC_API_KEY='))
client = anthropic.Anthropic(api_key=api_key)

def img_content(path, label):
    data = base64.standard_b64encode(open(path,'rb').read()).decode()
    return [
        {"type": "text", "text": label},
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": data}}
    ]

v6_slides = sorted(glob.glob('/tmp/v6_slide-*.png'))
v7_slides = sorted(glob.glob('/tmp/v7_slide-*.png'))

print(f"Sending {len(v6_slides)} v6 slides + {len(v7_slides)} v7 slides to Claude...")

content = [{"type": "text", "text": """You are reviewing a PowerPoint deck redesign.

I will show you:
- LEFT/V6: The original v6 deck slides (reference design - this is the TARGET visual style)
- RIGHT/V7: The current v7 deck slides (needs to match v6 visually but with updated content)

Please:
1. Identify every slide where v7 looks wrong compared to v6 (wrong content, missing sections, bad formatting, old text remaining)
2. Write a complete python-pptx script that fixes ALL issues in business/BioMate_Intro_Deck_v7.pptx

The v7 slides should have the SAME visual design as v6 (same layouts, colors, section structures) but with UPDATED content per the v7 plan.

Here are both decks side by side:
"""}]

# Add paired slides
for i, (v6, v7) in enumerate(zip(v6_slides, v7_slides)):
    content.extend(img_content(v6, f"\n--- SLIDE {i+1} V6 (reference) ---"))
    content.extend(img_content(v7, f"--- SLIDE {i+1} V7 (current, needs fixing) ---"))

# Add remaining v7 slides if more than v6
for i, v7 in enumerate(v7_slides[len(v6_slides):], len(v6_slides)):
    content.extend(img_content(v7, f"\n--- SLIDE {i+1} V7 only ---"))

content.append({"type": "text", "text": """
Now write a complete python-pptx script that:
1. Opens business/BioMate_Intro_Deck_v7.pptx
2. Fixes ALL the issues you identified visually
3. Makes v7 match v6's layout and structure with the correct v7 content
4. Saves the file
5. Prints what was fixed

Key v7 content updates needed (from the plan):
- Slide 1: Cover — BioMate AI, tagline, pharma/biotech platform
- Slide 2: The Problem (Speed/Cost/Quality — NOT Knowledge Gap/Cost&Access/Slow Cycles)
- Slide 3: The Solution (ASK/CONFIRM/RESULTS — NOT THINK/EXECUTE/COLLABORATE)
- Slide 4: Product Coverage (Drug Discovery/Genomics/Structural/Regulatory)
- Slide 5: Evidence-Graded QC (GOLD/SILVER/BRONZE)
- Slide 6: Traction (real metrics only — no fabricated numbers)
- Slide 7: Market Opportunity (TAM/SAM/SOM + timing signals)
- Slide 8: Business Model (Free/Premium/Team/Enterprise pricing table)
- Slide 9: Financial Projections (Year 1 revenue + 3-year projection)
- Slide 10: Go-To-Market (4 phases)
- Slide 11: Team (Yaoyun Zhang + core team)
- Slide 12: The Ask ($1M-$2M seed)
- Slide 13: Empty/Appendix

Output ONLY the Python code."""})

r = client.messages.create(
    model="claude-opus-4-7",
    max_tokens=8096,
    messages=[{"role": "user", "content": content}]
)

script = r.content[0].text.strip()
if '```' in script:
    m = re.search(r'```(?:python)?\n(.*?)```', script, re.DOTALL)
    if m: script = m.group(1)

pathlib.Path('scripts/fix_deck_v7_visual.py').write_text(script)
print(f"Script written ({len(script)} chars). Running...")

result = subprocess.run([sys.executable, 'scripts/fix_deck_v7_visual.py'],
    capture_output=True, text=True, cwd='/home/yzhang/biomate')
if result.stdout: print(result.stdout[-800:])
if result.stderr and 'Error' in result.stderr: print("ERR:", result.stderr[-500:])

size = os.path.getsize('business/BioMate_Intro_Deck_v7.pptx')
print(f"\nDone: business/BioMate_Intro_Deck_v7.pptx ({size//1024} KB)")
