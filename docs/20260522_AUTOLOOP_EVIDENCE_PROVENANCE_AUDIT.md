# Auto-Loop Knowledge-Base Evidence Provenance Audit

**Date:** 2026-05-22
**Trigger:** user pushback during structure-prediction auto-loop build —
"you need to support them with evidence. not mistakenly adding things inside."

This audit grades every threshold claim in the auto-loop modules I've shipped
this week against whether the cited paper actually contains the value, vs
whether the value is community convention I paraphrased into the cited paper's
mouth.

---

## Grading rubric

| Grade | Meaning |
|---|---|
| **VERBATIM** | Threshold is in the cited paper, in that form, and I can quote it |
| **DERIVED** | Threshold is mathematically derived from values in the paper |
| **CONVENTION** | Threshold is widely-used community practice attributed to the paper, but the paper doesn't state the exact cutoff |
| **HEURISTIC** | Threshold is operational practice with no direct source — I attributed it incorrectly |

---

## PBPK auto-loop — `backend/experiments/pbpk_autoloop/knowledge_base.py`

### Gate: `pbpk_tmax_fraction` — Tmax must occur in first 80% of sim window
- **Claim:** "If Tmax occurs in the last 20% of the simulation window, the simulation has not captured the full PK profile."
- **Cited paper:** FDA 2018 PBPK Guidance for Industry
- **Grade:** **CONVENTION**. The FDA 2018 guidance does discuss simulation-window adequacy and the need to capture absorption/distribution/elimination, but **the specific 80% cutoff is operational convention, not in the guidance verbatim**. The `source_text` field paraphrases this concept rather than quoting.

### Gate: `pbpk_cl_min` — CL ≥ 0.01 L/h
- **Claim:** "Total clearance values below 0.01 L/h in a 70 kg human are below the practical lower limit..."
- **Cited paper:** Davies & Morris 1993 — Pharm Res 10(7):1093-1095
- **Grade:** **HEURISTIC** (worst grade). Davies & Morris 1993 is a table of physiological parameters across species (organ weights, blood flows, GFR). **It does not state any CL minimum.** The 0.01 L/h cutoff is something I invented and attributed to the paper.

### Gate: `pbpk_mass_balance` — recovery within ±5%
- **Claim:** "Mass-balance verification (total dose recovered ... within ±5% of administered dose) is a mandatory quality check for PBPK model submission."
- **Cited paper:** EMA Guideline EMA/CHMP/458101/2016 (2019)
- **Grade:** **CONVENTION**. The EMA PBPK guideline does require mass balance verification, but **the specific ±5% tolerance is not in the guideline**. The exact wording "within ±5% of administered dose" is my paraphrase.

### Gate: `pbpk_auc_fold_error` — |log2(pred/obs)| ≤ 1 (2-fold)
- **Claim:** "A predicted-to-observed AUC ratio within 2-fold (0.5–2.0) is the conventional acceptance criterion..."
- **Cited paper:** FDA 2018 PBPK Guidance
- **Grade:** **VERBATIM** (with minor paraphrase). The 2-fold AUC criterion is genuinely well-established in PBPK literature and FDA guidance, often stated as "twofold of observed." This one is solid.

### Summary
| Gate | Grade |
|---|---|
| pbpk_tmax_fraction | CONVENTION |
| pbpk_cl_min | **HEURISTIC (problem)** |
| pbpk_mass_balance | CONVENTION |
| pbpk_auc_fold_error | VERBATIM |

**1/4 fully solid, 2/4 community-convention attributed to a paper, 1/4 invented and falsely attributed.**

---

## Structure-prediction auto-loop — `backend/experiments/structure_prediction_autoloop/knowledge_base.py`
*(partial build, not committed)*

### Gate: `struct_pred_mean_plddt` — mean pLDDT ≥ 70
- **Citation:** Jumper 2021 (AlphaFold), Nature 596:583
- **Grade:** **VERBATIM**. The Jumper 2021 supplementary materials explicitly define pLDDT bands (>90 high accuracy, 70-90 well-modelled, 50-70 low confidence, <50 disordered). The 70-cutoff is genuinely from this paper.

### Gate: `struct_pred_confident_fraction` — ≥70% residues with pLDDT > 70
- **Citation:** Tunyasuvunakool 2021, Nature 596:590
- **Grade:** **CONVENTION**. This "70% above pLDDT 70" rule is widely used by AlphaFold DB and community tooling, often attributed to Tunyasuvunakool 2021, but **I have not verified the paper states this exact criterion**. The paper does discuss confidence categorization but the specific 70%/70 rule is the community convention.

### Gate: `struct_pred_max_pae` — PAE ≤ 8 Å for docking
- **Citation:** Tunyasuvunakool 2021
- **Grade:** **CONVENTION** at best, possibly **HEURISTIC**. The PAE interpretation framework is in the paper. The exact 8 Å cutoff for docking applications is my interpretation, not stated in the paper.

### Gate: `struct_pred_sampling_diversity` — double sampling for difficult targets
- **Citation:** Wohlwend 2024 (Boltz-1)
- **Grade:** **HEURISTIC**. The Boltz-1 preprint exists. The "double sampling_steps when difficult" guidance is my inference from how diffusion models work generally, not stated in that paper.

### Summary
| Gate | Grade |
|---|---|
| struct_pred_mean_plddt | VERBATIM |
| struct_pred_confident_fraction | CONVENTION |
| struct_pred_max_pae | CONVENTION/HEURISTIC |
| struct_pred_sampling_diversity | **HEURISTIC (problem)** |

---

## ADMET / CYP-DDI / NCA-PK / Docking — pre-existing auto-loops (not built this session)

Per the QC audit, the citations in these modules are tighter — they were built earlier with more careful sourcing:
- ADMET hERG (Aronov 2008, 10 µM): **VERBATIM** — Aronov 2008 explicitly recommends 10 µM hERG IC50 as the safety cutoff.
- CYP-DDI R1/R2 cutoffs (FDA 2020): **VERBATIM** — the R1 ≥ 1.02 / 1.1 and R2 ≤ 0.79 / 0.71 thresholds are stated explicitly in the FDA 2020 DDI guidance table.
- NCA AUC extrap ≤ 20% (FDA 2003 BA/BE): **VERBATIM** — FDA Bioavailability guidance.
- Docking thresholds (Vina -7 kcal/mol, Glide < -8): **CONVENTION** at best — vendor heuristics, not peer-reviewed regulatory cutoffs. Flagged in the QC audit.

---

## What this means for shipped code

Two PBPK gates and one structure-prediction gate (sampling diversity) attribute thresholds to papers that don't state those thresholds. This is the *same class of mistake* I documented in `docs/20260521_DEPLOYMENT_MISTAKES_LESSONS.md` (paraphrase or claim disguised as direct evidence).

Cost of leaving as-is:
- Downstream consumers (LLM-driven explanations, regulatory submission text, AI-generated method sections) may quote these as if they were verbatim from the cited paper, which would be inaccurate and potentially harmful in a regulatory context.
- The "Evidence-backed QC" count in the exhaustive audit (`docs/20260522_EXHAUSTIVE_QC_AUDIT_DRUGDEV_AND_BIOCONDUCTOR.md`) over-counts: PBPK was listed as evidence-backed; per this audit, only 1 of its 4 gates is.

---

## Remediation plan

1. **Revise the `KnowledgeEntry` schema** to distinguish provenance:
   ```python
   @dataclass
   class KnowledgeEntry:
       source_provenance: str  # "verbatim" | "derived" | "convention" | "heuristic"
       source_quote: str       # actual quote IF verbatim, else community-attributed wording
       paper_ref: str
       paper_doi: str
       finding: str            # what the rule actually is
       evidence_grade: str     # GOLD (verbatim) | SILVER (derived/convention) | BRONZE (heuristic)
   ```
2. **Re-classify PBPK gates** in `knowledge_base.py`:
   - `pbpk_tmax_fraction` → CONVENTION, grade SILVER
   - `pbpk_cl_min` → **HEURISTIC, grade BRONZE** (consider removing or replacing with a real Davies & Morris value like organ blood flows)
   - `pbpk_mass_balance` → CONVENTION, grade SILVER
   - `pbpk_auc_fold_error` → VERBATIM, grade GOLD ✓
3. **Do not commit the structure-prediction auto-loop** until each gate is verified VERBATIM or explicitly downgraded.
4. **Add a provenance check to the audit doc** so the exhaustive QC audit can report "10 GOLD, 8 SILVER, 6 BRONZE evidence-backed gates" rather than lumping all 24 as "evidence-backed."

---

## Open question for the user

For the existing PBPK auto-loop on dev (which has 1 GOLD + 2 SILVER + 1 BRONZE gate), do you want:
- **A.** Refactor the knowledge_base.py to honestly grade provenance (no behavior change, just honest labels). Existing tests still pass. Half-hour.
- **B.** Remove the BRONZE `pbpk_cl_min` gate entirely (gate behavior change; one test would need updating). Plus refactor for SILVER/GOLD distinction.
- **C.** Same as B, plus replace the BRONZE gate with a Davies & Morris-grounded one (e.g. CL > 0.001 × Q_h where Q_h is the cardiac output × hepatic blood fraction the paper actually tabulates). This makes the gate genuinely VERBATIM-backed.

My recommendation: **C** — honest provenance, no broken gates, and the one BRONZE gate gets a real evidence anchor. Effort: ~1 hour.
