# Post-HTS QC report

_Generated: 2026-06-07T00:29:44Z · Updated: 2026-06-07_

## Scope

Post-publication-HTS quality control on the **primary inhibitor deck** (5,006-compound Vina screen) and the **INH-01 generative analogue lane**:

1. Purchasability / identity lookup for publication rigid top-20  
2. Ensemble Vina (6 receptor conformers) on publication top-20  
3. Ensemble Vina on generative top-5 rigid hits  

---

## 1. Purchasability (publication top-20)

**Script:** `lookup_publication_zinc_top20.py`  
**Output:** `publication_zinc/PUBLICATION_ZINC_TOP20_PURCHASABILITY.md`

All top-20 ZINC IDs resolved from `publication_zinc/dock_set.tsv`. PubChem CIDs mapped where available; several high ranks lack PubChem (custom ZINC20 IDs).

---

## 2. Publication top-20 ensemble docking

**Run:** `science_sprint/runs/20260607T000744Z/track_inh_ensemble`  
**Baseline:** `post_hts_qc/publication_top20_baseline.json` (rigid 9P3I)  
**Conformers:** 9P3I, 9P3L, 9P3M, 9P3X, 9P3Y, top_pocket fragment  

| Metric | Value |
| --- | --- |
| Compounds | 20 |
| Improved vs rigid | **10 / 20** |
| Strongest ensemble score | **−7.562 kcal/mol** |
| Strongest compound | ZINC828873353 (`O=C1N[C@@H](c2ccccc2)C(=O)N2C[C@H](O)C[C@@H]12`) |
| Best conformer | **9P3Y** |
| Rigid rank-1 behavior | #1 rigid −6.952 → ensemble −6.759 (**worsened** 0.19 kcal/mol) |

**Interpretation:** Ensemble rescoring is **heterogeneous** on the publication deck — roughly half improve, half flat or worsen. The global rigid #1 is **not** the ensemble winner; rank-12 improves by **−0.95 kcal/mol** on 9P3Y. Do not promote ensemble rank-1 without pose QC and purchasability confirmation.

---

## 3. Generative top-5 ensemble docking

**Run:** `science_sprint/runs/20260607T002113Z/track_inh_ensemble`  
**Baseline:** `post_hts_qc/generative_top5_baseline.json`  
**Source lane:** `reinvent_inh01/` — 1,468 medchem analogues → 50 filtered → 50/50 Vina  

| SMILES (truncated) | Rigid | Ensemble best | Δ | Improved |
| --- | ---: | ---: | ---: | --- |
| `NC(=O)NNC(=O)c1ncc(C(F)(F)F)nc1N` | **−7.004** | −6.969 | +0.035 | no |
| `NC(=O)NS(=O)(=O)Nc1ncc(C(F)(F)F)nc1N` | −6.772 | −6.480 | +0.292 | no |
| `Cc1cnc(NS(=O)(=O)NC(N)=O)c(N)n1` | −6.388 | −6.407 | −0.019 | yes |
| `NC(=O)NS(=O)(=O)Nc1ncc(Cl)nc1N` | −6.220 | −6.197 | +0.023 | no |
| `NC(=O)NC(=O)Nc1ncc(Cl)nc1N` | −6.156 | −6.206 | −0.050 | yes |

| Metric | Value |
| --- | --- |
| Improved vs rigid | **2 / 5** |
| Best rigid (generative lane) | **−7.004** kcal/mol |
| Best ensemble (generative lane) | **−6.969** kcal/mol (9P3I) |

**Interpretation:** The generative rigid winner **does not beat publication HTS after ensemble**. Claim “generative beats HTS” **only for rigid 9P3I Vina**, not ensemble-rescored ranking. No MD/pose QC on generative hits.

---

## 4. Wet-lab / manuscript implications

| Role | Compound | Rationale |
| --- | --- | --- |
| **Primary compute lead** | INH-01 | MD RMSD 0.41 nm; independent of rigid pub rank (#79) |
| **Publication HTS anchor** | ZINC239377869 | Rigid #1 −6.952; ensemble **worsened** |
| **Ensemble rescoring candidate** | ZINC828873353 | −7.562 on 9P3Y; needs pose QC + purchase |
| **Generative (exploratory)** | CF3-pyrimidine urea analog | Rigid −7.004; ensemble −6.969 — **not promoted** |

**Do not** rank by MM-GBSA (aspirin control failure). See `INHIBITOR_COMPOUND_SHORTLIST.md` for updated tier.

---

## Artifacts

| Artifact | Path |
| --- | --- |
| Publication ensemble | `science_sprint/runs/20260607T000744Z/track_inh_ensemble/` |
| Generative ensemble | `science_sprint/runs/20260607T002113Z/track_inh_ensemble/` |
| Purchasability | `publication_zinc/PUBLICATION_ZINC_TOP20_PURCHASABILITY.md` |
| Inhibitor shortlist | `wet_lab_package/INHIBITOR_COMPOUND_SHORTLIST.md` |
