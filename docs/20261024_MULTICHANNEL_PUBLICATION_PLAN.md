# Multi-channel publication plan — own-LLM / benchmark / harness program

**Date:** 2026-10-24 · Plan to publish this program across channels, with the **no-external-method-
disclosure** rule and an **honest framing** that matches what the evidence actually supports.

## The honest framing (what the evidence supports — and does NOT)
This session's measurements set the story:
- **Supported, strong:** the **harness / knowledge layer carries biomedical workflow automation** —
  base+harness routes at **0.885**; the open-model bare→+harness dividend is **+39–70pp** and
  converges small open models to ~80–94% (on-prem/China story). This is Paper B's thesis, now
  well-evidenced, and the honest headline.
- **Supported:** the **benchmarks** (RealBio, DrugDev) as objective, execution-grounded, bare-vs-
  harness evals; BixBench-exec 87.5% ≈ Biomni Lab after the run_code fix.
- **NOT supported (do not claim):** "our fine-tuned model beats frontier." The clean-data SFT
  **regressed** (routing 0.885→0.53; condition mismatch), GRPO-on-binary **stalled**. The honest
  model line is "a small on-prem model + harness reaches frontier-parity on domain tasks," never
  "our SFT wins."

## Papers on this topic (6)
A RealBio (benchmark) · B Harness-vs-LLM (KB-dividend) · D On-prem domain LLM (consolidated) ·
E Execution-first QC-governed platform · F Source→Nextflow conversion (plan) · DrugDev-Bench.

## Disclosure split (the hard gate)
| Tier | Papers | External treatment |
|---|---|---|
| **Public-by-design** | RealBio (A), DrugDev-Bench | Full external: benchmarks describe *what is measured*, not proprietary method. Post broadly. |
| **Thesis, careful** | Harness-vs-LLM (B) | Postable as the *finding* ("knowledge layer carries automation") without the training recipe. |
| **Method — protect** | On-prem LLM (D), platform internals (E) | External = **capability framing only** (what we deliver + light tag). Full method stays internal. |

## Channel × paper matrix
| Channel | A RealBio | DrugDev-Bench | B Harness | D On-prem | E Platform |
|---|---|---|---|---|---|
| **arXiv/bioRxiv preprint** | ✅ | ✅ | ✅ (finding only) | capability-only | capability-only |
| **GitHub** (public_export / drugdev_export: data+leaderboard+MANIFEST+LICENSE) | ✅ | ✅ | — | — | — |
| **Hugging Face** (dataset + leaderboard) | ✅ | ✅ | — | — | — |
| **Project website** (webpage_design_v2, capability framing) | ✅ summary | ✅ summary | ✅ | ✅ (capability) | ✅ (capability) |
| **Blog / social** (announce) | ✅ | ✅ | ✅ | — | — |

RealBio already has a GitHub/HF-ready bundle (`evaluation/datasets/public_export/`: README, README_GITHUB, MANIFEST, LICENSE, leaderboard.csv + 5D).

## Prerequisite before posting (from the completeness audit)
Do NOT post the benchmark leaderboards with holes:
1. Fill the **+harness column** for the whole roster (only ~7–12/25 have it) — the thesis depends on it.
2. Complete protocol/autofix/workflow_gen for the missing models; run **proteomics_search**.
3. Build a **DrugDev leaderboard** (drugdev_export has none) + run its suite across the roster.
(LAB-Bench/BioAgentBench/SAB are EXTERNAL — improvement-track only, NOT published as ours.)

## Sequence
1. **Complete RealBio + DrugDev leaderboards** (the gap-fill sweeps) — gating for a credible benchmark post.
2. **Post the benchmarks** (arXiv + GitHub + HF) with the bare-vs-harness result front and center.
3. **Post Paper B** (harness-vs-LLM finding) alongside — the honest headline.
4. **Website/capability** pages for D/E (no method).
5. Blog/social announce.

## Constraints honored
- No-method-disclosure: method papers external = capability-only.
- No Artifact tool (never publish via it).
- Can't auto-submit to arXiv/bioRxiv (manual accounts) — this plan + the prepared bundles are the deliverable; submission is a manual step.
