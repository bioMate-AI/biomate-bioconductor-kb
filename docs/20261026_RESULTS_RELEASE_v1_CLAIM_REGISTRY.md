# RealBio Results Release v1 — frozen claim registry (single source for all manuscript numbers)

**Freeze:** the committed repository state at the commit that adds this file (≥ `e21f3b671`, 2026-10-26).
**Scorer:** `evaluation/datasets/public_export/score.py` @ `e281c1bdd` (semantic: genome/bool aliases,
`_`≡space, region containment). **Addresses committee blocker #1** (2026-10-26 committee review): every
headline number below traces to ONE source + condition + denominator; the manuscripts must cite THIS release
and nothing else. Regenerate with `regen_leaderboard_csv.py`, `drugdev_export/leaderboard.py`,
`channel_routing/run_channel_routing.py`, `local_trial/measure_production_param_rules.py`.

## Condition definitions (the apples-to-oranges fix — committee blocker #2)
- **bare (direct-use)** = LLM + query only, NO candidate catalog. (leaderboard column `routing`.)
- **+harness (described menu)** = LLM + query + the retrieved candidate workflows WITH descriptions — the
  **matched same-model** comparison; THIS is the primary scientific comparison. (column `routing_harness`.)
- **BioMate product (engine-free, C2)** = full production retrieval, no LLM in the loop (0.965). A product
  data-point, **NOT the headline** (per committee — reporting it as the headline reads as a "rigged pitch").

## 1. Canonical routing leaderboard (n=200; scorer `e281c1bdd`; `results/<model>/…`)
| model | bare | +harness (described) | note |
|---|---|---|---|
| Claude Opus 5 | 0.615 | 0.990 | described |
| GPT-6.1-sol-pro | 0.590 | 0.985 | described (2026-10-26 re-run) |
| Gemini 3.1 Pro | 0.580 | 0.975 | described |
| Kimi K3 | 0.495 | 0.970 | described; bare fixed (21 truncation empties re-run) |
| GLM-5.3-prime | 0.375 | 0.955 | described |
| GLM-5.2 | 0.400 | 0.950 | described |
| GPT-5.6-luna | 0.355 | 0.950 | described |
| GPT-5.6 | 0.530 | 0.940 | **+harness = names-only menu (not on OpenRouter) — flagged** |
| Qwen3.8-Max | 0.345 | 0.940 | +harness from qwen3.8-max-prime; **bare 0.345 has 44% empty = NOT CITABLE** |
| Qwen3.5-27B | 0.240 | 0.935 | described |
| **BioMate 9B (base)** | 0.180 | **0.905** | described — the canonical on-prem base+harness number |
| Qwen3.8-27B | 0.175 | 0.875 | described |
| DeepSeek V4-pro | 0.415 | 0.850 | described |
| Qwen3.5-9B | 0.120 | 0.830 | described |
| BioMate 9B (SFT) | 0.285 | 0.810 | described (SFT adapter — regressed, do not deploy) |
| Qwen2.5-7B | 0.140 | 0.735 | described |
| Biomni (A1 scaffold) | 0.950 | 0.950 | agent scaffold (catalog file) |
| BioMate (engine-free, C2) | 0.965 | — | product retrieval, no LLM (not a headline) |

## 2. param_prefill — RAW LLM vs PRODUCTION (committee blocker #2)
The leaderboard `param_prefill_F1` column is the **raw LLM** (rule layer OFF). The rows labeled "BioMate 9B"
are therefore the raw on-prem LLM, **not** the shipping system. The PRODUCTION number:

| config | param F1 | precision | recall | must_not_fill viol | source |
|---|---|---|---|---|---|
| raw on-prem 9B ("BioMate 9B (base)" in the table) | 0.703 | 0.785 | 0.636 | 53 | `results/base/param_prefill.jsonl` |
| rule layer ALONE | 0.470 | 0.960 | 0.311 | 4 | `measure_production_param_rules.py` |
| **BioMate on-prem (production: rule layer + 9B + IO guardrail)** | **0.843** | 0.900 | 0.793 | 27 | `measure_production_param_rules.py` |

→ Cite the on-prem param number as **≈0.84 (production)**, not 0.70/0.63. (Canonical measurement =
`evaluation/runners/run_param_prefill.py` vs the live backend — still to run for the official figure.)

## 3. channel_routing (the new stage-1 "which resource" benchmark; n=84, 64% drug-dev)
On-prem 9B (`results/qwen_qwen3.5-9b/channel_routing_summary.json`): **bare 0.750 (dd 0.778) → +harness 0.964
(dd 0.982), dividend +21.4pp** — the harness dividend reproduced on a new capability. (Full roster still to run.)

## 4. DrugDev (3 adequate-n tasks; the 17 micro-tasks n=2–10 are NOT scored)
`drugdev_export/leaderboard.csv`: pbpk_2fold (n=15), boin_mtd (n=20), dd_spearman (n=15). Notable: BioMate 9B
base BOIN = 0.778 (best small/open). PBPK universally weak (0.0–0.2) — and PBPK prompt is endpoint-underspecified
(committee: do not call models "near-useless at PBPK" — fix the spec + rerun).

## 5. Number disambiguation — resolving the 0.880 / 0.885 / 0.905 / 0.915 / 0.92 the committee flagged
One quantity ("BioMate on-prem base + harness routing"), one canonical value — the rest are an evolution or
stale:
- **0.880** = original strict-string scorer (superseded).
- **0.885** = + underscore scorer fix.
- **0.900** = + 3 gold corrections (documented `acceptable_alts`).
- **0.905** = **CANONICAL** — BioMate 9B base routing_harness under the uniform `described` menu + semantic
  scorer (this release).
- **0.915 / ~0.92** = stale figures in earlier drafts → **SUPERSEDED, do not cite.**

## 6. Non-citable / flagged cells (carry these forward; see `LEADERBOARD_CAVEATS.md`)
- `gpt-5.6` +harness = names-only menu (not on OpenRouter); `qwen3.8-max` **bare 0.345 = 44% empty = not
  citable**; `opus-5.5` has 18 content-filter refusals (real behavior, not a row); DrugDev 17 micro-tasks
  unscored (tiny-n). 17/20 routing_harness cells are uniform `described`; the rest flagged.

## 7. Still-open before submit (committee punch list, beyond this freeze)
(a) matched bare-vs-harness must be the PRIMARY leaderboard + wire the rule layer into the param eval;
(b) **independence/held-out audit** — the scorer/rules/descriptions were changed after examining benchmark
errors, so those gains are currently dev-set; freeze + evaluate on independently-authored held-out items;
(c) fix PBPK/param/BOIN task specs + rerun; (d) Manuscript D needs real deployment (cost/latency/compliance)
numbers; (e) complete the full-roster channel_routing + the official `run_param_prefill.py` production figure.
Re-convene the committee before declaring submit-ready (submit-review gate).
