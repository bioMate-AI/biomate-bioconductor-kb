# Committee Review — αvβ6 cyclic-peptide / radioligand program manuscripts (pre-multi-channel release)

**Date:** 2026-10-24. **Chair / Handling Editor:** program lead (adjudication below).
**Manuscripts under review:**
- **M1 — Renal predictor:** `docs/20261022_RENAL_PREDICTOR_MANUSCRIPT.md` (v0.2)
- **M2 — Cyclic-LLM:** `docs/20261021_CYCLIC_LLM_PAPER_DRAFT.md` (rescoped 2026-10-24)

**Method:** 4 independent professional-lens reviewers (multi-model), each peer-reviewing BOTH manuscripts
blind to each other, to journal standard. Two reviewers (B, D) **re-ran the released renal pipeline** and
**inspected the cyclic-LLM artifacts on disk**. Findings adjudicated by the Chair; an item found by **≥2
reviewers = consensus (high confidence)**. Full reviews archived in the session transcript.

## Committee composition
| Reviewer | Lens | Model | M1 | M2 |
|---|---|---|---|---|
| **A** | Nuclear medicine / radiopharmaceutical sciences | Sonnet | Major | Major (borderline reject) |
| **B** | ML / biostatistics methodology (re-ran pipeline, conf 5/5) | Opus | Major | Minor (contingent) |
| **C** | Peptide / medicinal & computational chemistry, FEP | Opus | Major | Minor (conditional) |
| **D** | Reproducibility & research integrity (re-ran pipeline) | Sonnet | Major | Major |

---

## Overall editorial decision

- **M1 (Renal predictor): MAJOR REVISION — unanimous (4/4).** A genuinely useful dataset + honest
  framing, but the central generalization claim does not survive artifact-level checking (CI crosses zero,
  point estimate inflated by pseudo-replication) and the dominant feature (net charge) is computed with
  class-correlated chemistry errors. Not releasable in any channel until the P0 items below are fixed.
- **M2 (Cyclic-LLM): MAJOR REVISION — Chair ruling over a 2/2 split** (A, D: Major; B, C: Minor). The
  scientific content and honesty are sound and the fixes are well-defined, but the residual over-claims sit
  in the **title and abstract** (a 4/4 consensus on the FEP wording), the "rigorous" cross-target label is
  underpowered (3/4), and the one positive claim needs an independent replication (3/4). These exceed
  "minor." Path to acceptance is clear and mostly wording + one added control.

**Neither manuscript is ready for ANY public channel today.** Both are, however, fundamentally honest
work with no fabrication found by any reviewer — the problems are over-reach and reproducibility hygiene,
not integrity of the underlying computation.

---

## M1 — RENAL PREDICTOR

### Consensus BLOCKERs (found by ≥2 reviewers — high confidence)

1. **The headline 95% CI is not reproducible and crosses zero. [B, D — both re-ran the code]**
   Manuscript states ρ = 0.27, **95% CI [0.01, 0.51]**, p = 0.036. Re-running the seeded pipeline:
   B gets **[−0.012, 0.527]** (3.1% of bootstraps ≤ 0); D gets **[−0.01, 0.51]**. The stated lower bound
   **excludes** zero; the actual lower bound **includes** zero. The two reviewers' slightly different upper
   bounds (0.527 vs 0.51) themselves show the CIs were generated from an **unpinned run**, despite the
   paper's "all seeded and reproducible." → This is the load-bearing significance claim. **Fix:** pin the
   seed/n_boot, regenerate all CIs together, report the reproducible interval, and soften "generalizes" to
   "preliminary, CI consistent with zero."

2. **Scope is overstated: the analysis uses 103 observations / 8 classes, not "163 constructs / 11 classes." [A, B, D]**
   PSMA, FAP and FOLR1 — the best-known clinical comparators — are absent from every reported result (the
   script restricts to "common classes all models can rank"). **Fix:** state "103 observations, 8 target
   classes" in the abstract and §2.3; reserve "163/11" for the dataset description only.

3. **The point estimate is inflated by pseudo-replication. [B — Chair-elevated; new, load-bearing]**
   The estimand is computed per (construct, timepoint) observation, not per construct, so repeated
   timepoints of the same molecule (whose %ID/g varies with time, and `log_t` is a model feature) enter the
   within-class Spearman. Aggregating to one point per construct drops mean-per-class ρ **0.269 → 0.205**,
   and **SSTR2 collapses 0.252 → 0.013** (its "signal" was the within-molecule time trend). The large
   `drop_timepoint` ablation (−0.26) is the same artifact. **Fix:** compute the estimand at construct level;
   report corrected ρ and per-class values.

4. **The charge pipeline — input to the paper's dominant feature — has ~5 class-correlated systematic errors. [C — Chair-elevated; single reviewer but devastating and specific]**
   (a) metal-complex charge is **radiometal-blind** (assumes M(III); wrong for Cu-64(II)/Zr-89(IV)/Pb-203(II),
   ±1 on the top feature); (b) **acyclic chelators double-counted** (DTPA/DFO/macropa arms counted as free
   *and* complex charge added); (c) **N-terminal α-amine counted even when the chelator amide-conjugates it**
   (uniform ~+1 over-count across N-conjugated radiopeptides); (d) disulfide Cys treated as free thiols
   (SSTR2 octreotate family); (e) alcohol C-terminus (DOTATOC) mis-assigned a carboxylate; (f) phosphonate
   pKa₁ dropped. Because conjugation/chelator/metal **co-vary with target class**, these bias LOTO transfer
   rather than cancel. **Fix:** key complex charge on (chelator, radiometal oxidation state), exclude acyclic
   chelator atoms, honor amide conjugation at the N-terminus, zero disulfide Cys, fix the alcohol terminus
   and phosphonate — then **re-run LOTO** before the "net-charge-dominant, structure-learnable" claims stand.

5. **Unsupported / unhedged "first" claims. [A, B, D]** "the first structured … dataset" and "first
   demonstration" with no documented prior-art search. **Fix:** hedge ("to our knowledge," with a documented
   search) or drop — mandatory for any public excerpt.

6. **A held-out failure on the program's own target (αvβ6) is omitted. [D explicit; A noted the gap]**
   GBM αvβ6 held-out ρ = **−0.035**, yet §2.3 names only GLP-1R/NTS1 as failures and §2.8 still builds an
   αvβ6 design scan. **Fix:** disclose αvβ6 (and GLP-1R −0.359) in §2.3; qualify §2.8 accordingly.

7. **"NTS1 ρ ≈ −0.9 for every model" is misattributed. [B, D; C noted]** −0.894 appears only at the 2018
   temporal cut; the headline LOTO GBM NTS1 is **−0.224**. **Fix:** state the split.

8. **Duplicate rows + provenance-gate contradiction. [A, D]** Literal/near-duplicate constructs persist
   despite a stated "(construct, DOI)" dedup rule (so "163" is an upper bound); 13/163 rows lack a resolvable
   DOI/PMID despite the §2.1 quarantine claim; verification tiers (150 primary / 10 cited / 2 abstract / 1
   secondary) are not disclosed. **Fix:** enforce the gate or state the true counts and tier breakdown.

9. **The §2.8 U-shape "recovery" is circular. [A, C]** The grey-box was *constructed* with two
   positive-coefficient saturable charge routes, so a U-shape is a consequence of the functional form, not an
   independent validation. **Fix:** state this explicitly; frame as "recovers the prior-art rule," not evidence.

### Notable MAJOR findings (single reviewer, retained)
- **Garden-of-forking-paths vs the pre-analysis plan. [B]** The study protocol (same date) §13 itself says
  transfer "collapses at full target diversity (≈0 across 8 classes)," and lists an earlier integrin-only
  ρ=0.78. The 0.78 → ≈0 → GBM 0.27 path carries many analyst degrees of freedom (class-inclusion threshold,
  "common-classes" restriction, observation- vs construct-level, unit stratum), none corrected. The
  protocol's conservative read is arguably the honest one. p=0.036 is uncorrected across 3 models + analyses.
- **Clinical framing: %ID/g ≠ absorbed dose. [A]** The label is mouse %ID/g at one timepoint; the Abstract
  frames the work around dose-limiting kidney *dosimetry* (Gy/GBq). %ID/g ignores mass scaling, time
  integration and radionuclide physics (⁹⁰Y ≈ 3.5 vs ¹⁷⁷Lu ≈ 0.4–0.7 Gy/GBq). **Fix:** retitle as a
  *preclinical biodistribution* predictor, or show predicted %ID/g ranks human Gy/GBq on the human subset.
  **Tumour uptake is not modelled at all, so the tumour-to-kidney ratio — the quantity that sets therapeutic
  index — is not predicted;** state this.
- **Pooled heterogeneous labels. [A]** radiometal/chelator/timepoint pooled within class; the model may be
  learning "imaging-vs-therapy radionuclide + time," not structure. Provide a ¹⁷⁷Lu-DOTA-only stratified run.
- **Missing promised baselines. [A]** protocol promised logD/MW/TPSA + a published heuristic; only signed /
  |charge| run, and the |charge| result is not reported.
- **Specific receptor-mediated renal uptake not distinguished from megalin reabsorption. [A]** PSMA
  (proximal tubule), SSTR2, GRPR are kidney-expressed; name megalin(LRP2)/cubilin and cite per class.

### Strengths (consensus — credit where due)
- **The pipeline reproduces exactly** (B, D re-ran: GBM ρ 0.269, net-charge −0.045/p 0.733, grey-box
  0.17/p 0.20, cluster-CV 0.125 vs 0.072, all five ablation Δ's). Unusually clean and auditable.
- **Mandatory, never-imputed renal-protection flag** — the right design, and actually enforced in code (all).
- Honest estimand (mean-per-class, not confounded pooling), construct-cluster bootstrap, within-class
  permutation, leave-one-sequence-cluster-out for RGD-motif leakage — disclosed, not buried (B, C, D).
- Prior art (charge U-shape, two-route biology) explicitly ceded; grey-box admitted NOT to beat the black
  box; failure modes named as applicability limits (all four).

---

## M2 — CYCLIC-LLM

### Consensus BLOCKERs (found by ≥2 reviewers)

1. **The FEP control edge is over-claimed as "validated." [A, B, C, D — unanimous]** A double-Y→F edge
   with expected ΔΔG ≈ 0 is a **null-bias sanity check, not an accuracy validation**: (a) it is a physical
   *prediction* of ≈0, not a machinery control (the canonical controls are thermodynamic-cycle closure /
   forward–backward hysteresis / a self-edge); (b) **±0.15 kcal/mol is the BAR analytical error only** —
   single replica, 0.5 ns/window, no block/bootstrap/overlap gate → true σ ~0.5–1 kcal/mol, so the edge is
   consistent with zero but has little power to *detect* a real bias, and cannot show the engine
   *discriminates* the 0.5–2 kcal/mol differences a ranking needs (**dynamic range untested**); (c) the edge
   perturbs **Tyr, not the RGD-Asp that coordinates the MIDAS metal**, so it never tests the CaDA-Mn model
   where it matters (and 3× CaDA-Mn is non-physiological: MIDAS/ADMIDAS/SyMBS are Mg/Ca/Ca). **Fix:** every
   "validated / A2-anchor admissible" → "executed; recovered the expected null on one short single-replica
   control edge; predictive accuracy and dynamic range not yet validated." Applies to title-adjacent abstract
   line, §4, §6, and controls-doc §6c.

2. **"Rigorous"/"controlled" cross-target negative is underpowered. [A, B, D]** FIKK13 LOTO is a single
   held-out target from a **2-target** training set (and its own JSON shows conditioning doesn't fire even
   in-distribution — equally consistent with "model ignores its control tokens"); BoltzGen LOTO is **4
   designs × 3 targets**, mean Δiptm −0.16 driven by one −0.308 outlier, no CI; ipTM is a structure-confidence
   metric, not binding. **Fix:** downgrade to "preliminary / smoke-scale, underpowered negative," add a
   power/sensitivity statement, state the 2→1 probe.

3. **The sole positive claim (composition-beating) rests on one target. [A, B, C]** PADI4 only (67 binders,
   55 motif-distinct); on hIAPP (0.588) and hPCSK9 (0.266) the LM fails and the 2-mer logistic wins (LM beats
   2-mer on only 2/4). **Fix (condition of acceptance):** replicate on ≥1 independent within-target dataset,
   or scope the claim explicitly to PADI4 with a bootstrap CI. Disclose the 2-mer-beats-LM-on-2/4 fact in §3.1.

4. **The title/abstract still lead positive and retain "rigorous." [A, B, D]** After the rescope there is no
   positive deliverable beyond "beats composition on one target" + two negatives + a proposed experiment.
   **Fix:** retitle around the actual finding (display-NGS abundance-null circularity + cross-target null).

5. **Superseded supporting material is unmarked. [B, D]** §7 cites `…WITHIN_TARGET_RIGOR_CHECK.md`, which
   still asserts "the within-target win is real and leakage-safe"; `cyclic_llm_selector_PADI4_trajtrain.json`
   carries verdict string **"WIN"**. **Fix:** add supersession banners; cite the SOTA-benchmark doc and the
   per-target `*_leakagesafe.json` files in §7; never reuse the "WIN" string in any channel.

6. **Internal-process remarks don't belong in a public preprint. [A; C concurs on scope]** "prior internal
   review," companion manuscript "under major revision," and the "discredited in-distribution decomposition
   figure" allusion. **Fix:** remove from the public body (keep in internal docs).

### Notable MAJOR / integrity findings
- **FEP ΔΔG artifacts were cited but absent from the repo (on S3 only). [B]** — **RESOLVED this session:**
  pulled into `research/guangzhou_all_atom/cyclic_llm/results/fep_ctrl_build1_ddg/` and the §6c citation
  updated (commit `5e6d0cd97`). Numbers verified to match (solvent 146.45±0.28, complex 145.71±0.56 kJ/mol).
- **Cheap-surrogate result is selectively reported. [B, D]** "7 targets, 0.455–0.644, near-chance" — only 5
  evaluated (1 NaN), and the design-feature arm reaches 0.873; only the sequence arm was quoted. **Fix:**
  report all arms and the true target count.
- **DPO placebo p=0.004 is the resolution floor for n=5 and one-sided. [B]** 1/C(10,5)=0.00397 is the
  smallest attainable p at perfect separation regardless of effect. **Fix:** state one-sided + floor; lean on
  the effect size (+0.124 vs +0.014). (Scope is otherwise correct — permeability loop only.)
- **"Beyond composition" may be "display-fitness beyond composition." [C]** enrichment convolves affinity
  with display/translation efficiency, cyclization yield, proteolytic stability, PCR bias — reinforces why a
  measured-affinity label is required. **Fix:** say "display-enrichment signal beyond composition."

### Strengths (consensus — credit where due)
- **The abundance-null self-demolition is the paper's best contribution and is correctly reasoned** (all
  four). Reporting that `is_binder` is abundance-circular and the LM beats the trivial null on 0/4 targets —
  against the authors' own headline, and *more* conservative than its own "WIN" artifact — is a real service
  to the display-ML subfield.
- Leakage control (3-mer Jaccard, −0.011) and trivial baselines are the right controls, cleanly executed
  (B, C, D verified numbers match artifacts).
- The DPO shuffled-reward **placebo control exists and matches** (B verified); validity/novelty preserved in
  the cross-target eval (it's a transfer failure, not a generation failure) (C).
- Exemplary integrity posture: documents its own rescope/correction history, refuses to call
  score-disagreement superiority, no-speculative-GPU-spend discipline. **No fabrication** (all four).

---

## Dissents (Chair adjudication)
- **M2 severity (A/D Major vs B/C Minor).** Ruled **Major revision.** B and C are right that the science is
  honest and most fixes are wording already half-acknowledged in Limitations — but the over-claims sit in the
  **title and abstract**, the FEP wording is a **4/4** consensus, and "rigorous" + the single-target positive
  are substantive (3/4 each). A manuscript whose title and abstract overstate is not a minor fix. This is a
  *well-defined* Major revision, not a reject — closer to B/C's spirit than to a rejection.
- **No dissent on M1** — unanimous Major.
- **Chair-elevated to blocker despite single reviewer:** M1's charge-chemistry errors (C) and
  pseudo-replication (B). Both are load-bearing for the central claim and specific/actionable; the Chair
  weights them as blockers, not minor points.

## Cross-cutting findings (both manuscripts)
1. **Each paper has exactly one load-bearing claim that fails artifact-level checking** (B, D converge):
   M1's CI [0.01,0.51] (actual crosses zero) and M2's FEP artifact (was S3-only — now fixed). In both, the
   **supporting docs already state the more conservative truth** (renal protocol §13 "≈0 at full diversity";
   cyclic controls §4 "underpowered/circular"). Align the manuscripts to their own conservative docs.
2. **Metal chemistry is the shared technical weak point** (C): M1's radiometal-blind complex charge; M2's
   CaDA-Mn untested on the coordinating residue. A program this metal-centric should adopt one validated
   metal-charge/coordination treatment shared by both pipelines.

## Multi-channel / website-excerpt GATE (all four reviewers flag — hard gate)
- **Neither paper contains αvβ6 binder-design evidence** (M1: 18 αvβ6 constructs, mostly mouse, one human
  value, held-out ρ=−0.035; M2: no αvβ6 data). Any copy implying "we design low-kidney-dose αvβ6
  radioligands" is **clinically misleading** — prohibited in preprint, website and shareable.
- M1 abstract excerpted ("generalizes," "first," "eleven classes") overstates a ρ=0.27 whose lower CI bound
  is ~0 on 8 classes. M2 excerpted ("AUC 0.951, +0.077 over baseline") misleads — below the null everywhere,
  PADI4-only, ~16× prevalence-enriched test set. **Any excerpt must carry the abundance-null / CI-crosses-zero
  caveat.** Never reuse "WIN" / "physics-verified" / SOTA language in any channel.

---

## Prioritized remediation roadmap

### M1 — Renal (P0 = before ANY release)
- **P0-1** Fix the charge pipeline (C's 6 errors) → re-run LOTO → report corrected ρ/CI (may move the headline).
- **P0-2** Recompute the estimand at **construct level** (B) → report corrected ρ (~0.205) and per-class.
- **P0-3** Pin bootstrap seed; regenerate all CIs; report the reproducible CI (crosses zero); soften "generalizes" → "preliminary."
- **P0-4** State true scope (103 obs / 8 classes); disclose αvβ6 (−0.035) + GLP-1R failures; fix NTS1 attribution.
- **P0-5** Reconcile provenance gate (13 rows) + dedupe; disclose verification tiers.
- **P0-6** Drop/hedge "first"; distinguish megalin vs receptor-mediated uptake; add the promised baselines.
- **P1** Clinical framing: %ID/g ≠ dose — retitle as preclinical-biodistribution or add human-Gy/GBq ranking; state tumour uptake (hence T:K) is not modelled; qualify the single-point 0.66-vs-0.42 comparison; complete the reference list (Abdollahi/Trachsel missing; truncated titles); add a Zenodo DOI + licence for "released."

### M2 — Cyclic-LLM (P0)
- **P0-1** Temper all "FEP validated/admissible/A2-anchor" → "executed; recovered expected null on one short single-replica edge; accuracy/dynamic-range untested." (artifacts committed ✓).
- **P0-2** Retitle/reframe around the finding (abundance-circular display benchmark + cross-target null); drop "rigorous."
- **P0-3** Downgrade cross-target to "preliminary/underpowered (smoke-scale)"; add a power statement; state the 2→1 probe.
- **P0-4** Independent within-target replication (≥1 target) OR scope the positive claim to PADI4 with a CI; disclose 2-mer-beats-LM-on-2/4.
- **P0-5** Supersession banners on the RIGOR_CHECK doc + fix the JSON "WIN" verdict; fix §7 artifact paths; report all surrogate arms.
- **P0-6** Remove internal-process remarks; cite DPO p as one-sided at the n=5 floor and lead with effect size.

### Both — multi-channel
- No marketing/website/shareable copy until P0 done. No "αvβ6 radioligand design" claim. Carry the
  abundance-null + CI-crosses-zero caveats in every excerpt. Re-check any already-produced derivative for
  pre-rescope "physics-verified"/SOTA/"WIN" language.

## Change log
- 2026-10-24 — Created from a 4-lens peer-review committee (A nuclear-medicine, B biostatistics [re-ran
  pipeline], C peptide/comp chemistry+FEP, D integrity [re-ran pipeline]). Decisions: M1 Major (4/4), M2
  Major (Chair ruling over 2/2 split). FEP ddG artifacts pulled S3→repo + §6c citation fixed (commit
  `5e6d0cd97`) resolving B's artifact-availability flag. No fabrication found in either manuscript.
