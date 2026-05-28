# Autonomous Parameter Convergence under Regulatory QC Constraints: A Provenance-Graded Auto-Loop for Drug-Discovery Pipelines

**Status:** Draft — 2026-05-27 (§1 + §2 only; §3 Results and §4 Discussion pending finalised E2 reconciliation).
**Target venue:** *Journal of Medicinal Chemistry* (Featured Article); *Drug Discovery Today* (Perspective) as secondary.
**Companion papers:**
- BioMate Team. *Interactive Evidence-Graded QC Governance and Auto-Loop Convergence for Drug Discovery Workflows.* Manuscript in preparation. (Hereafter, **the flagship paper**.)
- Zhang Y, Zhang Y. *BioMate-Cryo: Evidence-Graded Interactive QC Governance for Automated Single-Particle Cryo-EM.* Manuscript in preparation.

---

## Authors

Yaoyun Zhang¹\*, Yuhan Zhang²\* *(placeholder — confirm with corresponding author)*

¹ BioMate AI
² Department of Structural Biology, St. Jude Children's Research Hospital, Memphis, TN, USA
\*Equal contribution.

---

## Abstract

*[To be drafted after §3. Will lead on the headline result: 96.4% gate-pass within ≤3 iterations across 125 benchmark scenarios spanning ADMET, CYP-DDI, NCA-PK, and ligand docking; 0% escalation in three of four domains; 14.3% by-design escalation in docking, traceable in audit trail.]*

---

## 1. Introduction

### 1.1 The cost of failed-gate runs in drug discovery

In production drug-discovery operations, the unit of waste is not a failed assay or a failed compound — it is a *failed-gate iteration*. A medicinal chemist runs a virtual ADMET panel on a 1,200-compound library; the panel reports that 740 compounds fail the hERG safety gate at the conventional IC50 ≤ 10 µM cutoff; the chemist has to decide which physicochemical filters to tighten before re-screening. A DMPK modeller runs a static drug–drug interaction prediction for a CYP3A4 inhibitor; the calculation returns a victim AUC-ratio R1 of 1.34, well above the FDA 2020 CLINICAL_STUDY trigger of 1.1¹; the modeller must propose a revised steady-state Cmax (C_max,ss) that the project team will accept. A non-compartmental PK analyst runs an NCA fit on a sparse-sampling Phase I dataset; the fit reports 28% AUC extrapolation beyond the FDA 2003 Bioavailability and Bioequivalence guidance limit of 20%²; the analyst must redesign the sampling schedule before the result can be used in a regulatory filing.

In each of these cases the computational tool has done exactly what it was built to do — it has reported a metric value, evaluated it against a threshold, and flagged the failure. What it has not done is the work the user actually needs done next: identify which input parameter caused the failure, propose a change with a defensible scientific justification, and re-run the calculation. That work — *remediation* — is left to expert judgment, and expert judgment is the scarce resource. A senior medicinal chemist working a single virtual library through three or four ADMET filter iterations consumes one to two days of senior staff time; a DMPK modeller iterating a static DDI calculation may turn over the cycle in an hour, but does so by drawing on tacit knowledge that is not transferable to a junior colleague or auditable in retrospect. Multiplied across the hundreds of compound–assay pairs and dozens of model-parameter sweeps that a single discovery program runs in a quarter, the cost of designer-in-the-loop remediation is material — both in elapsed wall time and in concentration of decision-making authority in a small number of practitioners.

The same pattern repeats in induced-fit docking (when no valid pose is generated, the chemist must decide whether to expand the binding box, raise exhaustiveness, or switch from Glide SP to XP), in *in vitro–in vivo* extrapolation (when total clearance comes out implausibly low, the modeller must choose between revising microsomal recovery factors or the unbound-fraction estimate), and in physiologically based pharmacokinetic modelling (when the mass-balance recovery falls outside the conventional ±5% tolerance, the user must locate the offending tissue compartment). In each case the *evaluation* is automated, the *remediation* is not, and the bottleneck has migrated to the operator.

### 1.2 Existing tools surface failure, not fix

Commercial and academic platforms that dominate the field — the Schrödinger Small-Molecule Discovery Suite for docking and ADMET prediction, Certara Simcyp for population PBPK, Simulations Plus ADMET Predictor for property prediction, Certara Phoenix WinNonlin for NCA — share an architectural choice: they report whether a calculation passes or fails its acceptance criteria, but they do not propose, score, or execute remediations. When the user wants to iterate, they iterate manually. The implicit assumption is that the user is an expert who knows what to change; in practice, the assumption holds for senior staff and breaks for everyone else.

A growing literature on autonomous parameter search in chemistry pipelines partially addresses this gap. Bayesian-optimisation frameworks for high-throughput screening parameter selection³ and design-of-experiments engines for medicinal-chemistry library design demonstrate that closed-loop iteration is feasible. What these systems do not do — and what distinguishes BioMate's auto-loop — is justify the parameter change. A Bayesian optimiser proposes a candidate point because the acquisition function favours it; the system cannot point to a peer-reviewed paper, a regulatory guidance document, or a community consensus that says "compounds at this logP have lower hERG affinity." For exploratory medicinal-chemistry settings the absence of justification is tolerable; for downstream stages whose outputs must enter a regulatory submission, it is disqualifying. The FDA's 2024 draft guidance on AI/ML-based software as a medical device and the EMA's 2024 reflection paper on artificial intelligence in the medicinal product lifecycle both require that automated decisions be traceable to a documented evidence basis. Bayesian-only remediation cannot meet that requirement.

### 1.3 Gap: autonomous parameter convergence with evidence anchors

The contribution of this work is to combine two capabilities that are routinely separated. The first is *convergence* — a remediation engine that, given a failed-gate condition, proposes and executes a parameter change and re-evaluates the gate, iterating until the gate passes or a bounded budget is exhausted. The second is *evidence anchoring* — every remediation rule is attached to a primary publication or regulatory document, classified by how directly that publication supports the operational threshold actually enforced, and surfaced to the user in the audit trail. Either capability alone is insufficient. Convergence without provenance produces results that the regulator and the project team cannot defend. Provenance without convergence is the status quo, in which a curated knowledge base sits unused while an analyst tunes parameters by hand.

The flagship paper describes the cross-domain governance framework within which our auto-loop operates — the gate evaluator, the GOLD/SILVER/BRONZE evidence grading, the JSONL audit schema, and the policy that auto-loop is permitted to act only on rules whose effect on the failing metric is mechanistically understood (BioMate Team, in preparation). The present paper takes the auto-loop as its central object of study, deepens the per-domain biology, and reports convergence behaviour at scenario granularity for four drug-discovery domains in which auto-loop is wired into production.

### 1.4 This work

We present the BioMate auto-loop across four drug-development domains. **ADMET** auto-loop tightens logP and molecular-weight filters in response to hERG, drug-induced liver injury (DILI), and Ames mutagenicity gate failures, using a knowledge base anchored on Redfern 2003⁴ and Bowes 2012¹⁰ (hERG 10 µM cutoff), Waring & Johnstone 2007¹¹ (quantitative logP/IC50 regression for the logP remediation), Aronov 2008¹² (*Curr Opin Drug Discov Devel*, property-tuning framework), Lammert 2010⁵ (DILI), and Kazius 2005⁶ (Ames). **CYP-DDI** auto-loop reduces the assumed steady-state Cmax in response to victim-AUC-ratio (R1) or net-effect (R2) gate failures, anchored on the FDA 2020 *In Vitro* Drug Interaction Studies guidance¹. **NCA-PK** auto-loop extends the last-sampling time and increases terminal-phase points in response to AUC-extrapolation or terminal-slope-coverage failures, anchored on the FDA 2003 BA/BE guidance². **Docking** auto-loop expands the binding box and increases sampling exhaustiveness (and, for Glide, escalates from standard-precision to extra-precision scoring) in response to no-valid-pose or insufficient-binding-score failures.

On 125 benchmark scenarios designed to fail one or more gates by construction — drawn from TDC ADMET Group conventions for ADMET, the FDA DDI guidance test matrix for CYP-DDI, the FDA NCA literature for PK, and DUD-E-style decoys for docking — the auto-loop achieves 100% gate-pass within ≤3 iterations in three domains (ADMET, CYP-DDI, NCA-PK) and 85.7% in docking (Figure 2). The 14.3% docking escalation rate is structural, not accidental: five scenarios in the docking benchmark are constructed as persistent-fail by design (decoys with no plausible binding mode against the target site), and we retain them deliberately so the audit trail demonstrates that auto-loop escalates rather than fabricating a result. Five drug-discovery domains are wired for auto-loop in production today; ten further domains carry gate evaluation with full evidence tooltips but no autonomous remediation, because the appropriate response at gate failure is an operator decision the engine cannot make safely. We disclose this boundary in §4.

The remainder of the paper describes the auto-loop architecture and the provenance grading (§2.1–2.2), the per-domain remediation rules with code line references (§2.3), the benchmark design (§2.4), and the fail-safe guarantees that prevent the engine from converging on an unphysical parameter (§2.5).

---

## 2. Methods

### 2.1 Auto-loop architecture

Each auto-loop module in BioMate follows the same three-component shape: a **QC evaluator** that translates a workflow step's structured output into a `PhaseQCResult` containing gate-by-gate verdicts (`PASS`, `WARN`, `HALT`); a **parameter tuner** that maps each `HALT` gate to a concrete parameter change on the workflow's parameter object; and an **enriched tuner** that wraps the parameter tuner with citation injection from the domain knowledge base. The orchestrator runs the workflow phase, calls the evaluator, and — if any gate halts — calls the enriched tuner to produce a new parameter set and a list of `Remediation` records, then re-runs the phase. The cycle terminates when the evaluator reports no halts, when the iteration budget is exhausted (default: three iterations), or when the tuner returns no parameter changes (gate has no remediation handler, or all changes are blocked by guard floors).

To make this concrete, consider the ADMET hERG gate. The QC evaluator reads the predicted hERG IC50 for each compound in a candidate library; if the worst-case IC50 falls below the safety threshold (10 µM, GOLD-anchored on Redfern 2003⁴ and Bowes 2012¹⁰), the evaluator emits a `HALT` with `value` set to the offending IC50 and `threshold` set to 10. The parameter tuner's `_fix_herg` handler (`backend/experiments/admet_autoloop/param_tuner.py:99–121`) reduces `logp_max` by 0.5 and, if `mw_max_da` exceeds the Lammert 2010 high-risk threshold of 400 Da, also reduces it by 10%. The rationale string returned with the remediation is grounded in the Waring & Johnstone 2007¹¹ logP↔hERG-IC50 regression (~2-fold IC50 increase per unit logP reduction), which predicts that a 0.5-unit reduction in logP raises mean IC50 by approximately 40% — enough, in most starting libraries, to recover compliance at the next iteration without exhausting the candidate pool. If logP reduction alone is insufficient, the secondary handler escalates to MW reduction and basic-amine attenuation per the Aronov 2008¹² *Curr Opin Drug Discov Devel* "Tuning out of hERG" framework. The enriched tuner appends the citation, the GOLD/SILVER/BRONZE provenance grade, and the relevant DOI to the rationale string, so that downstream consumers (audit log, LLM-driven explanation, regulatory submission text generators) receive both the operational decision and the evidence that justifies it.

### 2.2 Knowledge-base design: GOLD/SILVER/BRONZE provenance grading

The auto-loop draws every remediation rationale from a per-domain knowledge base whose schema separates two fields that are routinely conflated in scientific software: what the cited paper actually states, and what the operational rule actually enforces. The `KnowledgeEntry` dataclass (`backend/experiments/admet_autoloop/knowledge_base.py:46`) carries `paper_supports` (the factual content of the cited paper) alongside `rule_text` (the threshold that BioMate enforces), plus a `provenance` tier that grades how directly the paper supports the rule. We use the framework introduced in the BioMate auto-loop provenance audit (internal report, 2026-05-22) and summarised in the flagship paper (BioMate Team, in preparation):

> **GOLD** — the cited paper states the threshold (or a trivially derivable form of it) verbatim. A reader of the paper would arrive at the same numeric cutoff. Example: the FDA 2020 DDI guidance¹ states R1 ≥ 1.1 as the CLINICAL_STUDY trigger in its decision-tree figure; the BioMate gate uses 1.1.
>
> **SILVER** — the cited paper supports the underlying mechanism or concept; the exact numeric threshold is community/operational convention that has hardened around the publication by citation drift. Example: Waring & Johnstone 2007 establishes that lower logP correlates with weaker hERG affinity, but the 10 µM IC50 safety cutoff is the regulatory convention from Redfern 2003 (30× margin over free Cmax) and the cross-pharma operational consensus from Bowes 2012 — not a number that Waring & Johnstone quoted as an enforceable cutoff.
>
> **BRONZE** — operational heuristic; the cited paper is related context only and does not prescribe the cutoff. The rule is retained because it is the best operational practice we have, but it must not be represented in downstream prose as if the cutoff were a published value.

The schema enforces honesty by construction: a developer who copies a community-folk-cutoff into the knowledge base must classify it as SILVER (or BRONZE) and cannot label it GOLD without supplying the verbatim text from the cited document. This separation is the architectural fix for the failure mode — paraphrase rendered as quotation — documented in `docs/20260522_AUTOLOOP_EVIDENCE_PROVENANCE_AUDIT.md`. The flagship paper develops the rationale for this grading in the regulatory context (FDA 2024 draft AI/ML SaMD guidance, EMA 2024 AI reflection paper); we cite that discussion here and do not duplicate it.

### 2.3 Per-domain remediation rules

We summarise the production rule set for each of the four wired domains. Code-line references point to the `param_tuner.py` source so that reviewers can verify the rule against the corresponding `KnowledgeEntry` in `knowledge_base.py`.

**ADMET** (`backend/experiments/admet_autoloop/param_tuner.py`). Four handlers: `_fix_herg` (lines 99–121) reduces `logp_max` by 0.5 with a guard floor of 0.5; if `mw_max_da` > 400 Da it is also multiplied by 0.9. Citations: Redfern 2003⁴ + Bowes 2012¹⁰ (GOLD for the 10 µM cutoff), Waring & Johnstone 2007¹¹ (GOLD for the logP/IC50 regression), Aronov 2008¹² *Curr Opin* (SILVER for the property-tuning framework). `_fix_dili_probability` (lines 123–136) clamps `logp_max ≤ 4.0` and `mw_max_da ≤ 400` (the Lammert 2010 high-risk boundary). `_fix_dili_risk_level` (lines 138–148) shares the same `logp_max ≤ 4.0` clamp. `_fix_ames` (lines 150–168) enables Kazius-2005 structural-alert filtering and reduces `num_candidates` by 10 (guard floor 10), concentrating screening budget on cleaner scaffolds. The full ADMET knowledge base partitions 3 GOLD / 3 SILVER / 0 BRONZE across six entries.

**CYP-DDI** (`backend/experiments/cyp_ddi_autoloop/param_tuner.py`). Two handlers: `_fix_clinical_isoforms` (lines 57–65) halves `cmax_ss_uM` (guard floor 0.05 µM) when one or more isoforms cross the FDA 2020 CLINICAL_STUDY threshold R1 ≥ 1.1; `_fix_investigate_isoforms` (lines 67–75) applies a 30% reduction when the milder INVESTIGATE threshold R1 ≥ 1.02 is crossed. Both rationales cite the FDA 2020 *In Vitro* Drug Interaction Studies guidance¹, which states the thresholds verbatim in its decision-tree figure (GOLD). The full CYP-DDI knowledge base partitions 4 GOLD / 1 SILVER / 0 BRONZE.

**NCA-PK** (`backend/experiments/nca_pk_autoloop/param_tuner.py`). Two handlers: `_fix_auc_extrapolation` (lines 44–52) multiplies `last_sampling_time_h` by 1.5 (cap 168 h) when AUC extrapolation beyond the last measured concentration exceeds 20%, the FDA 2003 BA/BE guidance limit²; `_fix_terminal_slope` (lines 54–64) adds two terminal-phase points (cap 8) and extends the last-sampling time by 30%, addressing inadequate log-linear decline coverage. The NCA-PK knowledge base partitions 3 GOLD / 1 SILVER / 1 BRONZE.

**Docking** (`backend/experiments/docking_autoloop/param_tuner.py`). Two handlers: `_fix_valid_poses` (lines 44–52) doubles `exhaustiveness` (cap 32) and expands the binding-box edge by 1.0 Å (cap 5.0 Å) when no valid pose is generated; `_fix_binding_score` (lines 54–69) increments `exhaustiveness` by 4 and escalates Glide `docking_precision` from SP to XP when the best score is above the hit-rate threshold. **The docking knowledge base partitions 0 GOLD / 0 SILVER / 5 BRONZE.** Every docking remediation rule is a vendor-community heuristic — Vina's recommended exhaustiveness sweep, Glide's SP→XP escalation pattern — without a peer-reviewed publication that anchors the specific numeric move. We disclose this here, and again in §4, because it is the strongest finding in the provenance audit and because the paper's value comes from how honestly we handle it. The docking auto-loop still converges (Figure 2), but every successful docking run carries an audit trail in which the rationale strings are labelled BRONZE; users designing regulatory submissions must judge whether that grade is adequate for their context.

### 2.4 Benchmark design

We constructed 125 scenarios across the four wired domains: 36 in ADMET, 27 in CYP-DDI, 27 in NCA-PK, and 35 in docking. Each scenario is a synthetic compound or protocol designed to fail one or more gates at the first iteration; the auto-loop's task is to converge to all-PASS within the three-iteration budget. Scenarios are partitioned into (i) single-gate-then-pass cases drawn from the published baseline distributions in TDC ADMET Group (ADMET), the FDA 2020 DDI guidance test matrix (CYP-DDI), the FDA 2003 BA/BE literature (NCA-PK), and DUD-E-style decoy sets (Docking); (ii) multi-gate cases that fail two or more gates simultaneously; (iii) clean-pass cases (no failure at iteration 1); and (iv) for docking only, five persistent-fail cases for which no parameter change in the rule set will produce a valid pose — these test the audit-trail behaviour at escalation. Scenarios are catalogued in `evaluation/adapters/autoloop_benchmark_adapter.py`. Published single-shot baselines are 40% (ADMET), 30% (CYP-DDI), 50% (NCA-PK), and 20% (Docking); these represent the gate-pass rates at iteration 1 expected under the published distributions, against which BioMate's pass@1 and pass@≤3 rates are reported.

The scoring rubric assigns 1.0 to scenarios that pass at iteration 1, 0.8 to those converging in ≤3 iterations, 0.5 to those requiring more than three, and 0.0 to escalations (no convergence at the budget exhaustion). The pass@≤3 headline metric is the fraction of scenarios scoring ≥ 0.8.

### 2.5 Fail-safe architecture

The auto-loop is bounded by three safety mechanisms. **Hard iteration budget.** Three iterations is the default; no auto-loop module raises the limit silently. The orchestrator emits an `ESCALATE` event on budget exhaustion, preserving the original failure and every attempted parameter change. **Parameter guard floors.** Each tuner enforces per-parameter limits (`MIN_LOGP = 0.5`, `MIN_CMAX_uM = 0.05`, `MAX_LAST_SAMPLING_H = 168`, `MAX_EXHAUSTIVENESS = 32`, etc.) to prevent runaway excursions into unphysical regions. When a handler would cross a guard floor, it returns the clamped value and the rationale string records the clamp, so the audit trail captures the reason convergence may stall. **No remediation, hard halt.** If a `HALT` gate has no handler in the dispatch table (e.g., advisory-only gates such as CYP-DDI `tdi_concern`), the orchestrator returns an empty `param_changes` dict and the loop terminates with a "manual review required" annotation. Anti-collision against partial handlers is achieved at the architectural level: the dispatch table is the single source of truth for which gates auto-loop and which do not. The audit trail — itself the subject of the flagship paper's §3 — is the off-ramp; auto-loop never overwrites it.

---

## 3. Results

*[Pending finalised E2 reconciliation; see `methods/00_intake_notes.md` for the 125 vs 139 scenario-count question.]*

## 4. Discussion

*[Pending §3.]*

---

## References (placeholder; to be expanded)

1. US Food and Drug Administration. *In Vitro Drug Interaction Studies — Cytochrome P450 Enzyme- and Transporter-Mediated Drug Interactions: Guidance for Industry.* January 2020.
2. US Food and Drug Administration. *Guidance for Industry: Bioavailability and Bioequivalence Studies for Orally Administered Drug Products — General Considerations.* 2003.
3. Avilov S et al. Bayesian optimisation in pharmaceutical and chemical process development. *Reaction Chemistry & Engineering* 2023 — *(uncited evidence anchor; auto-loop without provenance)*.
4. Redfern WS, Carlsson L, Davis AS, et al. Relationships between preclinical cardiac electrophysiology, clinical QT interval prolongation and torsade de pointes for a broad range of drugs. *Cardiovasc Res* 2003;58(1):32–45. DOI: 10.1016/S0008-6363(02)00846-5.
5. Lammert C, Bjornsson E, Niklasson A, Chalasani N. Oral medications with significant hepatic first-pass metabolism are at increased risk for hepatic adverse effects. *Toxicol Sci* 2010. DOI: 10.1093/toxsci/kfq059.
6. Kazius J, McGuire R, Bursi R. Derivation and validation of toxicophores for mutagenicity prediction. *J Med Chem* 2005;48:312–320. DOI: 10.1021/jm040835a.
7. BioMate Team. *Interactive Evidence-Graded QC Governance and Auto-Loop Convergence for Drug Discovery Workflows.* Manuscript in preparation.
8. FDA. *Artificial Intelligence and Machine Learning (AI/ML) Software as a Medical Device — Lifecycle Management Considerations: Draft Guidance.* 2024.
9. European Medicines Agency. *Reflection Paper on the Use of Artificial Intelligence in the Lifecycle of Medicinal Products.* 2024.
10. Bowes J, Brown AJ, Hamon J, et al. Reducing safety-related drug attrition: the use of in vitro pharmacological profiling. *Nat Rev Drug Discov* 2012;11(12):909–922. DOI: 10.1038/nrd3845.
11. Waring MJ, Johnstone C. A quantitative assessment of hERG liability as a function of lipophilicity. *Bioorg Med Chem Lett* 2007;17(6):1759–1764. DOI: 10.1016/j.bmcl.2006.12.061.
12. Aronov AM. Tuning out of hERG. *Curr Opin Drug Discov Devel* 2008;11(1):128–140. PMID: 18175275.
