# Handoff — cyclic-peptide closed-loop RSI manuscript

**Date:** 2026-10-28
**Purpose:** cold-start resume point for a session taking over the **peptide closed-loop-as-RSI
manuscript**. Everything needed to continue without this session's context. The manuscript is a
*separate* paper from the SRVL/verifiable-guardrails thread (that is the general platform paper);
this one is the cyclic-peptide instance.

---

## 1. What this is
Write/finish a manuscript framing the all-atom cyclic-peptide computational closed loop as
**governed recursive self-improvement (RSI)**. Draft already written:
**`docs/20261028_MANUSCRIPT_cyclic_peptide_closed_loop_RSI.md`** — read it first.

**The honest thesis (do not drift from it):** the loop is computational-only and cross-target
generalization is NULL, so there is **no positive RSI result to claim**. The paper's contribution is
*evidential governance* — a cost-ordered verifier ladder (L0 gates → L1 exec → L2 physics → L3
wet-lab) + a biology-structured leakage firewall (held-out target/scaffold/assay) — demonstrated by
the firewall **catching three artifacts** that looked like gains: (i) abundance-circular selector,
(ii) renal ρ=0.27 charge-bug (retracted to null), (iii) metal-blind FEP frame-bug + control miss.

## 2. MERGE, don't fork (critical)
There is already a component paper and a program plan. Consolidate; do not create a 4th competing doc:
- `docs/20261021_CYCLIC_LLM_PAPER_DRAFT.md` — the enrichment-trained cyclic-LLM selector benchmark
  (within-target beats composition, NOT the abundance null; cross-target NULL). This is §5.1 of the
  RSI manuscript — decide: one paper with the LLM as a section, or two companions.
- `docs/20261026_INTEGRATED_PROGRAM_PLAN.md` — the single-claim verification-ladder plan + v1/v2 split.
- `docs/20261022_RENAL_PREDICTOR_MANUSCRIPT.md` — the ρ=0.27 retraction (= §5.2).
- `docs/20261027_BIOMATE_NATIVE_RSI_THESIS.md` — the SRVL spine (the RSI framing is shared with the
  general platform manuscript `docs/20261027_MANUSCRIPT_verifiable_guardrails_scientific_agents.md`).

## 3. Honest-status guardrails (the receiving session MUST hold these)
From the verified status (`docs/20261027_PROGRAM_STATUS_VERIFIED.md`) — every one is a line that has
been burned before, so do not soften:
- Cross-target generalization is **NULL** (ours) / ~3.3% honest SOTA (field). Never claim "our LLM
  generalizes across targets."
- Within-target selector "wins" are **abundance-circular** and partly **family-memorization** (3/5 targets).
- **FEP is masked** — ΔΔG unvalidated, control edge missed −0.95 by ~5×, metal model only
  *structurally screened* (screen ≠ validated). Do not admit FEP to any reward until 10 ns × 3 replicas
  + re-run controls.
- Permeability is **ranking-grade only** (scaffold-R² 0.23).
- The closed loop is **synthetic-only** (DPO on simulated KD). No wet-lab result exists.
- **v1 = computational preprint, no wet lab; wet lab is v2.** Only OUR OWN method counts.
- **Novelty UNVERIFIED** — abstract-level prior-art only; do a direct prior-art pass before submission
  (MFBind, PepThink-R1, DGDM, UnibindMD overlap).
- RSI is a **design, not a measured result**. Claiming a measured gain now = the leakage inflation the
  firewall exists to stop.

## 4. Plan / roadmap (what turns the draft into a submittable paper, in order)
1. **Decide merge topology** with the user: single paper (LLM benchmark + renal retraction + FEP bug as
   the three governance results) vs. companion. Reconcile abstracts of 20261021/20261022 into §5.
2. **Direct prior-art pass** → replace the SOTA-landscape self-cites with primary citations; settle the
   novelty claim (likely "evidential, not architectural").
3. **Complete LOTO** (generator + binding/permeability predictors) beyond smoke scale; report held-out
   target/scaffold transfer with CIs. Artifacts: extend `results/boltzgen_loto_summary`, the v3.1 LOTO.
4. **Re-validate L2 physics**: metal-correct FEP (fix landed 2026-10-25), 10 ns × 3 replicas, YY→FF
   (−0.95) + ≥2 more measured control edges; figure = computed vs measured ΔΔG.
5. **Figures**: (F1) the loop + ladder schematic; (F2) the firewall = three refutation panels (abundance
   null, ρ=0.27 before/after, FEP metal-distance + control miss); (F3) honest bounds (binding novel-target
   R², permeability scaffold-R², cross-target NULL); (F4) the pre-registered prospective round design.
6. **Pre-register** the v2 prospective closed-loop round (frozen ladder, held-out target, CRO panel,
   success/null before synthesis) — this is the first honest RSI datapoint; it is wet-lab = v2.
7. **Submit-review gate**: flag submit-ready and WAIT for the user's final round (per
   `feedback_manuscript_submit_review_gate`). Do not submit autonomously.

## 5. Discipline (so you don't relearn it)
- **Shared worktree** `/Users/kky/biomate-review`, concurrent committers: plain commits, explicit paths,
  no `--amend`, never `git add -A`.
- All docs under `docs/`, date-prefixed. Never the Artifact tool.
- Verify every number against the committed artifact before asserting (citation integrity); the agent
  synthesis that seeded the draft is in this session's transcript but re-verify from the result JSONs.

## 6. Key pointers (read first, in order)
1. `docs/20261028_MANUSCRIPT_cyclic_peptide_closed_loop_RSI.md` (the draft)
2. `docs/20261027_PROGRAM_STATUS_VERIFIED.md` (ground truth)
3. `docs/20261026_INTEGRATED_PROGRAM_PLAN.md` (program plan, v1/v2)
4. `docs/20261021_CYCLIC_LLM_PAPER_DRAFT.md` (component paper to merge)
5. `docs/20261025_CADA_MN_METAL_MODEL_VALIDATION.md` (FEP frame-bug)
6. `docs/20261022_RENAL_PREDICTOR_MANUSCRIPT.md` (charge-artifact retraction)
7. `docs/20261006_CYCLIC_LLM_V3_CROSSTARGET_RESULTS.md` + `…V3_1_MULTITARGET_RESULTS.md` (cross-target NULL)
8. `/Users/kky/sdl-macrocycle/README.md` (physical SDL harness, hardware TODO)

Results: `research/guangzhou_all_atom/results/{binding_model_metrics_cyclic, permeability_predictor_metrics,
avb6_metal_mmgbsa_gate, boltzgen_loto_smoke_summary, speed_surrogate_loto}.json`, `SIMULATED_closed_loop_20261003/`.

## 7. One-line status
*Honest governance-first RSI manuscript drafted (`20261028_MANUSCRIPT_…`); contribution = the firewall
caught 3 artifacts, not a performance win; next = merge-topology decision + prior-art pass + full LOTO +
FEP re-validation + the pre-registered v2 wet-lab round. v1 computational, no wet lab, submit-review-gated.*
