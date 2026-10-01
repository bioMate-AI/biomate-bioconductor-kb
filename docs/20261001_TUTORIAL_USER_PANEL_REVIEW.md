# Layman-Tutorial User Panel Review — T1 Design & Generate (+ reusable checklist)

**Date:** 2026-10-01
**Method:** 5-reviewer user panel, different backgrounds, multiple LLMs (Opus + Sonnet), each reading
`docs/user-manual/tutorials/T1-design-and-generate.md` as a specific persona and judging whether it works
for *their* background.
**Outcome:** T1 revised to v2 applying all consensus feedback. This doc records the findings and a
**reusable checklist** every layman tutorial (`docs/user-manual/tutorials/*`) should satisfy before review.

## Panel & scores (v1)
| Persona | Model | Score | One-line |
|---|---|---|---|
| Non-scientist / BD-investor | Sonnet | 3/5 | §1 lands; §4–5 assume prior tool experience; needs business anchor + SMILES source |
| Wet-lab biologist | Sonnet | 3/5 | Blocked at Step 3: has a *protein* target, box wants a *molecule* seed; where does a seed come from? |
| Medicinal chemist (accuracy) | Opus | 4/5 | Simple and (almost) correct; 2 factual slips + "structural alerts not known-toxic" |
| Clinician / MD | Opus | 4/5 | Followed the logic but never anchored to a disease/patient; add a disease+target example |
| Student / non-native (CN) | Sonnet | 3/5 | Idioms + long sentences hurt translation; Steps 3 & 6 need input/format hints |

## Consensus findings (found by ≥2 personas → high-confidence)
1. **SMILES unexplained + no source** (BD, biologist, clinician, student) → name SMILES; say "look it up on PubChem/ChEMBL, copy Canonical SMILES; your chemist can provide it."
2. **MW/logP/TPSA defined but not motivated** (BD, biologist, clinician, student) → say *why they matter* in the reader's terms (oral pill vs injection, membrane/brain crossing, inside- vs surface-cell target).
3. **"Target / seed" box confusion** (biologist, clinician, student) → clarify the input is a *molecule* (seed), the *target* is a protein, and where to get a seed if you only have the target.
4. **Pareto glossary is circular + "how do I act on it?"** (BD, biologist, student) → explain reading the trade-off edge; clarify the §5 screenshot is the table, the chart is separate.
5. **No disease/patient/business anchor** (clinician, BD, biologist) → add a recognizable disease+target (JAK1/RA), a "months→minutes" ROI line, who-acts-on-results, and "how far from a real drug."
6. **Idioms + long sentences** (student, BD) → remove "riff on / throwing out / black box / design around / envelope"; use "window" consistently; break compound sentences.

## Accuracy fixes (medicinal chemist, authoritative)
- **Chemical-space number wrong** → "~10⁶⁰, more than stars in the observable universe" (was "atoms in the solar system").
- **"most potent = least safe" is a false law** → "improving one goal often drags another down."
- **Safety gate = structural alerts** → "a caution flag, not a toxicity measurement" (not "known-toxic").
- **"runs in seconds"** → "under a minute" (don't imply it's doing full docking/physics).
- Biologist nuances: **liver = metabolism, not just hepatotoxicity**; **absorption ≠ clearance** (separate them).
- **Be honest the tool doesn't score target-binding/potency today** (no trained predictor → "not available", never a fabricated number) — the chemist called the no-fabrication posture the single best trust-builder; made it explicit.

## Strengths to preserve (all personas)
Background-first structure; "shortlist not a blank page" one-liner; visible safety gate; **unblended** objectives; "why?" per-row provenance; honest empty-states; the no-fabricated-numbers posture.

---

## Reusable checklist for EVERY layman tutorial (apply before review)
- [ ] **Motivation first** — the real-world problem + a recognizable disease/target example, before any mechanism.
- [ ] **Define every professional term in-line**, with *why it matters* to the reader (not just what it is).
- [ ] **No unexplained inputs** — for any field the user fills, say what format it is and *where to get the value*.
- [ ] **Interpretation, not just steps** — teach how to *read the result* (what's good/bad, what to do next).
- [ ] **Plain English, translation-ready** — no idioms; short sentences; consistent vocabulary (for CN translation).
- [ ] **Scientifically correct even when simplified** — simple must never become wrong; no fabricated numbers.
- [ ] **Honest about limits** — what runs today vs. not, surfaced early (not buried at the end).
- [ ] **Who acts / how far along** — the human hand-offs and realistic expectations.
- [ ] **Glossary adds usage value** (when you'd care / what number is concerning), not circular definitions.
- [ ] **Real, high-DPI, readable screenshots** (DSF3 + zoom + focused captures) showing a *populated* result.

## T2 (Models & the closed loop) — panel round
Scores: BD 3/5 · biologist 3/5 · ML-accuracy 4.5/5 · clinician 4/5 · student 3/5. Consensus fixes applied to T2 v2:
- **Accuracy (ML):** fixed the §6 "genuinely better on a fair test" overclaim (active-learning: held-out set goes stale) → "re-checked on untrained data; keeping up, not a score to climb"; decoupled "passed floor" from "trustworthy for *your* molecule" (tie to applicability); added the term **applicability domain** + a concrete example (kinase model vs peptide); softened "nothing deleted" → "every version kept, not overwritten"; stub = "not a real *prediction*"; Boltz-2 noted to do complexes, not only structure.
- **Clarity (all):** defined inference / held-out / applicability / retraining in-line on first use; added an exam analogy for the held-out gate.
- **De-duplication (BD, clinician):** the stub caveat appeared ~5× → consolidated to one line.
- **Value anchor (BD moat + clinician endpoint):** added a measured "why this matters" — workspace-private learning (moat) + patient/translation — with the honest note that the loop uses **bench/assay** data today (clinical data entering = forward direction).
- **Participation (biologist):** clarified §6 step 3 — what retraining is, who triggers it, that results feed back via a **campaign** (not a /models button), and the minimum measurements needed — without fabricating an exact upload form.
- **Clinical (clinician):** added an *illustrative* RA/JAK1 vignette ending at a cardiac-safety (hERG/QT) endpoint, clearly labelled illustrative.
- **Translation (student):** removed idioms ("compounding", "take it on faith", "windows onto"→"monitoring views", "one-shot", "ground truth"); shortened long sentences.

## Change log
- 2026-10-01 — 5-persona multi-LLM panel run on T1; T1 revised to v2 against all consensus + accuracy findings; reusable checklist extracted for the remaining tutorials (Models/closed-loop, workflow-run, etc., EN then CN).
