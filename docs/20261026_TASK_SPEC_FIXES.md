# Task-spec construct-validity fixes (committee blocker #4)

**Date:** 2026-10-26. The committee (2026-10-26) required repairing underspecified task definitions BEFORE
interpreting capability. Status per task:

## PBPK — FIXED (endpoint was unspecified)
**Bug:** the prompt said "predict the requested pharmacokinetic value" but never said WHICH, while each item's
`reference` holds four values (Cmax_uM, AUC_uM_h, t_half_h, Tmax_h). The scorer matched the *first number in
`str(reference)`* — i.e. Cmax by dict-ordering accident, never told to the model. So the ~0.07–0.20 scores
measured prompt ambiguity, not PBPK ability (the committee's exact point: do not call models "near-useless at
PBPK").
**Fix:** each item now carries explicit `target_endpoint="Cmax_uM"` / `target_units="uM"`; the prompt
(`run_baseline.py` GEN) asks explicitly for "peak plasma concentration Cmax in µM"; `score.py::score_pbpk`
reads `reference[target_endpoint]` (robust) with the legacy first-number regex as fallback. Re-scoring the
existing predictions is unchanged (gpt-5.6 0.2, base 0.067) because the endpoint was already (accidentally)
Cmax — but those preds were generated under the OLD ambiguous prompt. **The honest PBPK numbers require a
rerun with the fixed prompt** (billable); until then the committed PBPK cells are flagged "old spec — not a
capability measurement."

## param_prefill — CLARIFIED (condition, not a data bug)
The committee noted the prompt says "fill only if clearly stated" yet the gold expects an unstated reference
genome inferred from organism (human→GRCh38). This is the raw-LLM-vs-production distinction, already handled in
the merged suite paper: the raw-LLM column is a FLOOR (no inference layer); BioMate's production path does the
canonical organism→genome inference deterministically (rule layer) → F1 0.843. No data change; the honest
framing is "raw LLM scored without the inference layer the system ships." A future v2 may split param-prefill
into an explicit "canonical-inference" subtask vs a "restraint" subtask.

## BOIN — TO CLARIFY (documented, not yet changed)
The committee asked whether boin_mtd scores the algorithmic dose-escalation DECISION or recovery of the
simulation's latent true MTD — not equivalent. Action (pending): state the scored quantity in the boin README
and, if it is latent-MTD recovery, add the decision-accuracy variant. Not changed in this pass.

## Net
PBPK construct-validity fixed (explicit endpoint); its honest numbers are gated on a rerun. param is a framing
clarification (covered by raw-vs-production). BOIN needs a one-line spec statement + possibly a decision
variant. All flagged in `LEADERBOARD_CAVEATS.md` / Results Release v1 so no current PBPK/param/BOIN number is
cited as a capability result prematurely.
