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

| Figure | Status | Source / owner |
|---|---|---|
| E1 — false-rejection × profile × domain | **cryo done; HTS+LNP pending** | another agent (per user) |
| E2 — auto-loop convergence | **pending** | another agent |
| E3 — provenance grade × remediation reliability | **pending E2** | flagship paper |
| E4 — audit-trail completeness | **pending design** | flagship paper |

Intro is fully writeable now without E1–E4 numerical claims (those go in §3 Results).

---

## 4. Open questions for the user before §2 (Methods) / §3 (Results)

1. **Author list & affiliations final?** (mirror cryo paper byline?)
2. **Domain reconciliation:** 29 vs 31 gates — is the gap a roadmap item or a counting convention?
3. **E1 scope:** confirm HTS + LNP false-rejection benchmarks are running and what columns the CSV will deliver.
4. **E2 success criterion:** ≤3 iterations 96.4% is the current MEMORY claim; is this the headline number, or do we want stratified rates per domain (ADMET vs CYP-DDI vs PBPK)?
5. **E4 design:** what does "audit completeness" mean operationally — JSONL field coverage, replay determinism, or external-reviewer agreement?
6. **Comparator policy:** the cryo paper benchmarks against CryoSPARC Live; the flagship needs cross-domain comparators (KNIME, Galaxy, manual scripts?). User to choose.
