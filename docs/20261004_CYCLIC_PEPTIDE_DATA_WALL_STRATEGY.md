# Breaking the Cyclic-Peptide Data Wall — Strategy (public-first, then generate)

**Date:** 2026-10-04 · **Problem:** every generative cyclic-peptide model (ours included: M2c 0.326, cyclic-FTs 0.41–0.51, all plateaued) hits the same wall — only **low hundreds of bound cyclic-peptide–protein COMPLEX STRUCTURES exist in the PDB.** That structural scarcity caps structure/DockQ models. Chasing +0.04 DockQ is not publishable; breaking the data wall is the real contribution.

## Core insight: don't break the *structure* wall — change the data type
You cannot affordably get 10,000 cyclic co-crystals; the structure wall is effectively unbreakable by acquisition. **But structure is the wrong data for the problem.** Reframe the model from **structure→DockQ** (data-starved, plateaued) to **sequence→property** (binding, permeability, selectivity), where data *can* be abundant — from display selection and existing databases. This also reframes the paper away from DockQ toward the real challenges (multi-objective, generalizability, knowledge, efficiency) and feeds the Pareto-DPO method (`docs/20261002_BEST_PEPTIDE_LLM_PROGRAM.md`).

## Step 0 — WE ALREADY COLLECTED MOST OF THIS (verified 2026-10-04 — do not re-collect)
Before any "mine public data" step: we already have it on S3. Verified inventory:
- **CycPeptMPDB — HAVE IT:** `cyclic_peptide/raw/CycPeptMPDB_Peptide_All.csv` (19 MB, **7,334** cyclic peptides + experimental permeability); CycPeptMP model/benchmark in `code_refs/cycpeptmp.tgz` (991 MB). **Permeability objective data is in hand.**
- **Conformers:** `cremp_partial/`, `macroconf/` (computational cyclic conformers).
- **Structures:** `pepbdb/`, `pepbench/`, `bound_cyclic_v1/` + the 662-mine. (The scarce slice — the structure wall.)
- **Also:** `approved_cyclic_peptide_drugs/`, `peptideclm2_pepmsnd/` (4 MB), `nme_v1/` (N-methylation, 3 MB), `helm_monomers/`, non-canonical vocab.
- **⚠ Binding data is the REAL thin axis:** `datasets/_collect_status/bindingdb_peptide.json` is **65 bytes** — a stub. The BindingDB peptide collection effectively **failed/under-collected.** So the *binding/affinity* objective — the one that matters most — is the gap, and it's a **free re-collection**, not a paid campaign.

**Conclusion:** we are NOT data-collection-blocked and do NOT need to pay for a first result. The multi-objective model can train TODAY on permeability (CycPeptMPDB 7,334) + developability + conformers we already hold. The one free fix is re-collecting peptide **binding** data (BindingDB + ChEMBL peptide subset) that we botched. Paid display campaigns are only for later, proprietary, per-target binding at display scale — and only if the free binding re-collection proves insufficient.

### Authoritative held-data inventory (verified 2026-10-04)
| Objective | Dataset | Size / count | Status |
|---|---|---|---|
| Permeability | CycPeptMPDB (`raw/CycPeptMPDB_Peptide_All.csv`) | 8,466 rows; Permeability all, PAMPA 7,298, Caco2/MDCK/RRCK; SMILES+HELM+Sequence | ✅ have |
| Conformers/geometry | CREMP (`cremp_partial/`) + MacroConf | ~43 GB (pickle 29 GB + sdf/json 14 GB + summary.csv) | ✅ have |
| Structures (co-design) | PepBDB, PepBench, bound_cyclic_v1 (662-mine) | ~hundreds | ✅ have (scarce slice) |
| Developability calibration | approved_cyclic_peptide_drugs | CSV + notes | ✅ have |
| Chemical-LM pretrain | PeptideCLM / PepMSND | large (hashed dirs) | ✅ have |
| N-methylation | nme_v1 (`nme_dataset.jsonl/`) | 3 MB | ✅ have |
| **Binding affinity** | BindingDB | **65-byte stub (collector failed on URL scrape)** | ❌ re-collecting (ChEMBL + BindingDB) |

**Net:** data-RICH on permeability + conformers + structures + developability; the only gap is binding affinity, now being re-collected free. The Pareto-DPO multi-objective model can train on held data today for every axis except binding.

## Step 1 — (superseded by Step 0) what public binding data to re-collect
The permeability/structure/conformer data is already held (Step 0). The free task is the BINDING axis we under-collected (collect_bindingdb.sh failed: BindingDB Download.jsp scrape → url_unresolved → 65-byte stub). Re-collect via ChEMBL (stable API) + fixed BindingDB.

| Source | What it gives | Size | Use | Status |
|---|---|---|---|---|
| **CycPeptMPDB** (cycpeptmpdb.com; JCIM 2023) | experimental **membrane permeability** of cyclic peptides + HELM sequences + structures (45 papers + 2 pharma patents) | **7,334 cyclic peptides** | trains the **permeability objective** of Pareto-DPO directly | **confirmed public/downloadable** |
| **ChEMBL** | bioactivity (Ki/Kd/IC50/%inhib), incl. peptides/cyclics, sequence→activity | 10⁶s activities (peptide subset smaller) | **binding/affinity objective** | public; needs peptide/cyclic filtering |
| **BindingDB** | measured binding affinities incl. peptides | ~10⁶ binding data | binding objective | public |
| **Published display-selection NGS** (SRA/ENA) | raw reads from mRNA/phage display campaigns → millions of cyclic-peptide sequences with round-over-round **enrichment = binding labels** | 10⁶–10⁸ reads/study, scattered per-paper/target | the *scaled* sequence→binding substrate | public but **heterogeneous**, per-study harvest; no single index |
| **PDB** (cyclic complexes) | the ~hundreds of structures | low hundreds | the structure component (the wall) | have it |
| Cyclic DBs to verify | CyclicPepedia / Propedia / SATPdb / PepBDB | sequences/structures/annotations | augment | **verify scope before citing** |

**Takeaway:** CycPeptMPDB alone (7,334 with experimental permeability) is a real, free substrate for the permeability objective — far more than the ~hundreds of structures. ChEMBL/BindingDB + harvested display-NGS cover the binding objective. **Most of the Pareto-DPO objective data can likely come from public sources at $0.** Mine first; size the real gap; only then pay.

## Step 2 — GENERATE DATA only for the gaps (proprietary, our targets)
What public data will NOT give: large, clean **sequence→binding data on OUR specific targets (PD-L1, αvβ6)** at display scale — unless someone already ran display against them (check SRA first). Generating it = the moat (data nobody else has → a model only we can train).

| Route | Chemistry | Who | Cost (ESTIMATE — quote-based) |
|---|---|---|---|
| **Phage display, cyclic** — accessible, fee-for-service | disulfide / head-to-tail, natural AAs (matches round-1) | **Creative Biolabs** (explicit cyclic phage-library service); **GenScript** (also offers phage display — extends current relationship) | **~$30k–80k / target** (library + 3–4 panning rounds + NGS); weeks–months |
| **mRNA display / RaPID** — gold standard for drug-like macrocycles | 10¹²–10¹³ library, **non-natural AAs**, N-methylation | **PeptiDream** (Suga's RaPID; pharma-partnered) · **CD Biosynsis/Aspiregene** (service) · **Suga lab, UTokyo** (academic collab) | partnership/deal (≫ phage; $100k–$M or equity/royalty); academic collab cheaper but slower, IP-shared |
| Bicyclic | constrained bicyclics | **Bicycle Therapeutics** | partnership |

**Deliverable from a campaign:** the NGS enrichment dataset (millions of sequences × enrichment = quantitative binding labels on our target) → trains a sequence-level cyclic affinity/generator → feeds Pareto-DPO. **This is proprietary + is the data-advantage moat.**

## Recommended plan (cost-ordered)
1. **Now, $0:** download + mine **CycPeptMPDB** (permeability) + **ChEMBL/BindingDB** (binding, cyclic-filtered) + **search SRA for display-NGS on PD-L1/αvβ6 and general cyclic campaigns**; quantify coverage of the Pareto-DPO objectives. (Public-first; matches `feedback_verify_data_existence`.)
2. **Prototype** the sequence→property models + Pareto-DPO on public data; measure how far it gets (hypervolume, held-out generalization). This is a real result at $0.
3. **Only for the gap:** commission a **phage-display campaign on PD-L1 + αvβ6** (~$60k–160k for two targets) → proprietary binding corpus → the data-advantaged, genuinely-ours model.
4. Later: RaPID/PeptiDream for permeable non-natural macrocycles.

## Honesty flags
- All campaign costs are **estimates**; confirm by quote (no public pricing).
- CycPeptMPDB is **permeability**, not binding — covers one objective, not affinity.
- Display-NGS in SRA is real but **heterogeneous** (per-study formats/targets); harvesting is engineering, not a clean download.
- Whether public data suffices to break the wall for *binding* is **unproven until mined** — Step 1 answers it before any spend.

## Sources
- CycPeptMPDB: https://pubs.acs.org/doi/10.1021/acs.jcim.2c01573 · site cycpeptmpdb.com
- RaPID platform: https://pubs.acs.org/doi/10.1021/acs.accounts.1c00391
- Creative Biolabs cyclic phage display: https://www.biotechphage.com/phage-display-cyclic-peptide-library-construction.html
- CD Biosynsis mRNA display: https://www.aspiregene.com/mrna-display-based-macrocyclic-peptide-development.html
- Yeast display macrocycles (Nat Commun 2025): https://www.nature.com/articles/s41467-025-60907-x
