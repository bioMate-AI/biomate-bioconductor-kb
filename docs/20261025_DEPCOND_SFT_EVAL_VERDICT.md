# Deployment-condition SFT — eval verdict (honest negative)

**Date:** 2026-10-25 · Closes the "all" track-b retry (commit `57de48052` trained it; this is the eval).
Adapter: `sft_sftdepcond` (550 steps, QLoRA r16 on `clean_sft_depcond_corpus.jsonl`, 31,542 rows, routing
prompt = request + candidate catalog with prose descriptions → gold). Eval = base vs base+adapter, both
**with the harness**, OOG, greedy. Scores: `.../eval/spot_harness_sftv3real_20261025_182648/scores/`.

## Result — regression across the board
| Task | base + harness | depcond-SFT + harness | Δ |
|---|---|---|---|
| routing (catalog, n=200) | **0.880** [0.828–0.918] | 0.835 [0.777–0.88] | −4.5pp (CIs overlap) |
| param_prefill F1 (n=170) | **0.634** (P0.834/R0.512) | 0.516 (P0.613/R0.446) | **−11.8pp** |
| param must_not_fill violations | 31 | 76 | **+45 (2.5×)** |
| decomp_real structure_acc | **0.368** | **0.000** | **collapse** |
| decomp_real node_f1 | 0.025 | 0.000 | −2.5pp |
| litqa2 (n=199) | 0.251 | 0.241 | −1.0pp (noise) |

(decomp_v2 and task_decomposition for the adapter arm were still running at write time; decomp_v2 is
in-generator/leakage-prone and is not the honest metric — decomp_real already collapsed to 0.0.)

## What this means (the honest read)
1. **The condition-mismatch hypothesis is FALSIFIED.** The earlier clean SFT (bare query→filename) regressed
   routing 0.885→0.53; we hypothesized the cause was train/deploy condition mismatch and rebuilt the corpus
   in the deployment condition (query+catalog→gold). It **still regresses** — routing −4.5pp, param −12pp,
   must_not_fill 2.5× worse, decomp collapses to 0.0. So condition-matching was NOT the (only) root cause.
2. **Naive SFT on top of a strong base+harness intrinsically harms.** Two independent SFT attempts (bare,
   then condition-matched) both regress. The adapter overfits its supervised distribution and **catastrophically
   forgets** the general capability the harness relies on — most starkly decomposition (0.368→0.0) and the
   restraint behavior param must_not_fill measures (31→76 violations).
3. **Reconfirms the KB-dividend thesis (the publication headline).** The harness/retrieval is the lever, not
   the weights. base+harness already routes at 0.88; SFT cannot beat it and here actively degrades it. This is
   now evidenced by *two* failed SFT conditions, not one — a stronger negative.

## Actions
- **Do NOT deploy `sft_sftdepcond`.** It is worse than base+harness on every scored axis.
- **Stop pursuing naive routing/param SFT for the on-prem model.** The lever is the harness; the model should
  stay the clean base behind it. Further supervised fine-tuning of routing/param is a dead end on this base.
- **If training is revisited**, the only honest candidates are (a) execution-grounded preference signal
  (DPO/GRPO on real `real_exec_status` / execution-grader reward — note GRPO-on-binary already stalled, DPO
  from a clean base not yet run) and (b) capability-specific heads that do **not** touch the general policy the
  harness composes with. Neither is a routing/param SFT.
- **Publication (Paper D / on-prem story):** the honest line is "a small on-prem base + harness reaches
  frontier-parity on domain tasks; supervised fine-tuning of the small model does not improve and can harm it
  — the knowledge/harness layer carries the automation." Never "our SFT wins."

## Session's real wins remain
run_code firing fix (shipped, PR #299), committee-audit data discipline (caught 69% garbage), the honest
DrugDev leaderboard (`d93be6ec2`), and now a **clean, decisive negative** on SFT that saves future GPU spend.
This is benchmark-driven development working as intended: the eval told us the truth and we recorded it.
