# 2026-11-11 — Boltz-2 / cofold pitfalls (collected), applied to the fold path

Collected from our own cyclic-peptide / cofold work so the new Models-panel
"fold on our Batch" path (`server/model-fold.ts` → `boltz_structure_prediction`)
inherits what we already learned instead of re-hitting it.

| # | Pitfall (where we learned it) | Status in the fold path |
|---|---|---|
| 1 | **DataLoader worker OOM** — Boltz's default DataLoader worker subprocess crashes on AWS Batch ("DataLoader worker exited unexpectedly", small `/dev/shm`) for Fv+antigen-sized inputs. Fix: `--num_workers 0` (load in-process). | ✅ `boltz_structure_prediction/main.nf` already passes `--num_workers 0`. The antibody_antigen_complex `.nf` learned the same. |
| 2 | **GPU OOM on big inputs** — a ~840-residue complex OOMs on a 16 GB T4; Boltz prints "ran out of memory, skipping batch" / "Number of failed examples: 1" and **exits 0** with no structure. cofold-bench capped runs at **1200 true tokens** (test) / 600 (train) for exactly this reason. | ⚠️ The spot GPU queue can still place a job on a 16 GB T4. `model-fold.ts` caps the monomer fold at **1000 residues**. A larger fold needs the ≥24 GB GPU routing (open infra decision). |
| 3 | **Silent empty structure** — Boltz can **exit 0 and write a 0-byte / atom-less CIF** (`6ee3c1a653`: "reject 0-byte/atom-less sample CIFs"). A "SUCCEEDED" Batch job can have produced nothing. | ⚠️ Another session added the loud-fail guard to the antibody `.nf` (`49422cce21`). `boltz_structure_prediction`'s summary should assert a non-empty CIF before reporting success — verify during the GPU validation run. |
| 4 | **Wrapped mmCIF pLDDT** — Boltz-2 writes per-residue pLDDT in a **line-wrapped `_atom_site` loop**; a naive parser misses it. Fix: the token-stream parser `_plddt_from_cif` (`848294ab6b`, `models_inference.py`). | ✅ The confidence reader already handles it; reuse when surfacing fold confidence. |
| 5 | **MSA server** — `--use_msa_server` hits ColabFold's public server with no auth → rate limits / slow on large batches. | Present; fine for single interactive folds. For batch, consider an auth'd/own MSA. |
| 6 | **CCD component library** — 45,227 components; some ligand/ncAA codes missing (relevant for complexes/ligands, not plain protein monomers). | N/A for the monomer fold path. |
| 7 | **Cache/disk** — first run downloads Boltz weights + CCD (`mols.tar`); cache restore has run nodes out of disk (`2833317c7e`). Batch task disk must be ≥30 GB. | Infra: the Batch job disk sizing (see `project_nfcore_run_status_not_trustworthy` — 30 GB disk). |

## For the GPU validation run of the fold path
1. Pick a ~150–300 aa monomer → expect a non-empty CIF + pLDDT within a few minutes.
2. Confirm `boltz_structure_prediction` reports **no_structure / fails loudly** on an OOM (pitfall 2/3), not a silent empty success.
3. If a ~600–1000 aa fold OOMs on the landed GPU, that confirms the ≥24 GB routing need (pitfall 2).

## Found during live validation of the fold path (2026-11-11)

| # | Pitfall | Status |
|---|---|---|
| 8 | **Boltz FASTA needs a chain id, not a free-text record id.** `>query` → `ValueError: Invalid record id: query`; boltz exits 0 with no structure. | ✅ Fixed: `model-fold.ts` builds the Boltz **YAML** (one `protein` entity, chain `A`) and passes `input_yaml`, the format the working cofold workflows use. |
| 3b | **`boltz_structure_prediction` reports "completed" with zero structures** (exit 0, empty `boltz_summary.json`, no CIF). Same class as the antibody `.nf` before its loud-fail guard (`49422cce21`). | ⚠️ Open: that `.nf`'s summary step should exit non-zero when `n_structures==0` / no CIF, so a no-structure run surfaces as failed, not a silent "completed". Needs a GPU run to validate the failing path. |

**Validation protocol confirmed:** a run that reaches "completed" at the Batch level is NOT proof of a structure — always check `boltz_summary.json` `n_structures` and that a `*.cif` exists (this is exactly why the loud-fail guard matters, and why "pass = live outcome" caught the FASTA bug that unit tests could not).
