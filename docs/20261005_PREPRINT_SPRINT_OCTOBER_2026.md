# Preprint sprint — all preprints online in October 2026

**Date:** 2026-10-05 · **Goal (user):** put *all* preprints online this month. **Rationale:** every direct
comparator (Biomni/Science, Virtual Lab/Nature, LongevityBench/Cell) preprinted **8–13 months** before
journal publication and used the preprint to carry priority + visibility through review
(`docs/20261005_COMPETITOR_PUB_TIMELINES_AND_OUR_ESTIMATE.md`). Posting now locks priority while the slow
journal cycle runs.

> **Division of labor.** I make each manuscript **preprint-ready** (content polished, numbers reconciled,
> honesty caveats correct, figures, author/affiliation block). **The actual bioRxiv/arXiv/medRxiv upload is a
> human step** (requires the account, ORCID, license selection, PDF submission) — that's on the user. I
> prepare + stage; the user clicks submit. I'll flag each as READY-TO-UPLOAD.

> **Preprints do NOT wait on the fuller CPT run.** Papers B/D go up with current honest results (corrected
> +4.4pp concept-CPT, open-LLM refresh) and get a **v2** when the spark run lands. Standard practice.

## Readiness tiers (from `docs/marketing/manuscript-plan.md` §1)

### GO NOW — post as-is / trivial polish (Week 1: Oct 6–12)
| Paper | Server | Pre-upload task | Owner |
|---|---|---|---|
| **RealBio benchmark** | bioRxiv + arXiv (cs.LG) | manuscript-complete; confirm author block + CC-BY; final read | me→user upload |
| **Bioc-KB Paper 1** (NAR-bound) | bioRxiv | strongest data; add data-availability + DOI placeholder | me→user |
| **Bioc-KB Paper 2** | bioRxiv | finalize benchmark table; caveat "delta = automation, not first" | me→user |
| **anti-TNF IBD app note** | medRxiv | most-caveated; keep "not a novelty claim" framing; confirm GEO accessions | me→user |

### GO AFTER LIGHT UPDATE — 1–3 days each (Week 2: Oct 13–19)
| Paper | Server | Pre-upload task |
|---|---|---|
| **Paper B — harness-vs-LLM** | arXiv (cs.CL) + bioRxiv | fold in corrected **9B concept-CPT +4.4pp** (`docs/20260912_onprem_llm/20261005_9B_CONCEPT_CPT_EVAL_CORRECTED.md`) + **open-LLM refresh** (4 newest models confirm 9B+KB≈frontier); keep decomposition as open problem |
| **C1 flagship system** | bioRxiv | post as system description with the **live QC-gate proof** (run d0ff684b); caveats in-text: self-grading COI + Biomni full-surface baseline pending (these gate *journal acceptance*, not a preprint) |

### GO AFTER CONSOLIDATION — bigger lift (Week 3: Oct 20–26)
| Paper | Server | Pre-upload task |
|---|---|---|
| **Paper D — on-prem LLM** | arXiv (cs.LG) | consolidate the **3 overlapping drafts into one**; reconcile catalog count to **4,209 / 1,092 validated**; report **family-holdout retriever (0.694) only**, label random-split as leakage-inflated; fold in corrected concept-CPT + open-LLM refresh; frame as cost/compliance |
| **preprocessing-QC app note** | bioRxiv | finish Gates 1–2 write-up; keep "do NOT claim first; RBET 2025 prior art; delta = automation" |
| **Cryo-EM benchmark** (~70%) | bioRxiv | post with real EMPIAR-10028 3.98 Å + P52 1.78 Å results + explicit "comparison to CryoSPARC/RELION/Warp pending" caveat, OR hold to Nov if protocol-discrimination is close — **user call** |

### HOLD / REFRAME — do NOT preprint as empirical this month (honesty gate)
| Paper | Why held | Minimal fix to post honestly |
|---|---|---|
| **M1 endotyping, M3 isotype-gate, M4 antigen-resolution** | Analysis/Methods papers that **imply results**; "full pipeline not yet run end-to-end on a real cohort" | reframe explicitly as *frameworks/designs* (title + abstract), OR run one end-to-end on a real cohort first. Marketing/over-claiming rule forbids posting these as validated results. |
| **M2, M5 (Perspectives)** | non-empirical by design — **OK to preprint** as Perspectives | confirm author list (placeholders) + explicit "Perspective, no new data" framing |
| **CryoEnsemble** | "ALL results use a Gaussian perturbation model, NOT actual BioEmu/cryoDRGN" | do not post until real-model results exist, or reframe as a methods-proposal with the simulation explicitly labeled |

## Cross-cutting pre-upload requirements (apply to EVERY preprint)
1. **Catalog count:** cite **4,209 workflows / 1,092 validated** separately (reconciled 2026-10-04). Fix the on-prem drafts' stale 4,017/4,200.
2. **No fabricated citations;** family-holdout numbers only for the retriever; every number traces to a committed artifact.
3. **Author/affiliation block + ORCID + corresponding author** — **USER INPUT NEEDED** (M-series have placeholder author lists; confirm bylines before upload).
4. **License:** CC-BY-4.0 (matches the open-data/scorer posture).
5. **Preprint server accounts:** bioRxiv requires an affiliated-author account + a non-author co-submitter verification; arXiv needs endorsement for first-time cs submitters — **start account setup now** (lead time can bite the Oct deadline).

## Realistic October outcome
**~7 preprints postable honestly this month:** RealBio, Bioc-KB ×2, anti-TNF IBD, Paper B, C1 flagship,
Paper D (+ preprocessing-QC and M2/M5 Perspectives if author lists land; Cryo-EM a user call). **3–4 held**
(M1/M3/M4 as-is, CryoEnsemble) — posting those as empirical would breach the honesty/over-claiming rules.

## Immediate next actions (me)
1. Confirm each GO-NOW manuscript's current numbers against reconciled catalog count + committed artifacts (Week-1 batch).
2. Update Paper B with the corrected concept-CPT + open-LLM refresh (the one new-evidence fold-in).
3. Start the Paper D consolidation (3→1).
**User inputs needed:** (a) author/affiliation + corresponding author for each (esp. M-series); (b) bioRxiv/
arXiv account confirmation; (c) the Cryo-EM "post-now-with-caveat vs hold-to-Nov" call.
