# Latest Works Survey: Target/Molecule DB APIs · Fast MD · Quantum Computing

**Date:** 2026-07-19
**Scope:** answer three questions — (1) new target + small-molecule DBs with APIs to integrate, (2) new fast-MD approaches, (3) should we add quantum computing / do we already have it. Based on a 3-agent survey (codebase audit + two 2024–2026 literature sweeps) cross-referenced against what BioMate already ships.

---

## TL;DR / decisions

- **DB APIs — wire 4 net-new hosted sources** (extends the `operation`-based `query_database` API tier shipped 2026-07-19): **BindingDB, Pharos/TCRD, PDBe/PDBe-KB**, and promote **PubChem** to a first-class source. Add **ZINC-22 + SmallWorld** for billion-scale analog search. All keyless + commercial-safe.
- **Fast MD — the engines we already have; add the ML potentials we don't.** We already run OpenMM/OpenFE-RBFE/BioEmu/GROMACS/AMBER. **Net-new to adopt: AIMNet2 + MACE-OFF (ML interatomic potentials)** and **OPES/PLUMED (enhanced sampling)**.
- **Quantum — NO, not as a product capability. Sandbox only.** We have ~0 today; that's correct. The real strongly-correlated-chemistry win is **classical GPU-DMRG**, marketed as *multireference chemistry*, not "quantum." Prototype **CUDA-Q** on GPU simulators as a hedge; never a production dependency.

---

## 1. What we already have (audit)

| Area | Have | Gaps |
|---|---|---|
| **Quantum** | ~0 (a Qiskit *file converter*, QCxMS/PyMuonSuite semi-empirical — none run circuits) | everything |
| **MD** | 40+ GROMACS tools, full AMBER suite, **OpenFE RBFE (OpenMM 8)**, MM-PBSA/GBSA, **BioEmu-1**, Boltz-2, Chai-1, DiffDock | **ML potentials (AIMNet2, MACE-OFF, ANI)**, OPES/metadynamics, coarse-grained, REMD |
| **DB APIs** | 10 `live_api` + 38 Biomni query tools + 19-source `federated_query` (ChEMBL, PubChem, UniProt, PDB, AlphaFold, Open Targets, RCSB, gnomAD, KEGG, GtoPdb…) | **BindingDB, PDBbind, PDBe, Pharos, DrugCentral, ZINC, SureChEMBL** |

Key insight: on **fast MD we already own the engines** the survey recommends (OpenMM 8, OpenFE, BioEmu) — the real gap is the **ML-potential layer**. On **DB APIs** we have the backbone but miss the affinity + druggability + billion-scale-library sources.

---

## 2. New target + small-molecule DB APIs — ranked shortlist

Keyless + commercial-safe unless flagged. Wire as new `query_database` / `live_api` sources.

| # | Source | API | Why it's net-new | License |
|---|---|---|---|---|
| 1 | **PubChem PUG-REST** | `pubchem.ncbi.nlm.nih.gov/rest/pug` | public-domain chemistry backbone, broader than ChEMBL; promote to first-class (only in Biomni today) | Public domain |
| 2 | **BindingDB REST** | `bindingdb.org/rest/` | 2.9M **measured Ki/Kd/IC50** by target/compound — the affinity gap ChEMBL alone doesn't fill | CC BY 4.0 (ChEMBL-origin subset is SA) |
| 3 | **Pharos/TCRD GraphQL** | `pharos-api.ncats.io/graphql` | NCATS **druggability / target development level** (Tclin→Tdark); complements Open Targets | NIH public |
| 4 | **PDBe / PDBe-KB REST** | `ebi.ac.uk/pdbe/api/` | CC0 **residue-level** binding-site/variant annotations RCSB doesn't expose | CC0 |
| 5 | **ZINC-22 + SmallWorld** | `cartblanche22.docking.org`, `sw.docking.org` | **billion-scale tangible** analog / chemical-space search for hit expansion — nothing in-stack does this | free (compounds inherit vendor terms) |
| 6 | **GtoPdb REST** | `guidetopharmacology.org/services/` | expert-curated target–ligand pharmacology (already in Biomni; consider promoting) | CC BY-SA (copyleft) |
| 7 | **Boltz-2** (BioLM / NVIDIA NIM) | hosted REST | structure+**affinity** from seq+SMILES ~20s; the new DBTL primitive (weights MIT; we have the model in-catalog — wire a hosted inference path) | MIT weights |

### Licensing landmines (do NOT ship as clean OSS / commercial)
- **DrugBank** — academic data **CC BY-NC**; commercial = paid contract. **Skip** (ChEMBL/DrugCentral/GtoPdb cover it).
- **DisGeNET** — free tier academic-only; **Open Targets (CC0) already replaces it.** Drop.
- **AlphaFold3 Server** — **no API, docking/screening banned.** Use AlphaFold DB (CC-BY) or Boltz-2 (MIT).
- **PDBbind+/CSAR** — post-2020 paywalled, no API — offline benchmark asset only.
- Copyleft/ShareAlike (safe internal, risky to redistribute a derived DB): GtoPdb, DrugCentral, BindingDB SA subset.

### Maintenance catch (time-boxed)
- **AlphaFold DB API old fields sunset 2026-06-25** — update `_query_alphafold` / `_fetch_alphafold` before then.
- **RCSB ESM3 embedding (3D-similarity) search** went live Mar 2026 — an *upgrade* to the existing `_query_pdb`, not a new source; confirm request body against `search.rcsb.org/redoc` before wiring.

### Not `query_database` sources (no live REST) — watch list
PDBbind, PLINDER, **OpenBind** (first drop Jun 2026), TDC-2/PyTDC, Polaris, **OpenADMET** — ingest/training/benchmark assets, not lookups.

---

## 3. Fast MD — new approaches, mapped to what we own

Three layers; we own Layers 2–3, gap is Layer 1.

- **Layer 1 — ML interatomic potentials (DFT-accurate forces).** GAP. **Adopt AIMNet2** (best for **charged** drug-like ligands, MIT-class) + **MACE-OFF** (only validated engine for **explicit-solvent protein MD**; CC-BY weights / MIT code). *Caveat:* MLIPs are ~50–70× **slower** than classical FFs — the value is QM accuracy, not throughput. **Avoid materials-trained potentials (MACE-MP, Orb-v3, SevenNet) — wrong chemistry for drugs.** Meta **UMA/fairchem** is strong but **FAIR-License gated (jurisdiction-restricted)** — legal sign-off required.
- **Layer 2 — ML surrogates that replace sampling.** We have **BioEmu-1** — the only deployable option (MIT, monomer-backbone only; apo/stability/mutation, **not** ligand-bound). Everything else (MDGen, Boltzmann generators, AlphaFlow) is peptide/research-only or has no licensed weights.
- **Layer 3 — GPU engines + FEP + enhanced sampling.** We have **OpenMM 8** + **OpenFE RBFE** (production, FEP+-comparable, fans onto Batch GPU). **Add OPES/PLUMED** (enhanced sampling; ~4× vs metadynamics) for rare events (binding/unbinding, folding).

### Adopt-now (net-new only, ranked)
1. **AIMNet2** ML potential (charged ligands) — via `openmm-ml`/`NNPOps` on the OpenMM engine we already run.
2. **MACE-OFF** ML potential (solvated-protein MD).
3. **OPES/PLUMED** enhanced-sampling plugin.

(OpenMM 8, OpenFE, BioEmu are already in-stack — no new adoption, just leverage.) **Watch:** NVIDIA **ALCHEMI** batched-MD (best 2025–26 throughput lever, licensing pending).

---

## 4. Quantum computing — direct verdict

**Do we have them?** No — ~0, and that is the correct state.

**Should we add them?** **Not as a product capability. Sandbox only. Never a production dependency.**

Why (2025–26 reality, stated plainly):
- **~90% positioning.** No quantum computer has beaten classical DFT/CCSD(T)/DMRG for any real drug-relevant molecule. **No peer-reviewed, wet-lab-validated drug is attributable to a quantum computer — zero.**
- Real-hardware VQE is stuck at **~2–6 qubit active spaces**, below chemical accuracy. The showcase IBM [4Fe-4S] run had a **classical supercomputer (Fugaku) do the actual eigenvalue solve**; the QPU only sampled. Useful fault tolerance needs ~10³–10⁴ logical qubits (~200 logical ≈ early 2030s).
- Vendor "quantum" usually means classical ML on quantum-chem data or quantum-inspired optimization. SandboxAQ dropped "quantum"; Menten/Qubit pivoted to classical NNs; POLARISqb has predicted docking scores, nothing synthesized.

**The genuinely valuable adjacent tool is CLASSICAL:** GPU-accelerated **DMRG (block2 via PySCF)** — extends tractable active space ~18 → ~50+ orbitals for strongly-correlated systems (**metalloenzyme active sites, transition-metal catalysis**). **FeMoco — long the poster child for "needs a quantum computer" — was solved classically with DMRG+CC in Jan 2026.** Ship this as a **multireference-chemistry** feature, *not* "quantum." Skip quantum annealers (D-Wave/Fujitsu/Toshiba) — "win small, lose large," matched by Gurobi/simulated annealing.

**If we prototype quantum as a hedge:** one framework — **NVIDIA CUDA-Q** (Apache-2.0) + CUDA-QX, OpenFermion/PySCF for Hamiltonians. Rationale: the only useful quantum work today is *GPU simulation* of quantum algorithms; CUDA-Q owns that layer and scales on our GPU Batch, with one code path that can target a real QPU later. (PennyLane if the emphasis is differentiable/QML research.)

---

## 5. Recommended build order (all extend shipped work, all commercial-safe)

1. **Wire the 4–5 new DB APIs** into `query_database` (BindingDB, Pharos/TCRD, PDBe, PubChem-as-first-class, + ZINC/SmallWorld) — direct extension of the `operation`-based API tier just shipped. Highest ROI, lowest risk, testable like the ChEMBL/RCSB canary.
2. **AIMNet2 + MACE-OFF ML-potential workflow** on the OpenMM engine we already run (Batch GPU).
3. **OPES/PLUMED** enhanced-sampling option in the MD workflow.
4. **GPU-DMRG (block2/PySCF)** as a *multireference chemistry* capability (metalloenzyme active sites).
5. **CUDA-Q sandbox** — a single experimental notebook/workflow for fluency + positioning; not a product dependency.
6. Housekeeping: update `_query_alphafold` before the **2026-06-25** field sunset; add RCSB ESM3 3D-similarity to `_query_pdb`.

Also queued from prior speedup work: **ProstT5→Foldseek** (structure-homology search from sequence alone, ~1000× vs folding first — `foldseek --prostt5-model`, local binary supports it).
