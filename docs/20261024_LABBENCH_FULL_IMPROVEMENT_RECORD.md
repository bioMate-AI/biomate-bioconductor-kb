# LAB-Bench (FutureHouse) full run — detailed improvement record

**Date:** 2026-10-24 · **Purpose:** LAB-Bench is an EXTERNAL benchmark (not one of our proposed
benchmarks). We evaluate BioMate on it to find gaps and improve BioMate + the local LLM — recorded in
detail, NOT published as ours. Run: BioMate on dev-public (model served `gpt-5.6-luna` + harness),
all 5 subtasks, `--no-pubmed`, n=471. Harness: `evaluation/runners/run_labbench.py`.

## Scores (n=471)

| Subtask | n | BioMate | FutureHouse (Sonnet-3.5, 2024) | Δ |
|---|---|---|---|---|
| CloningScenarios | 33 | 93.9% | ~60% | +34 |
| SeqQA | 110 | 76.4% | ~45% | +31 |
| ProtocolQA | 108 | 82.4% | ~55% | +27 |
| LitQA2 | 110 | 62.7% | ~53% | +10 |
| **DbQA** | 110 | **41.8%** | ~60% | **−18** |
| **Overall** | 471 | **67.7%** | — | — |

**Fairness caveat (consistent with the on-prem analysis):** BioMate here is the SYSTEM
(`gpt-5.6-luna` backbone + harness); the FutureHouse figure is a single 2024 model (Sonnet-3.5) bare.
The deltas therefore overstate vs a *modern* bare model — the honest read is "BioMate 67.7% overall,
strong on protocol/sequence/cloning reasoning, weak on database-fact recall."

## Per-subtask failure analysis → improvement actions

### DbQA — 41.8% (the clear gap). 64/110 wrong.
- **Failure mode: confident-wrong.** 45/64 failures are a single wrong letter (not abstentions) —
  BioMate answers database-knowledge questions (DisGeNET / OMIM / UniProt gene–disease associations,
  identifiers) from **parametric memory and guesses**, because the MCQ path instructs "answer
  directly, no tool use." Only 15/64 abstained.
- **Root cause:** the data-plane retrieval tools (Open Targets / DisGeNET / UniProt / the 60+ DB
  connectors) are NOT wired into the knowledge-answer path for DB-fact questions.
- **ACTION (BioMate improvement):** for database-fact questions, route to a **retrieval-then-answer**
  path (query the real DB for the association/identifier, answer from the retrieved record) instead
  of forcing parametric direct-answer. This is the single highest-leverage LAB-Bench fix and is a
  real product gap (BioMate *has* the tools; the knowledge-MCQ path doesn't use them).

### LitQA2 — 62.7% (no-retrieval floor). 41/110 wrong.
- **Failure mode: correct abstention.** 24/41 failures are "I cannot answer with confidence based on
  training knowledge" — **good calibration, not hallucination.** They need the source paper's passage.
- **Root cause:** run was `--no-pubmed` (parametric only); the adapter has a EuropePMC/key-passage
  retrieval path that was disabled here.
- **ACTION:** re-run LitQA2 WITH literature retrieval (EuropePMC full-text passage) to measure the
  real ceiling; the abstention behaviour is correct and should be preserved (do not "fix" by forcing
  a guess — that would trade calibration for a fake score).

### ProtocolQA 82.4% / SeqQA 76.4% / CloningScenarios 93.9% — strong, no action.
BioMate handles wet-lab-protocol troubleshooting, sequence reasoning (ORFs/codons/translation), and
cloning design (restriction/Gibson/primer) well — the harness's compute-context injection helps here.

## Local-LLM-on-LAB-Bench (pending)
This run is the BioMate SYSTEM. To record the *local LLM* (the `sft_sftclean` adapter) on LAB-Bench,
serve it (vLLM) and re-run the same 5 subtasks — pending the SFT eval box. Same detailed recording.

## Other external benches (improvement track) — BLOCKED on data
- **ScienceAgentBench:** gold/eval data gated behind a password OneDrive zip; `sciagentbench_repo`
  config path empty. Needs manual download + unzip under the repo.
- **BioAgentBench:** dataset source (arXiv:2601.21800 repo) unconfirmed; `bioagentbench_dir` empty.
- Once their data is local, run BioMate + local LLM on them and record the same way.
