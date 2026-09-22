---
marp: true
theme: default
paginate: true
title: BioMate for Drug Discovery — Guangzhou product introduction
---

<!-- CLIENT product-introduction deck (reframed from 20260921_BIOMATE_PHARMA_GUANGDONG_DECK.md, which is the
     internal strategy version — kept). Client-centric arc; competitors condensed to the appendix; risks reframed
     as "scope & transparency". Design hooks marked [DESIGN: ...] for the Claude Design pass (vector diagrams,
     product screenshot, bilingual EN+中文). Facts faithful to the tender docs + 20260921_COMPETITIVE_INTEL. -->

<style>
:root { --navy:#0b2545; --teal:#12808a; --ink:#1b2a38; --muted:#5b6b7a; --line:#d8e0e8; --soft:#f3f8fb; }
section { font-family:-apple-system,"Segoe UI","Helvetica Neue",Arial,"PingFang SC","Microsoft YaHei",sans-serif;
  font-size:20px; color:var(--ink); background:#ffffff; padding:44px 56px; }
h1 { color:var(--navy); font-size:42px; }
h2 { color:var(--navy); font-size:29px; border-bottom:3px solid var(--teal); padding-bottom:6px; margin-bottom:14px; }
h3 { color:var(--teal); font-weight:600; margin-top:2px; }
strong { color:var(--navy); } em { color:var(--muted); } a { color:var(--teal); text-decoration:none; }
ul,ol { line-height:1.42; } li { margin:3px 0; }
table { width:100%; border-collapse:collapse; font-size:15.5px; margin:6px 0; }
th { background:var(--navy); color:#fff; text-align:left; padding:6px 10px; font-weight:600; }
td { padding:5px 10px; border-bottom:1px solid var(--line); vertical-align:top; }
tr:nth-child(even) td { background:var(--soft); }
blockquote { color:var(--muted); border-left:4px solid var(--teal); padding-left:12px; font-style:italic; }
section::after { color:var(--muted); font-size:12px; }
section.lead { background:linear-gradient(135deg,#0b2545 0%,#12808a 100%); color:#eaf3f5; justify-content:center; }
section.lead h1 { color:#ffffff; font-size:52px; margin-bottom:8px; }
section.lead h3 { color:#bfe3e8; } section.lead strong { color:#fff; } section.lead em { color:#d6e7ec; }
</style>

<!-- _class: lead -->

# BioMate for Drug Discovery

### AI molecular generation & optimization — on a verified execution platform

**Prepared for Guangzhou · Sept 2026**

*Generate → verify → learn — on cloud compute you own.*

<!-- [DESIGN: logo; a 中文 subtitle line: 面向药物发现的 AI 分子生成与优化平台] -->

---

## Your goal

*What your team asked for — a reusable molecular‑generation + optimization platform for lead discovery/optimization.*

- **Generate** chemically‑reasonable candidate compounds with potential activity (de novo + scaffold hopping).
- **Optimize** across your three dimensions: **synthetic accessibility · target affinity · safety**.
- One integrated workflow: **generation → activity prediction → property optimization → candidate ranking.**
- A **reusable platform** — configurable to new targets, your data, your objectives — for the **early discovery** stage.

> We build this *with* you — a jointly‑scoped, validated engagement, not a "drug‑from‑a‑button" claim.

---

## What BioMate is

*Not a single model, and not just a chat — a platform that **runs and verifies** the science on cloud compute.*

- **Generate → VERIFY (physics / ADMET) → learn** — the loop that turns model output into *evidence*, not just suggestions.
- **4,000+ workflows / 36 domains — production nf‑core pipelines** (RNA‑seq, sarek, chipseq, proteomics‑MS); **MCP‑native**; **Claude‑powered**.
- Every run **reproducible + auditable**: inputs, parameters, outputs, QC, and the decision context are recorded.
- **Invalid runs are blocked before compute is spent;** your chemists keep approval authority.

<!-- [DESIGN: a real product UI screenshot of the workflow panel here — this slide should show the product] -->

---

## Your 4 layers → BioMate

| Your layer | What you asked for | BioMate |
|---|---|---|
| ① Knowledge | literature + **patent/FTO** search, activity/SAR | platform‑wide **search** (workflows + tools + public data); lit/target retrieval; novelty/FTO as a design gate |
| ② Reasoning | hypothesis, target/chemotype rationale | agentic orchestration — rationale, **human‑reviewed** |
| ③ **Generation** | **de novo + scaffold hopping** | integrated open generators; **small‑molecule‑first, modality‑configurable** |
| ④ **Optimisation** | activity · docking/MD/**BFE** · ADMET/safety · **multi‑objective + closed loop** | docking/MD/**MM‑GBSA/FEP** · full ADMET · **multi‑objective governance** · DMTA loop |

---

## Optimizing your three dimensions

- **Target affinity** → molecular docking · molecular dynamics · MM‑GBSA / FEP binding free energy.
- **Synthetic accessibility** → SA scoring + **purchasable‑route** feasibility (retrosynthesis).
- **Safety** → ADMET panel — **hERG · CYP · hepatotoxicity · off‑target · metabolic stability.**
- **Multi‑objective by governance:** each criterion is **separate, inspectable, and human‑overridable** — configurable weights/ranges, **no single opaque score decides a compound.**

---

## How it works — the platform

<!-- [DESIGN: replace this text with a clean vector diagram of the 5 planes: Experience+governance / Orchestration /
     Capability (MCP tools) / Execution+Verify / Data+Provenance, running on AWS Batch] -->

- **Experience** — a program‑centric workspace (a "drug program", not a "run"), with on‑prem deployment + audit.
- **Orchestration** — an AI scientist team plans, calls tools, and an independent reviewer checks the work.
- **Capability** — one typed MCP tool per action (search · generate · verify · analyze · report).
- **Execution + Verify** — curated workflows + integrated open models; **generate → VERIFY (physics/ADMET) → learn.**
- **Data + Provenance** — public‑data connectors + your private data; every step traceable.

---

## How a drug program flows

<!-- [DESIGN: vector diagram of the generate → verify → learn loop with the reviewer gate + assay feedback] -->

`target/indication → generate candidates → VERIFY (docking/MD/FEP + ADMET + QC gate) → rank → (assay) → learn`

- **Verify gates advancement:** a candidate moves forward only if physics/ADMET **and** an independent review agree.
- **The loop compounds:** each assay round sharpens both the generator and the selection policy — a private‑data advantage that accumulates inside *your* environment.

---

## Beyond the requirement — a full platform, with search

*The molecular‑generation+optimization engagement is one slice of what you're adopting.*

- **Search across the whole platform** — 4,000+ workflows + 12k+ tools + 60+ data sources; one query finds the right pipeline.
- **All modalities, one engine** — small molecule (primary), peptide/macrocycle, roadmap to PROTAC/glue.
- **The whole pipeline** — discovery → DMPK/ADMET → PK/PD → (and clinical/regulatory *when you later want it*).
- **Configurable & on‑prem‑ready** — new targets, new objectives, ELN/LIMS integration, private deployment.

---

## Proof — verification changes the answer

*A live program on BioMate, run honestly:*

- Generator confidence alone was **not** a reliable predictor of binding → **physics verification is non‑optional.**
- A "binding‑sacrifice" finding turned out to be a **measurement artifact** — caught by the verify layer, not shipped.
- An **independent multi‑model review** audited the work, caught a real error, and forced corrections.

> This is the culture: **rigorous, self‑correcting, auditable** — the opposite of "trust the model."

---

## How we'd engage — a validated pilot

*To your 2026‑12‑31 milestone — jointly scoped, human‑in‑the‑loop.*

1. **Discovery + data audit** — agree the target profile, data dictionary, **scoring contract**, baseline, validation protocol.
2. **Retrospective evaluation** — generation/ranking on your **held‑out historical data**; report enrichment, calibration, uncertainty.
3. **Human‑reviewed design cycle** — diverse candidates through **affinity × developability × synthesizability × safety** gates.
4. **Prospective assay round** — synthesize/test a small agreed set; predicted‑vs‑observed; retrain under versioned governance.
5. **Decision package** — ranked, synthesis‑aware candidates + evidence + versions + expand/no‑go.

---

## Deployment, IP & governance

*Answering your Q5–Q18 directly.*

- **On‑prem / private / domestic stack** with **data‑residency controls** — your data and models stay inside.
- **IP ownership** — generated compounds, fine‑tuned models, and workflows assigned to you per agreement.
- **Trained on your data** — activity/property models fine‑tuned on your experimental data, versioned.
- **Integration** — bidirectional with **ELN / compound library / LIMS.**
- **Provenance** — every run, parameter, output, QC outcome, and decision recorded; chemists retain approval.
- *GxP / 21 CFR Part 11 available as an add‑on for later regulated phases — not required for this discovery pilot.*

---

## Why BioMate

- **We run & verify the science** — not a model or a chat, but real execution on cloud compute with a verify layer.
- **We compose the best open models** as generators — you get the frontier without lock‑in.
- **Breadth** — all modalities and the whole pipeline, so the platform grows *with* your programs.
- **Honest, governed, human‑in‑the‑loop** — multi‑objective by inspection, provenance everywhere, no black‑box calls.

---

## The ask

- **A jointly‑scoped pilot** — one small‑molecule lead‑optimization program, to the 2026‑12‑31 milestone.
- **Acceptance:** enrichment vs your baseline on retrospective data; a ranked, synthesis‑aware candidate set with evidence + provenance.
- **We bring:** the platform (search + all modalities + verify loop), on‑prem deployment, and a proven, self‑auditing R&D culture.

<!-- [DESIGN: closing lead slide; contact; 中文 CTA] -->

---

## Beyond early discovery — the whole R&D pipeline · 覆盖整个研发链条

*Your ask is early discovery — but BioMate services the whole R&D org. (For reference, Biomni×Chugai covers only 4 preclinical areas; AZ's agents span target-ID→pharmacovigilance.)*

| Stage | Workflows | BioMate |
|---|---|---|
| **Target ID** 靶点发现 | human genetics/GWAS · functional genomics · single-cell | ✅/◑ |
| **Disease biology** 疾病生物学 | single-cell / spatial · multi-omics integration | ✅ |
| **Target evaluation** 靶点评估 | tractability · Open Targets · target safety | ✅ |
| **Biomarkers / translational** 生物标志物 | immune deconvolution · survival stratification · companion-Dx | ✅ |
| **Safety / tox** 安全毒理 | ADMET · hERG/CYP · FDA safety signals | ✅ |
| **DMPK** | PBPK · PK-PD · NCA | ✅ |
| **Clinical** 临床 | trial simulation · adaptive dose-finding | ✅ |
| **NGS pipelines** 组学流程 | RNA-seq · variant (sarek) · ChIP/ATAC · proteomics-MS | ✅ **validated** |

- **The number that differentiates us:** BioMate covers **and runs** every stage as production nf‑core pipelines (4,000+ workflows · 36 domains · whole R&D pipeline) — everything AZ & Biomni service, BioMate covers *and runs* (validated production pipelines, not just tool orchestration).
- *(Honest roadmap: biobank-scale GWAS/coloc + a knowledge-graph target-ID layer, MAGeCK screen analysis, and a FAERS disproportionality suite are near-term additions.)*

---

# Appendix

---

## Where we fit — the landscape (condensed)

*The field is layering into ① foundation models · ② agentic orchestration · ③ execution.*

- ① and ② are **crowded and increasingly open** (ByteDance/ANew, Vilya, Stanford's Virtual Biotech, AstraZeneca's open tools).
- **BioMate is layer ③ — execution + verification** — and **composes ① and ②** (we integrate open generators like Protenix/PXDesign and adopt the agentic‑review pattern).
- **What leading pharma actually run** (AstraZeneca's ChatInvent, Biomni/Phylo at Ono & Chugai) validates this shape — **agentic tools + proprietary data + on‑prem** — which is exactly what we deliver, on validated pipelines.

*Full competitive detail + sources: `20260921_COMPETITIVE_INTEL_AI_DRUG_DISCOVERY.md`.*

---

## Scope & what we're transparent about

- **Discovery‑scoped:** we accelerate lead discovery/optimization — we do **not** claim autonomous drug discovery, candidate nomination, or clinical/regulatory outcomes.
- **Computational ≠ experimental:** ADMET/docking are prioritization signals, **not** regulatory‑grade or a substitute for assays; generated molecules aren't claimed synthesizable/active/safe/novel without **prospective evidence**.
- **Validated jointly:** capability is proven on **your** target + data (retrospective, then prospective), under versioned governance — not asserted.
- **Honest by design:** the verify layer + independent review exist to *catch our own errors before they reach you*.

---

## Sources & notes

- Requirement: your project brief + the 20‑question platform scope (Knowledge / Reasoning / Generation / Optimisation).
- Competitive facts: `20260921_COMPETITIVE_INTEL_AI_DRUG_DISCOVERY.md` (confidence‑flagged; some competitor claims unverified and omitted).
- Design brief for this deck: `20260921_GUANGZHOU_DECK_DESIGN_BRIEF.md`.

<!-- [DESIGN NOTE: produce a 中文 (Simplified) version as primary for the client; idiomatic, native‑reviewed.
     Replace [DESIGN: ...] hooks with vector diagrams + a product screenshot. Deliver PPTX + PDF, 16:9. ] -->
