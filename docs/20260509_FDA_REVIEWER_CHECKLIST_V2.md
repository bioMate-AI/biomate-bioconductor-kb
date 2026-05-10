# FDA Reviewer Checklist v2 — Regulatory LLM Evaluation

**Date:** 2026-05-09
**Status:** Active spec for evaluation infrastructure (replaces v1 sketch in `20260509_REGULATORY_LLM_SESSION_DOC.md`)
**Sources verified:** ICH M4S(R2), FDA Format and Content guidance, Manning et al. 2020 (Reg Tox Pharmacol)

---

## Why a v2

v1 captured the right intuition (FDA review is much stricter than `citation_recall`) but was vague on:
- Exact ICH M4S(R2) required structure (now enumerated)
- The dominant clinical-hold causes (MRSD/HED arithmetic, phase-gating, hERG) — these are now first-class checkers
- Which checks are deterministic vs LLM-based (clarified per checker)

The v2 checklist defines **9 deterministic checkers + 2 LLM judges**. Each maps to an SFT task and an RL reward component.

---

## Section A — Structural compliance (ICH M4S(R2))

Required structure. Subsection headings must be present, in order. Validator is pure regex / heading-tree parse.

| Section | Required subsections |
|---|---|
| §2.6.1 Introduction | drug class, indication, pivotal study list |
| §2.6.2 Pharmacology Written | Brief Summary, Primary PD, Secondary PD, Safety Pharmacology, PD Drug Interactions, Discussion and Conclusions |
| §2.6.3 Pharmacology Tabulated | per ICH templates |
| §2.6.4 PK Written | Brief Summary, Methods of Analysis, Absorption, Distribution, Metabolism, Excretion, PK Drug Interactions, Other PK Studies, Discussion |
| §2.6.5 PK Tabulated | per ICH templates |
| §2.6.6 Toxicology Written | Brief Summary, Single-Dose, Repeat-Dose, Genotoxicity (in vitro then in vivo), Carcinogenicity (long-term, short/medium-term, other), Reproductive (fertility, embryo-fetal, pre/postnatal), Local Tolerance, Other, Discussion and Conclusions, Tables and Figures |
| §2.6.7 Toxicology Tabulated | **34 standardized templates** — non-negotiable format |

**Checker:** `StructuralValidator.validate(text, section_id)` → returns missing-subsection list, ordering violations.

---

## Section B — Content correctness

| Check | Type | What it asserts |
|---|---|---|
| B1 Numeric traceability | deterministic | every dose/NOAEL/AUC/Cmax/safety-margin in narrative is present in source study record |
| B2 Unit specificity | deterministic | mg/kg vs mg/kg/day; AUC interval (0–24h, 0–τ, 0–∞); matrix (plasma, blood); analyte (parent, metabolite) |
| B3 Ordering | deterministic | in vitro before in vivo (ICH M4S(R2) explicit) |
| B4 Adversity language | deterministic | "no findings" / "no adverse findings" / "no test-article-related findings" / "NOAEL not established" — exact match to source conclusion |

---

## Section C — Safety-translation correctness *(highest priority — clinical-hold causes)*

Per Manning et al. (2020), most common nonclinical hold causes:

| Check | Type | What it asserts |
|---|---|---|
| C1 MRSD arithmetic | deterministic | NOAEL → HED via BSA factor (rat 6.2, mouse 12.3, dog 1.8, monkey 3.1) → ÷10 safety factor → matches stated MRSD |
| C2 Phase-gating completeness | deterministic | given proposed Phase + trial duration, all ICH M3(R2) Table 1 required studies are present/cited |
| C3 Genotox battery (FIH) | deterministic | Ames + in vitro mammalian + in vivo all present for first-in-human |
| C4 Safety pharmacology core | deterministic | CV/CNS/respiratory per ICH S7A all present |
| C5 hERG/QT addressed | deterministic | hERG IC50 or QT signal explicitly discussed when CV liability flagged |
| C6 Reproductive staging | deterministic | DART present when WOCBP enrollment proposed |

---

## Section D — Cross-section consistency

| Check | Type | What it asserts |
|---|---|---|
| D1 NOAEL consistency | deterministic | NOAEL in §2.6.6 narrative = §2.6.7 tables = §2.7.4 clinical safety summary |
| D2 Study-ID consistency | deterministic | study IDs cited in §2.6.6 exist in §2.6.7 table list |
| D3 Species/strain/sex/N consistent across narrative and tabulated summary |

---

## Section E — Regulatory-citation correctness

| Check | Type | What it asserts |
|---|---|---|
| E1 Correct guideline | deterministic | citation governs the section type (ICH S2(R1) → tox_genotox only) — already in `evaluate_regulatory_llm.py` |
| E2 No hallucination | deterministic | citation exists in known guideline registry — already implemented |
| E3 Citation specificity | tiered | "ICH S2(R1)" → 0.5; "ICH S2(R1) §3.2 in vitro test battery" → 1.0 |
| E4 Contextual placement | LLM judge | claim adjacent to citation is supported by guideline (BM25 + LLM) — already implemented |

---

## Implementation status

| Section | Implemented | File | Gap |
|---|---|---|---|
| A | ❌ | — | structural validator missing |
| B1 numeric | ❌ | — | needs source-record cross-check |
| B2 units | ❌ | — | needs unit grammar |
| B3 ordering | ❌ | — | trivial regex |
| B4 adversity | ❌ | — | requires ingester output |
| C1 MRSD | ❌ | — | **highest priority** |
| C2 phase-gating | ❌ | — | needs ICH M3(R2) Table 1 encoded |
| C3–C6 | ❌ | — | rule-based, straightforward |
| D | ❌ | — | parser + diff |
| E1, E2, E4 | ✅ | `scripts/evaluate_regulatory_llm.py`, `ich_corpus.py` | E3 (specificity tiering) missing |

---

## SFT task additions implied by v2 checklist

Current SFT is mostly "study data → fluent prose". Add:

1. **Section-skeleton completion** — fill ICH M4S(R2) subsections in required order. *Targets A.*
2. **MRSD computation task** — given NOAEL + species + BW, output HED + safety factor + MRSD with arithmetic shown. *Targets C1.*
3. **Phase-gating task** — given proposed trial design, list required ICH M3(R2) studies. *Targets C2.*
4. **§2.6.7 table generation** — given §2.6.6 narrative, generate conforming tabulated summary. *Targets A + D.*
5. **Adversity-language task** — restate study conclusion using ICH-compliant phrasing without semantic shift. *Targets B4.*

---

## RL reward design (for v7)

Composite reward = weighted sum:
- Structural compliance (A): 0.20
- Numeric traceability (B1): 0.20
- MRSD correctness (C1): 0.15
- Phase-gating (C2): 0.10
- Cross-section consistency (D): 0.15
- Citation correctness (E1+E2): 0.10
- Citation specificity (E3): 0.05
- Contextual placement (E4): 0.05

All deterministic checkers return pass/fail (1/0); E4 returns continuous BM25 score. Compose into shaped reward; bad-output regenerate-and-penalize at inference time.

---

## Version ladder (revised)

| Version | What it adds | Unlocks |
|---|---|---|
| v5 (DPO) | tox_genotox preference | citation_recall ceiling — won't fix MRSD or structure |
| **v6** (structural + numeric SFT) | tasks 1, 2, 4 | first version that survives structural review |
| **v7** (full-checker RL) | 9-component reward | first version where MRSD math is reliably correct |
| v8 (deployed w/ HITL) | inference hard gates on A/B/C | usable as CRO draft tool |

---

## Order of work (revised from session doc P3-P7)

**Before P3 (DPO):** build C1 MRSD verifier and A structural validator. These are pure-Python, fast, and the C1 result tells us whether DPO is worth doing first or whether v6's task additions should jump the queue.

1. **P3' MRSD verifier** (this session) — highest single-issue impact per Manning et al.
2. **P3'' Structural validator** — required-subsection checker; trivial.
3. Run both on v4's 227 test outputs → measurement baseline.
4. Decide P3 (DPO) vs P6 (v6 SFT redesign) based on which checker is failing more.
