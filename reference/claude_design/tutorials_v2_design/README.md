# BioMate tutorial walkthroughs — redesign handoff

Each subfolder is **one tutorial**, containing its English (`*-walkthrough.html`) and
Simplified-Chinese (`*-walkthrough.zh.html`) slide deck. Shared image assets live once
in `assets/` at this top level; the HTMLs reference them as `../assets/…`, so every deck
opens and renders self-contained from this folder (zip the whole folder to share).

**22 tutorials (44 decks):** t0–t4 (getting-started series) · m1–m3 · d1–d4 · s1 / s2 /
s4 · rb-routing / rb-param-prefill / rb-protocol-qc / rb-boin · qpcr-ddcq ·
b1-train-custom-model · drug-dev.

## For the design pass
Reformat the decks into one consistent, professional visual system. The full brief —
including the recording/mux **contract that MUST be preserved** (scene count/order,
`data-seconds`, `window.__timeline` / `window.__done`, the `.scene.active` toggle, the
`<img src="../assets/…">` screenshot slots, per-scene `.caption` text, EN/中文 parity,
1920×1080 headless-safe) — is in the repo at:

> `docs/20261019_TUTORIAL_WALKTHROUGH_REDESIGN_BRIEF.md`

After the reformat, updated screenshots and corrected narration are re-applied on top,
so keep the image slots and scene structure intact.
