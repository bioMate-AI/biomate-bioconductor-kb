# Master plan and critical path — "loop improves the LLM; small ≈ large" study (2026-10-29)

Single deliverable: one manuscript (docs outline in `20261028_CYCLIC_PROGRAM_MANUSCRIPT_INVENTORY.md` §F) with verified results only. Hypotheses: `20261029_HYPOTHESES_SMALL_LLM_LOOP.md`; comparison dimensions: `20261029_MODEL_COMPARISON_ANALYSIS_SPEC.md`.

## Workstreams, owners, dependencies
| id | workstream | output | depends on | status (2026-10-29) |
|---|---|---|---|---|
| WS2 | loop replay (L5 GBM controlled loop; L7 model comparison: GBM, atom LM, v4-subset, ChemBERTa, larger pretrained peptide/chemistry LMs fine-tuned (not NLP LLMs), 5 controls) | yield curves, controls, cost | adapters (exist: LoopModel/AtomLoopModel); frozen lists only for held-out recovery | L5 running on spot; L7 prereg done, not run — **critical path #1** |
| WS3 | benchmark instrument (analysis I; M2→M3 typicality fix; run_s3 harness) | validity-gated held-out recovery | none | M2 invalid (typicality control 0.665); M3 in progress — critical for the recovery metric |
| WS1 | v5 small model (corpus filter, trainer, staged training, stereo eval, cost meter) | upgraded small model | WS3 folds (done), corpus filter, trainer | not trained; **not on critical path** (atom LM serves as small model if v5 slips) |
| WS4 | stratification and substructure-effect analysis | strata, matched-pair effects, feature families | none | running |
| WS5 | knowledge-base audit and gap prototypes | KB verdicts, mined rules (leak-safe) | WS4 matched pairs (read-only) | running |
| SV | literature survey and prior-art table | related work, novelty risk | none | running |
| WS6 | manuscript writer (non-result sections) | Intro, Related Work, Methods, Hypotheses, Limitations, figure plan, result placeholders | SV (related work), docs | to start |
| S2 | physics-chain pilot on 60 αvβ6 compounds | chain-executed arm | owner approval (cap USD 80) | gated |

## Critical path (what determines finish time)
1. **WS2 runs L7 now with existing models** (GBM, atom LM, ChemBERTa, v4-subset, larger pretrained peptide/chemistry LMs fine-tuned (not NLP LLMs), 5 controls). Yield-based metrics need no frozen lists. This alone yields the central comparison. Do not wait for v5 or M3.
2. **WS3 M3** → validity-gated held-out recovery for the same models (adds the generalisation metric). Runs in parallel with step 1.
3. **Aggregation** (me): L5/L7 aggregates, comparison analysis (13 dimensions), figures.
4. **WS6 assembles** the manuscript; result sections filled only from aggregated, audited numbers.
Off the critical path (upgrade if ready): v5 (WS1), KB-mined rules (WS5), S2 chain arm.

## Gates (nothing proceeds past a gate without it)
- Pre-registration committed before any scored run (dated amendment).
- Planted-signal positive control passes per adapter/scorer before any null is believed.
- Benchmark validity gate: no-target and typicality controls must be CI-compatible with chance before arms are judged.
- Shuffled-label feedback must not improve (leak check); data-matched one-shot control reported.
- Audit-first on every unexpected result (suspect our own code).
- Every number in the manuscript traces to a committed artifact; unverified items tagged.

## Compute and cost caps (spot only; tag project=cyclic-selector)
L5 (running, per-task checkpointed); L7 frontier-LLM in-context estimate-first, stop above USD 25; v5 stage 1 stop above USD 40 against the HIGH end of the spot-price range; S2 USD 80 cap, **not started without owner approval**. Real spot prices (us-west-2, 2026-10-29): g6.xlarge 0.43–0.69, g6.2xlarge 0.45–0.92, g4dn.xlarge 0.25–0.27 USD/h.

## Definition of done (first full draft)
Methods and evaluation design complete; L5 and L7 aggregates with CIs and controls; model comparison on the 13 dimensions where data exist; held-out recovery on analysis I (and M3 if its validity gate passes); related work with verified citations and a prior-art risk table; limitations stated (retrospective only; generation needs wet lab; narrow task); all audits listed in `20261028_CODE_DATA_EVAL_AUDIT_LOG.md` plus workstream audit docs.


## Correction (2026-10-30)
'Large LLM' = large pretrained cyclic-peptide/chemistry LMs, not NLP LLMs. OpenRouter/in-context arms retired from the central comparison (≈USD 4.3 spent on exploratory runs; paid calls off). Model candidates: docs/20261030_PEPTIDE_CHEM_LM_MODEL_SURVEY.md (in progress).


## Definition update (2026-10-30)
The subject model is the in-house hybrid loop-native cyclic LLM (IH-LM), not 'small'. Comparators = external pretrained peptide/chemistry LMs fine-tuned plainly + baselines; required same-base ablation ladder (plain → +K_phys → +lab offset → +retrieval → +edit heads). See HYPOTHESES doc 'Definition update' and HYBRID proposal 'IH-LM definition'.
