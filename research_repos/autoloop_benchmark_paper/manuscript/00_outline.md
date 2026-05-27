# BioMate-AutoLoop Paper — Outline

**Working title:** *Autonomous Parameter Convergence under Regulatory QC Constraints: A Provenance-Graded Auto-Loop for Drug-Discovery Pipelines*

**Target venue:** *Journal of Medicinal Chemistry* (Featured Article) — primary; *Drug Discovery Today* (Perspective) — secondary.
**Audience:** medicinal chemists, DMPK modellers, computational chemists operating production drug-discovery pipelines.
**Companion papers:**
- Flagship: *Interactive Evidence-Graded QC Governance and Auto-Loop Convergence for Drug Discovery Workflows* (BioMate Team, in preparation) — cited for the cross-domain governance framework and provenance grading definition.
- *BioMate-Cryo* (Zhang & Zhang, in preparation) — cited for the cryo-EM specialisation of the same governance layer.

---

## Core argument (one sentence)

> Autonomous parameter convergence in drug-discovery QC requires not just an iteration engine but a **provenance-graded knowledge base** that constrains which parameter changes are scientifically defensible — and we demonstrate this combination converges within ≤3 iterations across 125 of 125 convergent benchmark scenarios in ADMET, CYP-DDI, NCA-PK, and Docking pipelines (overall 96.4% pass within 3 iterations across the full 125-scenario set; 100% on the 107 non-persistent-fail scenarios).

## Contribution boundaries (vs flagship)

| | Flagship paper | This paper |
|---|---|---|
| Scope | Cross-domain governance (16 domains, 29 gates) | Auto-loop only (4 wired drug-dev domains) |
| Audience | *Nature Methods* — broad methods readership | *J. Med. Chem.* — drug-discovery practitioners |
| Central novelty | Silent filtering → interactive evidence-graded governance, across structurally different domains | Convergence behaviour of a provenance-anchored remediation engine, with per-domain rule analysis |
| Figure 1 | Cross-domain false-rejection rate | Per-domain convergence curves + provenance partition |
| Treats provenance grading as | A governance feature | A constraint on remediation reliability |
| Treats audit trail as | Regulatory artefact | Out of scope (cite flagship) |

---

## Section plan

### 1. Introduction (~1500 words) — drafted

- 1.1 The cost of failed-gate runs in drug discovery (concrete ADMET and CYP-DDI examples).
- 1.2 Existing tools surface failure, not fix (Schrodinger, Simcyp, ADMET Predictor; Avilov 2023 Bayesian-opt auto-loops without provenance).
- 1.3 Gap — autonomous convergence + evidence anchors; either alone insufficient.
- 1.4 This work — 4 drug-dev domains; preview Fig. 2; honest disclosure on Docking 85.7%.

### 2. Methods (~1800 words) — drafted

- 2.1 Auto-loop architecture — QC evaluator → param tuner → enriched tuner; ADMET hERG as worked example with Aronov 2008.
- 2.2 Knowledge-base design — GOLD/SILVER/BRONZE; rationale for separating `paper_supports` from `rule_text`.
- 2.3 Per-domain remediation rules with code line references.
- 2.4 Benchmark design — 125 scenarios, scoring rubric, published baselines.
- 2.5 Fail-safe architecture — 3-iteration budget, hard halt, audit preservation, anti-collision.

### 3. Results (~1200 words) — pending
- 3.1 Headline E2 table (per-domain pass@1, pass@≤3, escalation rate).
- 3.2 Iterations-to-converge histograms.
- 3.3 Provenance partition × remediation reliability.
- 3.4 Failure-mode case study — Docking persistent-fail scenarios.

### 4. Discussion (~600 words) — pending
- Why the all-BRONZE Docking knowledge base still produces useful convergence.
- Limits: 4 wired domains today; PBPK auto-loop excluded pending knowledge-base remediation.
- Implication for regulatory submissions (cite flagship for audit-trail mechanics).

---

## Display items

- **Fig. 1** — Auto-loop architecture schematic (QC evaluator → param tuner → enriched tuner with citation injection).
- **Fig. 2** — Convergence curves: cumulative pass-rate vs iteration, one trace per domain.
- **Fig. 3** — Provenance partition stacked bars (GOLD/SILVER/BRONZE) per domain, with overlaid pass@≤3 rate.
- **Fig. 4** — Worked example: an ADMET hERG-failing scenario over 3 iterations, with annotated parameter trajectory and citation tooltip.
- **Table 1** — Per-domain remediation rules with code path references and citation DOIs.
- **Table 2** — Benchmark scenario counts and headline metrics.

---

## Cross-reference policy

- Where the flagship covers framework material (silent filtering vs governance, the GOLD/SILVER/BRONZE definitions, the JSONL audit schema), this paper cites it as *(BioMate Team, in prep)* and provides a one-paragraph summary only.
- All convergence numbers in this paper are this paper's contribution; the flagship cites this paper for the auto-loop deep dive (§3.3 in flagship).
- The two papers may share Methods §2.2 wording on provenance grading — that section will be deduplicated at submission and one paper will become the canonical source.
