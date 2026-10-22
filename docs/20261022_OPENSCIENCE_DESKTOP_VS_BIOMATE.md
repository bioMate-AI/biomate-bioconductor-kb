# Open Science Desktop (`ai4s-research/open-science`) vs BioMate — comparison

**Date:** 2026-10-22 · **Source:** shallow clone of `github.com/ai4s-research/open-science`
(README.md + PROGRESS.md, current as of 2026-10-22; MIT; DOI 10.5281/zenodo.21351225). Updates the
stale team review in `docs/20260711_OSS_ARCHITECTURE_OPEN_SCIENCE_AUTORESEARCH_OPENWORK.md` (that
was "Open Science"; it is now "Open Science Desktop").

## What it is now

A **local-first, model-agnostic AI research workbench** for macOS/Windows/Linux (Tauri 2 + React,
OpenCode runtime), self-described as "an open-source desktop alternative to **Claude Science**." It
connects agents, notebooks, files, figures, reports, runs and review into one auditable desktop
session. Actively developed (multiple commits/day in PROGRESS.md).

Current capabilities (from README "News" + features, grounded):
- **#1 on ResearchClawBench** (2026-07-09) — a Pass@1 end-to-end benchmark for autonomous scientific
  research agents (internscience.github.io/ResearchClawBench-Home). This is the one *scorable*
  overlap with BioMate.
- **Computer Use** (v0.6.0, 2026-10-04) — the agent operates desktop apps (ImageJ, Origin,
  instrument software), terminals, and a code editor; Claude Code / Codex resume after relaunch.
- **Agent Client Protocol, both directions** (v0.4.0) — drive Codex / Gemini CLI / Claude Code from
  inside it, or drive it from Zed / JetBrains / Neovim.
- **`osd server`** (headless) — runs the whole workbench with no display; `osd session send --wait`
  drives it from a script or another agent.
- **Provenance** — figures/tables/reports/notebooks/run outputs trace back to the run that made them.
- **Reproducible runs** — local, SSH/Slurm, Modal, notebook-batch backends.
- **Browser control** of the user's own Chrome; MCP connectors (arXiv/PubMed/Materials Project);
  `ai4s-agent` chains specialist skills; projects/memory/history; 7 UI languages.

## Category difference (the key framing)

They are **not the same kind of system**, so a single task-score is the wrong lens:

| Axis | Open Science Desktop | BioMate |
|---|---|---|
| Form factor | local-first **desktop workbench** | cloud **execution engine** (+ web / desktop / MCP connector) |
| Scientific scope | **general** science (materials, physics, bio) — broad, shallow per-domain | **bioinformatics + drug discovery** — deep (4,210 workflows, 42 domains) |
| Execution | local notebooks/terminals + **computer-use of desktop apps** + SSH/Slurm/Modal | **AWS Batch / Nextflow** pipelines at cloud scale + `run_code` sandbox |
| Domain logic | none domain-specific | QC auto-loop (verifiable rewards), param rules, novelty/FTO gate, ADMET/PBPK/BOIN/IND |
| Model | model-agnostic (OpenCode sidecar) | multi-provider **+ its own on-prem LLM** (trained on BioMate gold) |
| Interop | **ACP both directions**, MCP | MCP connector (19 tools), ChatGPT/Claude connectors |
| Provenance/audit | append-only JSONL + SQLite | run-state store (Redis), audit trail, billing ledger |
| Benchmarks | #1 ResearchClawBench | Biomni (RealBio row), **BixBench-exec 87.5% ≈ Biomni Lab 88.7%**, DrugDev, execution-grading |
| License | MIT, open-source | proprietary product |

## Where each leads

**Open Science Desktop is ahead on (BioMate could adopt):**
- **Computer Use of instrument/desktop apps** (ImageJ, Origin, vendor instrument software) — BioMate
  has Interactive Tools (Jupyter/RStudio/CellxGene) but not generic desktop-app control.
- **ACP interop** — being drivable by, and able to drive, other agents (Codex/Claude Code/Zed). A
  clean interop surface BioMate lacks (it exposes MCP but not ACP).
- **Local-first provenance + reproducible-run backends** (SSH/Slurm/Modal/notebook-batch) — a
  researcher-owned audit trail; BioMate's provenance lives server-side (run-state/billing).

**BioMate is ahead on (open-science lacks):**
- **Domain depth at cloud scale** — 4,210 validated workflows, AWS Batch, nf-core pipelines, QC
  gates, drug-dev/clinical modules. Open-science has no bio-specific pipeline catalog.
- **Verifiable-reward QC auto-loop** and the benchmark/execution-grading apparatus (this session:
  BixBench-exec 87.5%, run_code fix) — an evaluation loop open-science does not have.
- **Its own LLM** trained on BioMate gold (routing/decomposition/param), not just a model-agnostic
  shell.

## Actionable comparisons

1. **Scorable (if wanted):** evaluate BioMate on **ResearchClawBench** (where open-science is #1).
   Caveat: it is a *general* autonomous-research benchmark, so BioMate's bio/drug-dev depth is not
   the differentiator there — expect open-science/general agents to do well on general-science tasks;
   BioMate's edge shows on the bio-execution benchmarks (BixBench-exec, Biomni Eval1, RealBio).
2. **Capability (no score):** the three adopt-candidates above (computer-use of instrument apps, ACP
   interop, local-first provenance) are the concrete things to lift from open-science.
3. **Distinct from the task-benchmark comparators** (Biomni / BixBench / LAB-Bench-FutureHouse): those
   are *scored same-items*; open-science is a *product/architecture* comparator + one benchmark
   (ResearchClawBench).

## Clone

`/Users/kky/external_benchmarks/open-science` (shallow, read-only — outside any git worktree).
