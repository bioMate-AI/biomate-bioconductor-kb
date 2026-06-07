# Inhibitor Track C — Computational Shortlist (publication HTS tier)

**Generated:** 2026-06-07  
**Primary HTS:** `publication_zinc/vina/` — **5,006/5,006** docked; best rigid **−6.952** kcal/mol  
**Post-HTS QC:** ensemble on top-20 (`20260607T000744Z`); generative top-5 (`20260607T002113Z`)  
**MD-validated lead:** INH-01 (ZINC150 origin; pub deck rank **#79**, −6.208 rigid)

> **Scope:** Compute-only ranking for medchem / SPR triage. MM-GBSA is **not diagnostic** (aspirin control −13.05 kcal/mol). Generative rigid −7.004 **does not** beat publication HTS after ensemble rescoring.

---

## Tier 1 — Primary compute lead (MD + pose QC)

| ID | SMILES | Pub rigid Vina | MD RMSD | Notes |
| --- | --- | ---: | ---: | --- |
| **INH-01** | `N=C(N)NC(=O)c1nccnc1N` | −6.208 (#79) | **0.41 nm** | Only compound with stable MD; SPR/pseudotype candidate |

---

## Tier 2 — Publication HTS rigid top-5 (purchasability checked)

From `PUBLICATION_ZINC_TOP20_PURCHASABILITY.md`. Rigid 9P3I only.

| Rank | ZINC ID | Vina | Tranche | PubChem | Ensemble note |
| ---: | --- | ---: | --- | ---: | --- |
| 1 | 239377869 | −6.952 | BBAA | 124721936 | Rigid #1; ensemble **worsened** (−6.759) |
| 2 | 17299557 | −6.878 | BBAA | 235109 | Ensemble **−7.483** (9P3Y) ✓ |
| 3 | 347043 | −6.855 | BBAA | 826866 | Flat vs ensemble |
| 4 | 36696104 | −6.762 | BBAA | 51866101 | Ensemble worsened |
| 5 | 1875249477 | −6.754 | BBAA | — | Flat vs ensemble |

---

## Tier 3 — Ensemble-rescoring candidates (pose QC required)

Strongest ensemble hit from publication top-20 panel:

| ZINC ID | Rigid Vina | Ensemble best | Conformer | Δ |
| --- | ---: | ---: | --- | ---: |
| 828873353 | −6.615 (#12) | **−7.562** | 9P3Y | −0.947 |

Second notable improver: ZINC17299557 (#2 rigid) → **−7.483** on 9P3Y.

**Gate before synthesis:** visual pose inspection, protonation check, ZINC purchasability quote.

---

## Tier 4 — Controls & backups

| Label | Vina (pub deck) | Role |
| --- | ---: | --- |
| Z600-R1 | −6.527 (#15) | Blog-tier AAAC control; pose QC PASS (0.26 nm) |
| umifenovir | −6.362 (#39) | Antiviral benchmark |
| INH-02–05 | ZINC150 panel | MM-GBSA backups — **hold** until aspirin QC resolved |

---

## Generative lane (exploratory — not promoted)

**Source:** `reinvent_inh01/` (medchem enumeration; REINVENT4 Batch unavailable)

| Best rigid | Ensemble | Verdict |
| --- | --- | --- |
| −7.004 (`NC(=O)NNC(=O)c1ncc(C(F)(F)F)nc1N`) | −6.969 | Beats pub rigid only; **fails** ensemble vs pub −7.562 |

2/5 generative analogues improved on ensemble; no MD/pose QC.

---

## Recommended validation order

1. **INH-01** — SPR or thermal shift on GP ectodomain (9P3I/9P3Y)  
2. **ZINC828873353** or **ZINC17299557** — if ensemble-promoted hits pass pose QC  
3. **Z600-R1** — rigid Vina backup with existing pose QC  
4. Generative CF3 analogues — **after** pose QC pipeline extended to generative set  

## Assays (when cleared)

1. SPR / thermal shift on GP ectodomain  
2. Pseudotype entry inhibition (BSL-2)  
3. ADMET confirmation for any newly ordered ZINC hit  

Full compute package: `compute_package/COMPUTE_CANDIDATES.md` Track C (publication deck).
