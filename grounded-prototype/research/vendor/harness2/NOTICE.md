# Vendored: Harness² (harness2)

This directory is a **verbatim vendored subset** of Google Research's Harness²:

- Source: https://github.com/google-research/harness2
- Paper: *Harness²: Recursive Agent Harnessing for an Open World*, arXiv:2610.14224
- Copyright 2026 Google LLC
- License: Apache-2.0 (see `LICENSE`)

**What is vendored (and why):** the benchmark/substrate-independent *method* only —
`core/` (recursion, schedule, proposer, selection, spec, tree, library, judge,
ledger, context, prompts, report, runmark), `config.py`, `substrate/`
(base + the two reference substrates), and `demo.py` (the reference adapter).
The core has **no external dependencies** (pure stdlib, Python ≥3.12). The
`benchmarks/`, `cli/`, `install.py`, and `preflight.py` modules were NOT vendored
— they pull external benchmark repos / run the sandbox-disabled Codex substrate,
which BioMate replaces with its own executor (the deep-research controller) and
its own answer-free judge (the Grounded trust lattice).

**No modifications** were made to the vendored files. BioMate's integration lives
*outside* this directory (`research/h2_biomate.py`), implementing the
`BenchmarkAdapter` seam that `spec.py` documents. Re-vendor by re-copying from the
upstream repo.
