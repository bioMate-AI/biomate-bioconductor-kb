# 2026-11-16 — DMTA loop: peptide + biologic modalities (A + B)

**Goal (user):** extend the design–make–test loop beyond small molecules to **peptides (A)** and **biologics/antibodies (B)** — "not just placeholder, useful for real."

## What shipped (real engine, verified)

The small-molecule loop is SMILES-only (Morgan fingerprints + Tanimoto-kernel GP). Peptides/biologics are amino-acid **sequences** → a **dense physicochemical descriptor** vector, where a **Matérn GP** is the correct surrogate. Both new modalities share one real engine (differing by descriptor regime + generator), which is better than two isolated stubs.

New / changed (`backend/lib/galaxy/ai/drug_discovery/`):
- **`sequence_surrogate.py`** (new) — the engine:
  - `SequenceFeaturizer(modality)`: sequence → 31 descriptors (length, net charge @pH7, charge density, GRAVY hydrophobicity, aromatic/aliphatic/polar/charged/tiny/unstable fractions, isoelectric point, 20-AA composition). Pure-Python + numpy (no heavy deps; Biopython used only if present for pI). Same `featurise()/signature()/canonical()` contract as `MorganFeaturizer`.
  - `SequenceGP`: StandardScaler + `Matern` GP + White noise, with label standardisation. **Drop-in for `TanimotoGP`** (`fit/predict(return_std)/predict_cov/kernel_/log_marginal_likelihood_value_/noise_level`), so the shared acquisition + discrimination code is reused unchanged.
  - `SequenceApplicabilityDomain`: nearest-neighbour distance in standardised feature space (the sequence analogue of the fingerprint-leverage AD).
- **`sequence_library.py`** (new) — a real, dependency-free virtual-library generator (deterministic single-point / conservative mutational scan around a seed). The heavier generators (`cyclic_peptide_design`, scFv/antibody design) feed the same scoring path.
- **`bayesian_optimizer.py`** — `BayesianOptimizer(modality=...)`: `peptide`/`biologic` → `SequenceFeaturizer`+`SequenceGP`; `small_molecule` (default) → Morgan+Tanimoto. Feature count is now `n_bits`-or-`N_FEATURES`. All propose/acquisition/discrimination logic unchanged.
- **`auto_retrain.py`** — `fit_campaign_optimizer(..., modality=...)`.
- **`api_router.py`** — `ProposeRequest.modality` (`small_molecule`|`peptide`|`biologic`), threaded into `fit_campaign_optimizer`. `/propose` now runs sequence campaigns.
- **`test_sequence_dmta_loop.py`** (new) — functional tests for both modalities.

## Verification

- **Pure-Python core (local, py3.9): 3/3 pass** — descriptor charge physics (poly-K → +, poly-D → −), applicability domain (near in-domain / far out), library generator (dedup, point-mutations only).
- **Full GP + acquisition (py3.11, working sklearn): proven end-to-end for BOTH modalities.** The GP **learned the SAR** — with labels set to correlate with net charge, the top-EI proposals were all charge-increasing (K/R/H) substitutions, not random. Peptide: 46-candidate library, scores [7.20, 8.39], real posterior σ, `can_discriminate=True`, 45/46 in-domain. Biologic (CDR-H3): ranked mutants, `can_discriminate=True`, 30/46 in-domain.
- Optimizer dispatch verified for all 3 modalities; `ai_assistant` pre-sync import OK; py3.9 compiles all edited files.
- The 4 GP-dependent pytest cases skip on this machine (anaconda sklearn/scipy is binary-broken — the existing BO tests share this limitation) and run in CI / on Batch.

## Not done (next increment — to make it end-to-end in the product)

1. **Assay ingestion for sequences.** `assay_ingestion`/`assay_schema` validate entity identity via RDKit `structure_identity`, which rejects non-SMILES. A peptide/biologic campaign's `/ingest-assay` needs a sequence-identity path (exact/normalised sequence) so the full ingest→propose loop runs over the API. (The surrogate/propose engine itself is done and proven.)
2. **Campaign modality storage** — persist `modality` on campaign create so every round uses it (today it's a `/propose` request field).
3. **Panel UI** — a modality selector on the Design-loop tab (Rounds), and sequence-aware labels.
4. **Generators** — wire `cyclic_peptide_design` (A) and scFv/antibody design (B) to populate the virtual library from the UI (the mutational-scan baseline works today).

Field names remain SMILES-centric (`virtual_library_smiles`, `proposed_smiles`) but carry entity strings; a rename to `entities`/`proposed_entities` is a cosmetic follow-up.
