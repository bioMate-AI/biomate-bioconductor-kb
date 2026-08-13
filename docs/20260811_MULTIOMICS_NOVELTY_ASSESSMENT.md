# Is the multi-omics flexible-integration work paper-worthy? — honest verdict

Date: 2026-08-11. Sources: (1) live E2E tests this session; (2) external prior-art
literature scan; (3) audit of our OWN prior competitive surveys + code. All three
converge. Written to counter the known tendency to over-claim white space — leads with
the gap, not the pitch.

## What we actually have (verified this session)

- **Flexible pipeline runs E2E on real data, method-agnostically.** Same 2-modality CLL
  data (mrna + methylation), one normalize step, then:
  - MOFA2 (factor method) → **Factor 1 ↔ IGHV AUC 0.962** (runs af1f0a1f→7e8979d1).
  - SNF (clustering method) → **IGHV ARI 0.505** (run a6026cc9) — swapped method, same
    normalized inputs, no code change. *Note:* 0.505 < the 0.705 in
    MULTIOMICS_PLATFORM_MASTER.md — the exact number is preprocessing/seed dependent;
    reinforces "no magic," does not break the E2E claim.
- Selector + planner + routing: 36/36 unit tests; deterministic normalize→integrate
  chaining validated against real S3 layout.
- 7 integrators packaged (MOFA2, SNF, MCIA, intNMF, iClusterPlus, JIVE, rGCCA/MFA); 6
  "solid" on 3 cohorts (CLL, TCGA-AML, TCGA-BRCA); StabMap recommended but NOT runnable.

## The verdict: valuable product, NOT yet a research contribution

Convergent finding across the external scan AND our own 2026-07-28 reassessment:

- **Wrapping many integrators behind one interface** is commodity — momix (6 of our 7),
  mixOmics/DIABLO (~18), MOVICS (10, with consensus + auto-k). Published pattern.
- **"LLM + reproducible + cloud + multi-omics"** is NOT novel in mid-2026. Near-twins:
  OmniBioAI, OmicOS/OmicVerse, OmicsNavigator (spatial+LLM), PromptBio, BiomiX (already
  routes NL-ish → MOFA integration). Our own doc: *"not a contribution in mid-2026."*
- **Per-modality normalization + end-to-end execution** = standard pipeline engineering.

**The one genuinely unclaimed seam:** programmatic *data-shape → integration-method
selection, executed automatically*. Benchmarks (Cantini 2021, Duan 2021, scMultiBench
2025) stop at human-read guidance; MOVICS auto-picks k not method; OmicVerse's agentic
selection is a 2026 preprint scoped to MOFA/GLUE. **BUT two things currently gut it:**

1. **No validation that selection beats a fixed default.** `select_method()` is a
   hand-authored precedence cascade (mosaic→MFA→feature_sel→clustering→high-dim→NMF→MOFA2).
   Reasonable heuristics grounded in each method's assumptions — but there is zero
   evidence the *chosen* method beats "always MOFA2" or "always MCIA/intNMF" (Cantini's
   safe defaults) on held-out data. Without that, it's encoded domain knowledge, not a
   result.
2. **The method set doesn't cover the regime it advertises.** The pitch says
   "single-cell / partially-overlapping (mosaic)," but the 7 integrators are all
   bulk/paired; the SOTA for sc-mosaic is StabMap/GLUE/MultiVI/MIDAS/scMoMaT — none in
   the runnable set (StabMap isn't even packaged). An honest selector on sc-mosaic input
   would have to route *out* of our tools. As framed, it auto-selects a wrong-for-the-job
   method on the hardest case it markets.

## What would make it paper-worthy (pick a lane)

- **Lane A — Applications Note / tool paper** (*Bioinformatics*, *GigaScience*): achievable
  in weeks. Requires: fix the over-claims (universal-interface hardcoded-view-name bug;
  StabMap runnable or dropped from the pitch; honest modality coverage = 6/13 validated),
  reproducible runs on N public datasets, cost/wall-clock, and ideally a small
  usability study (non-expert time-to-result vs running momix/MOVICS by hand). Competes
  with BiomiX/MOVICS on convenience — the defensible "we do X they can't" is the
  auto-selection + NL + hosting triad, *demonstrated*, not asserted.
- **Lane B — Methods paper on data-shape-driven meta-integration** (higher ceiling,
  months): (1) add the sc-mosaic SOTA so the selector actually covers its advertised
  regimes → reframe as a *regime router* (bulk-paired factor methods ↔ sc-mosaic DL
  methods); (2) build a held-out benchmark across data-shape axes (bulk/sc, paired/mosaic,
  2–5 modalities, clustering/survival/biomarker goals) and show the selector **matches the
  oracle best-per-dataset and strictly beats always-MOFA, always-MCIA, and random-menu**,
  with CIs. That benchmark IS the contribution. If it can't beat "always intNMF for
  clustering," there is no selection paper.
- **Smaller science nugget worth finishing regardless:** the "no universal winner" +
  ARD-downweights-a-bad-view robustness finding (MOFA2 flat vs SNF −0.18 ARI on a sparse
  noise view). Preliminary (1 cohort/1 label); needs TCGA generalization + ≥3 weighting
  mechanisms. Could be a Brief Communication or a strong figure in Lane B.

## Recommendation

Not a methods paper today. The most honest, highest-EV path: **Lane A now** (tool note,
positioned as a convenience/reproducibility layer, over-claims removed), while doing the
**Lane B benchmark** as the real research bet — because "our selection beats any single
method across data shapes, on held-out data" is the only claim here that would survive
methods-venue review, and we have the harness (36/36 tests, proven executor contract) to
run it. Do NOT publicly claim "first/only" until PromptBio and Omics Copilot integration
behavior are manually verified.
