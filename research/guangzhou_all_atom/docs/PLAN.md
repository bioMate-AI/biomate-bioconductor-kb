# Peptide-first implementation plan

The Guangzhou program starts with peptides. This plan operationalizes the accompanying survey; it does not assume the partner has selected a target, chemistry or deployment platform.

## 1. Shared representation and evaluation — started

Implement chemical identity auditing across generator outputs before adding model-specific scoring. Preserve full stereochemical graphs, count failed attempts, detect exact training-set overlap, and distinguish graph identity from predictive reliability. The first implementation is `evaluate.py` with tests for peptide identity, cyclic atom-order equivalence, enantiomer distinction, salts, unspecified stereo, invalid samples and incomplete reference handling.

Next extend the candidate contract with SDF coordinates, monomer-to-atom mapping, terminal chemistry, explicit closure/crosslink edges and requested versus observed topology. Require topology validation against the requested design; a molecule being cyclic is not proof of the correct closure. Keep raw structures separate from relaxed structures. Preserve all sampling attempts before upstream filters, with an explicit counter for discarded/unserialized attempts.

## 2. Baseline qualification

Run BoltzGen's peptide protocol on an official benign example, then add PepGLAD or PepFlow on a matching canonical-peptide task. For cyclic peptides include RFpeptides; for modified peptide chemistry qualify PepTune and inspect PepALD's current artifacts. Record exact source revision, checkpoint checksum, environment, seed, atom/residue vocabulary and each supported covalent topology. Do not silently substitute an unsupported chemistry.

Begin with a bounded smoke sample to verify I/O and atom mapping. Then freeze a multi-target benchmark with at least three independent seeds and a fixed attempt budget per target. Choose the final number of targets after inspecting available data and estimating sampling cost; a small smoke test is not a scientific comparison. Keep a known-binder or conservative sequence-mutation control alongside learned generation.

## 3. Data and split ledger

Inventory target–peptide structures and measured activity, stability, solubility and permeability data. For modified peptides preserve chemical structure, not only sequence. Record assay source, conditions, units, censoring, monomers, cyclization and synthesis failures. CycPeptMPDB is a candidate permeability source; inspect licensing and original assay provenance before ingestion.

Create molecular-identity, peptide-family, target-family and temporal split reports. Compare every pretrained baseline's disclosed training data/cutoff against the test panel. Unknown training exposure must remain explicit. Freeze test data before adaptation and use validation data for checkpoint selection.

## 4. Target-conditioned adaptation

First adapt a qualified baseline using the partner's permitted peptide data. Test full fine-tuning versus adapter tuning, with a frozen baseline and equal-data specialist control. Do not start universal-model pretraining until the unified representation passes a reconstruction benchmark for all included chemistries.

Candidate contribution: a monomer/atom model preserving covalent topology and stereochemistry while using calibrated endpoint-specific feedback. Ablations: no adaptation; target adaptation only; chemistry-aware adaptation; measured-property feedback; uncertainty-aware selection; shared versus separate modality training. The study must distinguish improved generation from stronger filtering or a larger sampling budget.

## 5. Prospective DMTA

Connect validated candidates to the existing BioMate model registry and campaign optimizer. Add peptide endpoint adapters rather than using small-molecule QED/SA thresholds as peptide acceptance criteria. Use target-specific potency/selectivity, relevant stability and exposure, synthesis feasibility and diversity. Record applicability-domain warnings independently of novelty.

Deliver a synthesis-ready record with monomer identities, stereochemistry, terminal modifications, crosslinks and purity requirements. Ingest measured results and failures; rerank and update only with versioned training/validation rules. Compare against the agreed partner baseline at equal synthesis/assay budget.

## 6. Expansion

After peptide validation, add a small-molecule branch using FLOWR.root/FLOWR and REINVENT4 controls; FlowMol3 is an unconditional chemistry reference. Test UniMoMo-style shared representations only where they improve per-modality results. PROTACs, glues and conjugates require separate task contracts and mechanism-relevant endpoints.

## Acceptance evidence

- Software: malformed records fail visibly; identity invariance and stereochemistry preservation pass tests; missing measurements remain missing.
- Model: documented supported chemistry, reproducible outputs, raw attempt accounting, and correct requested topology.
- Scientific: blinded held-out performance against relevant baselines with uncertainty intervals and no test-driven tuning.
- Project: prospective synthesis and measured endpoint results trace to exact candidates and model versions.

## Current status and dependencies

The survey and first chemical-identity evaluator are implemented. No generator inference, model training, target-specific potency evaluation or wet-lab experiment has been performed in this work. The local RDKit environment supports the initial audit. A shell attempt to resolve the upstream FLOWR.root repository failed because network DNS was unavailable; its public documentation was accessible through web research. That small-molecule repository is not a dependency of the peptide-first audit.

The next model run needs a qualified checkpoint/runtime and an example or project target. Partner-specific training additionally needs the selected peptide chemistry and permitted assay data. These dependencies do not prevent representation/evaluation development.

## Execution update

Dataset collection is complete for the first structural baseline: PepBench v2 train/validation, LNR held-out test, ProtFrag augmentation and README are verified in S3. Existing CycPeptMPDB is reused. See `DATA_COLLECTION_AND_START.md` and `results/active_run.json` for the bounded AWS launch and actual training evidence; the earlier pre-launch status above is historical.
