---
marp: true
theme: default
paginate: true
title: BioMate-Pharma — Guangdong Product Strategy
---

<!-- Mixed exec + technical audience. Layered: landscape -> positioning -> architecture -> requirement fit -> roadmap.
     Render: `marp <this>.md -o deck.pptx` (or --pdf). Competitive facts sourced 2026-09; see COMPETITIVE_INTEL notes. -->

# BioMate‑Pharma
### An execution + verification substrate for AI drug discovery
**Guangdong pharma product strategy — Sept 2026**

*Three questions this deck answers:* Where does the field sit? Where does BioMate win? What do we build for pharma?

---

## Executive summary

- **The AI‑drug field is separating into 3 layers:** ① foundation models (generators), ② agentic orchestration (the "brain"), ③ **execution** (actually running & verifying the science).
- **Everyone is racing layers ① and ②. Almost no one owns ③.** ANew Labs (ByteDance) sells *models*; Stanford's *Virtual Biotech* *reasons* over public data — **neither runs real experiments or compute.**
- **BioMate owns layer ③** — 4,017 real workflows on cloud compute, producing verified artifacts, already MCP‑native — and can **compose** the other two layers on top.
- **BioMate‑Pharma = a curated subset of BioMate + integrated open models + an agentic orchestrator + GxP compliance.** A *vertical*, not a fork.
- **The moat is not the generator — it is verified execution + an honest generate→verify→learn loop.** We prove it below on a live cyclic‑peptide program.

---

## Why now: AI drug discovery is layering

- 2023–24: foundation models matured (AlphaFold3, RFdiffusion, generative chemistry).
- 2025–26: **agentic orchestration** arrived — LLM "scientist" teams that plan and critique.
- The missing middle for buyers: **turning model outputs and agent plans into real, reproducible, verified results** — docking, MD, ADMET, PK/PD, trials analysis — on demand, with an audit trail.
- **That middle is an execution engine. That is BioMate.**

---

## The landscape — three layers, one stack

```
        ┌───────────────────────────────────────────────┐
  ②     │  AGENTIC ORCHESTRATION  ("the brain")          │  Virtual Biotech (Stanford/Zou, Science 2026)
        │  plan · decompose · critique · synthesize       │  — reasons over public data, NO execution
        └───────────────────────────────────────────────┘
        ┌───────────────────────────────────────────────┐
  ①     │  FOUNDATION MODELS  (generators/predictors)     │  ANew Labs / ByteDance · Molo‑1 · BoltzGen
        │  structure · binder/peptide design · properties │  — great models, closed pipelines / no platform
        └───────────────────────────────────────────────┘
        ┌───────────────────────────────────────────────┐
  ③     │  EXECUTION  ("the hands")  ◀── BioMate          │  4,017 workflows · AWS Batch · verified artifacts
        │  run · QC · verify · report · comply            │  — the layer the others lack
        └───────────────────────────────────────────────┘
```

**Insight:** ① and ② are crowded and largely *open/commoditizing*. ③ is where verified value — and defensibility — lives.

---

## Layer ① — ANew Labs (ByteDance)  *[competitor / integration source]*

- **Who:** ByteDance's AI‑drug unit, **spun out June 2026**, **$290M @ ~$1.5B** (ByteDance keeps 56%). Shanghai + SF + Singapore.
- **Open, VERIFIED (ByteDance Seed):** **Protenix** (AF3‑level, Apache‑2.0), **PXDesign** (de‑novo binders, 20–73% nM hit rate), **DPLM/DPLM‑2** — weights + code. Anew‑branded: AnewOmni (generative), AnewFold, AnewSampling (MD), AnewMind (reasoning LLM).
- **Pipeline:** oral pan‑spectrum IL‑17 (shown AAI Apr 2026) + IL‑4R (all **preclinical**); thesis = replace injectable antibodies with oral drugs.
- **Read:** formidable on *models*; a **closed** drug company, not a platform vendor. **Their open models (Protenix/PXDesign/DPLM) are ours to integrate.**
- *Caveats: "beats AF3" / "first cross‑scale" are company/preprint‑stage, unvalidated. The earlier "APM" and "AnewDPSA (macrocyclic permeability)" are **UNVERIFIED** — no primary source; do not present as real.*

---

## Layer ① — peptide (多肽) players: a crowded, strong field

- **Vilya‑1** (*likely the "Molo‑1/Atomelogy" referenced*; Vilya — Baker/IPD spinout, US; $71M Series A, ARCH+NVIDIA): all‑atom **macrocycle foundation model** doing **structure + permeability + de‑novo design** in one. Benchmark: **89.2%** near‑native ring RMSD vs **Boltz‑2/RoseTTAFold3 ~15%**, ~2× physics methods. **Preview only — no public code/weights.** July 2026. *(Name match high‑confidence but unverified — confirm.)*
- **ByteDance ANew:** AnewOmni (cross‑scale generative) + open Protenix/PXDesign/DPLM — direct methods competitor whose open models we integrate. *(A dedicated "AnewDPSA" macrocycle‑permeability model is unverified.)*
- **2026 open works we adopt/inspire from:** **PocketXMol** (*Cell* 2026, **MIT** — pocket‑conditioned cyclic design), **MacroGuide** (ring closure 1%→99%), **EnsembleCycPerm** (chameleon 2‑env permeability), APCyc/PepALD (permeability‑conditioned gen). See leverage doc.
- **Others:** BoltzGen (open, what we use), Circle Pharma / Bicycle / Unnatural Products (macrocycle biotechs), Generate:Biomedicines (IPO 2026).
- **Takeaway:** the peptide **generator layer is contested and strong** (Vilya beats Boltz‑2/RF3 on structure). **We do not win by out‑generating them — we win by generate → *verify with physics/ADMET* → learn, on an execution substrate they don't have.** Vilya/ANew are *closed* (preview/pipeline); their edge is a model, not a runnable platform.

---

## Layer ② — The Virtual Biotech (Stanford, Zou lab · *Science*, 17 Sep 2026)

- **What:** an AI "drug‑development company" — **11 standing agents** (CSO orchestrator + 8 specialist scientists across 4 divisions + Chief of Staff + independent **Scientific Reviewer**), scaling to **~37,000 ephemeral per‑trial agents** for a 55,984‑trial meta‑analysis.
- **Powered by Claude** (Sonnet 4.5 + Haiku 4.5) via the Claude Agent SDK, over **~11 public‑data MCP servers** (Open Targets, ClinicalTrials, cBioPortal, OpenFDA, DepMap, gnomAD…).
- **Proof point:** proposed a B7‑H3 ADC for lung cancer on pre‑2025 data; months later Merck's *ifinatamab deruxtecan* (same strategy) won FDA Breakthrough — **external convergence**.
- **Critical limit:** **in‑silico reasoning only** — no wet‑lab, no compute execution. It *decides what to do*; it does not *do it*.
- *(≈370k was a recollection; the real figures are 11 standing + ~37k ephemeral.)*

---

## Layer ③ — BioMate (the layer the others lack)

- **Execution engine:** **4,017 workflows / 36 domains** on AWS Batch → **real data + artifacts**, not recommendations.
- **Already MCP‑native** (same interface paradigm as Virtual Biotech) — `run_workflow`, `search_workflow`, `fetch_public_data`, `analyze_results`, `export_report`…
- **Drug‑discovery domain today:** ADMET (hERG, CYP, oral BA, AMES), docking, MD, PK/PD, PBPK, accelerated stability, BOIN dose‑escalation, FAERS, IND §2.6.1 narrative, CRO compliance packages.
- **Generate→verify loops + auto‑QC + findings + reports.**
- **The one thing neither competitor has: it actually runs and verifies the science.**

---

## The gap = our position

| | ANew (①) | Virtual Biotech (②) | **BioMate (③)** |
|---|---|---|---|
| Delivers | Models | Recommendations | **Verified results + artifacts** |
| Executes real compute? | Partial (as a closed pipeline) | **No** | **Yes** |
| Sold as a platform? | No (closed drug co.) | Re‑impl only | **Yes** |
| Validation | Preclinical claims | External convergence | **Physics/verify loops + QC** |

**Compose, don't compete:** integrate ① as generators, adopt ②'s orchestration pattern — **on BioMate's execution substrate.**

---

## Inspire vs Integrate

**Integrate (literally wireable — Apache‑2.0 / MCP):**
- ANew's **Protenix / PXDesign / DPLM** → add as BioMate generation & structure workflows (menu, not "BoltzGen‑only").
- Virtual Biotech's **public‑data MCP servers** (Open Targets, ClinicalTrials, cBioPortal, OpenFDA, DepMap) → fill BioMate's data‑retrieval gaps.

**Inspire (adopt the design):**
- The **11‑agent org + independent Scientific‑Reviewer QA loop** — run on **BioMate's own MCP execution tools** (agentic brain on a verified substrate).
- Per‑program **reproducible session workspace** (reasoning trace + tool calls + code + figures) → **pharma GxP audit gold**.
- **Massively‑parallel ephemeral task agents** (fan‑out one agent per unit of work).

---

## BioMate‑Pharma = subset + composition (the strategy answer)

**"Is it just a subset of BioMate?"** — *At the resource layer, yes. As a product, it's subset + composition.*

- **Subset:** curate ~5–7 of 36 domains → discovery · DMPK/ADMET · PK‑PD/PBPK · clinical dose‑escalation · CMC/stability · reg/CRO.
- **+ Compose:** integrated open FMs (Protenix/PXDesign‑class generators) · agentic orchestrator (Virtual‑Biotech pattern over BioMate MCP) · **GxP/compliance module** · **verify‑learn loop as a headline feature**.
- **Build as a vertical/tenant profile, NOT a code fork** — shared engine, pharma catalog + UX + compliance + orchestrator. Configuration, not a second codebase.

---

## Architecture — the five planes (shared engine, pharma vertical)

```
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │ ① EXPERIENCE   Pharma UX (program-centric: a "drug program", not a "run")      │
 │                + GxP layer: 21 CFR Pt.11 · e-sign · RBAC · immutable audit     │
 ├──────────────────────────────────────────────────────────────────────────────┤
 │ ② ORCHESTRATION   CSO agent → 4 divisions (target · safety · modality ·        │
 │                clinical) + independent Reviewer-QA loop      ← Virtual-Biotech  │
 │                pure coordinator · per-agent MCP permission scoping             │
 ├──────────────────────────────────────────────────────────────────────────────┤
 │ ③ CAPABILITY (MCP tools)   run_workflow · search_workflow · fetch_public_data  │
 │                · analyze_results · export_report   (one typed tool per action)  │
 ├──────────────────────────────────────────────────────────────────────────────┤
 │ ④ EXECUTION + VERIFY   curated pharma catalog (subset of 4,017 wf)             │
 │                · integrated open FMs: Protenix/PXDesign/DPLM   ← ANew open      │
 │                · GENERATE → **VERIFY** (physics MM-GBSA/FEP · ADMET · QC gate) │
 │                  → LEARN     ← the step ① and ② lack                            │
 ├──────────────────────────────────────────────────────────────────────────────┤
 │ ⑤ DATA + PROVENANCE   public-data MCP (OpenTargets/ClinicalTrials/DepMap…      │
 │                ← Virtual-Biotech) · private assay flywheel · per-program        │
 │                trace.jsonl workspace (reasoning + tools + code + figures)       │
 └──────────────────────────────────────────────────────────────────────────────┘
        runs on: AWS Batch (GPU/CPU spot) · reproducible artifacts · reports
```

**Three properties that make it a *product*, not a demo:** (1) **MCP-native throughout** — the same
interface the orchestrator, the UI, and external agents all speak; (2) **verify is a first-class plane**,
not a post-hoc check; (3) **everything emits provenance** (trace.jsonl) → GxP audit for free.

---

## Architecture — how a drug program flows (generate → verify → learn)

```
  target/indication ─▶ ② orchestrator decomposes ─▶ ③ MCP tool calls
        │                                                   │
        ▼                                                   ▼
  ④ GENERATE            ④ VERIFY (non-negotiable)     ⑤ data pulled + logged
  open FM / BoltzGen  ─▶ physics (MM-GBSA/FEP) +     ─▶ OpenTargets, ClinicalTrials,
  designs candidates     ADMET + QC gate: does the      DepMap … + private assays
        │                score survive independent           │
        │                verification?                        │
        ▼                     │  fail → don't advance          ▼
  Reviewer-QA loop  ◀─────────┘  pass → rank & report ─▶ ⑤ LEARN: assay results
  (rubric, re-delegate)                                    retrain the private model
        │                                                        │
        └──────────────────  compounding moat  ◀─────────────────┘
```

- **The loop is the moat:** each assay round sharpens both the generator and the selection policy — a
  private-data + algorithm flywheel competitors' closed pipelines / read-only reasoners don't accumulate.
- **Verify gates advancement:** a candidate only moves forward if physics/ADMET *and* an independent
  reviewer agree — the honest-negative discipline (e.g. our ΔPSA3D result) is built into the flow.

---

## The differentiator: generate → **verify** → learn

- Foundation models and agents both **over‑trust their own scores.** Pharma R&D fails when unverified predictions advance.
- BioMate makes **independent verification a first‑class, automated step** — physics, ADMET, QC gates, and **adversarial review**.
- This is not a slogan — we run it. Next slide: a live cyclic‑peptide program where verification changed the answer.

---

## Proof: a live cyclic‑peptide (多肽) program on BioMate

- **Engine:** generate (BoltzGen) → **MM‑GBSA physics verify** → permeability‑aware select → N‑methyl redesign → re‑verify. Automated, cloud‑native.
- **Verification changed conclusions, honestly:**
  - Generator confidence (iptm) was **not** a reliable binding predictor → physics verification is non‑optional.
  - A permeability "binding‑sacrifice" finding was a **size artifact** — caught by ligand‑efficiency correction.
  - **An independent 3‑model review board** (Claude Opus 5, GPT‑6, Gemini 3.1) audited the work, caught a real cheminformatics bug, and forced corrections.
- **This is the culture pharma buyers should want:** rigorous, self‑correcting, auditable — the opposite of "trust the model."

---

## Requirement fit — Guangdong pharma needs → BioMate

| Pharma need | BioMate‑Pharma capability |
|---|---|
| Hit/lead discovery (small mol, peptide, antibody) | Integrated generators + docking/MD + verify loop |
| DMPK / developability | ADMET suite (hERG, CYP, oral BA), permeability, PK/PD, PBPK |
| CMC / stability | Accelerated‑stability workflows |
| Clinical design | BOIN dose‑escalation, trial analysis, FAERS pharmacovigilance |
| Regulatory (NMPA/FDA) | IND §2.6.1 narratives, CRO compliance packages, audit trail |
| Governance | Reproducible workspaces + GxP layer + adversarial review |

---

## Compliance / GxP — the additive layer (not a subset)

- **Data provenance & audit trail** per drug program (every run, param, and result traceable).
- **Reproducible session workspaces** (reasoning + tool calls + code + figures) — directly usable in filings.
- **21 CFR Part 11 / EU Annex 11‑style controls**; NMPA alignment for Guangdong filers.
- **Access control, e‑signatures, validation documentation.**
- *This is what turns a research tool into a pharma product — and what neither competitor emphasizes.*

---

## Roadmap

- **Phase 0 (now):** curated pharma catalog + program‑centric UX skin on the existing engine.
- **Phase 1:** integrate open FMs (Protenix/PXDesign/DPLM) as generation/structure workflows; add public‑data MCP servers.
- **Phase 2:** agentic orchestrator (CSO + specialists + Reviewer QA) over BioMate MCP tools.
- **Phase 3:** GxP/compliance module + reproducible‑workspace exports for filings.
- **Phase 4:** peptide/DMPK verify‑learn loops productized (from the live program); FEP finalist tier.

---

## Leverage roadmap: adopt the open frontier, spend our effort on the moat

The 2026 landscape lets us **build the table-stakes stack fast** and concentrate on what's defensible:

| Brief clause (生成→验证→学习) | We ADOPT (open) | Our MOAT (own effort) |
|---|---|---|
| Pocket‑conditioned all‑atom design (small mol + cyclic peptide) | **PocketXMol** (*Cell* 2026, MIT), **BoltzGen** (MIT) | one backbone + **validated** per‑modality plugins (closure, non‑natural chemistry) |
| Conformational ensembles + permeability | **EnsembleCycPerm** (2‑env chameleon) + open CycPeptMPDB‑4D | permeability as a **generation objective**, not a filter |
| Physical constraints / ring closure | **MacroGuide** (ring formation 1%→99%), **openfe/ATM** (FEP) | **automated cyclic MM‑GBSA verify** — the "验证" others skip |
| Multi‑objective Bayesian optimization | **APCyc**, **PepTune** (guided sampling) | developability **+ expected‑information‑gain** (experiment‑native loop) |
| Continuous training on experimental feedback | — (no shortcut) | **compounding private‑data flywheel** + honest adversarial review |

- **Honest calibration:** cyclic‑peptide permeability SOTA is **R²≈0.55 (random split)** and drops on scaffold — we cite the 13‑method benchmark and don't over‑promise.
- **Message:** *we don't out‑generate Vilya/ANew — we compose the open frontier and win on **验证 + 学习 + execution**.*
- Detail: `research/guangzhou_all_atom/docs/20260921_LEVERAGE_AND_INSPIRATION.md`.

---

## Honest risks

- **Competitors are strong** on models (ANew) and reasoning (Virtual Biotech); the generator layer is commoditizing.
- **Our peptide program is preclinical / in‑silico** — as are theirs; verification ≠ wet‑lab truth (that's the ultimate gate).
- **Integration debt:** wiring open FMs + MCP servers + orchestrator is real engineering, not free.
- **Compliance is a build**, not a checkbox.
- **Mitigant:** we don't need to win layers ① or ②; we need to **own ③ and compose the rest** — a narrower, more defensible bet.

---

## The ask / next steps

- **Position:** *"Agentic drug‑discovery orchestration on a verified execution substrate."*
- **Decision:** green‑light BioMate‑Pharma as a **vertical** (not a fork) — Phases 0–1 first.
- **Guangdong pilot:** pick 1–2 partner programs (a peptide or small‑molecule lead) to run the full generate→verify→select→report loop with compliance artifacts.
- **We bring:** the only execution+verification layer, plus a proven, self‑auditing R&D culture.

---

# Appendix / sources

- **Virtual Biotech:** Zhang, Eckmann, Miao, Mahon, Zou. *Science* (17 Sep 2026), DOI 10.1126/science.aeg6779. Re‑impl: github.com/gliaropoulos/virtualbiotech.
- **ANew Labs / ByteDance:** anewbt.com; Protenix/PXDesign/DPLM/APM at github.com/bytedance; $290M raise (SCMP, Sep 2026).
- **Vilya‑1** (likely "Molo‑1/Atomelogy"): vilya.ai/vilya‑1; arXiv 2607.09998 (Jul 2026); Vilya‑2 arXiv 2607.25156. No public code/weights.
- **BioMate peptide program:** research/guangzhou_all_atom (MANUSCRIPT.md, COMMITTEE_REVIEW.md, PERMEABILITY_DRIVEN_GENERATION.md).
