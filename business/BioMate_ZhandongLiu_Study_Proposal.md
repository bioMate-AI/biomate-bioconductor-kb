# Joint Study Proposal
## AI-Assisted Multi-Modal Genomics for Rare Neurological Disease

**Proposing parties:** BioMate AI · Dr. Zhandong Liu Lab, Baylor College of Medicine  
**Target venue:** Nature Methods / Genome Biology / Bioinformatics (Oxford) — tools & resources  
**Initial evaluation:** 1 week  
*March 2026 · Draft for discussion*

---

## Executive Summary

BioMate is an AI-native life science research platform. A researcher describes an analysis in plain language — BioMate selects the appropriate tools, connects them, runs them, and returns a consolidated result. The platform covers the full range of modern multi-omics analysis and is designed to be extensible: research groups can integrate their own tools and pipelines into BioMate, so specialized methods gain the same natural language interface, literature assistance, and session memory as everything else on the platform.

This study proposes to evaluate BioMate in one of the most demanding settings in computational genomics — rare neurological disease diagnosis — using the Liu lab's multi-modal analysis workflows as the benchmark. The lab's own tools (PolyAMiner-Bulk, SEAGAL) will be integrated into BioMate for the study. Four questions are examined: output concordance with established pipelines, efficiency and convenience across analysts, usefulness of the integrated literature assistant, and the effect of session memory on repeated analytical work.

| | |
|---|---|
| **Partner** | Dr. Zhandong Liu Lab, Baylor College of Medicine |
| **Analysis domains** | Rare disease genomics, transcriptomics, chromatin profiling, single-cell, alternative polyadenylation |
| **Data** | Public benchmark cohorts (Phase 1); de-identified patient cohorts (Phase 2) |
| **Initial trial** | 1 week, public data only, no IRB required |
| **Compute cost to lab** | $0 |
| **Output** | Peer-reviewed tools and resources paper; target *Genome Biology* or *Nature Methods* |

---

## Background and Motivation

Diagnosing rare neurological disease from multi-modal genomic data requires integrating evidence across variant calls, transcriptomic outliers, splicing signals, and phenotype information. The Liu lab has built and published leading AI-assisted systems for this task — RareCollab, LA-MARRVEL, PolyAMiner-Bulk, and SEAGAL — each addressing a specific layer of this problem.

BioMate operates as the computational platform that connects these layers. A researcher describes what they need; BioMate orchestrates execution across the relevant tools, surfaces literature context within the session, and carries analyst decisions forward across cases through session memory. The lab's own published tools become part of this environment once integrated, extending their reach to any analysis that touches them.

The study evaluates whether using BioMate as the execution and interaction layer for this work changes outcomes: are results concordant with current pipelines, is analysis faster and easier for analysts at all experience levels, does the literature assistant change how findings are interpreted, and does session memory reduce the repeated overhead of decision-making across similar cases?

---

## Research Questions

1. **Output concordance:** When BioMate runs the same multi-modal analyses on the same data, how closely do the results agree with existing pipelines? Where they differ, what is the cause?

2. **Efficiency and convenience:** Does working through BioMate reduce the time and effort of executing a rare disease workup — across analysts at different experience levels, and across standard and non-standard analysis types?

3. **Research intelligence usefulness:** When analysts use BioMate's literature assistant during a session — to understand a result, explore a gene, or find relevant precedent — does it change decisions or save time?

4. **Session memory and self-adaptation:** When BioMate carries forward analyst decisions and context from a prior session, does it reduce re-orientation time and prevent the same work from being repeated on subsequent cases?

---

## Study Design

### Datasets

**Phase 1 — public data (no IRB required):** Published benchmark cohorts with validated results for transcriptomic outlier detection, variant analysis, and chromatin profiling. BioMate runs the same analyses on the same inputs and results are compared directly.

**Phase 2 — internal cohorts:** De-identified rare neurological disease patient cases with existing ground-truth results. The lab defines which cases to include.

### Phase 1 — One-Week Trial

The first week runs on public data only. No patient data, no IRB amendment, no infrastructure change on the lab's side. A few lab members spend one to two hours running analyses through BioMate and giving structured feedback.

Session memory is also tested: an analyst runs two short back-to-back sessions — the first establishes decisions and preferences; the second opens with memory active. This takes 30 minutes and produces a concrete first answer on whether memory works as expected.

**Measurable pass/fail gates for the trial week:**

| Metric | Target | Measurement |
|---|---|---|
| Workflow quality | ≥ 80% of analyses complete without manual parameter correction | Platform telemetry |
| Time-to-result | ≤ 30 minutes query-to-result for a standard bulk RNA-seq DE pipeline | Backend timestamp |
| QC defensibility | ≥ 70% of outputs rated publication-ready by a domain-expert lab member | Structured exit form |
| Hallucination incidents | 0 — no commands issued for non-existent tools or invalid parameters | QC log audit |

These gates apply to the trial week. Results against each gate are shared at the go/no-go debrief. If the trial meets all four gates, the full study proceeds. If any gate is missed, BioMate commits to a specific remediation before the full study begins.

The week produces a shared go/no-go decision for the full study.

### Phase 2 — Full Study

**Arm A — Output concordance**

BioMate runs the same multi-modal analyses as the lab's established pipelines on the same inputs. Variant rankings, expression outlier calls, and splicing signals are compared. Discordances are classified by type and root cause.

*Primary metric:* Concordance rate across modalities; discordance classification breakdown.

*Success threshold:* ≥ 70% of outputs rated defensible for a research manuscript (QC defensibility gate); 0 hallucinated tool names or invalid parameters across all sessions.

**Arm B — Efficiency and convenience**

Analysts at different experience levels run the same analysis tasks twice — once with current tools, once through BioMate. Tasks include both routine workups and analyses that involve non-standard data types. Time-to-result, number of manual steps, output completeness, and errors are measured. A structured interview after each session captures analyst experience.

*Primary metric:* Time-to-result; number of manual steps; analyst-reported friction and trust by experience level and task type.

*Success threshold:* ≥ 80% of BioMate sessions complete without manual correction (workflow quality gate); average time-to-result ≤ 30 minutes for standard RNA-seq pipelines (time-to-result gate).

**Arm C — Research intelligence usefulness**

BioMate's literature assistant is available throughout Arm A sessions. Analysts use it freely — to understand a result, look up a gene, or find relevant precedent. A log captures which queries were made, whether responses were useful, and whether any changed a decision.

*Primary metric:* Fraction of queries rated useful; decisions changed by a response; query categories where the assistant fell short.

**Arm D — Session memory and self-adaptation**

A controlled two-session experiment. In Session 1, an analyst runs a workup and makes specific decisions about how to handle the data. In Session 2 — a new case of the same type — BioMate opens with memory of Session 1 active. Three measurements: whether prior decisions are surfaced without re-entry, whether previously rejected approaches are avoided, and how long re-orientation takes compared to a memory-off control.

*Primary metric:* Decision recall accuracy; re-orientation time; analyst preference for memory-on vs. memory-off.

---

## Division of Labor

| Task | Lab | BioMate |
|---|---|---|
| Public benchmark data (Phase 1) | | ✓ |
| Patient cohort data and de-identification (Phase 2) | ✓ | |
| Existing ground-truth results | ✓ | |
| Analyst participation | ✓ | |
| Platform execution and compute | | ✓ |
| Integration of lab's tools (PolyAMiner-Bulk, SEAGAL) | | ✓ |
| Discordance analysis and manuscript preparation | ✓ | ✓ |

---

## Data and Ethics

Phase 1 uses only publicly available data — no IRB required. Phase 2 runs on de-identified patient data under the lab's existing IRB approvals. No patient data is retained by BioMate outside the analysis session.

---

## Contribution to the Community

**1. A capability boundary map for AI-assisted rare disease genomics**

Which analysis types can an AI platform execute with results a domain expert accepts, and which still require human judgment? This study produces a systematic, empirically grounded answer for multi-modal rare neurological disease genomics — useful to any group building or evaluating similar tools.

**2. A measured efficiency and convenience study**

Whether AI-assisted platforms reduce analyst burden — for whom and for which tasks — is not well established. This study measures it directly across experience levels and analysis types, producing a generalizable evaluation framework.

**3. A naturalistic assessment of embedded AI research assistance**

Arm C captures how analysts actually use a literature assistant during real analyses — what they ask, what they act on, what they ignore. This behavioral data is more informative for platform design than any scripted benchmark.

**4. A controlled measurement of session memory in a scientific AI platform**

Arm D isolates the effect of cross-session memory using a within-study on/off control. The result — whether persistent context measurably reduces analyst overhead across recurring case types — applies broadly to AI-assisted scientific workflows.

---

*Draft for discussion — BioMate AI & Liu Lab, March 2026*
