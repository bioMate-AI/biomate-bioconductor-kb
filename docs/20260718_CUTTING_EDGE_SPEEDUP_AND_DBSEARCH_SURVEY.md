# Cutting-Edge Tools for Workflow Speedup & DB Search (2025–2026 Survey)

**Date:** 2026-07-18
**Purpose:** Catch BioMate up to the newest (2025–2026) open-source tools / APIs — from prestigious venues (Nature/Science/Cell/NBT/Nat Methods/NAR) and labs/companies (Steinegger, Baker/IPD, DeepMind, Meta FAIR, NVIDIA, Microsoft, Arc, Recursion) — for (a) accelerating workflows and (b) large-DB search. Three parallel deep surveys + adversarial verification of high-stakes claims.
**Discipline:** almost every "N×" figure is vendor/author-stated and usually **CPU-vs-GPU, not algorithmic**. Treat as directional; benchmark on our own data before committing.

---

## Cross-cutting "adopt now" shortlist (highest confidence × BioMate fit)

| # | Tool | What it buys us | Venue / License | BioMate fit | Confidence |
|---|---|---|---|---|---|
| 1 | **MMseqs2-GPU + Foldseek-GPU** | Kills the MSA bottleneck (176× vs JackHMMER; ColabFold **31.8× vs AF2** end-to-end) + GPU structure search | Nat Methods 2025 · GPL-3.0 · ships as NVIDIA NIM | Workflow/service — slots into the existing **`BioNeMo NIM client`** (`b437a4324`); GPU Batch nodes | **High (peer-reviewed)** |
| 2 | **nvMolKit** | GPU RDKit fingerprints + Tanimoto — a GPU accelerator for the **FPSim2 workflow shipped today** | NVIDIA Digital-Bio · open (v0.5.1, 2026) | Workflow — GPU chem-similarity on Batch GPU | Med (bench first; claims span 5 fns) |
| 3 | **cuVS + IVF-RaBitQ** | <25% storage + 7.7× faster build for **hosted reference indices** (Foldseek, FPSim2, embeddings); GPU-build→CPU-serve | NTU+NVIDIA, arXiv 2026 · **Apache-2.0** | Infra — cuts cost/memory of every hosted index | Med-High (genuinely new algo) |
| 4 | **Boltz-2** | Structure + **binding affinity** ~1000× cheaper than FEP (Pearson 0.62 vs FEP+) | MIT Jameel+Recursion · **MIT (commercial-OK)** | Service — affinity pre-screen before/instead of FEP | Med (broadly adopted) |
| 5 | **Seqera Fusion + Spot/Graviton** | Biggest **infra cost lever** on AWS Batch (~76% vs FSx Lustre; spot up to 90%; Graviton up to 40%) | Seqera · **proprietary (license)** + AWS-native spot | Infra — zero model-accuracy risk | High (spot/Graviton native) |
| 6 | **ProstT5 → Foldseek** | Structure-quality remote-homology search **from sequence alone**, ~1000× cheaper than folding first | NARGB 2024 · open (in Foldseek 9) | Workflow — extends the Foldseek workflow shipped | High (production) |

**Strategic opportunity (differentiator):** **no one openly hosts an ANN embedding index over full ChEMBL/PubChem or Swiss-Prot.** Build one (Uni-Mol2 / ProtT5 embeddings + cuVS/IVF-RaBitQ) → semantic chemical/protein retrieval BioMate uniquely offers. EBI publishes downloadable ProtT5 embeddings (no query API) — seed from those.

---

## 1. Sequence & structure search

- **MMseqs2-GPU** (Nat Methods 2025, GPL, NVIDIA NIM) — the headline. 6× CPU MMseqs2; **176× JackHMMER**; ColabFold **31.8× vs AF2**. Highest-ROI, lowest-risk adoption.
- **Foldseek-GPU** (same release) — `--gpu 1`; ~4× (1 GPU) to ~27× (8 GPU) with slightly *better* SCOPe sensitivity. Drop-in over our Foldseek index.
- **Foldseek-Multimer** (Nat Methods 2025) — whole-complex structural alignment, 10³–10⁴× vs US-align. New capability.
- **ProstT5 → Foldseek** — search-from-sequence (see shortlist). **SaProt** (ICLR 2024, 1.3B) is the emerging structure-aware embedding substrate.
- **Dense Homolog Retriever (DHR)** (Nat Biotech 2025) — dual-encoder + FAISS MSA acceleration, up to 28,700× vs HMMER on hard cases; research-credible.
- **Hosted, zero-infra:** **RCSB PDB 3D-similarity API** now uses **ESM3 embeddings**, searches ~1M computed models, accepts external structures **by URL** — a free prefilter for our predicted structures. **BFVD** (NAR 2025) — 351K viral structures, downloadable Foldseek DB, fills AFDB's viral gap.
- **Skeptic:** dense-embedding structure search (RCSB/ESM3, SSAlign) is *faster but not more accurate* than Foldseek — value is scale/prefilter. Evo 2 has **no** genomic search API; ESM Atlas API is stale/unreliable (use the static dump).

## 2. Chemical & vector search

- **nvMolKit** (NVIDIA) — GPU fingerprint/Tanimoto/shape/conformers; GPU successor to FPSim2/GPUSimilarity. Bench vs FPSim2 before relying (headline spans 5 functions).
- **cuVS + IVF-RaBitQ** (Apache-2.0) — see shortlist; the one *genuinely new* ANN algorithm, beats CAGRA on build-time + storage (the metrics that matter for hosting).
- **ROSHAMBO2** (Biogen, JCIM 2025) — GPU shape/pharmacophore overlay (open ROCS successor). **V-SYNTHES2** (npj Drug Discovery 2026, GPL) — synthon screening to 36B+ REAL, >10,000× vs full-space docking (structure-based, not FP).
- **Uni-Mol2** (NeurIPS 2024, open weights) — best fully-open 3D chemical embedding backbone → feed a cuVS index for semantic retrieval. **ChemBERTa-3** (RSC 2026, MIT) is a *training framework*, not a checkpoint.
- **Hosted:** only **ChEMBL 36** + **PubChem PUG-REST** are genuinely open similarity APIs. No open prebuilt ANN embedding index exists (the opportunity above).
- **Licensed (avoid/API-only):** chemfp commercial, SmallWorld/SpaceLight/Arthor (REAL-space nav), Enamine REAL (~83–94B), MolFormer-XL full weights (closed), NVIDIA MolMIM/GenMol (restrictive license, generative).

## 3. Workflow / compute acceleration

- **GPU genomics/single-cell/cryo-EM:** **Parabricks v4.6** (pangenome DeepVariant; Giraffe path 14× vs CPU) → WGS/variant workflows. **rapids-singlecell** (now scverse core, MIT) → GPU scanpy. **RELION 5.0** (Blush CNN regularization, GPLv2) + **CryoDRGN-AI** (Nat Methods 2025) → cryo-EM.
- **ML-accelerated simulation:** **Boltz-2** (MIT, affinity ~1000× vs FEP — see shortlist). **BioEmu** (Science 2025, MIT) — equilibrium ensembles, ~1 kcal/mol; replaces long MD. **ORB-v3** (Apache-2.0), **AIMNet2** (MIT, charged organics) — commercial-clean MLIPs.
- **Structure/design:** **Protenix-v1** (ByteDance, Apache-2.0) + **Boltz-1/2** = commercial-safe AF3-class folders. **RFdiffusion3** (IPD, BSD-3 but commercial needs Rosetta Commons license) — all-atom design.
- **Execution/infra:** **Seqera Fusion + Wave** (see shortlist), **Fusion Snapshots** (spot checkpoint/resume — private preview, watch), **BioNeMo NIM** (GPU-batched folding/docking endpoints; NIM needs NVIDIA AI Enterprise license), **AWS Batch Spot + Graviton** (native, default to `SPOT_PRICE_CAPACITY_OPTIMIZED`).
- **Skeptic:** agentic "self-driving lab / AI co-scientist" (Biomni, Sakana, AI co-scientist) are **research-demo-grade with no production throughput metrics** — do not build acceleration dependencies on them yet (Sakana's peer-review claim was withdrawn; Biomni runs code with full privileges → sandbox required).

---

## Licensing landmines (do NOT adopt as clean OSS)

- **UMA / OMol25** (Meta FAIR) — license **excludes China/Russia/Belarus + AUP**; not clean OSS. Due-diligence gate before any commercial use.
- **ESM3 weights**, **MACE-OFF / MACE-MH weights** — **non-commercial** (ASL). **Chai-2** — proprietary/gated.
- **RFdiffusion3** — BSD-3 code but **commercial use needs a Rosetta Commons license**.
- **Seqera Fusion**, **BioNeMo NIM** — require licenses (Fusion proprietary; NIM = NVIDIA AI Enterprise). Budget for these where the ROI is infra-scale.
- **chemfp commercial / SmallWorld / SpaceLight / Arthor** — licensed; integrate as API, don't self-host.

---

## Recommended sequence (folds into the Excel Roadmap)

1. **MMseqs2-GPU / Foldseek-GPU via the BioNeMo NIM client** — kills the MSA bottleneck across folding + accelerates the Foldseek workflow. Reuses code we already have.
2. **nvMolKit** GPU acceleration for the **FPSim2 workflow shipped today** (bench vs CPU FPSim2 first).
3. **cuVS + IVF-RaBitQ** as the hosting substrate for all reference indices (Foldseek, FPSim2, and the new embedding index).
4. **Host the open ChEMBL/PubChem (Uni-Mol2) + Swiss-Prot (ProtT5) embedding indices** — the differentiator nobody offers.
5. **Boltz-2 affinity service** + **ProstT5→Foldseek** as new capabilities.
6. **Seqera Fusion + Spot/Graviton** — the infra cost lever (evaluate the license against AWS bill).

*Verification note:* adversarial checks corrected several vendor claims — BioEmu is Science (not Nat Methods); Fusion's "2.41× wall-time" did not verify (kept the ~76%-vs-Lustre + spot figures); MMseqs2-GPU end-to-end is 31.8× vs AF2 (not 1.65×); RFdiffusion3 needs a Rosetta Commons commercial license.
