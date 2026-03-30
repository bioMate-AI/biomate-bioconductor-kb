# Joint Study Proposal
## AI-Assisted Drug Screening: Accuracy, Efficiency, and Adaptive Intelligence

**Proposing parties:** BioMate AI · UT Southwestern Simmons Cancer Center  
**Target venue:** Journal of Chemical Information and Modeling / Nature Chemical Biology / Drug Discovery Today  
**Proposed duration:** 6 months  
*March 2026 · Draft for discussion*

---

## Executive Summary

### What BioMate Is

BioMate is an AI-native computational research platform that converts a plain-language description of a screening task into a fully configured, QC-governed pipeline — and runs it. A medicinal chemist types: *"Screen these 20 compounds against EGFR for ADMET liabilities and docking affinity."* BioMate generates the pipeline, runs ADMET profiling with hERG, DILI, Ames, and ClinTox gates, executes molecular docking, ranks the compounds, and produces a methods narrative — with every QC threshold anchored to a published evidence source and tagged by evidence tier. No tool configuration. No manual threshold look-up. No post-hoc documentation.

The platform covers **12 drug discovery phases**, applies **9 QC profiles** specific to compound class and assay context, and draws on **950+ indexed workflows** across drug discovery, genomics, proteomics, and structural biology. It runs on cloud compute (AWS Batch), on institutional HPC, or locally — selected once in settings, applied to all subsequent runs.

### What the Problem Costs Today — Without BioMate

| Task | Without BioMate | With BioMate |
|---|---|---|
| Pipeline setup (ADMET + docking) | 2–4 hours for a computational chemist; days if waiting for core facility | ~5 minutes via plain-language query |
| QC threshold sourcing | Manual literature look-up per campaign; ~1 hour; not documented | Automatic; evidence-tier cited in audit log |
| Methods section for each run | Written post-hoc by analyst; ~2–3 hours per batch | Auto-generated HTML/PDF with tool versions, parameters, and QC outcomes after every run |
| Reproducibility across batches | Ad hoc; thresholds and parameters drift across analysts and time | Versioned QC profile; identical configuration guaranteed across runs |
| Context carry-over between sessions | Zero; analyst re-enters campaign context manually at session start | Structured session memory; prior compound outcomes, override decisions, and QC adjustments loaded at next session open |
| Borderline compound decisions | Analyst judgment; undocumented; irreproducible | Flagged with exact metric, threshold, evidence source, and override audit log |

Across a typical 10–20 compound screening batch, the configuration and documentation overhead alone represents **6–10 hours of analyst time per batch** that BioMate eliminates. For a campaign running 5–10 batches over a project lifetime, that is **30–100 hours recovered** — time that returns to chemistry and biology decisions.

### Why This Study

The benefits above are claimed; this study measures them. Three questions drive the study design:

1. **Does BioMate's output agree with expert computational chemistry?** — measured on a real compound set against the partner's existing pipeline (Arm A)
2. **Is BioMate actually faster and less burdensome for the people who will use it?** — measured across analysts at different computational experience levels (Arm B, C)
3. **Does session memory reduce re-orientation overhead and prevent repeated mistakes?** — measured in a controlled two-session experiment (Arm D)

### What the Partner Gets From This Study

- A fully governed computational screening environment for an active compound series, at no compute cost
- ADMET + docking results on 50–100 compounds, with a complete QC audit trail and auto-generated methods narrative per batch
- An independent measurement of where AI-assisted screening saves analyst time and where it does not — useful for internal platform adoption decisions
- Co-authorship on a tools and resources publication with direct relevance to the field's growing interest in AI-assisted drug discovery

### Study at a Glance

| | |
|---|---|
| **Partner** | UT Southwestern Simmons Cancer Center |
| **Compound set** | 50–100 small molecules; one cancer-relevant target |
| **Analyses covered** | ADMET (hERG, DILI, Ames, ClinTox), molecular docking, compound prioritization, NCA if PK data available |
| **Duration** | 6 months |
| **Compute cost to partner** | $0 (covered by BioMate) |
| **Data commitment from partner** | De-identified compound SMILES, target structure, existing pipeline results for Arm A comparison |
| **Primary output** | Peer-reviewed tools and resources paper |

---

## Background and Motivation

Computational drug screening is well-established in practice, but the workflow remains fragmented and expert-dependent. ADMET profiling, molecular docking, compound prioritization, and PK/PD modeling are each supported by mature tools — yet assembling them into a reproducible, QC-governed campaign that a medicinal chemist without a dedicated computational colleague can run and interpret remains a daily friction point.

BioMate addresses this directly: a plain-language query generates a fully configured, sequentially QC-gated screening campaign. For a small molecule series against a cancer-relevant target, a scientist can go from SMILES input to ranked compounds with toxicity flags, docking poses, and a defensible methods narrative — without configuring individual tools or interpreting raw score distributions. The QC layer applies hERG, DILI, Ames, and ClinTox gates automatically, with each threshold anchored to published evidence and tagged by tier (GOLD/SILVER/BRONZE).

Beyond single-session execution, BioMate introduces a capability that conventional screening tools do not address: **adaptive memory across a campaign**. Over the course of weeks of screening iterations, the platform builds context — which compound classes failed which gates, which scaffold modifications improved which properties, which QC thresholds the team consistently overrides and why. This accumulated context shapes subsequent sessions: BioMate anticipates the team's screening logic, applies tighter pre-filters to known failure classes, and surfaces the campaign history directly in each new session without the analyst re-entering it.

Whether this adaptive behavior genuinely improves screening outcomes — and how to measure it rigorously — is the central open question this study addresses.

---

## What Makes This Study Distinctive

Three things separate this from a standard tool comparison:

1. **The QC layer is a first-class research object.** BioMate's ADMET and docking QC gates are not post-hoc filters — they are integral to the pipeline and auditable at the evidence level. Testing whether automated, evidence-graded QC changes how teams handle borderline compounds is itself a publishable question.

2. **The study runs longitudinally, not as a single session.** A campaign spans weeks. The self-adaptation arm (Arm D) measures whether the platform improves within that campaign — not through retraining, but through persistent memory and context accumulation. No existing drug screening platform has been evaluated this way.

3. **The efficiency comparison is separated from the accuracy comparison.** A faster tool that produces worse compound rankings is not a net gain. Arms A and B measure these independently, and the interaction between them tells the complete story.

---

## Research Questions

1. **Execution concordance:** For ADMET profiling, molecular docking, and compound prioritization, how closely does BioMate's automated output match what an experienced computational chemist would produce using standard tools (Schrödinger, MOE, or equivalent)? Where do they diverge, and does the divergence change prioritization decisions?

2. **Efficiency and convenience:** Does BioMate reduce the time and configuration burden for medicinal chemists who are not computational specialists? Is the reduction consistent across different levels of computational experience?

3. **Research intelligence during a campaign:** When analysts use BioMate's research agent to answer questions during screening — mechanism of a toxicity flag, structural reasons for a poor docking score, literature precedent for an analogue series — does it surface information that changes decisions?

4. **Self-adaptation across a campaign:** Does BioMate become more useful over the course of a multi-week screening campaign as it accumulates context about the compound series, the target, and the team's screening preferences? Can that improvement be measured, and what forms of accumulated context drive it?

---

## Proposed Study Design

### Dataset

**Compound library:** 50–100 small molecules from an active cancer target campaign at the partner site. De-identified structures (proprietary details removed) or a matched public set if internal structures cannot be shared. Includes compounds already screened with known ADMET and activity outcomes, serving as ground truth for Arm A.

**Target:** A kinase or surface receptor with an available crystal structure or high-confidence AlphaFold model. Docking redocking RMSD validation requires a reference ligand pose.

**Campaign history:** Prior screening data from the same campaign (previous compound batches, notes on failed analogues, override decisions) loaded into BioMate at study start to seed Arm D's memory baseline.

### Analysis Arms

**Arm A — Execution concordance**

BioMate is run on the same compound set and target as the partner's existing computational pipeline. For each compound:
1. ADMET profiles compared: hERG IC₅₀ estimate, DILI risk score, Ames flag, ClinTox probability, physicochemical profile
2. Docking scores and top poses compared against partner's docking output
3. Final rank order compared: where does BioMate's ranking agree with the expert ranking, and where does it diverge?
4. Discordances classified: parameter difference, tool difference, threshold difference, or fundamental disagreement in the scoring model

*Primary metric:* Rank correlation (Spearman) between BioMate and expert compound rankings; F1 of ADMET flag agreement on compounds the expert flagged as problematic; RMSD of top docking pose vs. reference.

**Arm B — Efficiency and convenience across experience levels**

A set of screening tasks is run by 3–4 people: at least one experienced computational chemist, at least two medicinal chemists with limited computational background. Each runs the same task with current tools and with BioMate.

Measurements: time-to-result; number of configuration steps; completeness of the methods narrative produced; number of errors or dead ends. Post-session interview: where did BioMate reduce friction, where did it add it, which outputs were trusted and which were not?

*Primary metric:* Time-to-result by experience level; methods narrative completeness; analyst trust score by output type (ADMET flag, docking pose, overall rank).

**Arm C — Research intelligence during screening**

During Arm B sessions, analysts use BioMate's research agent freely — asking why a compound triggered a hERG flag, what structural modifications are known to improve DILI profiles for this scaffold, or what the literature says about analogues near this docking pose. Sessions are logged; useful queries and responses are identified post-hoc.

*Primary metric:* Fraction of queries rated useful; cases where a response changed a compound decision or scaffold direction; query categories where the agent consistently fell short.

**Arm D — Short-term context retention across sessions**

A focused two-session experiment. In Session 1, the analyst runs a screening batch: compounds are evaluated, ADMET gates fire, some compounds are overridden with a stated reason, QC thresholds are adjusted. In Session 2 — run the following day with a new compound batch — BioMate opens with its memory of Session 1 active.

Three specific questions are tested:

1. **Does BioMate avoid re-suggesting compound classes that were rejected in Session 1?** If the analyst rejected all compounds above a certain molecular weight with a stated reason, does BioMate apply that as a filter in Session 2 without being told again?
2. **Does BioMate correctly recall override decisions?** If the analyst overrode a hERG flag in Session 1 with a justification, does BioMate surface that context when a similar compound appears in Session 2 — rather than treating it as a fresh flag?
3. **Does context-informed session opening save time?** The analyst rates how much re-orientation they needed at the start of Session 2 with vs. without active memory.

A control condition runs the same two sessions with memory disabled — each session starts fresh.

*Primary metric:* Rejected-class filter accuracy (did BioMate correctly suppress re-suggestions?); override recall accuracy (did it surface the right prior decision?); analyst-rated re-orientation time; analyst preference for memory-on vs. memory-off.

---

## Division of Labor

| Task | Partner | BioMate |
|---|---|---|
| Compound library and target structure | ✓ | |
| Ground-truth ADMET and docking results (existing) | ✓ | |
| Campaign history for memory seeding (Arm D) | ✓ | |
| Analyst participation (Arms B, C, D) | ✓ | |
| Structured interviews | ✓ | |
| BioMate platform execution and infrastructure | | ✓ |
| Campaign memory system implementation (pre-study) | | ✓ |
| Compute costs for all BioMate analyses | | ✓ |
| Discordance root cause analysis (Arm A) | ✓ | ✓ |
| Suggestion concordance analysis (Arm D) | ✓ | ✓ |
| Statistical analysis | ✓ | ✓ |
| Manuscript preparation | ✓ | ✓ |

**Pre-study engineering commitments (Month 1, BioMate):**
- Session memory module: structured storage of compound outcomes, ADMET gate results, and override decisions per session; retrieval layer for context-informed session opening
- Memory audit trail: all retrieved context logged and attributable to the specific prior session it came from
- Memory on/off toggle for the control condition in Arm D

---

## Expected Outputs

**Primary manuscript:** An evaluation paper covering all four arms. Partner site as co-first or senior author on the scientific evaluation; BioMate as co-corresponding author on the platform and self-adaptation methodology. Target: *Journal of Chemical Information and Modeling* or *Nature Chemical Biology*.

**Secondary outputs:**
- A benchmark dataset: de-identified compound set with BioMate ADMET and docking outputs, expert rankings, and session-level suggestion concordance data over time — deposited for the community as the first longitudinal AI-assisted drug screening benchmark
- Conference presentation at ACS or AACR on AI-assisted compound prioritisation with adaptive campaign memory

---

## Timeline

| Month | Milestone |
|---|---|
| 1 | Campaign memory module built and tested; compound library and target confirmed; campaign history loaded; analysis plan finalised |
| 2 | Arm A concordance study on full compound set |
| 3 | Arm B efficiency study; Arm C research intelligence (embedded in Arm B sessions) |
| 4 | Arm D two-session memory experiment (memory-on vs. memory-off control) |
| 5 | Full results compiled; root cause analysis |
| 6 | Manuscript draft; review; submission |

---

## Data and Confidentiality

Proprietary compound structures remain under the partner's data governance. BioMate analyses run on de-identified or structure-masked data where required. Campaign memory data (ADMET outcomes, analyst decisions, override notes) is retained only within the partner's data environment; no proprietary screening data leaves the partner's infrastructure. All campaign memory is exportable and deletable at any time.

---

## Contribution to the Community

**1. The first longitudinal evaluation of AI-assisted drug screening**

Almost all published evaluations of AI screening tools are cross-sectional — a single batch of compounds, a single session. This study runs over weeks of a real campaign, producing the first time-series measurement of whether an AI platform improves within a project as context accumulates. That evaluation design is applicable to any domain where analysts work on extended projects, not just drug discovery.

**2. Evidence-graded QC as a research variable**

BioMate's ADMET and docking QC gates are explicitly evidence-tiered. Arm A measures whether automated, anchored QC changes which compounds get advanced compared to informal threshold application. If it does — particularly for borderline compounds — that has direct implications for how preclinical screening reproducibility should be evaluated.

**3. A controlled measurement of short-term context retention in a scientific AI assistant**

Arm D provides a clean, reproducible measurement of whether session-to-session memory changes analyst behavior and saves time — using a within-study control condition (memory on vs. off) that isolates the memory effect from other platform differences. This is a direct contribution to the open question of what forms of AI memory are practically useful in scientific work, grounded in current memory architecture research (Jiang et al. arXiv:2512.16301, 2025; Zep arXiv:2501.13956, 2025).

---

*Draft for discussion — BioMate AI & UT Southwestern Simmons Cancer Center, March 2026*
