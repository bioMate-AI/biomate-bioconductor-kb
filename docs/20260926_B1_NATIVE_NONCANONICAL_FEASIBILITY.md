# B1 Feasibility Spike — NATIVE Non-Canonical (N-Me) Generation in PepGLAD

**Date:** 2026-09-26
**Scope:** Track B / B1 of `docs/20260925_PEPTIDE_EXECUTION_PLAN.md`. Assess + sketch extending the frozen
PepGLAD generator (`pepglad_ldm_epoch221`) to emit **N-methylation natively** (during generation, not
post-hoc redesign). N-Me first (head start); D-amino-acids and staples noted as follow-ons.
**Constraint honored:** no GPU, no training run. This is a code-grounded feasibility read + a CPU-only
representation scaffold with tests.

---

## 1. Verdict

**Feasible, but it is a RETRAIN, not a guidance patch. Effort: L (as the plan states).**

The single load-bearing finding: PepGLAD is a **latent diffusion model over a frozen autoencoder (AE)**, and
the AE hard-codes the chemical vocabulary in three places that all assume the 20 canonical amino acids and a
fixed 14-atom-per-residue template. Native N-Me requires changing that vocabulary, which changes AE tensor
shapes and the decoder head — so **the AE (and then the LDM prior on top of it) must be retrained.** There is
no shortcut where sampling-time guidance alone produces N-methylated residues, because the guidance hook can
only move coordinates, never change residue chemistry or add atoms (proven below, §3).

The good news: the *representation* change is small, well-localized, and the model is small/cheap to retrain
relative to a foundation model. The head start (§4) is real. The honest hard part is data (§6), not code.

---

## 2. How PepGLAD works (the parts that matter for B1)

Files: `research/guangzhou_all_atom/runtime/PepGLAD/`.

- **Representation** (`data/format.py`, `utils/const.py`): a peptide is a list of `Block`s (residues). Each
  block has a **residue type token** `S` and a **coordinate tensor `X` of shape `[MAX_ATOM_NUMBER=14, 3]`**.
  The vocabulary `VOCAB = MoleculeVocab()` defines:
  - `idx2block = specials + aas` — the 20 canonical AAs only (small-molecule vocab is explicitly disabled:
    `sms = []`, `format.py:24`).
  - a per-residue **atom template**: `backbone_atoms=['N','CA','C','O']` + `const.sidechain_atoms[symbol]`.
  - an **atom position-code alphabet** `idx2atom_pos = ['pad','msk','lat','','A','B','G','D','E','Z','H','XT','P','sml']`
    (Greek-letter positions; `format.py:40`).
- **AutoEncoder** (`models/autoencoder/model.py`): encodes each residue to a latent `H` (sequence) + latent
  `Z` (coordinates); decodes back to `S` and `X`. The sequence decoder is
  `self.seq_linear = nn.Linear(hidden_size, len(self.s_remap))` where `s_remap` has **21 classes**
  (20 AAs + UNK). `argmax` over these 21 is the ONLY way a residue identity can come out
  (`model.py:180, 342-347, 449`). The atom template that fills `X` per residue is built once, tensorized, and
  frozen in `SeparatedAminoAcidFeature` (`dyMEAN/nn_utils.py:86-121`) from `const.sidechain_atoms`.
- **Sidechain builder** (`models/autoencoder/sidechain/sidechain.py`, ported from Chroma): builds all-atom
  coords from a z-matrix keyed by `constants.AA_GEOMETRY` — a **fixed 20-AA ideal-geometry table**
  (`num_aa = len(constants.AA20)`, `num_atoms = 10` sidechain slots).
- **Latent diffusion** (`models/LDM/ldm.py`, `diffusion/dpm_full.py`): runs entirely in the AE's latent
  space. `sample()` denoises latent `H`/`X`, then calls `autoencoder.test(...)` to decode. So **the LDM can
  never emit chemistry the AE cannot decode** — the AE is the chemical bottleneck.

**Net:** the AE's 20-AA / 14-atom / 21-class assumption is baked into parameter *shapes*
(`seq_linear` width, the `residue_atom_type/pos` buffers, the z-matrix tables). Changing chemistry = changing
shapes = retrain.

---

## 3. Why guidance-only injection is impossible (the tempting shortcut, ruled out)

The sampling guidance hook is coordinate-only. In `dpm_full.py:310-327`:

```python
if energy_func is not None:
    with torch.enable_grad():
        cur_X_state = X_t.clone().double(); cur_X_state.requires_grad = True
        energy = energy_func(X=..., mask_generate=..., batch_ids=...)
        energy_eps_X = grad([energy], [cur_X_state], ...)[0]      # gradient wrt COORDINATES only
    energy_eps_X[~mask_generate] = 0
X_next = self.trans_x.denoise(X_t, eps_X, ..., guidance=energy_eps_X, guidance_weight=energy_lambda)
```

The gradient is taken w.r.t. `X_t` (coordinates) and applied only to `X_next`. There is **no guidance term
on `H` (the sequence latent)** and no mechanism to add an atom slot or change a residue token mid-sampling.
`developability_guidance.py` and `ph_closure_guidance.py` both exploit exactly this hook — they nudge
*geometry* (ring closure, compactness, interface contacts). They cannot make a residue N-methylated, because
"N-methylated" is a change of atom count + token identity, decided by the AE decoder, not by coordinates.

So the existing DCG/PH guidance is the wrong lever for B1. (It is the right lever for B2/B3 — geometry and
learned developability heads.) **B1 must go through the representation + AE.**

---

## 4. The head start (what already exists we can reuse)

The current N-Me work is **verification/redesign, entirely post-hoc**, but it hands us three reusable assets:

1. **The chemistry lever is proven and quantified.** `chemistry_permeability_analysis.py` measures on 8,466
   CycPeptMPDB peptides that N-methyl count correlates + with log Papp and HBD/TPSA correlate − — i.e.
   removing a backbone NH donor is *the* permeability lever. `perm_redesign_v1.py` / `perm_generation_v3.py`
   already identify **which** backbone amides are N-methylatable (exposed, non-interface, non-Pro, not
   H-bonding the receptor). That selection logic becomes the **validity constraint + reward** for native
   generation (§5, step 5), unchanged.
2. **The N-Me force-field patch exists.** `MODALITY_EXTENSION.md` + `peptide_nmethyl_mmgbsa.sh` document a
   working `NMET` CHARMM patch for MM-GBSA. So once we generate N-Me natively, the **verify layer (A1) can
   already score it** — no new physics needed to close the loop.
3. **The atom accounting is settled.** `perm_redesign_v1.py:117` and the SMARTS in
   `chemistry_permeability_analysis.py:21` (`[NX3;$([N]C=O)][CH3]`) define exactly the atom we add (a methyl
   C on the backbone amide N, removing one donor H). The new scaffold (`noncanonical_vocab.py`) turns that
   into a machine-checkable representation delta.

So B1 is not starting from zero: the *objective*, the *validity rule*, and the *downstream scorer* are done.
Only the **generator's representation + weights** are missing.

---

## 5. File-level implementation sketch (native N-Me)

Chosen route: **orthogonal 1-bit "N-methylated" head** (not doubling the token set 20→40). Reasons: it keeps
the 21-way `seq_linear` intact, it composes cleanly with future D-AA/staple flags, and it matches the
biology (N-Me is a modification of a residue, not a different residue). The token-doubling alternative is
documented in the scaffold for completeness.

1. **Vocabulary / atom template — `data/format.py` + `utils/const.py`**
   - Add `NME_ATOM_NAME='CN'` to a per-residue **optional** atom slot; add atom_pos code `'N'` to
     `idx2atom_pos` (methyl-on-backbone-N). Add one `AA_GEOMETRY`-style ideal-IC entry for `CN`
     (parents `[N, CA, C]`, len 1.45 Å, angle 120°, dihedral 180° — provided in `noncanonical_vocab.py`).
   - **Raise `MoleculeVocab.MAX_ATOM_NUMBER` from 14 → 15.** This is forced: TRP already fills all 14 slots
     (4 bb + 10 sc), so N-Me-TRP needs 15. This is the change that makes it a retrain (tensor shapes move).
     Verified by the scaffold: only TRP overflows; all other 18 N-Me monomers fit within 14.
2. **AE atom-feature buffers — `models/dyMEAN/nn_utils.py` (`AminoAcidFeature.__init__`)**
   - The `residue_atom_type` / `residue_atom_pos` buffers (`nn_utils.py:86-121`) are built from the atom
     template and become `[num_res_type, 15]`. When the N-Me flag is set for a residue, append the `CN`
     atom type/pos to that residue's row and drop the amide-H (the AE is heavy-atom + implicit-H, so the
     "removed donor H" is bookkeeping for the FF/scorer, not a coordinate — but the flag must ride alongside
     `S` into the encoder features and the sidechain builder).
3. **Sequence representation — carry the N-Me flag**
   - Add an `nme_mask` (per-residue bool) parallel to `S` through `encode`/`decode`/`sample`
     (`model.py:291-365`, `ldm.py:76-208`, `dpm_full.py:sample`). On encode, concatenate a learned
     N-Me embedding into `H_0`. On decode, add a **second linear head** `self.nme_linear =
     nn.Linear(hidden_size, 1)` next to `seq_linear` (`model.py:180`) predicting the N-Me bit per residue;
     the LDM diffuses it as an extra latent channel (cheapest: 1 extra dim on `H`).
4. **Sidechain / all-atom builder — `models/autoencoder/sidechain/sidechain.py`**
   - Extend the z-matrix maps (`_init_maps`, `num_atoms 10→11`) so `SideChainBuilder` places `CN` off
     `[N,CA,C]` when the N-Me flag is set. This reuses the exact `extend_atoms` machinery already used for
     every sidechain atom (`sidechain.py:156-187`) — no new geometry code, just one more parented atom.
5. **Validity constraint (guardrail) — reuse existing selection logic**
   - Port `perm_redesign_v1.interface_positions` / `perm_generation_v3.analyze` into a post-decode validator:
     forbid N-Me on Pro (already tertiary) and optionally discourage N-Me on interface backbone amides that
     H-bond the receptor (binding-critical). This is the rule half of the hybrid rule+LLM approach the repo
     mandates; it is already written, just needs to run at generation time instead of redesign time.
6. **Retrain — `train.py` + `launch_pepglad_train.sh`**
   - Retrain the AE first (it owns the shape change), then the LDM prior on the AE's new latent space (the
     LDM loads a frozen AE ckpt: `ldm.py:39-42`). Training data must include N-Me examples with the flag set
     (CycPeptMPDB has them; §6).
7. **Output — `generate.py` `overwrite_blocks` / `list_blocks_to_pdb`**
   - When writing the PDB/CIF, emit the `CN` atom for flagged residues so the verify layer (A1) and the
     `NMET` MM-GBSA patch pick it up automatically.

**Scaffolded now (CPU-only, committed with this report):**
- `research/guangzhou_all_atom/noncanonical_vocab.py` — enumerates the 19 N-Me monomers, computes the exact
  representation delta (`representation_delta()`), the `CN` ideal geometry, and the 14→15 collision. Pure
  Python; torch-free; `python3 noncanonical_vocab.py` prints the delta.
- `research/guangzhou_all_atom/tests/test_noncanonical_vocab.py` — 7 tests locking the load-bearing facts
  (TRP overflow, +1 donor removed per N-Me, Pro ineligible, delta self-consistency, `CN` frame validity,
  RDKit SMARTS validity). Runs under plain `pytest`, no GPU. **All 7 pass.**

---

## 6. The honest hard parts

1. **AE retrain is unavoidable (this is the "L" effort).** The 14→15 channel bump and the extra decoder head
   change parameter shapes; the frozen `epoch221` checkpoint cannot be reused for the N-Me-capable AE.
   Budget one AE training + one LDM training. Mitigation: the model is small; a warm-start from the current
   AE weights (copying the overlapping 14 channels, zero-init the 15th + the N-Me head) should converge fast.
2. **Data, not code, is the real limiter.** `chemistry_permeability_analysis.py`'s own note says the natural-
   AA generator "cannot produce" non-natural monomers — because the *training data* was canonical. Native
   N-Me needs N-Me-labeled training complexes. CycPeptMPDB (8,466 cyclic peptides, many N-methylated, with
   SMILES) is the obvious source, but it must be parsed into the per-residue block + `nme_mask` format and
   ideally paired with structures (a data-engineering task; some are structure-poor).
3. **The N-Me bit interacts with the sidechain builder's symmetry/idealization** (`sidechain.py`
   `AllAtomFrameBuilder`, `_reconstruct(..., idealize=True)`). CN must be idealized consistently or it will
   clash with the amide-H position the FF expects removed. Test with a single-residue N-Me build before any
   full run.
4. **Guidance is the wrong tool for B1** (§3) — resist the temptation to fake N-Me via a coordinate energy;
   it cannot change atom count. Guidance is for B2 (hard ring closure) and B3 (learned developability heads).
5. **Validation must show a real distribution shift, not just "it emits CN."** Accept only if the permeability
   distribution of natively-generated N-Me peptides shifts favorably vs canonical-only, measured by
   `chemistry_permeability_analysis.py` (its "chemistry_generated_designs" vs "chemistry_permeable_subset"
   comparison), on a leakage-filtered split, with the full 7-metric panel (per the plan's honest gates).

---

## 7. Recommended first REAL (GPU) experiment

**Smallest experiment that proves the representation extension trains and shifts chemistry:**

1. **Data (CPU, first):** parse CycPeptMPDB into the PepGLAD block format with `nme_mask`, keeping only
   peptides whose residues are all in {20 AAs, optionally N-methylated} and that have (or can be folded to) a
   structure. Split family-disjoint (leakage-honest).
2. **AE retrain (GPU):** raise `MAX_ATOM_NUMBER=15`, add the `CN` template + N-Me embedding + `nme_linear`
   head, warm-start from `epoch221`. Train to convergence on reconstruction; **acceptance gate: the AE
   reconstructs held-out N-Me residues' flag + CN placement** (AAR on the N-Me bit, CN RMSD). No LDM yet.
3. **LDM retrain (GPU):** train the prior on the new AE latent space (small run first, `n_samples` sanity).
4. **Validate:** generate on the held-out cyclic targets; run `chemistry_permeability_analysis.py` and A1's
   verify layer (`NMET` MM-GBSA already exists). **Acceptance:** native N-Me peptides show a favorable
   permeability-distribution shift vs the canonical-only baseline, without binding (ΔG) or diversity collapse.

**Why this order:** step 2 is the cheapest way to falsify the whole plan — if the AE can't even reconstruct
N-Me, the LDM never will, and we've spent one small AE run instead of a full pipeline. This mirrors the
"review-before-expensive-run" discipline: prove the representation before paying for the prior.

---

## 8. Follow-ons (noted, not scoped here)

- **D-amino acids:** cheaper than N-Me in one sense (no extra atom → no channel bump) but requires encoding
  **chirality** (an L/D flag per residue, + the sidechain builder must mirror the CA frame). Same
  orthogonal-flag pattern as N-Me; `noncanonical_vocab.py` leaves a `kind='d_amino'` slot for it.
- **Staples:** a bond between two sidechains (e.g. i, i+4). This is a *topology* change, not a per-residue
  atom change — it needs an explicit inter-residue bond in the representation and pairs naturally with B2's
  hard cyclic-manifold closure. Hardest of the three; do last.

---

## Appendix — commands

```bash
cd research/guangzhou_all_atom
python3 noncanonical_vocab.py                        # print the representation delta + monomer table
python3 -m pytest tests/test_noncanonical_vocab.py -q  # 7 tests, CPU-only, ~1s
```
