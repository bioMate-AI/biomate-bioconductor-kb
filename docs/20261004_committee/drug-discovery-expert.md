# Drug-Discovery / Computational-Chemistry Expert Audit — BioMate Tutorial Videos

**Date:** 2026-10-04 · **Auditor lens:** skeptical drug-dev / comp-chem domain expert
**Scope audited (source, not rendered video):**
- Walkthrough HTML: `reference/claude_design/tutorials/drug-dev-walkthrough.html` (flagship T11), `t1-design-and-generate-walkthrough.html`, `t2-models-and-the-closed-loop-walkthrough.html`, plus t0/t3/t4.
- Narration: `reference/claude_design/tutorials/narration/{drug-dev,t1-design-and-generate,t2-models-and-the-closed-loop}.{en,zh}.md`.
- Written tutorials: `docs/user-manual/tutorials/{T1,T2,T11}-*.md`.
- Cross-checks: `docs/20260922_DECK_CAPABILITY_HONESTY_AUDIT.md`, `docs/20260923_DOMAIN_VALIDATION_RESULTS.md`, workflow source under `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/`.

---

## 1. Verdict

**Overall: substantially honest and scientifically literate — the best-hedged marketing science I have audited — but with one material self-contradiction and a recurring "available / runs on cloud" framing that is more generous than both the written manual and the internal reality.**

The conceptual chemistry is accurate and unusually well-caveated: docking-vs-RBFE-vs-MD, hERG, ADMET, Pareto, Lipinski-as-soft-preference, and structural alerts are all described correctly and with the right epistemic warnings ("prioritization signal, not measured affinity"; "estimated, not measured IC50"; "not a clinical claim"). Coverage of the pipeline is complete end-to-end at the *concept* level.

However: **only ONE stage (ADMET) is actually demonstrated live end-to-end.** Everything else is either a concept slide, a form-only view, or labelled "available … not validated here." The single most serious problem is that the **flagship video and T1 describe the same generation engine differently** — the flagship headlines "REINVENT4 Generative Lead Design" while T1 (correctly, matching the code and the honesty audit) says the engine is deterministic **BRICS enumeration, not a trained model**. A chemist watching both videos receives contradictory information, and the flagship over-credits a component that does not actually run in the demo. Three further slides (docking/RBFE/MD, PBPK, and the T2 community models) assert "available / runs on cloud & GPU" for capabilities the written manual explicitly flags as *demonstration-pending / unverified*.

Recommendation: ship after fixing the REINVENT4/BRICS contradiction (blocker) and down-grading "runs on cloud & GPU" to "coded; not yet demonstrated end-to-end" for Stage 4 and Stage 7.

---

## 2. Accuracy findings

### A1 — [HIGH] Flagship headlines REINVENT4 as "the real workflow"; the engine that actually runs is BRICS enumeration
- **Quote (flagship HTML line 269 / narration Step 4):** "The real workflow is **REINVENT4 Generative Lead Design**, with four design modes." / "…using the REINVENT4 lead-design workflow in four modes — de novo, scaffold decoration, linker design, and scaffold hopping. … the workflow runs end to end today."
- **Contradiction (T1 HTML lines 183/187/348, narration Step 3):** "today the variations are produced by **deterministic chemical enumeration (the BRICS method) — a rule-based generator, not a trained generative model**"; "Generator engine — Deterministic BRICS — learned model on roadmap."
- **Ground truth (code):** `.../drug_discovery/reinvent4_lead_design/main.nf` defines `params.generator = 'reinvent4' // reinvent4 | brics`, but the REINVENT4 process is documented in-file as the **"SWAP-POINT"**, and `GENERATE_BRICS` is the "enumeration baseline (NOT REINVENT4 RL, NOT a trained policy)". The honesty audit (`20260922…`) records REINVENT4 as "wired (43 tests)" but **"no real gen run yet (x86 container unbuilt)"**. So in any live demo the molecules are produced by BRICS, not a trained REINVENT4 policy.
- **Why it's wrong/risky:** The flagship never says the word BRICS and attributes generation to REINVENT4 with four learned modes, implying a trained generative model is operational. This directly contradicts the honest T1 framing of the *same feature* and over-credits an unrun component. A domain audience will read "REINVENT4 … runs end to end today" as "the RL generative model works." The "trained de-novo generator not yet built" caveat is present but is drowned by naming REINVENT4 as "the real workflow."
- **Severity: HIGH** (cross-video self-contradiction + over-claim on the headline capability).

### A2 — [MEDIUM-HIGH] Docking / RBFE / MD presented as "run on BioMate's cloud and GPU workers" while the written manual says demonstration is pending and FEP has a fabrication history
- **Quote (flagship HTML line 429 / narration Step 9):** "Available on BioMate's cloud & GPU workers — not independently validated here." / "These **run** on BioMate's cloud and GPU workers; we do not claim an independent accuracy here."
- **Written manual (T11 Stage 4):** "Their current **end-to-end user journeys must be checked separately before filming**." / pipeline table: "Dedicated demonstration pending."
- **Ground truth:** honesty audit — docking "needs **one verification Batch run** (blocked on GPU spot capacity)"; OpenFE RBFE is newly real but "**Real ΔΔG needs the openfe container on GPU Batch**" (i.e., not run); and the *prior* `openfe_rbfe` workflow **fabricated** ΔΔG = −1.23 kcal/mol + synthetic convergence until 2026-09-22. MD/MM-GBSA have no end-to-end evidence cited.
- **Why risky:** "run on … workers" (present tense, operational) is stronger than "coded but unverified." The hedge "not independently validated here" guards *accuracy* but not *whether the stage runs at all*. Given the recent FEP fabrication, asserting these as running is the highest-trust-risk framing in the set.
- **Severity: MEDIUM-HIGH.** The *conceptual* content of this slide (dock-many / RBFE-few / MD-last; "docking score is a prioritization signal, not a measured affinity"; "RBFE … agreement with experiment must be shown") is scientifically excellent — only the operability claim is the problem.

### A3 — [MEDIUM] hERG "estimated IC50" via a terfenadine-anchored power law — presented as a per-compound ranked number, which the written manual explicitly warns against
- **Quote (flagship HTML lines 508–513 / narration Step 11):** "432 µM — caffeine (worst)"; "These are estimated IC50s — derived from the model's classification probability via a **terfenadine-anchored power law**, not measured IC50s. The gate takes the worst case."
- **Written manual (T11 3a):** "an hERG blocker-class score is unitless; an IC50 is a concentration. **They are not interchangeable** … interpret them separately."
- **Why risky:** (i) Converting a classifier probability to a concentration via a power law anchored to a *single* reference drug (terfenadine, a potent ~56 nM blocker) is an unvalidated heuristic with no cited calibration; the resulting µM values carry false quantitative authority. (ii) Ranking aspirin/caffeine/ibuprofen and declaring caffeine "the worst" is an estimator artifact — none of the three is a clinically relevant hERG blocker, and 432 µM is itself essentially non-cardiotoxic. The video does say "nothing is strongly cardiotoxic" (good) and labels it "estimated, not measured" (good), but it still collapses to one ranked IC50 per compound — exactly the score↔IC50 conflation the manual cautions against.
- **Severity: MEDIUM** (well-hedged as illustrative, but presents a heuristic as a quantitative safety ranking).

### A4 — [MEDIUM] PBPK "available — projects exposure scenarios" vs manual "execution still needs a dedicated demonstration"
- **Quote (flagship HTML line 551 / narration Step 12):** "Available — projects exposure scenarios; not independently validated here." / "BioMate's chain **runs** three steps: allometric scaling … PBPK organ model … virtual-patient cohort."
- **Written manual (T11 Stage 7):** "Its current user-facing execution and outputs **still need a dedicated demonstration before this stage can be filmed as working**."
- **Why risky:** same over-generous "runs / available" framing for an unverified user journey. Concept content (Cmax, AUC, allometric scaling, virtual cohort, "not a guaranteed safe dose") is accurate.
- **Severity: MEDIUM.**

### A5 — [LOW] Flagship lists REINVENT4's four native modes while the product UI exposes only "Stay / Hop / Grow"
- The flagship enumerates "de novo, scaffold decoration, linker design, scaffold hopping" (REINVENT4's modes); T1 shows the actual control as a 3-level scaffold policy (Stay/Hop/Grow). Describing the underlying library's modes as if they are the product's modes is a minor mismatch that compounds A1.
- **Severity: LOW.**

**Accurate claims worth affirming (no action):** hERG mechanism and withdrawal history; ADMET = A/D/M/E/T; ADMET-AI = Chemprop GNNs on ~2M measurements (manual); docking/RBFE/MD distinctions and cost ladder; Pareto-front definition; Lipinski/property-window as soft preference; BRICS correctly labelled rule-based in T1; "~10⁶⁰" drug-like space; structural alerts / PAINS flagged-but-shown.

---

## 3. Honesty / over-claim findings

1. **(HIGH) Cross-video inconsistency on the generator (A1).** The flagship is less honest than T1 about the same feature. Honesty should be *monotonic* across the set — the flagship must not retract T1's BRICS disclosure.
2. **(MEDIUM-HIGH) "Runs on cloud & GPU workers" for unrun stages (A2, A4).** For Stage 4 and Stage 7 the videos assert operation ("run"/"available"); the manual says "demonstration pending." Given the documented FEP fabrication, the committee should treat "runs" claims for any unverified workflow as a trust liability.
3. **(MEDIUM) T2 community models — "BioMate hosts them so you can use them directly" vs "may come back as a stub."** T2 Step 3 lists AlphaFold2, OpenFold2, Boltz-2, Evo2 and says BioMate "hosts them so you can use them directly"; T2 Step 9 then warns a structure prediction "may come back as a clearly-labelled stub … when the heavy model service isn't connected." These are in tension — if the heavy service isn't connected, it is not usable "directly." The stub disclosure is good; the earlier "hosts … directly" should be softened to match.
4. **(GOOD) Properly disclosed gaps.** Trained de-novo generator = gap; GP/Pareto optimizer "written but not wired"; live hERG QC gate / auto-loop "not confirmed firing on dev"; ADMET predictive accuracy deliberately not quantified ("needs a named dataset, endpoint, metric, split"); "withheld, never fabricated" findings rule; provenance record "shows the gap rather than hiding it." These are exemplary and consistent across video + manual.
5. **(GOOD) Framing.** "Not a drug-discovery campaign result, not a clinical claim"; "in-silico triage, not a drug"; "idea slide vs product slide" with per-stage verdicts (demonstrated / available / gap) is a responsible structure.

---

## 4. Drug-dev pipeline coverage map

Legend: **LIVE** = demonstrated running end-to-end in the video · **CONCEPT** = explained, not shown running · **FORM-ONLY** = UI shown, no live output · **CODED/UNVERIFIED** = asserted available but not demonstrated/validated · **GAP** = acknowledged missing.

| Stage | Pipeline step | Coverage in videos | Status vs reality |
|---|---|---|---|
| 1 | Target / objective / constraint framing | CONCEPT (correctly called a planning step) | Accurate; always-available |
| 2 | Design & generate (de novo / scaffold) | FORM-ONLY + results view; flagship says REINVENT4, T1 says BRICS | **Runs via BRICS enumeration**; trained generator = GAP; **A1 contradiction** |
| 3a | ADMET incl. hERG | **LIVE** (real run `c40459b2`/`c40459…`; pre-run → running → completed → outputs) | Execution + downloads verified; predictive validity not established (honestly stated) |
| 3b | Physicochemical / Lipinski | CONCEPT (RDKit descriptors) | Available; arithmetic exact |
| 3c | QSAR / target potency | CONCEPT; "not available" when no trusted model | Available, needs user's labelled data; honest |
| 4 | Docking / RBFE-FEP / MD | CONCEPT slide + "runs on cloud & GPU" claim | **CODED/UNVERIFIED**; FEP had fabrication history; **A2** |
| 5 | Multi-objective / Pareto ranking | CONCEPT + results-view (read-it-yourself) | Ranking real; auto-optimizer = GAP (honestly "written, not wired") |
| 6 | Closed loop (DBTL) + QC gate / auto-loop | CONCEPT (T2 Rounds = empty-state monitoring view) | Design real; **live hERG gate firing UNPROVEN on dev** (honestly stated) |
| 7 | PK / PBPK | CONCEPT + "available" claim | **CODED/UNVERIFIED** (manual: demonstration pending); **A4** |
| 8 | Report / provenance / lineage | **LIVE** (for the ADMET run: Outputs, reproducibility JSON, lineage) | Tabs + 6 downloads verified; record fields partly empty (honestly shown) |
| — | Community predictive models (AF2/OpenFold2/Boltz-2/Evo2) | CONCEPT/LIVE-ish (Registry + Run) | May return stub if service not connected; **A3 honesty tension in §3.3** |
| — | IND / regulatory narrative (§2.6.1 DOCX) | **NOT COVERED** in these drug-dev videos | Gap in coverage (exists elsewhere in product per CLAUDE.md; absent from this set) |

**Bottom line on coverage:** the pipeline is narrated end-to-end, but **live demonstration = ADMET run + its report/provenance only.** Design/generate is form+results but engine-misattributed; docking/RBFE/MD, closed-loop firing, and PBPK are concept-or-coded-unverified; the trained generator and the MPO optimizer are acknowledged gaps; IND/regulatory authoring is not in this video set at all.

---

## 5. Prioritized recommendations

1. **(BLOCKER — A1) Reconcile the generator claim across the set.** In the flagship, replace "The real workflow is REINVENT4 Generative Lead Design" with the T1-accurate framing: the live engine is **deterministic BRICS enumeration (a rule-based baseline, not a trained model)**; REINVENT4 is the wired-but-not-yet-run swap-point. Do not list REINVENT4's four learned modes as if operational. Honesty must not regress between T1 and the flagship.
2. **(HIGH — A2/A4) Down-grade "runs on cloud & GPU / available" for Stage 4 and Stage 7** to "coded; end-to-end run not yet demonstrated" to match the written manual. Given the documented FEP ΔΔG fabrication, apply a blanket rule: no "runs" claim for any workflow lacking a verified Batch run on record.
3. **(MEDIUM — A3) Re-frame the hERG panel.** Lead with the native model output (blocker-class probability/score), present the terfenadine-anchored IC50 as a clearly-secondary heuristic with "no validated calibration," and drop or caveat the "caffeine = worst" ranking so a heuristic artifact is not read as a cardiac-safety signal. Mirror the manual's "scores and IC50 are not interchangeable" sentence on-slide.
4. **(MEDIUM — §3.3) Fix the T2 community-model tension.** Soften "hosts them so you can use them directly" to "hosts these; some structure services may return a labelled stub on dev when the heavy model isn't connected," consistent with Step 9.
5. **(LOW) Add one explicit "what is LIVE vs CONCEPT in this video" frame** near the top of the flagship — the closing recap does this well; promoting a one-line version up front would prevent a viewer from over-reading the concept slides. Consider noting that IND/regulatory authoring is out of scope for this set.
6. **(PROCESS) Treat the written T11 manual as the honesty ceiling.** Wherever the video is more generous than T11, bring the video down to T11's wording — T11 is consistently the more careful document.
