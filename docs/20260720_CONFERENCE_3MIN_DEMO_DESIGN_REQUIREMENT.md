# BioMate 3-Minute Conference Demo — Design Requirement
**Conference:** Boston BD Summit, July 21–23, 2026  
**For:** Claude Design team  
**Format:** Tutorial-style video with narration (same format as prior Tier 0 demos)  
**Reference prior work:** `docs/20260513_tier0_demo_narratives_v2.md` — use same 6-beat time budget and overlay style  
**Screenshots from live system:** `reference/claude_design/biomate/screenshots_conference/`

---

## What this demo must convey

This is a **platform demo**, not a use-case demo. Unlike prior Tier 0 demos that showed a single pipeline, this 3-minute video must convince a pharma BD contact that BioMate is a comprehensive research infrastructure — not just another AI chat that runs scripts.

The three things every viewer must leave believing:

1. **BioMate connects everything.** Your AI assistants, your lab instruments, and a large curated set of scientific databases — all unified in one platform.
2. **BioMate runs the hard stuff.** Cross-specialty, multi-day, multi-layer research tasks that no single expert can execute alone — launched from a single sentence.
3. **Your team works together.** Projects, shared runs, collaborative findings, role-based access — not a solo tool.

---

## Part 1: Platform Overview

### What BioMate is

BioMate is an AI-powered bioinformatics platform that:
- Routes natural-language research goals to 2,455 indexed scientific workflows
- Executes pipelines on AWS Batch (GPU + CPU) with real-time progress streaming
- Connects to live biological databases, AI assistants, and lab instruments
- Organizes work in team projects with shared run history and downloadable reports

**One-sentence positioning:**  
*"BioMate is where you describe the science and the platform takes care of the rest — from database queries to pipeline execution to findings."*

### Main interface (screenshot `02_chat_empty.png`)

The BioMate interface is a split-pane design:
- **Left sidebar** — workspace navigation: New Chat, Workflows (2,455 indexed), Connectors, IND Report, Projects
- **Center chat** — natural-language interface; the user types a research goal
- **Right panel** — workflow panel: pre-run params, live phase cards, outputs, findings
- **Top bar** — Run Manager (live run count badge)

**Screenshot reference:** `02_chat_empty.png` — shows full sidebar with Workspace section and Projects. Shows CURRENT chat history. Shows "Ask BioMate anything" input at bottom.

**Screenshot reference:** `10_workflows_dialog.png` — Workflows modal showing Run History tab with 140 real runs (1–50 of 140 shown). Run entries show workflow name, status dot (green=completed, blue=running, red=failed), date, and "Open / New analysis" actions. Tabs: Run History · My Imports · Import Workflow. This is the team's shared run library.

**Design note for this frame:** Annotate the sidebar with callout bubbles labeling: "Workflows (39 starred)", "Connectors", "Projects", "Run Manager (3 active)". The goal is to signal platform depth, not just chat.

---

## Part 2: Databases

### What BioMate queries (no upload needed)

BioMate connects to the following live biological databases. In the demo video, show these as a connector map overlay (see Part 5 Beat 3.5).

#### Genetics & Genomics
| Database | Contents | Used for |
|---|---|---|
| GWAS Catalog | 500k+ genome-wide significant associations | Target genetics, disease loci |
| OpenTargets Genetics | GWAS + eQTL colocalization scores | Target prioritization |
| GTEx v10 | eQTL data, 54 tissues, 15,000+ samples | Tissue-specific gene expression |
| eQTLGen | cis-eQTL in 31,684 blood samples | Blood/immune eQTL |
| Ensembl | Genome annotation, variant consequence | Gene annotation |
| gnomAD | Population allele frequencies | Variant interpretation |

#### Single-cell & Transcriptomics
| Database | Contents | Used for |
|---|---|---|
| CellxGene Census | 750,000+ human single-cell profiles | Cell-type expression |
| GEO / SRA | Published RNA-seq, ChIP-seq, ATAC-seq | Existing datasets |
| EBI ArrayExpress | European microarray/RNA-seq datasets | Multi-cohort studies |

#### Chemistry & Drug Discovery
| Database | Contents | Used for |
|---|---|---|
| PubChem | 115M+ compounds | SMILES lookup, ADMET input |
| ChEMBL | 2.4M bioactivities | Selectivity profiling |
| PDB | 200k+ 3D protein structures | Docking, structure-based design |
| UniProt | 250M+ protein sequences | Target annotation |
| DrugBank | 15,000+ drugs | Drug repurposing |

#### Clinical & Literature
| Database | Contents | Used for |
|---|---|---|
| ClinicalTrials.gov | 500k+ trials | Clinical precedent |
| PubMed + EuropePMC | 36M+ abstracts | Literature search |
| Semantic Scholar | AI-indexed citations | Citation network |
| OMIM | Mendelian disease genetics | Rare disease targets |

**Total: 18+ live databases** queryable from a single BioMate chat message.

**Screenshot reference:** `11_connectors_dialog.png` — the Connectors database browser inside BioMate. Tabs: All · AI · Protein & Structure · Genomics & Variants · Cells · Delta · Chemical & Drug · Pathway. Grid shows named connectors (UniProt/Swiss-Prot, PDB/RCSB, AlphaFold, IntePro, STRING, Ensembl, NCBI Gene, gnomAD, GTEx, ClinVar, GWAS Catalog, COSMIC, and more). This is the design reference for what the connector catalog looks like — use this screenshot as the basis for the connector map overlay in Beat 3.5.

---

## Part 3: Connectors

BioMate connects in two directions: **into your AI assistant** (so you can trigger BioMate from Claude, ChatGPT, Cursor, etc.) and **from your instruments** (so raw data flows automatically into BioMate when a run finishes).

### AI platform connectors (21 MCP tools)

The BioMate Connector (`npx @biomate/connect`) installs a 21-tool MCP server in your AI assistant of choice:

| Surface | How to connect |
|---|---|
| Claude Code / Claude Desktop | `npx @biomate/connect claude-code` |
| Cursor IDE | `npx @biomate/connect cursor` |
| Codex CLI | `npx @biomate/connect codex` |
| ChatGPT | Plugin install (see INSTALL.md) |
| Slack | Bot install (1 click for workspace) |
| WeChat / Open Claw | `npx @biomate/connect open-claw` |

**Key MCP tools exposed:**

| Tool | Purpose |
|---|---|
| `biomate_session` | Primary: runs a full BioMate session from a plain-English goal |
| `search_workflow` | Browse 2,455 indexed workflows |
| `run_workflow` | Execute a specific workflow with explicit params |
| `watch_run` | Stream live progress and return results |
| `query_database` | Query any of the 18+ live databases directly |
| `fetch_public_data` | Download GEO/SRA/ENA/UCSC files into BioMate workspace |
| `resolve_accession` | Identify GEO/SRA accession and route to right pipeline |
| `analyze_results` | AI interpretation of a completed run |
| `export_report` | PDF/markdown report from a run |
| `search_literature` | PubMed + EuropePMC + Semantic Scholar |
| `recall_memory` | Prior runs on similar inputs (cross-session) |
| `upload_file` | Sign-upload file to BioMate S3 workspace |
| `list_instruments` | Discover connected lab instruments on the network |
| `run_instrument_protocol` | Execute Opentrons liquid-handling protocol |

### Lab instrument connectors (10 instruments)

BioMate watches physical instruments for new data. When a run finishes, the file goes directly to the correct pipeline — no manual upload.

| Instrument | Trigger | Pipeline routed to |
|---|---|---|
| Illumina BaseSpace | New sequencing run completes | nf-core/rnaseq, sarek, ampliseq |
| Oxford Nanopore MinKNOW | Run complete signal | nf-core/nanoseq |
| CryoEM EPU | New `.mrc` micrographs appear | cryosparc_standard_spa |
| LC-MS (Thermo/Bruker/Waters/SCIEX) | New `.raw`/`.d`/`.wiff` files | ProteomicsDB pipeline |
| Flow Cytometer (BD/Beckman/Sony) | New `.fcs` files | FlowJo/FACS pipeline |
| qPCR (QuantStudio/Bio-Rad CFX) | New `.eds`/`.pcrd` | qPCR quantification |
| Plate Reader (BioTek/Mol. Devices) | New `.xlsx` exports | ADMET/assay pipeline |
| Opentrons OT-2/Flex | Protocol complete | Downstream liquid-handling analysis |
| Benchling ELN | New assay result or entry | Data integration pipeline |
| SiLA2 devices | gRPC event (Hamilton, Sartorius) | Configurable routing |

**Screenshot reference (`02_chat_empty.png`):** The "Connectors" sidebar item ("Databases, LLMs & platform integrations") is the entry point for the Connectors configuration page. Claude Design should show this panel being opened as a beat between parts 2 and 3 of the demo.

---

## Part 4: Team Workspace

### Run history (shared across team)

The Workflows dialog (`10_workflows_dialog.png`) is the team's shared run library. It shows every run ever executed — 140 in the screenshot — with workflow name, status, timestamp, and one-click "Open" and "New analysis" actions. A researcher can jump from any prior run directly back to the workflow panel, re-run with modified params, or trigger a downstream analysis. This is not a personal history — it is the team's collective research record.

The "Import Workflow" tab allows the team to bring in custom Nextflow workflows not yet in the catalog — extending BioMate's coverage to proprietary pipelines.

### Projects

Every BioMate run belongs to a **Project**. Projects organize:
- All runs for a specific program or target
- Shared findings across team members
- Downloaded reports (PDF/DOCX/markdown)
- Run history with status indicators (blue=running, green=completed, red=failed)

**Screenshot reference (`02_chat_empty.png`):** Left sidebar shows PROJECTS section with named project folders. The CURRENT section below shows recent chats with status dots. This is the team workspace in its resting state.

**What the design should highlight in this beat:**
- Multiple project folders visible in sidebar (realistic project names in final demo, not `e2e_test`)
- Status dots showing completed runs (green)
- "New project" button at bottom of project list
- "Run Manager" badge in top-right showing active run count

### CRO Compliance workspace

`/drug-discovery-cro` — a dedicated workspace for CRO compliance campaigns, separate from the chat interface.

**Screenshot reference (`04_cro_library.png`):** Shows the CRO Compliance Campaigns page with "21 CFR Part 11" and "ICH M4" compliance badges, "+ New Campaign" button. This is the drug discovery compliance module.

### IND Report

The IND Report feature (sidebar: "Generate regulatory submission documents") composes ICH M2/M4-structured narratives from BioMate run outputs. Relevant for pharma BD contacts considering regulatory use cases.

---

## Part 5: 3-Minute Use-Case Tutorial (The Demo Anchor)

After showing the platform overview (Parts 1–4, ~90 seconds of the video), the second half of the video is a **live tutorial** showing all of the above working in a single run.

### Demo identity

**Title:** "CD40L Indication Expansion — Genetics to Cell Types in One Run"  
**Use case:** A BD director asks BioMate to map the genetic evidence for CD40L across three neuroimmune diseases before committing to a new indication.  
**Workflow:** `gwas_scrna_eqtl_target_chain`  
**Why this demo:** Uses 5 databases, 3 scientific disciplines, runs 14 minutes on AWS Batch — the most complex cross-specialty task BioMate can demonstrate.

---

### Beat plan (3:00 strict)

| # | Beat | Timing | On-screen | Narration tip |
|---|---|---|---|---|
| 1 | **Hook** | 0:00–0:12 | BioMate logo / empty chat | "Three diseases, one target, one sentence. This is the indication expansion brief a BD director would normally need a full genetics team to produce." |
| 2 | **Type query** | 0:12–0:50 | User types query (see below); AI streams response text; wf-chip appears below response | *(no tip — let AI stream)* |
| 3 | **Panel review** | 0:50–1:15 | Right panel shows `gwas_scrna_eqtl_target_chain`; 3 phase cards (GWAS Layer / eQTL Layer / scRNA Layer); params: `target_gene=CD40LG`, `diseases=…` | "Three phases, five databases, zero files uploaded. BioMate pulls GWAS Catalog, eQTLGen, and CellxGene programmatically." |
| 3.5 | **Connector overlay** | 1:15–1:23 | Full-screen overlay: database map (see below) | "The same databases a genetics team queries across weeks — now one workflow." |
| 4 | **Click Run** | 1:23–1:30 | Click "Confirm & Run"; footer → "Running…"; overall badge `data-status="running"` | "Submitting to AWS Batch. Watch each layer update live." |
| 5a | **Phase 1 running** | 1:30–1:52 | GWAS Layer: `pending`→`running` spinner; SSE pills in chat | "Phase 1: scanning 500 kb around CD40LG in GWAS Catalog across all three diseases." |
| 5b | **Phase 1→2** | 1:52–2:18 | GWAS Layer ✓ completed; eQTL Layer flips to running | "Three MG loci found. Phase 2: colocalization — does each locus have an eQTL for CD40LG in immune cells? Checking GTEx and 31,000 blood samples." |
| 5c | **Phase 2→3** | 2:18–2:44 | eQTL Layer ✓; scRNA Layer running; first output tile (`candidate_genes.csv`) appears | "Colocalization confirmed in PBMC. Phase 3: which immune cell types express CD40LG? 750,000 human single-cell profiles." |
| 6 | **Completion + findings** | 2:44–3:00 | COMPLETED badge; Findings tab; download button | "MG has the strongest signal. CD40LG highest in activated T and B cells. That's the indication brief — no team required." |

---

### Exact query to type (Beat 2)

```
Analyze CD40L genetic evidence and cell-type expression across myasthenia gravis, 
CIDP, and GBS using the GWAS and eQTL target chain. Target gene is CD40LG. 
Show me which disease has the strongest genetic support and which immune cell types 
drive the signal.
```

---

### Connector map overlay design (Beat 3.5)

8-second full-screen dark overlay. BioMate logo center. Design based on the actual Connectors browser (`11_connectors_dialog.png`) which groups databases into category tabs: **Protein & Structure · Genomics & Variants · Cells · Chemical & Drug · Pathway · AI**.

For this beat, show a simplified version — the 5 databases used in this specific run, plus the category they belong to:

```
  Genomics & Variants          Cells
  ┌──────────────────┐    ┌──────────────────┐
  │  GWAS Catalog    │    │  CellxGene       │
  │  OpenTargets     │    │  Census          │
  │  GTEx v10        ├────┤  750k cells      │
  │  eQTLGen         │    └──────────────────┘
  │  31,684 samples  │
  └──────────┬───────┘
             │
             ▼
          BioMate
          AWS Batch
             │
             ▼
          Findings
```

Caption overlay text: **"5 databases · 31,684 eQTL samples · 750,000 single cells · 1 sentence"**

After Beat 6, cut to the full connector browser screenshot (`11_connectors_dialog.png`) for 3 seconds with caption: **"18+ scientific databases. One platform."** This closes the loop from the database section back to the use case.

**Design note:** The actual Connectors dialog in the app shows a searchable grid of database tiles with category filter tabs (All / AI / Protein & Structure / Genomics & Variants / Cells / Delta / Chemical & Drug / Pathway). The overlay should reference this real UI — it is much more compelling than a diagram because it is an actual screenshot of working software. Consider using the real screenshot as a background in the overlay rather than an illustrated diagram.

---

### Required on-screen states

| State | Chat panel (left) | Workflow panel (right) |
|---|---|---|
| Pre-run | AI text summarizing 3-layer chain; wf-chip below text | Workflow name, domain badge, 3 phase cards pending, params prefilled |
| Running | SSE progress pills streaming (`WF` speaker) | Footer "Running…", phase cards flipping one-by-one |
| Complete | wf-chip → "In panel" badge | COMPLETED badge, Outputs tab, Findings text, Download button |

**Screenshot reference (`08_ai_response_complete.png`):** Shows the AI response to the CD40L query, including the BioMate reasoning text and routing output. The design team should use this to see what the AI message actually produces.

**Screenshot reference (`06_query_typed.png`):** Shows the exact state at the end of Beat 2 — query in the input box, sidebar visible with all workspace items.

---

## Part 6: Production Notes

### Recording spec
- **Resolution:** 1440×900 (native retina = 2880×1800 actual). Do not crop sidebar.
- **Split:** 30% sidebar / 40% chat / 30% workflow panel (or 50/50 chat+panel after Beat 2)
- **Audio:** Same narrator, same pace as `int_rare_disease_tutorial_branded.mp4` — one tip per beat, 2–3 sentences max
- **Text overlay:** Bottom-third white pill on dark semi-transparent bar, Euclid Circular font
- **End card:** 5-second static frame: COMPLETED state with Findings visible + BioMate logo + `biomate.ai`

### Run the job before recording
`gwas_scrna_eqtl_target_chain` takes ~14 minutes on AWS Batch. Run it first on `dev-public.biomate.ai` with the exact query above. Verify all 3 phase cards complete and Findings tab shows ranked output. Then record the second run live — do not fake phase card transitions.

### Project setup for recording
Create a project named `"CD40L Indication Study"` (not `e2e_test`). The sidebar must show realistic project names. Before recording, populate at least 3 prior runs in the project so the CURRENT section shows a real history with green completion dots.

### Fonts and colors to match in overlays
From `02_chat_empty.png`:
- Sidebar background: white (#FFFFFF) with light gray section labels
- BioMate blue (primary): `#1A6FD4` (logo color)
- Run Manager badge: filled blue circle, white count
- Project folder icons: muted blue-gray
- Status dots: `#22C55E` (green/completed), `#3B82F6` (blue/running), `#EF4444` (red/failed)

---

## Summary: What the video covers in 3:00

| 0:00–0:12 | Hook — platform positioning |
|---|---|
| 0:12–0:50 | Live query + AI routing |
| 0:50–1:15 | Workflow panel — databases + params |
| 1:15–1:23 | Connector map overlay (all 18+ databases) |
| 1:23–2:44 | Live Batch execution — 3 phase cards updating |
| 2:44–3:00 | Findings + download — the deliverable |

**Message sequence a BD viewer takes away:**  
BioMate knows the databases → BioMate plans the research → BioMate runs the science → BioMate delivers the findings. One tool. Their team gets this on day one.
