# Non-Canonical (N-Me) Training-Data Availability — CycPeptMPDB → PepGLAD

**Date:** 2026-09-26
**Scope:** Track B / B1 gating data question. The B1 feasibility report
(`docs/20260926_B1_NATIVE_NONCANONICAL_FEASIBILITY.md`) concluded that native N-Me generation is a
**retrain, not a guidance patch**, and that the *real limiter is data*, not code. This doc answers that
question with measured numbers from the local CycPeptMPDB corpus and gives an honest go/no-go verdict.

**Parser:** `research/guangzhou_all_atom/cycpeptmpdb_to_pepglad.py` (CPU-only; reuses
`noncanonical_vocab.py` for the N-Me monomer set). **No GPU, no training** was run for this analysis.

---

## 1. What the source contains

`research/guangzhou_all_atom/data/raw/CycPeptMPDB_Peptide_All.csv` — 8,466 cyclic peptides, 247 columns.
Verified per-row: **every** row has `SMILES`, `HELM`, and a `Sequence` monomer-token list, plus a measured
`Permeability` (log Papp) for most.

The monomer tokens carry the modification **in the name** (this is what makes N-Me parseable without any
chemistry inference):

| token | meaning | parent | N-Me | D |
|---|---|---|---|---|
| `L` | L-Leu | L | – | – |
| `dL` | D-Leu | L | – | ✓ |
| `meL` | N-methyl-L-Leu | L | ✓ | – |
| `Me_dL` | N-methyl-D-Leu | L | ✓ | ✓ |
| `Sar` | sarcosine (N-methyl-Gly) | G | ✓ | – |
| `Me_Bmt(E)`, `Bn_Gly`, `Nle`, `Mono115`, `ac-`, `-pip` … | non-canonical sidechain / cap | — (out of vocab) | (name-detected) | — |

**Critical structural fact:** the CSV has **NO 3D coordinate columns**. The only "3D"-named fields
(`_3DPSA`, `CHCl3_3DPSA`, `H2O_3DPSA`) are *scalar descriptors* computed from a transient conformer at
DB-build time — not stored geometry. PepGLAD trains on **per-residue heavy-atom coordinates read from a
PDB** (`runtime/PepGLAD/data/converter/pdb_to_list_blocks.py:66`; a peptide = list of
`Block(abrv, [Atom(name, coord=[x,y,z], element)])`). CycPeptMPDB provides none of that.

**→ CycPeptMPDB is SMILES-rich / structure-poor. Every 3D structure PepGLAD needs must be generated.**

The two auxiliary raw sets do not close the structure gap:
- `data/raw/macroconf/` — ~40 cyclic peptides as **NOE distance constraints** (NMR), not ready coordinates;
  turning them into structures needs restraint-guided MD.
- `data/raw/peptideclm2_pepmsnd/` — a permeability/property table (PepMSND), SMILES-based, no coordinates.

---

## 2. The numbers (measured)

Full corpus, `python3 cycpeptmpdb_to_pepglad.py --stats`:

| quantity | count | of 8,466 |
|---|---:|---:|
| total peptides | 8,466 | 100 % |
| with SMILES | 8,466 | 100 % |
| **with stored 3D structure** | **0** | **0 %** |
| **(a) with ≥1 N-Me modification** | **7,395** | **87.3 %** |
| with ≥1 D-amino-acid | 6,802 | 80.3 % |
| **all monomers in vocab** (canonical + N-Me/+D only) | **1,418** | 16.7 % |
| **in-vocab AND N-Me** | **1,233** | 14.6 % |
| pure canonical-L (no mods) | 24 | 0.3 % |
| N-Me residues (token level) | 22,951 | of 71,102 residues (32 %) |

Structure-generation success (RDKit ETKDG macrocycle embedding, CPU), measured on a random 120-peptide
sample of the **in-vocab AND N-Me** subset:

| quantity | value |
|---|---|
| **(b) usable 3D structure — ETKDG embeddable** | **120 / 120 = 100 %** of sample (→ ~1,233 of the in-vocab N-Me set) |
| **(c) both N-Me AND usable structure** (after generation) | **≈ 1,233** (the in-vocab N-Me subset, all embeddable) |
| distinct Murcko scaffolds in the in-vocab N-Me subset | 156 |

So the honest funnel for **an N-Me AE retrain** is:

```
8,466 peptides
  → 7,395 carry N-Me                 (abundant label; the modification is NOT the limiter)
  → 1,418 all-monomers-in-vocab      (the 82% drop is non-canonical SIDECHAINS/caps, not N-Me)
  → 1,233 in-vocab AND N-Me          (the trainable N-Me set for a canonical-parent + N-Me-bit AE)
  → 1,233 embeddable to 3D via ETKDG (structure is GENERATED, not measured; 0 came with coordinates)
```

**The single most important finding:** N-Me *labels* are abundant (87 %); the binding constraint is that
only **16.7 %** of peptides are built from canonical parents (the other 83 % use exotic sidechains/caps a
20-AA-parent vocab cannot name), and **0 %** ship a structure — so the ~1,233 usable examples all need
**generated** geometry.

---

## 3. Go / No-Go verdict

**GO — for the falsification experiment (B1 report §7 step 2, the AE-reconstruction gate), with one
mandatory data-engineering step. NO-GO for training directly on stored structures (there are none).**

Reasoning:

- **N-Me signal is not the limiter.** 1,233 in-vocab N-Me peptides with 22,951 N-Me residues is *ample* to
  train and, more importantly, to *falsify* the representation extension: the B1 report's cheapest gate is
  "can the retrained AE reconstruct held-out N-Me residues' flag + CN placement?" — 79 held-out (test-split)
  in-vocab N-Me peptides is enough to answer that yes/no. This gate does not require binding structures, only
  self-consistent geometry, which ETKDG supplies.
- **Structure must be generated, and that step is cheap and reliable here.** ETKDG embedded 100 % of the
  sampled macrocycles on CPU. This is the "fold the SMILES-only ones" step the B1 report anticipated. It is a
  *2D→3D conformer generation*, not a binding-pose prediction — appropriate because PepGLAD's AE learns
  peptide geometry, not a receptor complex.
- **Two honesty caveats that gate scope, not the go decision:**
  1. **Per-residue atom→block partitioning is unfinished.** The parser proves a structure is *obtainable*
     (it embeds and stores heavy-atom coords) but currently emits a **single fallback block** per peptide,
     not the per-residue `Block` partition PepGLAD's AE ingests. Splitting an arbitrary macrocycle SMILES
     into residue blocks (trace the backbone `N–Cα–C(=O)` repeat, assign the CN methyl to its residue's
     amide N) is the one remaining data-engineering task before an AE retrain. It is deterministic
     cheminformatics (SMARTS backbone walk over the HELM-ordered monomers), not research — but it is
     **not done in this scaffold** and must not be hand-waved.
  2. **ETKDG conformers are unconstrained solution guesses.** They are fine for an AE that models intrinsic
     peptide geometry; they are **not** bound-state structures. If a later stage needs receptor-bound N-Me
     peptides, ETKDG is insufficient and MD/docking or the MacroConf NOE-restrained route is required.

**Bottom line:** there IS enough N-Me data to run the B1 falsification (retrain AE, check it reconstructs
N-Me), *provided* the SMILES→3D step (ETKDG, already validated) and the per-residue block partition (the one
open cheminformatics task) are completed first. Do NOT expect ~8k trainable examples — expect **~1,233**,
because the vocab constraint (canonical parents only) and the structure constraint (generate everything)
both bite.

---

## 4. Acquisition / structure-prediction step needed

Ordered by necessity for the B1 experiment:

1. **(required) Per-residue block partition.** Extend `cycpeptmpdb_to_pepglad.embed_blocks` to walk the
   backbone and split the embedded conformer into per-residue `Block`s aligned to the HELM monomer order,
   attaching the CN methyl to the correct residue and setting that residue's `nme` bit. Deterministic;
   no GPU.
2. **(required) Batch ETKDG embed of the 1,233 in-vocab N-Me set.** `--emit out.jsonl --embed` already does
   this end-to-end; it is CPU-bound (~seconds per macrocycle). Cache to avoid re-embedding.
3. **(optional, scope expansion) Extend the vocab beyond canonical parents.** ~5,977 additional N-Me
   peptides are locked out only because a sidechain is non-canonical (`Nle`, `Bn_Gly`, `Me_Bmt(E)`, `Mono*`).
   Adding those monomers is a *different, larger* representation task (new sidechain geometries) — out of
   scope for the N-Me-only B1 gate, noted for later.
4. **(optional, quality upgrade) Restraint-refined / MD structures.** For any downstream stage needing
   physically realistic (or bound) geometry, replace ETKDG with short vacuum/implicit-solvent MD, or fold
   the MacroConf NOE-restrained subset. Not needed to falsify the AE.

---

## 5. Family-disjoint evaluation split (leakage-honest)

To prevent the AE (and later the LDM) from being scored on near-duplicates of training peptides, the split
is **by Bemis–Murcko scaffold**, hashed so every peptide sharing a scaffold lands in the same bucket
regardless of row order (`cycpeptmpdb_to_pepglad.assign_split`, ~10 % val / 10 % test).

Measured on the **1,233 in-vocab N-Me** set (156 distinct scaffolds):

| split | peptides |
|---|---:|
| train | 1,107 |
| val | 47 |
| test | 79 |

**Acceptance gate (from B1 report §7 step 2):** the retrained AE must reconstruct the **test-split** N-Me
residues' `nme` bit (AAR on the bit) and place the CN atom (CN RMSD) — evaluated *only* on those 79
family-disjoint peptides, none of whose scaffolds appear in train. Because the split is scaffold-disjoint,
a pass cannot be an artifact of memorizing a near-identical training peptide.

---

## Appendix — commands (all CPU)

```bash
cd research/guangzhou_all_atom
python3 cycpeptmpdb_to_pepglad.py                       # self-test (classifier + parse + 1 embed)
python3 cycpeptmpdb_to_pepglad.py --stats              # full-corpus availability counts (Table §2)
python3 cycpeptmpdb_to_pepglad.py --stats --limit 200 --embed   # add ETKDG embed success on a sample
python3 cycpeptmpdb_to_pepglad.py --emit nme.jsonl --embed      # write PepGLAD records (slow: ETKDG)
```
