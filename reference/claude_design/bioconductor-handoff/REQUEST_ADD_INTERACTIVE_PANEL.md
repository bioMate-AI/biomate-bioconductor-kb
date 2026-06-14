# Request — add the Interactive Launcher panel to the Bioconductor design

**Date:** 2026-06-10
**From:** BioMate engineering
**To:** Claude design team (this directory)
**Why:** alignment between the Claude prototype and BioMate production, so the same Bioconductor tutorial can be recorded end-to-end with **no missing panels**.

---

## Context

The current handoff (`HANDOFF_BIOCONDUCTOR.md`) covers the chat view, the workflow panel, and the After-run report in detail. Production BioMate already ships a feature that the design does not yet model: the **Interactive Launcher** — a dialog that spawns RStudio / Jupyter / CellxGene against the run's outputs, so a scientist can poke at a `.rds` / `.csv` / `.h5ad` file in a real R or Python kernel without leaving BioMate.

For all three Bioconductor tutorials this matters because every output is something you'd expect a bench scientist to *open in RStudio* next:

| Tutorial | Output worth opening interactively |
|---|---|
| `bioc_kb` — DESeq2 | `deseq_results.rds`, `dds.rds` → RStudio with DESeq2 loaded |
| `bioc_sc` — scRNA-seq (OSCA) | `sce_annotated.rds`, `pseudobulk_counts.rds` → RStudio with scran/scater **or** CellxGene for UMAP browsing |
| `bioc_methyl` — 450k methylation (minfi) | `grset.rds`, `dmrs.rds` → RStudio with minfi/bumphunter |

Today these end with a **download** button. The natural follow-up is **"explore in RStudio"** — which we already have in production but the design doesn't surface, so it's invisible in the tutorial.

## What exists in production today

`frontend/client/src/components/interactive-launcher.tsx` (BioMate v1, 380 lines):

- Modal dialog opened from a **two entry points**:
  - per-output **`Open in RStudio`** button on any `.rds` / `.rdata` file row in `step-output-preview.tsx`
  - top-level **`Jupyter`** quick-action button in the workflow-artifact summary
- Dialog body:
  - **Three radio-style tiles**: Jupyter (Python 3.10), RStudio (R 4.3), CellxGene (scRNA viewer).
    Each tile shows: name, one-line description, "best for" line, 4 preloaded-packages chips, "+N more" badge.
  - **Output picker**: checkbox list of the run's outputs, with size and select-all.
  - **Timeout alert** (info banner): "Interactive sessions timeout after 2 hours of inactivity. Your work is saved to the Galaxy history."
  - **Launch button** ("Launch RStudio" / etc) — disabled while launching, shows a spinner.
- Active-session view (after launch returns):
  - Green alert "<Tool> Session Active" + the session state.
  - **Open in new tab** primary button (`entry_point_url`).
  - **Quick-start code snippet** with copy button (R or Python depending on tool selected; pre-populated `read_tsv()` / `pd.read_csv()` lines for each selected output).
  - **"Pre-loaded data" list** mapping each selected output to `/data/<name>`.

Backend wiring:
- `POST /api/interactive/launch` → Node proxy → Galaxy `POST /api/tools` with `tool_id` ∈ `{interactive_tool_jupyter_notebook, interactive_tool_rstudio, interactive_tool_cellxgene}`.
- Returns `{job_id, entry_point_url, state}` — `entry_point_url` is what the **Open in new tab** button opens.

## What the design should add

Two surfaces, in the existing right-panel after-run flow:

### 1. Per-output **"Open in RStudio"** (or **"Open in CellxGene"** for `.h5ad`) button

Inline on each After-run Outputs row, next to **view** / **dl**:

```
phase  step                 file                       type      [view] [dl] [⌘ open in RStudio]
A      filter_genes         dds.rds                    rds       view   dl   ⌘ Open in RStudio
B      pseudobulk           pseudobulk_counts.rds      rds       view   dl   ⌘ Open in RStudio
F      visualize            volcano.png                png       view   dl
```

Routing rule: show **Open in RStudio** for `.rds` / `.rdata`; **Open in CellxGene** for `.h5ad`; **Open in Jupyter** for `.csv` / `.tsv` / `.h5` only when there's no R-native equivalent (default to RStudio when both apply, since these tutorials are Bioconductor-flavored).

### 2. **Interactive Launcher dialog** (modal)

The dialog from the production component, but in design fidelity:

```
┌─ Launch Interactive Environment ─────────────────── ✕ ┐
│  Explore your workflow outputs in an interactive       │
│  computing environment                                 │
│                                                        │
│  ┌─ Choose Environment ──────────────────────────────┐ │
│  │ ◉ RStudio                                         │ │
│  │   R 4.3 statistical computing environment         │ │
│  │   Best for: Statistical analysis, Bioconductor    │ │
│  │   [DESeq2] [edgeR] [ggplot2] [tidyverse] [+1]    │ │
│  │                                                   │ │
│  │ ◯ Jupyter Notebook                                │ │
│  │   Python 3.10 interactive environment             │ │
│  │   Best for: Custom analysis, visualization, ML    │ │
│  │   [pandas] [numpy] [matplotlib] [seaborn] [+2]   │ │
│  │                                                   │ │
│  │ ◯ CellxGene                                       │ │
│  │   Interactive single-cell visualization           │ │
│  │   Best for: Single-cell RNA-seq exploration       │ │
│  │   [Scanpy] [UMAP/t-SNE] [Gene expression] [+0]   │ │
│  └───────────────────────────────────────────────────┘ │
│                                                        │
│  ┌─ Data to Load ────────── Select All ──────────────┐ │
│  │ ☑ dds.rds                              45 MB      │ │
│  │ ☐ deseq_results.rds                    12 MB      │ │
│  │ ☐ pseudobulk_counts.rds                 8 MB      │ │
│  │ 1 file selected                                   │ │
│  └───────────────────────────────────────────────────┘ │
│                                                        │
│  ⓘ Interactive sessions timeout after 2 hours of      │
│    inactivity. Your work is saved to the Galaxy       │
│    history.                                            │
│                                                        │
│           [ Cancel ]  [ 🖥  Launch RStudio ]           │
└────────────────────────────────────────────────────────┘
```

After launch (success state):

```
┌─ Launch Interactive Environment ─────────────────── ✕ ┐
│  ✓ RStudio Session Active                              │
│    Your interactive environment is ready.              │
│    State: running                                      │
│                                                        │
│  ┌───────────────────────────────────────────────────┐ │
│  │  [ ↗ Open RStudio in New Tab ]                    │ │
│  └───────────────────────────────────────────────────┘ │
│                                                        │
│  Quick Start Code                          [📋 Copy]   │
│  ┌───────────────────────────────────────────────────┐ │
│  │ library(tidyverse)                                │ │
│  │ # Your data is in /data/                          │ │
│  │ dds <- readRDS('/data/dds.rds')                   │ │
│  └───────────────────────────────────────────────────┘ │
│                                                        │
│  Pre-loaded data:                                      │
│   • /data/dds.rds                                      │
│                                                        │
│                                  [ Close ]             │
└────────────────────────────────────────────────────────┘
```

### Data contract

The design's tape can post a single `showCard {card:'interactive_launcher', data:{outputs:[…]}}` event after a tutorial reaches a "now let's explore in R" beat. For Bioconductor tutorials the natural beat is **right after the After-run Outputs tab** — i.e. after step 6 of `afterRunSteps(...)` in `BiocTours.jsx`. One added tutorial step:

> *"Click **Open in RStudio** on `dds.rds` — BioMate spins up an RStudio session with your DESeqDataSet pre-loaded. The session expires after 2h of inactivity."*

The backend side is already wired in production. The design only needs the UI surfaces; the request flow can be mocked exactly the way the rest of the prototype mocks SSE.

### Why this matters for tutorial recording

Today our recording of the v2 surfaces has a hole right at the moment a user would naturally say "ok, what now?" The whole point of the Bioconductor walkthrough is to leave the user with a `DESeqDataSet` they can poke at. **Open in RStudio** is the answer. Without the design including it, we either:

1. Skip the moment (tutorial ends limply at "download the .rds").
2. Cut to the BioMate-v1 production UI mid-recording (jarring, breaks design fidelity).

With the design including it, we record one continuous tutorial that ends with **"and here's your interactive session"** — which is the actual product story.

## Suggested implementation order for the design team

1. **Two viz buttons** (lowest cost): add **Open in RStudio** / **Open in CellxGene** affordance on the After-run Outputs rows for `.rds` / `.h5ad`. No dialog yet — clicking just toasts "launching…".
2. **Launcher dialog** (the modal above), opened on click.
3. **Active-session state** (post-launch).
4. **One new `BiocTours.jsx` step per tutorial** pointing at the new affordance.

## What we'll do on the BioMate side once the design has it

Replace the current generic `InteractiveLauncher` (`frontend/client/src/components/interactive-launcher.tsx`) with the design-aligned port, plus:

- Per-output **Open in RStudio** button on each `step-output-preview.tsx` row (we already have an entry point on `.rds` files; CellxGene wiring on `.h5ad` is missing — add it).
- Backend: confirm `interactive_tool_*` is registered on dev Galaxy (phase 1 enablement is in flight today — see `docs/20260610_*` session notes).
- DNS / reverse-proxy work for the wildcard `*.interactive.<host>` subdomain so `entry_point_url` resolves in a real browser. Currently the launch button POSTs successfully but the URL won't open until this is set up.

---

**Action requested:** add the Interactive Launcher to the next iteration of `HANDOFF_BIOCONDUCTOR.md` + the prototype HTML, so we can record a Bioconductor tutorial end-to-end with no missing panels.
