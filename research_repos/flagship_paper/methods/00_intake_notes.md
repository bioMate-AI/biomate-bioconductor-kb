# Flagship Paper — Intake Notes

**Title (working):** *Interactive Evidence-Graded QC Governance and Auto-Loop Convergence for Drug Discovery Workflows*

**Target venue:** Nature Methods (Article)
**Status:** Section 1 (Introduction) drafted 2026-05-27. Sections 2–5 pending E1/E2/E3/E4 data.
**Authors (placeholder):** Yaoyun Zhang¹\*, Yuhan Zhang²\* (mirror cryo paper byline; confirm with user).

---

## 1. Skill application

The Galaxy-Dawn `claude-scholar/skills/nature-writing` skill was not installed as a registered Claude Code skill in this session (skill installation flow not exercised to avoid blocking the writing task). Instead, the nature-writing pattern was applied **inline** following the standard Nature Methods Article intro architecture:

  field-scale framing → bottleneck identification → prior-art survey → unresolved gap (numbered) → present-study contribution (numbered, mapped 1:1 onto gaps).

Standard Nature-style discipline followed:
- No fabricated numbers. Every quantitative claim is either traceable to a repo audit doc (cited below) or marked `[TBD: pending Ex results]`.
- Domain-specific cryo numbers (FSC=3.98 Å, 26,284 particles, etc.) are not repeated in the flagship — they are referenced via `(Zhang & Zhang, manuscript in preparation)`.
- 2-of-29 BRONZE gates explicitly disclosed in §1.4 (honesty about evidence-grade distribution).

---

## 2. Claims grounded in repo audit docs

| Claim used in §1 | Source of truth |
|---|---|
| 29 gates across 16 domains | `docs/20260526_QC_GATES_WORKFLOWS_AUTOLOOP_STRATEGY.md` §1 |
| 22 GOLD / 5 SILVER / 2 BRONZE | same |
| 5 auto-loop wired domains (ADMET, CYP-DDI, NCA-PK, Docking, PBPK) | same |
| 10 gate-only domains (HTS, ICH S5, ICH S7, clinical_trial, allometric, IVIVE, OpenFE, P0 PK/PD, pocket_detection, AiZynthFinder) | same |
| 226 drug-development workflows audited | same |
| Auto-loop convergence ≤3 iterations 96.4% | MEMORY: BiomniEval1 v17–v20 entry; also `experiments/admet_autoloop/` 96/96 tests passing |
| Membrane-protein false-rejection 100% → 0% | cryo paper §3.4 (cited as in-prep) |
| Provenance audit (PBPK over-attribution) | `docs/20260522_AUTOLOOP_EVIDENCE_PROVENANCE_AUDIT.md` — used to justify our honesty-disclosure paragraph |

**User-spec called "31 gates" and "15 gate-only";** the canonical audit doc reports 29 gates (22+5+2) and 10 gate-only domains. The flagship uses the audit-doc numbers and flags the discrepancy here for the user to reconcile before submission.

---

## 3. Data status by figure

| Figure | Status (updated 2026-08-27) | Source / owner |
|---|---|---|
| E1 — false-rejection × profile × domain | **DONE** — HTS + LNP implemented (`run_e1.py`, `results/e1_*.csv`, `figures/e1_false_rejection.*`); matches the manuscript §3 claim exactly (verified); cryo panel is from the companion cryo paper | flagship paper |
| E2 — auto-loop convergence | **NOT a flagship experiment** — demoted to companion **C6** per option-A decision (2026-08-26); the flagship makes no convergence claim (Limitations) | companion C6 |
| E3 — provenance grade × remediation reliability | **NOT a flagship experiment** — belongs to **C6** (depends on E2) | companion C6 |
| E4 — audit-trail completeness | **DONE** — implemented (`scripts/e4_*.py`, `results/e4_*.csv`, figure) and the manuscript is now aligned to the committed experiment (per-decision provenance completeness 1.0 vs 0.0, domain-tool baselines, Mann–Whitney p=1.6e-4) via option-A (#191) | flagship paper |

Only **E1** and **E4** are flagship experiments; both are done and consistent with the manuscript. E2/E3 are C6.

---

## 4. Open questions for the user before §2 (Methods) / §3 (Results)

1. **Author list & affiliations final?** (mirror cryo paper byline?)
2. **Domain reconciliation:** 29 vs 31 gates — is the gap a roadmap item or a counting convention?
3. **E1 scope:** confirm HTS + LNP false-rejection benchmarks are running and what columns the CSV will deliver.
4. **E2 success criterion:** ≤3 iterations 96.4% is the current MEMORY claim; is this the headline number, or do we want stratified rates per domain (ADMET vs CYP-DDI vs PBPK)?
5. **E4 design:** what does "audit completeness" mean operationally — JSONL field coverage, replay determinism, or external-reviewer agreement?
6. **Comparator policy:** the cryo paper benchmarks against CryoSPARC Live; the flagship needs cross-domain comparators (KNIME, Galaxy, manual scripts?). User to choose.

---

## 5. E4 implemented ≠ E4 as described in the manuscript — ✅ RESOLVED via option A (#191, 2026-08-27)

> **✅ RESOLVED (2026-08-27, author chose option A).** The manuscript E4 claims were rewritten to match the committed experiment (per-decision provenance completeness 1.0 vs 0.0; domain-tool baselines CryoSPARC Live / RELION 4 / DataWarrior / PK-Sim / Spotfire / SAS BOIN; Mann–Whitney U=0, p=1.6e-4 read as a formality) across all six locations — abstract, Fig 4b caption (was contradicting its own figure), §3 Results, Methods/Statistics, Related-work §1.2, §5.3. Tower/Galaxy/KNIME are retained only as the C3 companion data-model comparison. See PR #191. The original finding is preserved below for the record.

E4 is **no longer "pending design"** (§3 table line 48 is stale): a full harness is committed — `scripts/e4_generate_logs.py`, `scripts/e4_audit_completeness.py`, `results/e4_completeness_summary.csv` + `..._per_run.csv`, `figures/e4_audit_completeness.{py,png}`, and 10 BioMate + 10 baseline logs across 5 domains. **But the implemented experiment and the manuscript prose (abstract, Fig 4b caption, §3) describe three different things**, verified against code:

| Axis | Manuscript prose (abstract / Fig 4b / §3) | **Committed experiment (script + figure + methods)** |
|---|---|---|
| **Metric** | "**10 governance-specific fields**, BioMate carries all ten, **10/10 vs 0/10**" (field checklist) | **per-decision provenance completeness** = fraction of gate decisions carrying `paper_ref + DOI + provenance grade`, scored 0/.33/.67/1.0, mean per run → BioMate **1.0** vs baseline **0.0** |
| **Comparators** | "**Nextflow Tower, Galaxy, KNIME Server**" | **domain scientific tools**: CryoSPARC Live, RELION 4, DataWarrior, manual ADMET CSV, TIBCO Spotfire, PK-Sim/GastroPlus, SAS BOIN macro |
| **Statistics** | "deliberately attach **no** inferential p-value … a significance test would be inappropriate" | **Mann–Whitney U = 0, two-sided p = 1.57×10⁻⁴** (computed in the script, annotated on the figure) |
| **n** | (implied 10 fields) | **n = 10 runs per group** (5 domains × 2) |

Net: the Fig 4b **caption contradicts its own figure** (the figure plots the domain-tool baselines with the p-value; the caption talks about Tower/Galaxy/KNIME and a 10-field checklist with no p-value). "Tower/Galaxy/KNIME" appears **only** in prose (`00_outline.md`, `MANUSCRIPT_DRAFT.md`, this file) — there is no data, script, or figure for that comparison.

**Decision for the user (one of):**
- **(A)** Align the manuscript to the experiment that exists — describe E4 as per-decision provenance completeness (1.0 vs 0.0) against the **domain-tool** baselines, with the Mann–Whitney p reported (as a formality on a near-degenerate table, like the stability Kappa=1.0). This is the honest, already-backed option and arguably the stronger comparison (real per-domain tools). Also fix §Related-work's "appear here only as the Fig. 4b audit-field comparators" line (currently names Tower/Galaxy/KNIME).
- **(B)** Keep the Tower/Galaxy/KNIME 10-field framing and **build that experiment** (new logs + field-coverage analysis for the three orchestration platforms). Not yet run.

I did **not** edit the manuscript E4 claims — the reconciliation direction is an authoring decision. (I also earlier removed the fictional `approver`/`override-justification` audit field from §5/§A9 in PR #176; the audit *schema* those sections now describe is verified against the emitter code.)
