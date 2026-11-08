# Cyclic-Peptide Drug-Development — Integration Map (tools + DBs) & Where Our Novel Work Fits

**Date:** 2026-10-04. Priority #1 = complete, mature integration of all tools+DBs. Priority #2 = our own novel work inside it (faster OR more accurate — real but bounded; prior work in an area ≠ no room). Built from the actual asset inventory, not memory.

## Pipeline stages → what we HAVE → maturity / gap
| Stage | Our assets (held) | Maturity | Gap to close |
|---|---|---|---|
| **Target/pocket prep** | boltzgen_ourtarget (pocket from native ligand), avb6_pocket_truncate, rcsb_cyclic_index | works | standardize pocket extraction as one module |
| **Binder generation** | BoltzGen, UniMoMo (+cyclic-FT), PepGLAD/M2c, **RFpeptides** (launcher ready) | multiple generators, standalone | one entry point + method selection |
| **Cyclic folding / self-consistency** | Boltz refold (refold_rerank), cyclize_and_rescore; RFpeptides filter (AfCycDesign/CyclicBoltz1) | partial, fragile installs | robust folder env; MSA caching (the refold bottleneck) |
| **Binding affinity** | MM-GBSA (launch_mmgbsa_pool), **binding_affinity_v1 (136k measured)**, FEP poc, binding_features; **Track-A real model building now** | proxy→real in progress | finish the real-data model; wire as the binding scorer |
| **Permeability** | **CycPeptMPDB (8.5k)**, permeability_predictor, conformer_permeability, build_physchem_calibration, perm_uncertainty, perm_size_correction | strong (field R²≈0.77) | adopt a current SOTA perm model; OOD still weak |
| **Developability / multi-objective** | developability_guidance, multi_property_selection, property_guided_selection, peptide_gate | composite works (hand-tuned) | principled MO (qNEHVI) — Track A2 |
| **Synthesizability** | SA score, noncanonical_vocab, nme (N-methylation) | partial | synth-route feasibility, scale |
| **Synthesis (CRO)** | GenScript RFQ/email (send-ready) | external | — |
| **Assay (SPR)** | GenScript SPR request; campaign_assay_to_pairs; assay ingestion | external + ingest | — |
| **Closed loop (Learn)** | dpo_pairs, dpo_peptide_trainer, dpo_unimomo_adapter, **wetlab_kd_to_pairs**, campaign_assay_to_pairs | built, synthetic-verified | turn on REAL CRO KD (pending round-1) |
| **Benchmarks/eval** | cyclic_eval, official_eval, cyclic_benchmark_eval, collect_experimental_benchmarks | works | one leakage-controlled harness |
| **Databases** | PDB, **CycPeptMPDB**, **binding_affinity_v1 (ChEMBL+BindingDB)**, **CREMP (36k conformers)**, MacroConf, PepBDB, PepBench, approved drugs, PeptideCLM/PepMSND, HELM monomers, nme | comprehensive | one unified data registry |

**Integration verdict:** we have ~the entire pipeline + an unusually complete data holding. The real work for #1 is **orchestration + maturity** (wire the scattered scripts into one coherent, tested target→generate→fold→score→select→synth→assay→learn flow with a unified data registry + a robust folder env), not acquiring new tools.

## #2 — where our OWN novel work fits (calibrated: faster OR more accurate)
Prior work exists in each area, but there is room for a real improvement **where we have an edge: we uniquely hold permeability + binding + conformers + structures together.** Candidates (to validate, not assert):
1. **Accuracy via multi-modal / multi-task (our data edge).** Single-property models are the norm; a joint model that uses CREMP *conformers* to inform BOTH permeability AND binding (shared conformational representation) could be more accurate — especially the acknowledged weak spot, **out-of-distribution** prediction (perm OOD R²≈0.19). We're one of the few holding all modalities jointly. This is "more accurate," bounded, testable (vs single-property baselines, incl. OOD split).
2. **Speed in the loop.** The self-consistency fold (1–2 min/fold) is the DBTL bottleneck; a learned fast designability/self-consistency surrogate replacing per-candidate co-folding = real speedup, measurable (throughput, correlation to true scRMSD).
3. **OOD-robust scoring** via the closed loop (active learning on our proprietary assay data) — incremental OOD gains, honestly measured.

**Honest framing:** these are "faster / more accurate" contributions within a mature platform — real, bounded, publishable as method+platform improvements — not a paradigm breakthrough (none is available, verified). The data-edge multi-modal accuracy play (#1) is the strongest because the edge (all modalities jointly) is genuinely ours.

## Proposed execution
- **A (now):** wire the mature integration — orchestrate the scattered stages into one pipeline + a unified data registry + robust folder env (the real gap for priority #1).
- **B (in parallel):** build the **multi-modal accuracy model** (binding + permeability + conformers, joint) with an honest OOD eval vs single-property baselines — our data-edge novelty.
- Both feed the closed loop that turns on real CRO KD.
