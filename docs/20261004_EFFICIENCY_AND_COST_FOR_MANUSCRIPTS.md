# BioMate efficiency & cost — manuscript-ready numbers (measured vs projected)

**Date:** 2026-10-04
**Rule for manuscripts:** cite the **MEASURED** set as results; present the **PROJECTED** set only as design
targets / modeled estimates, explicitly labeled. **No invoice-grade cost A/B exists** — every "$/run, spot-%,
N×-cheaper" figure is modeled from list pricing, so none may be stated as an empirical saving.

## A. MEASURED speed-ups (safe to cite as achieved results)
| Result | Measured number | Source |
|---|---|---|
| **CryoEM 4-GPU vs 1-GPU parallel speedup** (EMPIAR-10028, 26,312 particles), equal Nyquist-limited resolution | GPU-bound **92 → 27 min = 3.4×**; 2D-class **5.7×**, ab-initio 2.8×, homo-refine 2.5× | docs/20260428_CRYOSPARC_MULTIMODE_BENCHMARK_RESULTS.md:47,131-134 |
| CryoEM 1-GPU full pipeline (EMPIAR-10028, 20 movies, g6.2xlarge) | **2.8 GPU-h / 7.4 h wall**, FSC 3.98 Å, 0 QC halts | docs/20260427_CRYOEM_BENCHMARK_RUN_AND_PAPER_STATUS.md:21,25-29 |
| **Findings-analysis cache** cold → warm (dedup hit) | **~10 s → 236 ms** (<250 ms re-open) | docs/20260604_PHASE4_FINDINGS_CACHING.md:52-53 |
| Project-module `/api/projects` list latency; the one real lever | med **428 ms**; `ensureLtmUser` upsert = **~97 ms (~20%)** | docs/20260722_PROJECT_MODULE_PERF_AND_TIER_PROPOSAL.md:112,145 |
| `/projects` page-load cold → warm (FCP) | **2.1–3.9 s → 368 ms** | docs/20260722…:155-156 |
| Docker ECR cleanup (real sizes) | **~55 GB freed**; ARM64 vs x86 base **−50 to −75%** per image | docs/20260429_PHARMA_DOCKER_OPTIMIZATION.md:31; docs/20260122_DOCKER_IMAGE_OPTIMIZATION.md:13-19 |
| On-prem/local LLM throughput & marginal cost | **8.2 tok/s** (qwen3:32b), **$0 API cost**; BioMate own $/task **$0.003–0.015** (Sonnet) / $0.0001–0.0005 (Flash) — real tokens × list price | docs/20260427_PUBLISHED_BENCHMARK_COST_SURVEY.md:77-83 |
| Prompt caching implemented (`cache_control: ephemeral`) | code confirmed (gain not independently measured) | frontend/server/galaxy-assistant.ts:7138,7603,8568 |

## B. MEASURED cost (measured input × list price — fair to cite WITH that caveat)
| Result | Number | Source |
|---|---|---|
| **CryoEM 4-GPU cheaper than 1-GPU** despite 1.76× higher $/h (amortized over the speedup) | effective GPU cost **$1.28 → $0.75 (1.7× cheaper)** | docs/20260428…:96-99,136 |
| CryoEM per-run compute (1-GPU, excl. storage) | **~$6.29** (g6.2xlarge, 2.8 GPU-h) | docs/20260427…:29 |

## C. PROJECTED / modeled / design-target (cite ONLY as targets, labeled)
| Claim | Number | Status | Source |
|---|---|---|---|
| Spot vs on-demand GPU | **~60–70% COGS saving** (spot ≈30% of on-demand) | modeled from pricing | docs/20260504_OPERATION_COST_BREAKDOWN.md:108-117 |
| ADMET array/fan-out throughput | **20–50×** (100–10,000 compounds) | local-tested; **dev Batch pending** | docs/20260712_UNIFIED_SPEEDUP_BACKLOG.md:33; docs/20260704_SPEEDUP…:75-79 |
| Tiered model routing (Sonnet→Haiku) | **3–5× latency** on ~80% of calls; ~4 s → ~0.8 s | proposal | docs/20260704_SPEEDUP_LLM_PILOT…:15,18 |
| Nextflow `-resume` on QC-loop reruns | **60–80%** on partial reruns | shipped; % estimated | docs/20260712…:18 |
| Skip `ensureLtmUser` on read | **−~97 ms (~20%)** | recommended; **not yet shipped** | docs/20260722…:372 |
| Prompt caching on system prompt | **~80–90%** cached-input token reduction | modeled | docs/20260504…:647 |
| S3 Glacier vs Standard | **−83%** storage $ | list-price | docs/20260507_STORAGE_COST_MODEL.md:106-109 |
| Local LLM HW-amortized $/task | **5–10× cheaper** than cloud API | modeled | docs/20260427…:102 |
| CryoEM GPU scaling 1→8→20 GPU | 3.6× → 6.7× → **15.6×** | in-progress / projected | docs/20260416_CRYOEM_SPEEDUP…:85-90 |

## D. Where to put it (per manuscript)
- **Flagship Paper A (systems):** an "Efficiency & cost" subsection — lead with CryoEM 3.4× + 1.7×-cheaper (measured), findings cache 10 s→236 ms, Docker 55 GB/50–75%; spot/tiered/ADMET-array as a "designed-for" paragraph labeled projected.
- **Paper B (task-split / on-prem):** the cost case for on-prem is the **measured $/task ($0.003–0.015) + $0 marginal local** × the accuracy result (9B+KB ≈ frontier) — i.e. match frontier capability at a fraction of frontier-API $/token. Keep the spot %-savings as projected.
- **C4 CryoEM/QC paper** already carries the measured cryo numbers — but **fix two internal inconsistencies before submission:** headline "$6.29" (:545) vs table "$2.38" (:303) (~2.6× apart — reconcile which includes what); and "5.7× … approaches theoretical 3× limit" (:324) is self-contradictory (5.7× > 3×). (docs/manuscripts_to_share/C4_BioMate_Cryo_QC_Governance.docx)
- **C5 CryoEnsemble:** the "10³–10⁵× faster than MD" is **BioEmu (Noé et al., Science 2025), NOT BioMate** — attribute it, don't claim it.

## E. Honesty flags (carry into any paper)
- No invoice-grade before→after cost comparison exists; all spot/$/run/%-saved numbers are modeled. State as "modeled from AWS list pricing."
- `dataScope` sampling and lazy step-fetch are shipped but have **no quantified speed/cost gain** — don't assign one.
- The CryoEM 1-GPU baseline (P49) was "aborted, baseline only" — the 3.4× is parallel-vs-sequential on the same dataset; state that framing.

## F. EMPIRICAL cost + time per task — from RealBio's collected usage × real prices (NO new collection)
Built from the 53 committed `results/*/*.usage.json` files (measured token counts + latency p50/p95) ×
current OpenRouter model prices. This is the measured cost+TIME difference the modeled rows in §C approximated.
Tasks where all models overlap: boin / pbpk / drug_discovery_e2e (frontier) + routing/param/etc. (local).

| model | time/task (range) | $/task (range) | basis |
|---|---|---|---|
| **on-prem base 9B** | **0.5–3.6 s** (routing 1.3s, pbpk 0.7s, boin 0.8s) | **$0 API** (local; amortized ≈ g5 spot $0.50/h ÷ throughput) | measured latency; local = no API bill |
| anthropic/claude-opus-5 | 2.4–11.4 s | $0.003–0.016 | tokens×real price |
| google/gemini-3.1-pro | 3.4–16.3 s | $0.004–0.023 | " |
| deepseek/deepseek-v4-pro | 7.8–36.2 s | $0.0002–0.0007 | " |
| moonshotai/kimi-k3 | 2.7–42.6 s | $0.003–0.028 | " |
| z-ai/glm-5.2 | 2.8–20.8 s | $0.0014–0.014 | " |
| openai/gpt-5.6-luna | 2.2–17.4 s | $0.0001–0.0019 | " |

**Headline (empirical):** the on-prem 9B runs each task in **0.5–3.6 s at $0 marginal API**, vs frontier at
**~9–49 s and up to ~$0.028/task** on reasoning-heavy tasks (pbpk/boin) — i.e. **~10–40× faster and ~$0 vs
cents per task**, because frontier reasoning models spend large output/reasoning-token budgets (pbpk: 9–49s,
up to ~2,000 output tokens). At 10k tasks/day that is roughly $0–$few vs **$70–$280/day** in frontier API.
**Caveats:** $/task = measured tokens × *current list* price (invoice-adjacent, not a billed statement);
local models' output tokens were not captured (irrelevant — $0 API); gpt-5.6 and qwen3.8-max had no price in
the live model list (n/a). Latencies include provider/network and vary with reasoning length. Source: the
`.usage.json` files; prices OpenRouter /models (fetched 2026-10-04).

**NOTE on method:** this replaces the need for a new cost-collection run — RealBio already captured per-model
token+latency usage; applying real prices is sufficient. (A redundant fresh OpenRouter cost run was started
then abandoned in favor of this existing data.)
