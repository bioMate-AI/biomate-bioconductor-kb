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

## Reality check — what a top‑20 pharma (AstraZeneca) actually runs

AZ has **published** its agentic R&D stack (2026) — it validates the tender's direction *and* our architecture:

- **ChatInvent** — production molecular‑design + synthesis agent (supervisor + 4 sub‑agents: Design · Synthesis · Analyzer · Utility); runs the **DMTA loop** conversationally. **Open‑sourced as `MolecularAI/langdmta-lab`** — and it is **MCP‑based** (Model Context Protocol), *the same tool interface BioMate uses.* (Drug Discovery Today, Jan 2026)
- **Research Assistant** — biomedical R&D agent, **~15k internal users/yr**; literature/target/KG reasoning over BIKG (14M‑entity knowledge graph). (arXiv 2608.12395)
- **Open tools under it (MolecularAI, Apache/MIT):** **REINVENT4** (de novo, scaffold hop, R‑group, linker, library), **AiZynthFinder** (retrosynthesis), QSARtuna (ADMET/QSAR), DockStream (docking), maize (comp‑chem DAG).

**The point:** the client's ask (**generation + optimization + closed loop**) is exactly what AZ productized — MCP‑orchestrated, human‑in‑the‑loop, DMTA.

---

## BioMate coverage vs AstraZeneca's stack

| AZ workflow (what their agents run) | BioMate today |
|---|---|
| MCP tool orchestration | ✅ **MCP‑native** — same paradigm (`run_workflow`, `search_workflow`, `fetch_public_data`…) |
| De novo design / scaffold hop (REINVENT4) | ✅ generators integrated; **REINVENT4 is open → wire it in directly** |
| Docking / MD / SBDD (DockStream/Icolos) | ✅ docking + MD + MM‑GBSA/FEP verify |
| ADMET / QSAR + uncertainty (QSARtuna) | ✅ ADMET suite (hERG/CYP/hepatotox/off‑target) |
| Literature / target‑ID / KG reasoning (BIKG) | ◑ lit + platform search present; **KG‑target reasoning is lighter** — a fast‑follow |
| Retrosynthesis / synthetic feasibility (AiZynthFinder) | ◑ SA scoring present; **AiZynthFinder is open (MIT) → integrate for full retro** |
| DMTA‑loop orchestration (ChatInvent) | ✅ generate→verify→learn loop + QC gates + provenance |

- **Takeaway:** BioMate matches AZ on **architecture (MCP)** and most workflows, and AZ's two biggest gaps for us — **REINVENT4 + AiZynthFinder — are open**, so we absorb them. The client gets **AZ‑class capability, self‑hosted and governed.**

---

## The agent‑vendor model — Biomni / Phylo → Japanese pharma

- **Biomni** (Stanford SNAP lab; *Science* 2026) — general‑purpose biomedical AI agent: **Claude + 150 tools / 59 DBs / ~106 packages**, composes workflows on the fly. Commercialized by **Phylo** ("Biomni Lab"; $13.5M seed from a16z + Anthropic's fund, Feb 2026).
- **Deployed at two Japanese pharma:**
  - **Ono** (Jul 2026) — rolled out to *every discovery scientist*; ingest proprietary historical data; reason + design follow‑on experiments.
  - **Chugai / Roche** (Aug 2026) — **on‑premises, inside Chugai's secure perimeter**, on proprietary data; **4 preclinical areas: single‑cell · human genetics · disease biology · target evaluation.**
- **This is the exact shape the Guangzhou tender wants** — an agentic workspace on the partner's **own data, on‑prem** (their Q18) — and it's being bought by top pharma *now*.

---

## BioMate coverage vs Biomni / Phylo

| What Phylo provides pharma | BioMate |
|---|---|
| Agentic workspace on proprietary data, **on‑prem** | ✅ on‑prem / data‑residency deployment (tender Q18) |
| Single‑cell · human genetics/GWAS · disease biology · target eval | ✅ workflows across all four (scRNA, GWAS, multi‑omics) |
| Docking (DiffDock/Vina) · ADMET · binding affinity · repurposing (TxGNN) | ✅ docking + ADMET + repurposing workflows |
| Powered by **Claude** | ✅ BioMate is Claude‑based + **MCP‑native** (Biomni ships a Claude connector) |
| Tools = **ad‑hoc Python functions** (generalist agent) | ✅ **curated, validated production pipelines** (Nextflow/AWS‑Batch) — reproducible, QC‑gated, provenance |
| *(not emphasized)* | ✅ **cryo‑EM · large nf‑core NGS · proteomics‑MS · PBPK** — beyond Biomni's catalog |

- **Net read:** the winning pharma‑agent model (agentic workspace + proprietary data + on‑prem) is validated by **AZ and Biomni@Ono/Chugai** — and BioMate delivers it with **validated execution + governance**, not ad‑hoc scripts. *Differentiator vs Biomni = verified pipelines; vs AZ = self‑hosted + broader domain coverage.*

---

## Requirement fit — the Guangzhou tender's 4 layers → BioMate

*The tender (RMB 70M, deadline 2026‑12‑31) asks for a **reusable molecular generation + optimization platform** for **lead discovery/optimization** — optimizing **synthetic accessibility · target affinity · safety**. Scope is discovery — explicitly **not** clinical, regulatory submission, or candidate nomination.*

| Their layer | What they ask | BioMate today |
|---|---|---|
| ① Knowledge | literature + **patent/FTO** search, activity/SAR | platform‑wide **search** (workflows + tools + public data); lit/target retrieval; **novelty/FTO as a design gate** |
| ② Reasoning | hypothesis, target/chemotype rationale | agentic orchestrator — target/chemotype rationale, **human‑reviewed** |
| ③ **Generation** *(core)* | **de novo + scaffold hopping** | integrated open generators (Protenix/PXDesign/DrugCLIP/BoltzGen…); **small‑molecule‑first, modality‑configurable** |
| ④ **Optimisation** *(core)* | activity pred · docking/MD/**BFE** · ADMET/safety · **multi‑objective + closed loop** | docking/MD/**MM‑GBSA/FEP** · ADMET (hERG/CYP/hepatotox/off‑target/metabolic) · **multi‑objective governance** · DMTA loop |

- **Their 3 named dimensions, mapped:** target affinity → docking/MD/FEP · synthetic accessibility → SA score + purchasable‑route check · safety → ADMET panel.
- **No single opaque score decides** — each criterion is separate, inspectable, human‑overridable (their multi‑objective ask = our *governance*).

---

## Beyond the requirement — BioMate is a full drug‑development platform (with search)

The tender is a **subset** of what BioMate already is — so the client isn't boxed into one narrow tool:

- **Search across the whole platform** — 4,017 workflows / 36 domains + 12k tools + 60+ data sources; one query finds the right pipeline (their Knowledge layer, platform‑wide).
- **All modalities, one engine** — small molecule (primary), peptide/macrocycle (proven loop), roadmap to PROTAC/glue (their Q1 "or a combination").
- **Whole pipeline, not just discovery** — also genomics → variant → structure → ADMET → PK/PD (and clinical/reg *when later wanted*): the platform grows *with* them, no second vendor.
- **Configurable & on‑prem‑ready** — new targets, new objectives/weights, ELN/LIMS integration, private deployment + data residency (their Q4/Q6/Q8/Q18).
- **Message:** *you asked for the generation+optimization slice; you're buying a platform that already exceeds it.*

---

## How we'd run it — a jointly‑scoped, validated pilot (not "drug‑from‑a‑button")

1. **Discovery + data audit** — agree the target product profile, data dictionary, **scoring contract**, baseline, validation protocol.
2. **Retrospective evaluation** — generation/ranking on **held‑out historical activity data**; report enrichment, calibration, failure modes, uncertainty (their acceptance, Q17).
3. **Human‑reviewed design cycle** — diverse candidate set; explicit **affinity × developability × synthesizability × safety** gates; documented keep/kill rationale.
4. **Prospective assay loop** — synthesize/test an agreed small set (partner lab or CRO); predicted‑vs‑observed; retrain only under **versioned data/model governance** (their DMTA, Q11‑15).
5. **Decision package** — ranked candidates + evidence + parameter/model versions + limitations + expand/no‑go.

**Claims we do NOT make:** independent drug discovery, candidate nomination, or that generated molecules are synthesizable/active/safe/novel without prospective evidence; computational ADMET/docking ≠ regulatory‑grade. *Honesty is the differentiator.*

---

## Deployment, IP & governance — their actual asks (Q5–Q18)

- **On‑prem / private / domestic stack** with **data‑residency controls** (Q18) — data and models stay inside the partner.
- **IP ownership:** foreground work — generated compounds, fine‑tuned models, workflows — assigned per agreement to the partner (Q7).
- **Train on their data:** activity/property models fine‑tuned on the partner's experimental data behind a **versioned workflow contract** (Q5).
- **Integration:** bidirectional with **ELN / compound library / LIMS** (Q6).
- **Provenance:** every run, parameter, output, QC outcome, and decision recorded; **invalid launches blocked before compute is spent**; medicinal chemists retain approval authority.
- *GxP / 21 CFR Part 11 available as an add‑on for later regulated phases — not required for this discovery‑scoped pilot.*

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

- **Position:** *"A governed molecular generation + optimization platform — search → generate → verify → learn — that you own and run on‑prem."*
- **Pilot (to the 2026‑12‑31 milestone):** one small‑molecule lead‑optimization program — retrospective benchmark on the partner's held‑out data → human‑reviewed design cycle → a small prospective assay round.
- **Acceptance:** enrichment vs the partner's baseline on retrospective data; a ranked, **synthesis‑aware** candidate set with evidence + provenance.
- **We bring:** the full platform (search + all modalities + verify loop) + honest, self‑auditing governance — **exceeding the requirement without boxing them in.**

---

# Appendix / sources

- **Virtual Biotech:** Zhang, Eckmann, Miao, Mahon, Zou. *Science* (17 Sep 2026), DOI 10.1126/science.aeg6779. Re‑impl: github.com/gliaropoulos/virtualbiotech.
- **ANew Labs / ByteDance:** anewbt.com; Protenix/PXDesign/DPLM/APM at github.com/bytedance; $290M raise (SCMP, Sep 2026).
- **Vilya‑1** (likely "Molo‑1/Atomelogy"): vilya.ai/vilya‑1; arXiv 2607.09998 (Jul 2026); Vilya‑2 arXiv 2607.25156. No public code/weights.
- **BioMate peptide program:** research/guangzhou_all_atom (MANUSCRIPT.md, COMMITTEE_REVIEW.md, PERMEABILITY_DRIVEN_GENERATION.md).
