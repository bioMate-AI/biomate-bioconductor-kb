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

## Acceptance re-review (2nd panel round, on revised T1 v2 + T2 v2)
Each persona re-read both revised tutorials, verified prior fixes landed, re-scored.
- **T1:** BD 4.5 · biologist 4 · accuracy **5** · clinician 4 · student 4 → **ship-ready** (prior issues confirmed fixed; minor polish applied).
- **T2:** BD 4.5 · biologist 3.5 · accuracy **5** · clinician 4.5 · student 4 → **ship-ready** after polish (biologist's "how does bench data get back" addressed with an honest, concrete-as-verifiable hand-back paragraph — campaign-mediated, assay defined, no fabricated upload UI).
- Final polish applied (committed): clinical-toxicity anchor on T1 safety gate; "Target/seed box takes a molecule" inline note; de-idiom sweep (removed surviving "window onto"/"compounds"); softened the moat line to a factual privacy statement; applicability-domain consequence; `drug_like` flagged heuristic; retraining → "combined data". Idiom scan clean on both.
- **Process lesson:** the first revision of T2 did a partial-only search/replace (two flagged idioms survived) — always re-scan for every flagged term after revising, which is what the acceptance round caught.

## T3 (Running a workflow & reading the report) — panel round
Grounded in a REAL completed run (in_vivo_cart_codesign, 4 phases, 11 outputs) captured at HQ. Scores: BD 3 · biologist 3 · accuracy 4 · clinician 4 · student 3 → revised to v2.
- **Accuracy (must-fix, verified vs screenshots):** checksums are **compute-on-demand** (screenshot shows "–" + "Compute checksums") — reworded (was "every output has a checksum"); softened the **CD19/DLBCL/T-cell parameter** claim (the reproducibility record shows empty params / 0 input bindings — no Phases screenshot to back it); fixed **fratricide** (T-cells killing *each other*; CD19 not on T-cells → check passes, not a real concern here); nuanced **LNP tropism** (biodistribution to the right cells, not "choosing a vehicle"); added in-vivo-vs-ex-vivo context.
- **Honesty framing (BD+clinician+biologist):** reframed the withheld-Summary as a deliberate feature **before** the screenshot (not a buried apology); said what a *normal* Summary shows; qualified "validated" (= established methods, not clinical proof); promoted "never silently passes a failed check" as a trust feature.
- **Content gaps (biologist):** added a **"bringing your own data"** concept + step (FASTQ/CSV/FASTA/SMILES); explained the `1e2dca6c` step-hash labels; added a clinical **go/no-go + "in-silico aid, not clinical evidence"** note; defined Atlas-safety/LNP/fratricide in plain clinical terms.
- **Clarity/translation (student):** de-idiomed ("stitching tools together", "wired together", "fix-and-retry loop", "defensible rather than just done", "six months later", "end to end", "nothing is hidden/discarded"); defined "audit trail"/"manifest"/checksum inline; glossed RNA-seq/variant-calling/file-types; added action guidance to steps 2/4/5.
- Note: couldn't show a *populated* Summary (dev output-access issue withholds findings) — handled honestly rather than faking one; this is itself a real product gap to fix (findings path can't read run outputs on dev).

## T3 Chinese (zh/T3) — native-Chinese review round
Native-CN translator+reviewer read EN source + CN side by side. Scores: idiomatic naturalness 4/5 · **fidelity 5/5**
(all six honesty caveats verified intact: validated≠clinically-proven, findings *withheld* not fabricated, in-silico
aid≠patient-data, in-vivo-vs-ex-vivo, checksums compute-on-demand, CN-UI-screenshot note correctly added) · terminology 4/5.
Fixes applied + committed:
- **P1 correctness:** `脱靶于肿瘤之外…` inverted the meaning (脱靶 = *off-target* in CN) → rewrote to the proper
  "在靶、脱瘤" (on-target, off-tumour) with a plain gloss. This was the one must-fix-before-ship item.
- **De-calque:** `为…结果辩护` ("justify", 3×, carries a legal/defensive tone) → 解释清楚/有理有据/给出解释和依据;
  `都不是一步` → `都不是一步就能完成的`; `最清晰视角` → `最直观的界面`.
- **Terminology:** standardized audit-trail to `审计记录` throughout (was mixed 审计记录/审计留痕); `输入框` →
  `编排区 / Composer` (named UI surface); `三个分节标签` → `三个板块标签`; `一种模式` → `一种治疗方式`.
- Residual-term scan clean (辩护/脱靶/审计留痕/输入框 all gone). **CN T3 ship-ready.**

## T0 (Getting started — your first question) — panel round
5-persona multi-LLM panel. Scores: BD 4 · biologist 4.5 · accuracy 4 · clinician 4.5 · student 3.5 (avg ≈4.1) → **light revision**, applied:
- **P1 overclaim (accuracy):** "BioMate never fabricates to fill a section" → "is built not to pad a section with invented content" (the anti-confab guard is a protection, not an absolute guarantee — see [[project_research_confabulation]]); "keeps only the sources…every item is a source the text leaned on" → "lists only the sources…rather than a padded bibliography".
- **P2 hedge unverified UI (honest CAPTURE posture):** lane-restatement "shows" → "is designed to show" (it's CAPTURE-pending); softened the "open → reader pane" and "Check against our data" button claims to action-level wording until verified on the live `/` route.
- **P3 dangling refs:** reframed the cold "Patents option" as "if you ask a patent/FTO question, the 'Patents' framing is a doorway…"; lane-override now says "adjust your wording (or pick the lane in the message box)".
- **P4 de-idiom (translation-ready):** dossier→report; front desk/"points you the right way"→reception desk/"points you in the right direction"; "spending compute"→"paid computation"; split the long §1 either/or sentence.
- Confirmed by panel: nothing claimed to auto-run; Instant/Cloud accurate; no invented module; the one real screenshot (i01-1-cold-start.png) referenced correctly; 2 CAPTURE placeholders are the known acceptable gap. **EN T0 ship-ready after these edits; CN T0 to follow.**

## T4 (Bringing your own data) — panel round
5-persona multi-LLM panel, verified against the code-truth `modules/I05-files-and-dataset-object.md`. Scores: BD 4 · biologist 4 · accuracy 4 · clinician 4 · student 4 (avg 4.0) → **light revision**, applied:
- **P1 accuracy (caption↔image mismatch — the gate):** the i05-3 screenshot is a **FASTQ flagged Watch** (reads / read length / mean Phred / "below 20 — consider trimming"), but the caption described table-only fields → rewrote caption to match the real image; added a "for sequencing reads it shows reads, read length, average base quality (Phred) instead of rows/columns" clause to the §5 Quality bullet.
- **P2 accuracy (lineage):** "each result's Lineage pointing at the **input**" overstated it — per I05 the Lineage tab shows the producing **run/workflow/step** → reworded to "points back to the run that produced it (and that run records the input)".
- **P3 (biologist):** flagged that a **FASTA stays grey** (profiler doesn't read it, not a problem) at the quality-dot step; added a paired-end FASTQ (R1/R2 — bring both) note to the file-types list.
- **P4 de-idiom (translation-ready):** "the thing everything orbits"→"the centre everything connects to"; "bookkeeping…where mistakes hide"→"manual tracking…where mistakes creep in"; "judge it at a glance"→"see its status at once"; "go ahead"→"you can proceed".
- **Disease-anchor decision:** panel recommended keeping the **generic** CSV/FASTQ example (format-agnostic mechanic is clearer generic) + ONE RA/JAK1 continuity sentence for series thread → added "e.g. a CSV of JAK1-inhibitor assay readings from Tutorial 1, or RNA-seq reads from a rheumatoid-arthritis cohort" in §4.
- Panel confirmed: grey="not profiled, never bad", profiled types, versions-log-not-undo, project-scoping, lineage-not-clickable, honest-empty consumers all faithful to I05; 4 screenshots real + correctly referenced. **EN T4 ship-ready after these edits; CN T4 to follow.**
- **Follow-up logged:** the I05 module doc's own i05-3 caption has the same FASTQ/Watch-vs-table defect — fix alongside.

## Change log
- 2026-10-01 — 5-persona multi-LLM panel run on T1; T1 revised to v2 against all consensus + accuracy findings; reusable checklist extracted for the remaining tutorials (Models/closed-loop, workflow-run, etc., EN then CN).
- 2026-10-01 — T3 EN 5-persona panel + revision; CN T3 written and native-CN-reviewed (fidelity 5/5); one correctness term fix (脱靶→在靶脱瘤) + de-calque/terminology polish applied. **T1/T2/T3 now complete and validated in EN + CN.**
