# Flagship Paper — Outline

**Working title options:**
1. *Interactive Evidence-Graded QC Governance and Auto-Loop Convergence for Drug Discovery Workflows*
2. *From Silent Filtering to Auditable Governance: Cross-Domain QC and Autonomous Remediation in Computational Drug Discovery*
3. *BioMate: An Interactive, Evidence-Graded Quality-Control Layer for Drug-Discovery Pipelines with Autonomous Parameter Convergence*

**Recommended:** Option 1 (matches user-supplied tasking; concise; foregrounds two contributions).

**Target venue:** Nature Methods (Article, ~3,000–4,000 words main text, 5–6 display items).
**Classification:** Methods + application demonstration (cross-domain).
**Companion paper:** *BioMate-Cryo: Evidence-Graded Interactive QC Governance for Automated Single-Particle Cryo-EM* (Zhang & Zhang, manuscript in preparation) — cited from §1.2 and §3.

---

## Core argument (one sentence)

> BioMate replaces silent QC filtering with **interactive, evidence-graded governance** plus **autonomous auto-loop remediation**, and we demonstrate the first cross-domain implementation across cryo-EM, ADMET, drug–drug interaction, non-compartmental PK, docking, and PBPK.

## Two contributions (must be kept separable in the prose)

1. **Interactive evidence-graded QC governance** — gate halts, GOLD/SILVER/BRONZE provenance, JSONL audit. Applies to 16 domains in production today (5 auto-loop-wired, 10 gate-only display, 1 cryo-EM specialised).
2. **Autonomous auto-loop convergence** — rule-based remediation engine that iterates parameter space until gates pass or budget exhausts. Applies to 5 wired domains.

These are *complementary*, not redundant. Governance bounds *what* the system is allowed to silently change; auto-loop is *how* it converges within those bounds.

---

## Abstract structure (~200 words; to draft after §3)

- **Context (1–2 sentences).** Computational drug discovery pipelines apply QC thresholds at every stage, but the dominant pattern is silent filtering — exposures, compounds, or model parameters fail thresholds and are dropped without explanation, audit trail, or evidence grading.
- **Gap (1–2 sentences).** Three architectural gaps: protocol blindness across domains; no actionable diagnostics at gate failure; no provenance grading distinguishing peer-reviewed thresholds from operational heuristics.
- **Approach (2–3 sentences).** BioMate orchestrates 226 drug-discovery workflows behind a single QC governance layer: 29 gates across 16 domains, graded GOLD (22 verbatim regulatory/peer-reviewed), SILVER (5 community convention) or BRONZE (2 operational heuristics), each surfacing a citation tooltip to the user. For 5 domains (ADMET, CYP-DDI, NCA-PK, docking, PBPK) the same gate signal feeds an auto-loop remediation engine that proposes parameter changes and converges within a bounded number of iterations.
- **Result (2–3 sentences).** `[TBD pending E1]` false-rejection rate reduction × profile × domain; `[TBD pending E2]` auto-loop convergence within ≤3 iterations at `[TBD]`% across `[TBD]` benchmark scenarios; `[TBD pending E3]` cross-grade remediation reliability; `[TBD pending E4]` audit-trail field coverage.
- **Implication (1 sentence).** First cross-domain, evidence-graded, audit-trailed QC framework compatible with 21 CFR Part 11 and emerging FDA AI/ML SaMD guidance.
- **Boundary (1 sentence).** Two of 29 thresholds remain BRONZE operational heuristics; full enumeration of these and their proposed paths to SILVER are in supplementary materials.

---

## Section plan

### 1. Introduction (~1500 words) — drafted in MANUSCRIPT_DRAFT.md
- 1.1 The QC governance gap across drug discovery
- 1.2 Current automated tools across the industry perform silent filtering
- 1.3 Three unaddressed gaps (protocol blindness, no actionable diagnostics, no evidence provenance)
- 1.4 BioMate's contribution: cross-domain interactive evidence-graded governance + autonomous auto-loop

### 2. Methods (~1200 words)
- 2.1 Cross-domain pipeline orchestration (Nextflow + AWS Batch backend; common SSE event bus)
- 2.2 The gate evaluator architecture (`qc_trace_monitor.py` → dual emitters)
- 2.3 Evidence tier framework (GOLD/SILVER/BRONZE definitions + a worked example per tier)
- 2.4 Auto-loop remediation engine (rule-based per domain; budget + termination conditions)
- 2.5 Audit-trail schema (JSONL, 21 CFR Part 11 alignment)
- 2.6 Benchmark design across four domains:
  - E1: false-rejection rate (cryo + HTS + LNP)
  - E2: auto-loop convergence (ADMET / CYP-DDI / NCA-PK / docking / PBPK)
  - E3: provenance grade × remediation reliability
  - E4: audit completeness

### 3. Results (~1200 words)
- 3.1 Coverage at a glance (table: 29 gates × 16 domains × evidence grade × auto-loop wired)
- 3.2 E1 — false-rejection elimination across domains (Fig. 1)
- 3.3 E2 — auto-loop convergence (Fig. 2)
- 3.4 E3 — provenance grade × remediation reliability (Fig. 3)
- 3.5 E4 — audit completeness vs comparator systems (Fig. 4)
- 3.6 Case study — IND §2.6.1 narrative generation with full audit chain

### 4. Discussion (~400 words)
- The 2 BRONZE gates: why they remain operational heuristics and the proposed path to SILVER
- Boundaries: domains we do *not* claim (free-text generation, image analysis without ground truth)
- Regulatory alignment (21 CFR Part 11, FDA AI/ML SaMD draft guidance 2024)

### 5. Data availability / code availability / acknowledgements

---

## Display items

- **Fig. 1 (E1) —** False-rejection rate × profile × domain. Three panels: cryo (membrane vs purified, from companion paper), HTS (`[TBD]`), LNP (`[TBD]`).
- **Fig. 2 (E2) —** Auto-loop convergence curves per domain (ADMET, CYP-DDI, NCA-PK, docking, PBPK); iterations-to-pass histogram.
- **Fig. 3 (E3) —** Provenance grade vs remediation reliability scatter; GOLD gates expected to dominate top-right.
- **Fig. 4 (E4) —** Audit-trail field coverage radar: BioMate vs Nextflow-Tower vs Galaxy vs KNIME.
- **Table 1 —** Full gate catalog (29 rows × {domain, gate, metric, evidence tier, citation DOI, auto-loop wired?}).
- **Table 2 —** Auto-loop remediation rule set, per domain.
