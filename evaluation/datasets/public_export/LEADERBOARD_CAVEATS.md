# RealBio leaderboard — integrity caveats (READ before citing or publishing any cell)

Authoritative list of every known data-quality caveat in `leaderboard.csv`, from the 2026-10-25/26
benchmark error-analysis (`../../../docs/20261025_BENCHMARK_ERROR_ANALYSIS_ROOTCAUSE.md`). Reproduce any
claim here with `audit_routing_provenance.py` and the per-model `*.audit.json` sidecars under `results/`.
Do not publish the leaderboard without these caveats resolved or stated.

## Scoring (applies to every row)
- `score.py` measures **semantic** correctness, not string identity: workflow names match with `_`≡space;
  param values match canonical genome/bool aliases (hg38≡GRCh38, disabled≡False) + region containment.
  This lifted every system uniformly vs. the old exact-string scorer (e.g. param F1 +~5pp across the board).

## routing (bare, direct-use column)
- **Empties were diagnosed by cause, not blanket-deleted:**
  - `kimi-k3`: 21 truncation-artifact empties were **re-run and resolved** (0.450→0.495, 0 empties).
  - `opus-5.5`: 14 empties are **content-filter refusals** (`finish_reason=content_filter` on drug-discovery
    queries) — a **real routing failure**, correctly scored as wrong (0.610). Not an artifact.
  - **`qwen3.8-max` (44% empty) is NOT CITABLE** and `gpt-5.6` (5% empty) is mildly understated — neither is
    cleanly re-runnable here (no exact OpenRouter slug / not on OpenRouter). Re-run against their exact
    endpoints before citing their bare cells.

## routing_harness (catalog column — the thesis-critical one)
- **UNIFORM RE-RUN DONE 2026-10-26 (`rerun_routing_openrouter.py`, empties-aware):** 6 leaderboard rows moved
  from the legacy names-only menu to the uniform `described` menu (0 empties each): Kimi 0.860→0.970,
  GLM-5.3-prime 0.885→0.955, GLM-5.2 0.890→0.950, GPT-5.6-luna 0.885→0.950, Gemini-3.1-Pro 0.960→0.975,
  DeepSeek 0.800→0.850. Now **15 models are on the uniform `described` menu.**
- **Update 2026-10-26 (round 2):** `qwen3.8-max` and `gpt-6.1` ARE reachable (earlier claim was wrong — the
  slugs are `qwen/qwen3.8-max-prime`/`-0902` and `openai/gpt-6.1-sol-pro`). Both re-run clean on the uniform
  described menu (0 empties): **Qwen3.8-Max routing_harness now from `qwen3.8-max-prime` = 0.940**; added
  **GPT-6.1-sol-pro = 0.985** as the current-gen GPT representative. (Correction: gpt-6.1-sol-pro did NOT
  "hang" — it runs fine fresh; the earlier full-run incompletion was cumulative OpenRouter rate-limiting at
  the tail of a 1,600-call run.) **17 models now on the uniform described menu.**
- **Residual caveats:**
  - `gpt-5.6` is not on OpenRouter — its routing_harness cell stays on the names-only menu (flagged);
    GPT-6.1-sol-pro is the current-gen GPT representative in its place.
  - `opus-5.5` (not a main leaderboard row) has 18 **content-filter** refusals in the described condition too
    (real behavior, understates it).
  - **Provenance:** the 6 re-run cells are OpenRouter-served; the already-`described` cells (opus-5, base/sft,
    qwen2.5/3.5 series) came from their own harness. Same menu CONDITION now (the fairness fix), but serving
    provenance differs per model — a secondary caveat for a strict publication.
- **Finding:** under the uniform described menu, **BioMate 9B base+harness = 0.905**, within range of the
  frontier (0.94–0.99) and well above same-class open models (qwen3.5-9b 0.830, qwen2.5-7b 0.735) — the
  harness-is-the-lever thesis holds on a fair, uniform comparison.

## param_prefill
- The rows labeled **"BioMate 9B (base/SFT)" are the RAW LLM with BioMate's production rule layer OFF** — they
  under-state BioMate. The real production number (rule layer `_rule_based_param_inference` +
  `_validate_extracted_params` + IO guardrail) is **F1 ≈ 0.84**, not 0.63/0.70 (see the doc; canonical
  measurement = `evaluation/runners/run_param_prefill.py` against the live backend). Relabel the raw rows and
  add a "BioMate on-prem (production)" row before publishing.
- param empties are **legitimate** (`{}` is the correct restraint answer when nothing is specified); the F1
  scorer already counts a wrongful empty as a recall miss. Not a contamination.

## Model-training claims (do NOT make)
- Both SFT attempts **regressed**: bare-query clean SFT (routing 0.885→0.53) and condition-matched deployment
  SFT (param 0.634→0.52, decomp→0.0). GRPO-on-binary stalled. The honest line is "small on-prem model +
  harness reaches frontier-parity," never "our SFT wins." See the SFT verdict doc.

## Reasoning-model measurement
- Large reasoning models return `content=None`/`finish_reason=length` when `max_tokens` is eaten by thinking
  tokens → fake ~0 cells + ±20pp run-to-run swings. The on-prem `qwen3.5-9b` is by contrast **deterministic**
  (0.000 spread over 3 rounds, 0 empties, ~2% stable hallucination). Any roster number must come from an
  **empties-aware** harness (budget max_tokens past thinking tokens, retry, flag empties).

## The one prerequisite that clears most of this
Run `rerun_routing_openrouter.py` across the full roster (uniform `described` menu, empties-aware) + the
production param path, then `regen_leaderboard_csv.py`. That yields a uniform, empties-flagged, fairly-scored
leaderboard. It is a bounded but real API spend — fire deliberately.
