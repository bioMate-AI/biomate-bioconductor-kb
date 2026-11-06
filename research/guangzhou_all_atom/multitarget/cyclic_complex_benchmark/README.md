# Cyclic-peptide / macrocycle–protein complex benchmark (curation + feasibility; no GPU run)

Built 2026-10-25 from live RCSB queries. `manifest.csv` = 884 complexes (878 PDB entries). Nothing here ran a
co-folding model. Scripts in `scripts/` (run from a work dir holding the caches; paths are cwd-relative):
`q1.py` (search) -> `gq2.py` (GraphQL fetch) -> `detect.py` (cyclisation rule) -> `iface.py` (per-entry mmCIF, interface)
-> `build_manifest.py` (filters, MMseqs2 clustering, flags). `tests/test_manifest.py`: 7 pytest checks (pass).
Full counts: `stats.txt`.

## What already existed (reused / audited, not reused as data)
`research/guangzhou_all_atom/mine_bound_cyclic_complexes.py` + `data/bound_cyclic/{v1,v2,agg}` (v2 = 784 rows, agg = 776; the "~855"
in docs/20261001_M2C_RETRAIN_ENLARGED_PLAN.md is not literally present in any file I found; that plan cites 235 + v2's 776).
Selection there: RCSB pool = protein entity <=N residues in an assembly with >=2 protein entities (8,807 dropped + 776 kept
of ~9.6k candidates, "cyclic_hit_rate 0.081"), then COORDINATE-based closure detection (SG-SG<2.5 A; C-N<1.8 A; any other
N-C<2.0 A). Audit findings that made me not reuse it as a benchmark:
* no deposit date, no cutoff split, no dedup, no resolution filter; candidate list covers only older IDs (max id 6P4Z -> essentially no post-2019 entries);
* false positives: insulin A-chain (GIVEQCC..; interchain-bonded subunit) is a large block; the "sidechain_backbone" heuristic (N-C<2.0 A) fires on
  ordinary peptide bonds across numbering gaps (HIV V3 peptides HIGPGRAF.., etc.). Of 147 non-insulin in-scope old entries absent from my set,
  104 have no deposited closure record in the pool (spot-checked ones are linear), 42 were removed by the new filters (interchain bond / receptor<40 / interface<5).
New code reuses its idea (RCSB pool) but uses deposited covalent-link records instead of coordinate distances.

## Step 1: candidate query and detection rule
* Search API (polymer_entity): `rcsb_entity_polymer_type = Protein` AND `rcsb_sample_sequence_length 5..25` AND
  `rcsb_assembly_info.polymer_entity_count_protein >= 2` AND `rcsb_entry_info.resolution_combined <= 3.5`
  -> 14,082 peptide entities / 13,641 entries (15,815 / 15,055 before the resolution filter). NMR entries have no resolution and are excluded by design.
* Data API (GraphQL `polymer_entities`): `rcsb_polymer_struct_conn` per chain instance. A chain is a **macrocycle** if it has >=1 deposited
  intra-chain link (disulfide bridge or `covalent bond`, symmetry 1_555) between residues with label_seq_id separation >= 3 (ring >= ~12 atoms).
  Type by atoms: disulfide; head_to_tail_amide (backbone C-N, residues within 2 of both termini); thioether (any S-C); lactam_isopeptide_ester (N/O involved);
  carbon_carbon_staple (C-C). Closure count 1/2/>=3 = monocyclic/bicyclic/polycyclic. Result: 2,849 chain instances in 1,296 entries.
* Exclusions (judgment calls): peptide chain covalently tied to a *different* polymer chain (insulin A-B type; removes covalent protein subunits and covalent inhibitors);
  receptor must be a protein entity of >=40 residues (drops peptide-peptide); peptide must have >=5 residues with a heavy atom <=5 A of receptor
  (asymmetric unit, model 1, no symmetry mates) -> 884 complexes. One row per (entry, peptide entity), using the copy with the largest interface.
* Known recall gaps: closures not recorded in struct_conn; scaffold-bridged bicycles (peptide Cys linked through a non-polymer such as TBMB/TATA) and
  cyclic peptides deposited as non-polymer BIRD/PRD ligands are not detected; disulfide-only "peptides" include natural toxins/hormone fragments (306 rows; the
  weakest definition of macrocycle -- filter on `cyclisation_type` if you want only synthetic macrocycles).

**Precision (manual audit via data API, entity description + closure atoms + title).**
Run 1 (before the interchain exclusion, seed 20261025, 15 random rows): 9/15 = 60% -- 6/15 were insulin A chains. Fixed by the interchain rule.
Run 2 (final rule, fresh draw seed 20261026, 15 rows): 15/15 true bound macrocycles (2VUM_13, 9NX0_1, 4N5T_2, 8QU2_1, 3AVM_2, 9PUT_2, 6WHN_2, 6AYN_3,
7K2Q_2, 2BR8_2, 1CWB_2, 9R9M_3, 5Y7W_2, 7S4G_3, 5LY2_2). 95% Wilson lower bound for 15/15 is ~80%; the sample is small and I looked at
description/links, not at the 3D ring. Recall was not measured.

## Step 2-3: sets, dedup, composition (all numbers from manifest.csv)
Cutoffs relied on (deposit date, which is <= release date, so deposit>=cutoff is leakage-safe for release-date cutoffs):
AlphaFold3-class / Protenix-base: 2021-09-30 (Protenix README table, fetched; AF3 value taken as "aligned with AlphaFold3" per that README).
Protenix `protenix_base_20250630_v1.0.0`: 2025-06-30 (same README; this model trains on newer data, so the 2023-10 "post" set is NOT clean for it).
Boltz-2: 2023-06-01 -- from secondary web sources only (search summary of the Boltz-2 paper/NIM model card); the primary paper fetch was rate-limited -> **UNVERIFIED primary**.
Chai-1: cutoff **UNVERIFIED** (not found in README/blog; I recall 2021-01 but did not verify). The study cutoff 2023-10-01 is later than all verified/secondary dates except Protenix-applied.

| set | complexes | receptor clusters (MMseqs2 40% id, 80% cov) |
|---|---|---|
| all | 884 | 225 |
| PRE (<2023-10-01) | 686 | 179 |
| POST (>=2023-10-01) | 198 | 82 (46 have no pre-cutoff member *in this set*) |
Peptide clusters (60% id, cov 0.8; short-peptide clustering is approximate): pre 376, post 139.
Deposits per year: 1989-2000 sparse; 2015 58, 2016 52, 2019 43, 2020 60, 2021 48, 2022 61, 2023 65, 2024 83, 2025 78, 2026 (to Oct) 14 (full table in stats.txt).
Peptide length: 5-25, mode 11 (115); post median ~14. Cyclisation (all): disulfide 306, head-to-tail 198, lactam/isopeptide/ester 173, thioether 105, staple 71, mixtures 31;
monocyclic 765 / bicyclic 102 / polycyclic 17. Post: head-to-tail 52, thioether 46, disulfide 43, lactam 36, staple 15, disulfide+H2T 6.
Method: 760 X-ray, 124 cryo-EM (post: 136 / 62). Non-canonical content: 75.2% of complexes contain >=1 non-standard component (84% in post); this counts
terminal caps ACE (185) / NH2 (206). 434 distinct CCD ids; most frequent: NH2, ACE, MLE, DAL, MVA, SAR, ABA, BMT, DTY, MK8, DPR, DTR, HYP, MAA, MP8, NLE, BAL, ALY, DPN, DCY (full list in stats.txt).
Judgment calls: 40% id/80% coverage on the primary receptor entity only (multi-chain receptors clustered by the entity with most contacts); Fabs/antibodies cluster loosely at 40%.

## Step 4: feasibility for co-folding (docs fetched from GitHub main, 2026-10-25)
* Boltz (jwohlwend/boltz `docs/prediction.md`): YAML; polymers get `cyclic: true|false` (whole chain, head-to-tail); `modifications: [{position, ccd}]` for non-standard residues; `constraints: bond` (atom1/atom2, "currently only supported for CCD ligands and canonical residues"); ligands by `ccd` or `smiles`. README is silent on training cutoff. Whether D-residues/N-methyl CCD "modifications" are well handled by Boltz-2 is UNVERIFIED.
* Chai-1 (chaidiscovery/chai-lab README + examples/covalent_bonds/README): non-standard residues as CCD codes in parentheses in the FASTA, e.g. `RKDES(MSE)EES`; covalent bonds via restraints CSV, but "Chai-1 was not trained on intra-chain bonds (e.g. disulfides) and we have not evaluated..." -> no documented cyclic flag/head-to-tail support (UNVERIFIED beyond README).
* Protenix (bytedance/Protenix `docs/infer_json_format.md`): `proteinChain.modifications[{ptmType:"CCD_xxx", ptmPosition}]`; `covalent_bonds` between polymer residues "generally not supported" except cyclic peptides: head-to-tail amide and disulfide.
Runnable flags (manifest): `runnable_strict` = all 20-standard residues AND every closure expressible (head-to-tail via cyclic/bond; other closures only if both bonded residues canonical); `runnable_ccd` = non-standard residues allowed as CCD modifications (incl. caps; D-residue handling and cap-as-residue are UNVERIFIED) but closures must join canonical residues (or be head-to-tail). Both are about Boltz-2 expressibility; Chai-1 and Protenix are narrower (Protenix: only head-to-tail/disulfide).
Counts (all 884): strict = 187 pre + 32 post = 219; runnable_ccd = 405 pre + 98 post = 503.
Main blocker for the rest: closure through a non-standard residue (e.g. chloroacetyl-Tyr/Cys thioether, RaPID 48V lactam, MK8 staples).

## Step 6: the headline number
POST-cutoff (>=2023-10-01), non-redundant (one per 40% receptor cluster), runnable:
* strict (canonical-only, expressible): **32 complexes / 23 independent receptor clusters** -> **< 30: underpowered**.
* ccd tier: 98 complexes / **48 clusters** (24 of them with receptor not represented pre-cutoff in this set).
* Strictest model cutoff (Protenix-applied, >=2025-07-01): 55 complexes / 23 clusters; runnable_ccd 31 / 14; strict 8 / 6.
Alternative cutoffs (>= date): 2021-10-01: 305 cx / 115 clusters, ccd-runnable 146 / 64 clusters, strict 56 / 30 clusters; 2023-06-01 (Boltz-2): 212 / 85, ccd 100 / 49, strict 32 / 23.
Only 42 of 82 post receptor clusters have a single complex, the largest has 18 -> per-target bootstrap is weak for most targets (bootstrap over clusters, not complexes).
Recommendation: (1) report strict and ccd tiers separately, claim "powered" only for the ccd tier (48 > 30) with the caveat that NCAA/CCD handling is unverified;
(2) to get >=30 strict clusters add a model-specific split (cutoff 2021-10-01 gives exactly 30 strict clusters, but leaks for Boltz-2 which trained to 2023-06), or add pre-cutoff
complexes with an explicit leakage covariate (pre ccd-runnable: 105 clusters) and analyse calibration against "max sequence identity of receptor to training PDB";
(3) extend recall (scaffold-bridged bicycles, BIRD ligands) and re-pull quarterly (this set grows ~80 deposits/yr -> ~+25 clusters/yr).

## Scoring plan
Per complex, per model, per seed x diffusion sample: align on receptor Calpha of the binding-site chain(s) (<=10 A of peptide in the crystal); metrics: DockQ (peptide as ligand
chain; DockQ v2 handles NCAA by backbone/heavy-atom mapping, mapping NCAA is the risk), peptide backbone iRMSD, ligand RMSD after receptor alignment (heavy atoms, symmetry-corrected),
interface-residue recovery (contacts <=5 A), and ring geometry check (closure atoms distance within 0.3 A of ideal). Success = DockQ>=0.23 (acceptable) / >=0.49 (medium).
Calibration: ipTM, ranking_score (Boltz/Protenix/Chai aggregate) vs DockQ -> reliability curve (bin ipTM, mean success), ECE, AUROC of ipTM for DockQ>=0.23, Spearman per model;
CIs by cluster bootstrap (resample receptor clusters, then complexes within cluster; 10k reps). Report separately by cyclisation type, length bin, pre/post, and receptor-seen-in-training flag.
Baselines: (a) random placement of the peptide (conformer from a CCD/ETKDG ensemble) at the known site, rigid receptor, best-of-N = same sample budget; (b) known-binding-site template null: transplant the pose of the nearest-in-sequence *other* complex's peptide
(same receptor cluster, leave-one-out, receptor-aligned) -> measures how much is learnable from a site prior; (c) shuffled-ipTM null for calibration. Do not score a model on complexes with deposit date <= its own cutoff in the headline.

## GPU cost estimate (assumptions; NOT run, prices UNVERIFIED)
Assume 3 models (Boltz-2, Chai-1, Protenix) x 5 seeds x 5 diffusion samples/seed (one run per seed ~3 min incl. recycling, avg complex 300 aa + peptide; MSAs from a one-time ColabFold server pass per receptor cluster, not counted), spot g6.xlarge (L4 24 GB) at assumed $0.35/h (on-demand assumed ~$0.8/h).
minutes = complexes x 3 x 5 x 3.
| scope | complexes | GPU-hours | spot cost | on-demand |
|---|---|---|---|---|
| post, strict | 32 | 24 | ~$8 | ~$19 |
| post, ccd tier | 98 | 73.5 | ~$26 | ~$59 |
| all runnable_ccd (pre+post) | 503 | 377 | ~$132 | ~$302 |
Wall clock is parallel (N instances); large cryo-EM receptors (>1,500 aa) may need g5/A10G-or-bigger memory and 2-4x time; add ~30% for retries.
