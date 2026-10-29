# Paper 1 — morning package (2026-10-31; prepared autonomously overnight; nothing submitted or sent)

## 1. One-page status
**What the paper is.** An evaluation-and-controls paper (`docs/20261030_MANUSCRIPT_EVAL_CONTROLS_DRAFT_v2.md`, ~4,100 words) with two delivered, audited contributions (a validity gate as an equivalence test; a leak-aware replay protocol) and one finding that matters for the field: gains attributed to feedback loops on public cyclic-peptide data are mostly the initial fit, analog lookup and laboratory concentration. It is not a model paper, and it carries no performance claim for the in-house model. Committee verdict (round 3): v2 = major revision, the stronger framing; venue fit JCIM / J Cheminformatics / Digital Discovery or a workshop.
**Headline now:** loop − frozen is small (+8.0 A, +1.5 B; regime L +47.3 aware / +13.2 blind full protocol); loop − random (+186) is post hoc, transductive and an upper bound; no benchmark we built is VALID (analysis I NOT_VALID_BIASED; censoring dominant: 63.6 % of inactives censored against 3.1 % of positives); few-label gain is nearest-neighbour lookup.

## 2. What is final (cited from committed files; verifier 120 checks; final_pass clean)
- v2 body, Sections 1 to 7 and Appendix A; the learner-labelled L7 tables from the aggregate e5da79e9ab27086a505ced08fd18845deafd98e6c949428b1bbe4f357c80ef13 (aware, blind, physicochemical never pooled); the validity-gate results (V5); the C2 binding loop; the stratification numbers after the source fix (41 sources; leave-labs-out 0.22 / 0.21 / 0.25); the frozen aware-vs-blind appendix finding; the committed figures F1, F2, F3, FH4b, F8, F9, FCV, FK, FL5 and tables with a hash manifest.
## 3. What is pending
(a) L7q re-aggregation (deterministic shuffled-knowledge permutation; confirmatory seeds): K_phys vs shuffled stays exploratory and out of every claim. (b) T1/T1b corrected cells: folded in (f595013b3); fusion stays exploratory and out of the primary claims. (c) Causal-normalisation arm: not implemented, so the loop-vs-random headline stays demoted. (d) Owner decisions below.
## 4. Decisions defaulted overnight (owner to confirm)
v2 as the paper; prune to a ≤ 250-word planned section; demote the +186 headline; apply committee-3 text fixes; prior art named with tags (numbers only for Amirahmadi); pilot 1 as one limitation sentence; activate the AWS `project` cost-allocation tag (open, not defaulted).
## 5. Numbers that depend on a pending job (itemised)
| number(s) | where | depends on |
|---|---|---|
| every K_phys − K_shuffled yield, E-gain and cluster-column value; the 54-contrast and nine-configuration counts (15/54, 9/54); the Holm count (1/54 at 0.05, 0/54 at 0.01); A13 and A35 rows | long draft §5.2, D1, appendix; brief; patch note | L7q aggregate and hash [REGEN-K] |
| K_phys 'loop' leads (aware A +5.9, B +2.3, L +1.8; blind L +7.1) | long draft D1 | L7q |
| K_phys offline row (median ρ 0.252, p 5 × 10⁻⁵; 10 of 21 laboratories) | v2 §3.6, long draft §5.3 | recomputation after the source fix (labelled pre-source-correction) |
| T1/T1b permeability cells: now corrected (PT 0.401 / 0.369 / 0.388; PT+k 0.425 / 0.418 / 0.429; F2 supported at k = 5 only, +0.058; F1 k = 25 passes t95; T1b unchanged); superseded values 0.419 / 0.454 etc. kept only as 'superseded' | long draft §5.7, A34, patch note, v2 §6 | none pending; exploratory (5 seeds per cell; T1b shuffle-null diagnostic 5 of 15 intervals excluding 0, undiagnosed) |
| loop − random headline (+186.3, +22.2, +163.4, 346 of 500 picks from one laboratory) and the 75 % / 92 % frozen shares | v2 P2, §3.1; long draft abstract and §5.1 | causal-normalisation arm (not run) |
| the SHA-256 e5da79e9… and all numbers read from `l7_aggregate.json` | all four documents, verifier | any further aggregate re-freeze |
| fusion weight convention (starts at 0.5, counting the initial 100 labels) | v2 §6 | documentation only |
| anchor design (D1) statement | v2 §6 | none (final), but limited to the simulation's assumptions |
## 6. How to re-verify
`python3 research/guangzhou_all_atom/cyclic_llm/qa_audit/verify_artifacts.py` and `.../final_pass.py`; figures: `research/guangzhou_all_atom/figures_paper/run_all.py`, manifest in `figures_paper/committed/MANIFEST.json`.
