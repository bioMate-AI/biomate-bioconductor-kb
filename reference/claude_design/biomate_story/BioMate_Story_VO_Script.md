# BioMate — Story Intro · Voiceover Script & Production Notes

Companion to **BioMate_Story.html**. Target runtime ≈ 75 seconds.

## How to turn the HTML into a video

1. Open `BioMate_Story.html` in a browser (Chrome). It auto-fits any screen.
2. Press **space** to autoplay — each scene advances on its own timing, with a
   progress bar. The player chrome auto-hides so the frame stays clean.
3. **Screen-record** the autoplay run, or step manually with **→**.
4. Alternatively: **Cmd/Ctrl+P → Save as PDF** exports one clean 1920×1080
   frame per scene (no chrome) — drop those stills into any video editor.
5. Press **S** any time to show this voiceover script on screen; **H** hides
   all player UI.

## Voiceover script

| Scene | Duration | Narration |
|---|---|---|
| 1 — The question | ~8s | "Every discovery begins with a question." |
| 2 — The friction | ~9s | "But in the lab, the answer can take weeks — lost in queues, handoffs, and six-figure CRO invoices." |
| 3 — The turn | ~8s | "What if the lab could think alongside you?" |
| 4 — Ask | ~9s | "With BioMate, you ask in plain language — and it maps your question to a validated, expert-grade workflow." |
| 5 — The work | ~10s | "From target discovery to a regulatory submission package — six stages of computational work, handled in one conversation." |
| 6 — Defensible | ~10s | "Every result stays traceable. Every number stays citable — built to survive scientific and regulatory review." |
| 7 — Trust | ~9s | "Thousands of validated workflows, quality-controlled at every step. Science you can stand behind." |
| 8 — The vision | ~8s | "A virtual lab that thinks — and shows its work." |
| 9 — Close | ~5s | "BioMate. From question to defensible result." |

## Direction notes

- **Tone:** scenes 1–2 soft and curious; scene 3 is the lift / turning point;
  4–7 confident and clear; 8 warm; 9 settles.
- **Music:** a single understated bed — slow piano or warm synth pad. Let it
  swell slightly into scene 8, resolve on the logo.
- **Captions:** add burned-in captions in your video tool — the on-screen
  text is the kinetic headline, not a substitute for subtitles.
- **Pacing:** scene timings live in each `<section data-dur="…">` in the HTML;
  adjust there if your VO runs long or short.

## Two things to decide

1. **Voice** — a calm, credible read (think the Medtronic reference). AI VO is
   fine for v1; a human read lands better for the final.
2. **Open vs. registered** — scene 9 ends on `biomate.ai`. Confirm that's the
   URL you want on the card before final render.

## Note on reuse

This same HTML can double as an **autoplaying hero** embedded on the BioMate
webpage — it's self-contained (logo embedded, no external assets) and scales
to any container.
