# Peptide Model — Evaluation Protocol for Publication (tasks · benchmarks · metrics · competitors)

**Date:** 2026-09-27 · **Status:** manuscript evaluation spec (internal — method/metric detail).
**Purpose:** define, at publication rigor, *what we measure, on what data, against whom* — so every claim in
the paper is falsifiable and head-to-head. Grounds on `20260926_PEPTIDE_SOTA_AND_WHITESPACE.md` (SOTA-per-metric),
`20260927_CYCLIC_CORPUS_AND_TRAINING_STRATEGY.md` (split/leakage discipline), `20260926_PEPTIDE_LLM_ARCHITECTURE_IP.md`
(the claims), `20260925_PEPTIDE_EXECUTION_PLAN.md` (the loop).

---

## 0. Evaluation philosophy (the rules the reviewers will hold us to)

1. **Claims-driven.** Every task exists to test one paper claim. No claim without a task; no task without a
   named public benchmark, a defined metric, and ≥1 competitor + a naive baseline.
2. **Head-to-head on a SHARED split, not a table of self-reported numbers.** The literature has *no* common
   cyclic benchmark — cross-paper rankings are directional only. So for every competitor with open code
   (PepGLAD, PepFlow, RINGER, PeptideCLM, HELM-BERT, CycPeptMP, ProteinMPNN), we **re-run it on our unified
   benchmark + split**. Self-reported numbers are used *only* where code is unavailable (RFpeptides,
   AlphaProteo — flagged in every table). This is the single biggest credibility lever.
3. **Multi-metric, never a single number.** Report the full panel; a model that wins DockQ by collapsing
   diversity is worse. (The 0.557-plateau lesson.)
4. **Leakage-honest splits, frozen before training.** Family-disjoint (sequence + scaffold + receptor-fold);
   report train/test nearest-neighbor similarity so reviewers can audit contamination.
5. **Physics baseline + naive baseline everywhere.** If a neural method can't beat AutoDock Vina / FEP and an
   RF-on-ECFP4 / train-mean, it doesn't earn the complexity.
6. **Experimental validation is the ceiling of the claim.** In-silico DockQ/ΔG are necessary, not sufficient;
   the binder and loop claims are gated on wet-lab (Section 8).

---

## 1. Tasks (each maps to a paper claim)

| Task | Capability / claim | Component | Paper role |
|---|---|---|---|
| **T1 — Canonical peptide–protein co-design** | We match the field on the standard task | generator | base competence (table-stakes) |
| **T2 — Macrocycle geometry / conformer generation** | AE learns valid cyclic geometry | AE | validates the latent (M1) |
| **T3 — Non-canonical macrocycle generation** | Native N-Me/D-AA/staple generation | rep #1 + generator | **crown differentiator** |
| **T4 — Target-conditioned de-novo cyclic binder design** | The unbuilt intersection | full system | **headline result** |
| **T5 — Developability / permeability prediction** | Calibrated developability heads | verify heads | supports guidance + loop |
| **T6 — Closed-loop DMTA lift** | Loop compounds on proprietary data | loop A1–A4 | **the moat** (honest limiter) |

---

## 2. Benchmark data (named, sized, sourced, split)

| Dataset | Task | Size | Content | Access | Split |
|---|---|---|---|---|---|
| **PepBench** | T1, T4 | ~ curated peptide–protein complexes | seq + full-atom 3D + receptor | PepGLAD release | PepGLAD's split (comparability) **+** our family-disjoint recut |
| **PepBDB** | T1 | ~13k complexes (cyclic subset small) | experimental peptide–protein | pdbbind/pepbdb | family-disjoint |
| **CREMP** | T2 | 36,198 macrocycles / 31.3M conformers | xTB solution conformers | Zenodo/Sci Data 2024 | scaffold-split, **per-molecule** hold-out (never split a molecule's conformers) |
| **Experimental macrocycle NMR ensembles** | T2 | small (10s–100s) | solution NMR reference | literature/PDB | eval-only oracle |
| **CycPeptMPDB** | T3, T5 | **~7,334** unique | permeability (Papp) + SMILES; ncAA-rich | cycpeptmpdb.com | scaffold-split (mandatory — random-split inflates) |
| **nme_v1 (ours)** | T3 | 1,225 N-Me | native N-Me macrocycles + structure | S3 `cyclic_peptide/datasets/nme_v1` | family-disjoint |
| **TDC-ADME suite** | T5 | 20+ tasks | sol/perm/logD/PPBR… | `pip install PyTDC` | TDC scaffold-split |
| **Held-out cyclic-binder targets** | T4 | small curated | targets from RFpeptides/EvoBind2 for comparability | from those papers | **receptor-fold-disjoint** from training |
| **cyclic_corpus_v1 (ours, frozen eval)** | all | ~36–42k | assembled + de-duped + provenance-tagged | S3 (Part A of corpus doc) | eval frozen **before** training |

**Provenance tag on every structure** `{PDB_experimental | NMR_experimental | xTB_CREMP | ETKDG | HighFold3}`;
metrics stratified by provenance. Bound-geometry claims use experimental-only test subsets.

---

## 3. Metrics (per task, with definitions)

**T1 — Canonical co-design (the 7-metric panel + stability):**
- **DockQ** (0–1, interface quality; Success = DockQ ≥ 0.23 or field threshold)
- **RMSD-Cα** (Å, backbone) and **full-atom RMSD** (Å)
- **AAR / Slide-AAR** (%, amino-acid recovery, alignment-robust)
- **Consistency** (does the generated sequence fold to the generated structure — refold RMSD)
- **Diversity** — Sequence, Structure, Codesign (pairwise, must not collapse)
- **Stability / ΔG** (Rosetta ddG or MM-GBSA on the designed complex)

**T2 — Geometry / conformer (AE):**
- **Ring-closure validity** (%), **stereochemistry validity** (%), **clash score**
- **Reconstruction all-atom RMSD** (Å)
- **Ensemble coverage / precision** (GEOM-style recall/precision vs reference within RMSD threshold; vs NMR where available)
- **Ring-strain energy** distribution vs xTB reference (distribution match, not point error)

**T3 — Non-canonical generation:**
- **Chemical validity** (%, parseable + valence/chirality-correct)
- **Modification recovery / accuracy** (does it place the *requested* N-Me/D-AA/staple? — the silent-collapse guard)
- **Novelty** (fraction not in training, Tanimoto < 0.4) + **Uniqueness**
- **Developability shift** — permeability (ΔPSA3D) / SA distribution of generated ncAA **vs canonical-only** (the capability payoff)
- **Synthesizability** (SA score / retrosynthesis feasibility)

**T4 — Target-conditioned binder design:**
- In-silico: **DockQ**, **ΔG (FEP / MM-GBSA)**, **predicted binding success rate**, novelty, diversity
- **Experimental (gold):** measured **Kd / IC50 / EC50**, **hit rate** (% with measurable binding), **best affinity**, **synthesis yield** — reported per target, with #compounds-synthesized (the RFpeptides yardstick: ~20/target)

**T5 — Developability prediction:**
- **Spearman ρ**, **Pearson r**, **RMSE**, **MAE** on log Papp (regression)
- **AUROC / AUPRC** for permeable-vs-not (classification)
- Reported on **scaffold-split** with a random-split comparison to expose inflation

**T6 — Closed-loop DMTA:**
- **Developable-candidate yield lift** per round (7-metric panel, no diversity collapse)
- **Hit-rate improvement** round-over-round; **sample efficiency** (rounds/compounds to target)
- **Prospective predicted→measured correlation** (the honest proof)
- Baselines: no-loop single-shot, random batch, greedy (no diversity), physics-only ranking

---

## 4. Competitors & baselines (per task)

Legend: **[OSS]** = open code, we **re-run on our split**; **[SR]** = self-reported only (no code), flagged in tables.

**PRIMARY CO-DESIGN COMPARATOR (T1 + T4) — the head-to-head:**
- **APCyc** [OSS, KDD 2026] — pocket-conditioned full-atom joint seq+struct latent-diffusion **cyclic** co-design
  + Bayesian multi-property loop; same PepGLAD lineage as us. **We must match it on the shared panel and add the
  sidechain-ncAA axis it lacks.** Beating APCyc is the gating experiment for the co-design claim.
- **CP-Composer** [OSS, ICML 2025] — zero-shot cyclic (staple/head-to-tail/disulfide/bicycle) on PepGLAD, full-atom, target-binding.

**T1 Canonical co-design** — targets to beat (verified, all self-reported on own splits):
- **PepGLAD** [OSS, MIT] — DockQ 0.592 · Diversity 0.506 · Consistency 0.789 · Success 55.97% · RMSD-Cα 4.09 Å (linear)
- **PepFlow** [OSS, MIT] — AAR 51.25% · RMSD-Cα 2.07 Å · Designability 65% (linear)
- **D-Flow** [OSS, license unconfirmed] — AAR 58.69% · RMSD-Cα 1.63 Å · Designability 75% (linear D-peptides — mirror, not cyclization)
- **MultiFlow** [OSS, MIT] — co-designability PMPNN@8 81.4% (linear); **RFdiffusion+ProteinMPNN** [OSS, BSD/MIT]
- **Newer successors to verify/add:** SurfFlow (AAR 54%), **PepBFN** (AAAI 2026, THU PepGLAD-successor), A-CODE (81.2%), FoldFlow-2
- Physics: **Rosetta FlexPepDock / AutoDock Vina**. Naive: random sequence + native backbone, native-rotamer.

**T2 Geometry (AE):**
- **RINGER** [OSS, MIT] — macrocycle-peptide SOTA: **coverage-recall 79.7%** vs ETKDG 35.8% / OMEGA 32.3%; needs SLSQP ring-closure post-processing; trained on 4/5/6-mer canonical sidechains (match or retrain for our split)
- **RDKit ETKDGv3-macrocycle** [OSS, BSD] — free default baseline; **CREST/xTB** (CREMP data oracle)
- **OMEGA-macrocycle** [proprietary — **academic-only license, excludes CRO/commercial**; cannot use in our commercial context]
- **PuckerFlow** (2026) — fixes post-hoc closure but on 5–8-membered rings, not peptide macrocycles (not like-for-like)

**T3 Non-canonical generation** — these are receptor-blind (the whitespace):
- **PepINVENT** [OSS] — ncAA chem-LM (CHUCKLES); **PepTune** [OSS] — multi-objective ncAA; **NCFlow** [SR] — structure-aware ncAA (mutation, not de-novo)
- Comparison framing: **match their ncAA chemical validity while adding full-atom 3D + target conditioning they lack** (capability matrix, Section 6).

**T4 Target-conditioned cyclic binders** — experimental bar (verified):
- **RFpeptides** [OSS, BSD] — **6 nM (GABARAP) / 9.4 nM (RbtA)**, µM on MCL1/MDM2; hit rate **21–37%**; 4 targets;
  **~6–14 synth/target**; crystal Cα-RMSD 0.7–1.4 Å. **All-canonical L-AA — the affinity bar, and it needs no ncAA.**
- **EvoBind2** [OSS, CC-BY-**NC** → non-commercial] — 19 nM best, 46% sub-µM, 75% cyclic success, sequence-only
- **HFGuidedDesign** [OSS, Chem Sci 2026] — MDM2 ~1.2 µM / 75% success, canonical seq-only; **HighPlay2 / CycleRFdiffusion** — target+cyclic search pipelines w/ wet-lab hits (µM), some ncAA
- **Context, NOT cyclic competitors:** AlphaProteo [SR, closed] + BindCraft [OSS] are **protein-binder** methods
- Physics: **Vina/FEP** on random cyclics (zero-data reference).

**T5 Developability prediction** (verified — report scaffold-split; random-split is inflated):
- **HELM-BERT** [OSS, MIT] — **PRIMARY comparator**: scaffold-split **R² 0.483** (random 0.668); custom-split ready
- **DMPNN** [OSS] — winner of the 13-method benchmark, random R² 0.555 (collapses on scaffold); **CycPeptMP** [OSS, MIT] R² 0.772 **but Kennard–Stone split — not comparable**
- **PeptideCLM** [OSS] (random R² 0.536), **MolFormer-XL** [OSS] baseline (random R² 0.578); **RF/XGBoost on ECFP4** — mandatory floor
- **Honest scaffold-split ceiling ≈ R² 0.48–0.50.** Reference protocol: **"Systematic benchmarking of 13 AI methods for cyclic-peptide permeability"** (JCIM 2025).
- **Strategic threat (data moat):** **PEGASUS** (J Med Chem 2026) — billions of cyclic peptides via massively-parallel NGS assays + de-novo design. Track it; differentiate our moat as *learned generator on proprietary pharma data*, not HT-assay throughput.

**T6 Closed loop:** baselines are ablations of our own loop (no-loop / random / greedy / physics-only). **External comparators to distinguish from:** **GALILEO** (embodied AI-scientist, wet-lab in the loop — differentiate as *peptide-specialized generator + proprietary pharma data*, not a general agent) and **PEGASUS** (HT-assay flywheel — differentiate as *learned generator*, not assay throughput).

**Ablations (own model — required for the method claims):**
- Training strategy: AE init {small-mol, linear-epoch221, random}; generator curriculum stages {binding-prior, +cyclic-mid-train, +target-SFT}
- Representation: {atom-level, residue-level, topology-explicit}
- IP components: −rep#1, −hard-closure#3, −DPO#4, −consistency-objective (leave-one-out)

---

## 5. Splits, leakage & statistics

- **Splits:** family-disjoint by **sequence identity (≤40%, local-align on cyclized seq) + Bemis-Murcko-alternative scaffold (Tanimoto-MaxMin) + receptor-fold** (for T1/T4). **Freeze eval before assembling training.** Report **median train/test nearest-neighbor Tanimoto** (< 0.35 target) in every table.
- **CREMP special case:** hold out **whole molecules**, never conformers of a train molecule.
- **Benchmark-as-training leakage:** CREMP-CycPeptMPDB is the standard permeability benchmark → excluded from training when used as T5 eval.
- **Statistics:** ≥3 seeds; report **mean ± std**; **paired Wilcoxon signed-rank** for model-vs-competitor on per-target/per-compound metrics; **Benjamini-Hochberg** correction across metrics; bootstrap 95% CIs for aggregate rates (hit rate, success rate).
- **Compute-matched comparison:** competitors re-run at matched sampling budget (#samples/target) — report it.

---

## 6. The intersection claim — capability matrix (the headline figure)

**⚠️ Updated 2026-09-27 after the verified competitor pass — the intersection is now PARTLY OCCUPIED.**
The co-design core (full-atom + target + de-novo + cyclic) is held by **APCyc (KDD 2026)** and **CP-Composer
(ICML 2025)**, both PepGLAD-derived. The claim must be written at the **narrow surviving cell** and the
"native ncAA" column split into **sidechain ncAA (N-Me/D-AA/staples)** vs **linkage/PTM chemistry** — that
split is the whole differentiation.

| Method | sidechain ncAA (N-Me/D-AA/staple) | full-atom 3D | target-*structure* conditioned | de-novo (not mutation) | cyclic co-design |
|---|:---:|:---:|:---:|:---:|:---:|
| PepGLAD / PepFlow / D-Flow / MultiFlow | ✗ | ✓ | ✓ | ✓ | ✗ (linear) |
| **APCyc** (KDD 2026) | ✗ (linkage only) | ✓ | ✓ | ✓ | ✓ |
| **CP-Composer** (ICML 2025) | ✗ (geom. constraint) | ✓ | ✓ | ✓ | ✓ |
| RFpeptides | ✗ (L-canonical) | ✓ | ✓ | ✓ | ✓ |
| NS-Pep | ⚠️ (PTM-dominated) | ✓ | ✓ | ✓ | ✗ (not cyclic-primary) |
| NCFlow | ✓ | ✓ | ✓ | ✗ (mutation/DMS) | ✓ |
| PepALD / PepINVENT / PepTune | ✓ | ✗ (SMILES/HELM) | ✗ | ✓ / ✗ | ✓ |
| **Ours** | **✓** | **✓** | **✓** | **✓** | **✓** |

**The narrow surviving claim (write exactly this):** *full-atom cyclic-peptide co-design at a receptor pocket
with **native sidechain** non-canonical chemistry (N-Me/D-AA/staples as first-class residues — not
cyclization-linkage tokens (APCyc/CP-Composer) or PTM residues (NS-Pep)), de-novo (not mutation, cf. NCFlow).*
Each ✓ backed by a task (sidechain-ncAA→T3, 3D→T2, target→T4, de-novo→T4, cyclic→T4). **Do NOT claim** "first
non-canonical" (PepINVENT) or "first cyclic co-design" (APCyc). **Name and distinguish APCyc, CP-Composer,
and NS-Pep explicitly in related work — reviewers will raise them.**

**The honest ncAA caveat (load-bearing):** RFpeptides reaches nM with all-canonical chemistry → native ncAA
is **not an affinity advantage**. The T3/T4 ncAA claim is only valid if tied to a **developability result**
(permeability / oral / protease-stability the canonical binder can't reach) — a DockQ delta alone does not
justify the ncAA machinery.

---

## 7. Honest calibration (what we will NOT claim)
- Multi-objective in-sampling guidance is **prior art** — presented as a held capability, not a novelty.
- The backbone (latent-diffusion-over-AE) is **leveraged** — not claimed as invention.
- In-silico ΔG/DockQ is **not** binding proof — the binder claim is gated on T4 experimental.
- Generated-conformer quality (T2) is **not** evidence of binding (distinct claim).

---

## 8. Experimental validation (the ceiling of T4 & T6)
- **T4 binder claim:** synthesize a matched panel per held-out target (target the RFpeptides yardstick,
  ~20/target), measure Kd/IC50; report hit rate + best affinity vs the experimental competitors. IP-clean CRO.
- **T6 loop claim:** one **prospective** DMTA round on a real target — predict, synthesize, assay, show
  predicted→measured lift over the no-loop baseline. Until this exists, the loop is described as
  *architecture + retrospective replay*, with prospective validation as stated future work (the honest limiter).

---

## 9. Reproducibility (for the venue)
- Release: the **frozen splits**, the assembled public-subset benchmark, seeds, configs, and eval harness.
- Report compute (GPU-hours), sampling budgets, and competitor commit hashes for every re-run.
- Provenance and leakage tables shipped as supplementary.

---

## 10. Pre-submission checklist (falsification gates)
- [ ] Every claim ↔ a task ↔ a public benchmark ↔ a metric ↔ ≥1 competitor + naive baseline
- [ ] All OSS competitors re-run on our shared split (SR ones flagged)
- [ ] Full panel reported (no single-metric wins); diversity not collapsed
- [ ] Family-disjoint splits + train/test similarity table; CREMP per-molecule hold-out
- [ ] ≥3 seeds, error bars, paired significance + multiple-comparison correction
- [ ] Physics + naive baselines present in every quantitative table
- [ ] Ablations for rep #1 / closure #3 / DPO #4 / curriculum stages
- [ ] Capability matrix backed by task evidence per ✓
- [ ] T4/T6 experimental status stated honestly (measured vs future work)
