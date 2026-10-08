# Full-Atom Approaches for Peptide & Macrocycle / Cyclic-Peptide Modeling — Survey + Datasets

**Last updated:** 2026-10-08
**Maintained:** living survey; add methods/datasets as they appear. Part of
[[20261008_LIVING_REFERENCES_INDEX]].
**Integrity:** [[feedback_citation_integrity]] — each method/dataset verified against a primary
source (DOI/arXiv/official URL) 2026-10-08; unconfirmed items flagged **(verify)**.
**Confidentiality:** public literature + public datasets only ([[feedback_website_no_internal_work]]);
no internal targets/methods/results.
**Relation to existing BioMate docs (expand, don't duplicate):**
`20260719_CYCLIC_PEPTIDE_MODALITY_TRACK.md`,
`20260714_MULTIOMICS_VIRTUAL_CELL_SPATIAL_CYCLICPEPTIDE_BENCHMARK.md`; memory
[[project_allatom_finetune_untried_lever]], [[project_cross_target_sota_bound]],
[[project_macrocycle_closedloop]], [[project_peptide_pk_learning_gap]].

> Journal version preferred over preprint where both exist. Dates/venues = most authoritative record found.

---

## 1. Approaches

### 1.1 Structure prediction / cofolding
| Method | What it does | Inputs → Outputs | Strengths | Limitations | Citation |
|---|---|---|---|---|---|
| **AlphaFold2 / AF-Multimer** | MSA+Evoformer+structure module; multimer retrained for complexes; not cyclic-aware | seq(+MSA/templates) → all-atom + pLDDT/PAE | gold-standard monomer; peptide–protein complexes; ColabFold ecosystem | linear-chain assumption; poor on short/under-represented peptides and head-to-tail cyclics w/o mods; MSA-dependent | Jumper 2021 Nature 10.1038/s41586-021-03819-2; Evans AF-Multimer bioRxiv 10.1101/2021.10.04.463034 |
| **AF2 cyclic-offset (AfCycDesign)** | overrides relative-position encoding to "wrap" the ring → predicts/designs head-to-tail macrocycles | cyclic seq (+offset) → cyclic all-atom; design → new cyclic seqs | no retraining; X-ray RMSD <1.0 Å on 8 de novo; unifies predict+design+hallucinate | head-to-tail/disulfide mainly; canonical AAs; MSA/recycle cost | Rettie 2025 Nat Commun 10.1038/s41467-025-59940-7; Kosugi & Ohue 2023 IJMS 10.3390/ijms241713257 |
| **AlphaFold3** | diffusion all-atom joint prediction of proteins+NA+ligands+ions+modified residues | tokens (seq, SMILES/CCD, PTMs) → joint complex | native small-molecule/modified-residue; best-in-class protein–ligand; covers non-canonical blocks | initially closed weights/server limits; diffusion hallucination; cyclic not first-class w/o tricks | Abramson 2024 Nature 10.1038/s41586-024-07487-w |
| **Boltz-1** | open-source AF3-class all-atom cofolding (MIT) | seqs+ligands → complex + confidence | fully open; AF3-level; fork base | same cyclic caveats; v1 no affinity | Wohlwend/Corso/Passaro 2024 bioRxiv 10.1101/2024.11.19.624167 |
| **Boltz-2** | Boltz-1 + binding-affinity head + controllability (method conditioning, distance constraints) | seqs+ligands(+constraints) → structure + affinity | joint structure+affinity ~FEP-approaching, ~1000× faster; distance constraints can enforce macrocyclization geometry; open | affinity head mostly small-molecule; cyclic-peptide affinity less validated | Passaro/Corso/Wohlwend 2025 bioRxiv 10.1101/2025.06.14.659707 |
| **Chai-1** | AF3-class; proteins+small molecules+NA+glyco; optional restraints | seqs+ligands(+restraints) → complex | 77% PoseBusters (≈AF3); restraint conditioning; free non-commercial + web server | weights non-commercial (local); cyclic not native | Chai Discovery 2024 bioRxiv 10.1101/2024.10.10.615955 |
| **HighFold** | AF2/AF-Multimer + Cyclic Position Offset Encoding (CycPOEM) for head-to-tail + disulfide | cyclic seq (+target) → cyclic structure/complex | models both head-to-tail and S–S; strong cyclic monomer+complex | canonical AAs (v1); AF2 cost | Zhang 2024 Brief Bioinform 10.1093/bib/bbae215 |
| **HighFold2** | extends HighFold to cyclic peptides with unnatural amino acids | cyclic seq w/ ncAAs (+target) → structure | handles ncAAs (key for real macrocyclic drugs) | niche/newer; limited validation | Guo 2025 Brief Bioinform 10.1093/bib/bbaf202 **(verify)**; preprint bioRxiv 2025.01.16.633493 |

*Adjacent 2025 work (leads, verify): HighFold3 (AF3+CycPOEM); "Precision Design of Cyclic Peptides using AlphaFold" arXiv:2510.13127.*

### 1.2 De novo design
| Method | What it does | I/O | Strengths | Limitations | Citation |
|---|---|---|---|---|---|
| **RFdiffusion** | denoising-diffusion backbone generation (binders, scaffolds, symmetry) on RoseTTAFold | spec → novel backbone | SOTA backbone generator; validated binders; base for RFpeptides | backbone only (needs MPNN); not cyclic w/o RFpeptides encoding | Watson 2023 Nature 10.1038/s41586-023-06415-8 |
| **RFpeptides** | RFdiffusion + cyclically-symmetric position encoding → N–C closed macrocycle backbones; + ProteinMPNN + Rosetta Relax | target(+hotspots,length) → cyclic backbone+seq | first DL de novo high-affinity binding macrocycles; validated X-ray/NMR sub-Å, nanomolar | compute-heavy multistage; canonical backbone; new | Rettie 2024 bioRxiv 10.1101/2024.11.18.622547 (Nat Chem Biol 2025 **verify DOI**) |
| **ProteinMPNN** | GNN inverse-folding: sequence for a backbone | backbone → sequence(s) | 52.4% recovery (vs 32.9% Rosetta); fast; standard post-RFdiffusion step | backbone-only context; not generative | Dauparas 2022 Science 10.1126/science.add2187 |
| **LigandMPNN** | ProteinMPNN conditioned on non-protein atoms (small molecules, NA, metals) | backbone+ligand → sequence | big gains in ligand/NA/metal contexts; >100 validated | sequence-only; not cyclic-specific | Dauparas 2025 Nat Methods 10.1038/s41592-025-02626-1 |
| **RINGER** | diffusion transformer over internal coords → 3D macrocycle conformer ensembles from 2D | 2D macrocycle → 3D ensemble | fast/diverse ≪ CREST cost; cyclic-aware | conformer ensembles (not target-conditioned design); CREMP chemistry | Grambow 2023/24 arXiv:2305.19800 10.48550/arXiv.2305.19800 |

### 1.3 Docking
| Method | What it does | I/O | Strengths | Limitations | Citation |
|---|---|---|---|---|---|
| **ADCP (AutoDock CrankPep)** | folds+docks in AutoDock FF; MC "crankshaft"; dedicated flexible-cyclic protocol | receptor(grid)+peptide/cyclic → ranked poses | purpose-built for peptides incl. cyclics; larger/flexible peptides; free | rigid receptor default; accuracy drops with long peptides; grid-box dependent | Zhang & Sanner 2019 Bioinformatics 10.1093/bioinformatics/btz459; cyclic 2019 JCTC 10.1021/acs.jctc.9b00557 |
| **Rosetta FlexPepDock** | high-res flexible peptide–protein docking; refinement + ab-initio protocols | receptor+(approx) peptide → sub-Å complex | sub-Å refinement; backbone+sidechain flexibility; ab-initio removes need for good start | needs anchor; sampling-limited for long peptides; Rosetta cost | Raveh 2010 Proteins 10.1002/prot.22716 **(verify)**; London 2011 PLoS ONE 10.1371/journal.pone.0018934 |

### 1.4 Physics-based / sampling
| Method | What it does | I/O | Strengths | Limitations | Citation |
|---|---|---|---|---|---|
| **Rosetta simple_cycpep_predict** | GenKIC closure sampling of backbone-cyclized peptides; design validation filter | cyclic seq(+chirality) → closed conformers + landscape | rigorous closure; D-/ncAAs; validated by 12 X-ray/NMR | CPU-intensive; FF limits; expert setup | Bhardwaj 2016 Nature 10.1038/nature19791 |
| **MD (OpenMM/AMBER/CHARMM)** | all-atom explicit/implicit MD for sampling/stability/binding | topology+FF+coords → trajectories/ensembles/ΔG | physically grounded; parameterizable ncAAs; OpenMM GPU/extensible | slow ring-flip sampling on plain MD; ncAA FF quality | OpenMM 7 Eastman 2017 PLoS Comput Biol 10.1371/journal.pcbi.1005659 |
| **Enhanced sampling (metadynamics/REMD/CREST-xTB)** | overcome ring-flip barriers; CREST+xTB = macrocycle ensemble "gold standard" | structure+CV/xTB → broad ensemble | reaches conformers plain MD misses; underpins CREMP | high cost; CV choice nontrivial; semi-empirical approximations | CREST in Grambow CREMP 2024 Sci Data 10.1038/s41597-024-03698-y; Poongavanam 2020 JCAMD 10.1007/s10822-020-00277-2 |

### 1.5 Conformer generation
| Method | What it does | I/O | Strengths | Limitations | Citation |
|---|---|---|---|---|---|
| **RDKit ETKDGv3** | distance-geometry + torsion preferences; v3 adds small-ring/macrocycle terms | 2D → 3D ensemble | free/open; fast; v3 improves macrocycles; scriptable | needs FF min; weaker energy ranking; very large rings hard | Wang/Witek/Landrum/Riniker 2020 JCIM 10.1021/acs.jcim.0c00025 |
| **Schrödinger MacroModel** | FF conformational search (MCMM/low-mode/mixed) | structure+FF → ensemble | mature, validated; diverse | commercial; can under-sample rings vs Prime-MCS | Poongavanam 2020 JCAMD 10.1007/s10822-020-00277-2; method Mohamadi 1990 JCC 11:440 **(verify)** |
| **Schrödinger Prime-MCS** | macrocycle sampling via ring-opening + loop closure | macrocycle → ensemble | best crystal-conformer reproduction/diversity/speed in 44-complex test | commercial; threshold-dependent | Sindhikara 2017 JCIM 10.1021/acs.jcim.7b00052 **(verify)** |
| **Conformator** | knowledge-based ensemble generator; robust; handles macrocycles | 2D/3D → ensemble | median min-RMSD 0.47 Å (≈OMEGA); free academia | less macrocycle-specialized than Prime-MCS/ETKDGv3 | Friedrich 2019 JCIM 10.1021/acs.jcim.8b00704 |
| **Macrocycle-specific (OMEGA-Macrocycle; cpeptools; RINGER)** | dedicated ring modes: OMEGA (DG+FF), Riniker cpeptools (custom ETKDG bounds), RINGER (ML diffusion) | 2D macrocycle → 3D ensemble | tailored ring sampling; RINGER fast ML | OMEGA commercial; ML limited to trained chemistries | OMEGA Hawkins 2012 JCIM 10.1021/ci300314k **(verify)**; cpeptools github.com/rinikerlab/cpeptools; RINGER arXiv:2305.19800 |

---

## 2. Datasets

| Name | Content | Scale | URL | Access |
|---|---|---|---|---|
| **PDB** | experimental 3D structures; source of curated peptide sets; cyclic entries searchable | >230,000 structures (2026); cyclic a subset | rcsb.org | Open |
| **PepBDB** | cleaned peptide–protein complexes (≤50 aa) + interaction annotations | thousands (updated) | huanglab.phys.hust.edu.cn/pepbdb/ | Open |
| **Propedia (v2.3)** | peptide–protein complexes + clustering/search/signatures | >49,300 complexes (v2.3) | bioinfo.dcc.ufmg.br/propedia2 | Open |
| **CycPeptMPDB** | cyclic-peptide membrane permeability (HELM structures + experimental perm, 45 papers + 2 patents) | 7,334 cyclic peptides | cycpeptmpdb.com | Open |
| **CREMP** | CREST/xTB conformer-rotamer ensembles of macrocyclic peptides for ML; subset w/ permeability | 36,198 macrocycles; ~31.3M geometries; 3,258 w/ permeability | Zenodo 10.5281/zenodo.7931445 | Open (CC) |
| **Riniker/Landrum macrocycle benchmark** | diverse macrocycles (CSD+PDB+BIRD) for conformer-gen benchmarking | 208 macrocycles | SI of 10.1021/acs.jcim.0c00025 | Open (SI) |
| **Prime-MCS macrocycle–protein benchmark** | macrocycles from X-ray complexes for conformer reproduction | 44 complexes | 10.1021/acs.jcim.7b00052 dataset | Open (SI) |
| **AfCycDesign designed set** | hallucinated/designed cyclic scaffolds + validated | >10,000 designs; 8 X-ray-validated | huggingface.co/datasets/RosettaCommons/AfCycDesign | Open |
| **PoseBusters** | protein–ligand (incl. peptide-like) cofolding validation (AF3/Boltz/Chai) | 308 (v1) crystal complexes | github.com/maabuu/posebusters | Open |
| **CASP15/16 targets** | blind structure (15) and affinity (16) benchmarks | dozens/round | predictioncenter.org | Open |

*No single canonical "cyclic-peptide structural benchmark" exists — the field uses the 208-macrocycle set, the 44 macrocycle–protein complexes, CREMP (ML), and curated PDB subsets inside the HighFold/AfCycDesign/RFpeptides papers.*

---

## 3. References
Jumper 2021 Nature 10.1038/s41586-021-03819-2 · Evans 2021 bioRxiv 10.1101/2021.10.04.463034 · Rettie 2025 Nat Commun 10.1038/s41467-025-59940-7 · Kosugi&Ohue 2023 IJMS 10.3390/ijms241713257 · Abramson 2024 Nature 10.1038/s41586-024-07487-w · Wohlwend 2024 bioRxiv 10.1101/2024.11.19.624167 · Passaro 2025 bioRxiv 10.1101/2025.06.14.659707 · Chai 2024 bioRxiv 10.1101/2024.10.10.615955 · Zhang 2024 Brief Bioinform 10.1093/bib/bbae215 · Guo 2025 Brief Bioinform 10.1093/bib/bbaf202 **(verify)** · Watson 2023 Nature 10.1038/s41586-023-06415-8 · Rettie 2024 bioRxiv 10.1101/2024.11.18.622547 **(Nat Chem Biol 2025 verify)** · Dauparas 2022 Science 10.1126/science.add2187 · Dauparas 2025 Nat Methods 10.1038/s41592-025-02626-1 · Grambow 2023 arXiv:2305.19800 · Zhang&Sanner 2019 Bioinformatics 10.1093/bioinformatics/btz459 · Zhang&Sanner 2019 JCTC 10.1021/acs.jctc.9b00557 · Raveh 2010 Proteins 10.1002/prot.22716 **(verify)** · London 2011 PLoS ONE 10.1371/journal.pone.0018934 · Bhardwaj 2016 Nature 10.1038/nature19791 · Eastman 2017 PLoS Comput Biol 10.1371/journal.pcbi.1005659 · Poongavanam 2020 JCAMD 10.1007/s10822-020-00277-2 · Wang 2020 JCIM 10.1021/acs.jcim.0c00025 · Sindhikara 2017 JCIM 10.1021/acs.jcim.7b00052 **(verify)** · Friedrich 2019 JCIM 10.1021/acs.jcim.8b00704 · Hawkins 2012 JCIM 10.1021/ci300314k **(verify)** · PepBDB Wen 2019 Bioinformatics 10.1093/bioinformatics/bty579 · Propedia Martins 2021 BMC Bioinformatics 10.1186/s12859-020-03881-z; v2.3 2023 Front Bioinform 10.3389/fbinf.2023.1103103 · CycPeptMPDB Li 2023 JCIM 10.1021/acs.jcim.2c01573 · CREMP Grambow 2024 Sci Data 10.1038/s41597-024-03698-y (Zenodo 10.5281/zenodo.7931445).

### Verification flags
- HighFold2 journal DOI (bbaf202), RFpeptides Nat Chem Biol 2025 DOI, FlexPepDock-refinement (2010), Prime-MCS (2017), OMEGA (2012), MacroModel (Mohamadi 1990) — confirm final records before external citation (preprints/standard DOIs confirmed; exact journal pages not all re-pulled).
- HighFold3 and arXiv:2510.13127 surfaced as adjacent 2025 leads — vet before use.

## Update log
- **2026-10-08** — Survey created (5 approach subsections + 10-dataset catalog). Next: add HighFold3
  and arXiv:2510.13127 after verification; track Boltz-2 cyclic-affinity validation.
</content>
