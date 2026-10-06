# Drug Novelty / FTO Gate — general (small molecule + peptide)

**Date:** 2026-10-05 · Adds a novelty / freedom-to-operate (FTO) check to the validation+filtering
pipeline, **general across drug modalities**, and runs it on the 22 generated cyclic peptides.

## Why this exists (the gap it closes)

The 22 peptides we assembled into CRO panels (`results/CRO_SEND_pdl1_panelA.csv`,
`CRO_SEND_avb6_panelB.csv`) had **no novelty / patent / FTO check** before being queued for
synthesis — confirmed by grep over `peptide_verify.py` / `peptide_gate.py` / `peptide_select.py`
(no `novelty|patent|fto|surechembl` path) and by the CRO panels carrying no novelty column.

A prior "0/22 exact sequence hits in binding_affinity_v1" check was **meaningless**: that CSV's
`sequence` column is empty for all 136,730 rows (it is a SMILES-based known-actives set). The real
check must go **structure-wise**: seq → SMILES → fingerprint similarity against the SMILES column.

An FTO/novelty screen **should be part of validation+filtering**, not an afterthought. This change
makes it a gate at the pre-CRO chokepoint.

## What was built

### 1. `research/guangzhou_all_atom/drug_novelty_fto.py` — the general engine
Modality-general (small molecule via `smiles=`, peptide via `seq=`). Three honest axes:

| Axis | Method | Applies to | Occupied when |
|---|---|---|---|
| **Structure** | Morgan/ECFP4 (r=2, 2048 bit) Tanimoto NN vs a known-actives library (ChEMBL/BindingDB SMILES) | all drugs | `max_tanimoto >= cutoff` (default 0.85) |
| **Patent** (opt-in, network) | SureChEMBL/PubChem patent-presence for the canonical structure (POST, so long SMILES don't 400) | all drugs | PubChem CID has ≥1 patent xref |
| **Sequence** (peptides) | Needleman–Wunsch normalised identity vs known/patent peptide sequences | peptides, when a sequence reference is supplied | `identity >= 0.80` |

- **Peptide → SMILES** is RDKit-native: linear via `MolFromSequence`, head-to-tail macrocyclised by
  RWMol bond surgery, and **validated by molecular weight** against the residue-sum formula before use
  (status `ok_cyclic`); falls back to the linear form rather than fabricate a ring.
- Reuses the **same logic** as the backend `compound_novelty_scorer` subworkflow (Tanimoto NN + the
  SureChEMBL/PubChem patent pattern), run locally with RDKit instead of the mounted FPSim2 `.h5`.
- **Honesty contract:** an axis that cannot run reports `status=unavailable` for that axis; it never
  scores 0 / "novel" by default. If **no** axis runs, `occupied=None` / `verdict="unknown"`
  (fail-OPEN — a broken scorer never silently kills a batch; the caller sets policy).

### 2. Pipeline integration — `select_to_rfq.py` (G5, the pre-CRO chokepoint)
`build_rfq(..., fto_gate=, fto_drop=, fto_records=)` + CLI flags `--fto-gate`, `--fto-library`,
`--fto-cutoff`, `--fto-check-patents`, `--fto-flag-only`, `--fto-report`. With `--fto-gate`, every
resolved candidate is screened **before it can ship**; occupied candidates are **dropped** (default)
or **flagged** (`--fto-flag-only`), and a per-candidate verdict sidecar JSON is written next to the
CSV. Fail-open: `occupied is None` never drops. Items renumber contiguously after drops.

### 3. Root-cause fix shipped to the shared backend path
`compound_novelty_scorer/main.nf` had the same GET-based CID lookup that **400s on long
macrocycle/peptide SMILES**. Fixed to **POST** the SMILES (verified: aspirin → CID 2244 / 111,159
patents; a de-novo peptide → no CID / `present=false`). This is the general drug novelty workflow, so
the fix lands there too.

## Result on the 22 (structure axis, full 136,730-compound ChEMBL/BindingDB library)

| Verdict | Count | Candidates |
|---|---|---|
| **novel** (max_tanimoto < 0.85) | **20 / 22** | all 10 PD-L1; 10 of 12 αvβ6 |
| **occupied** (≥ 0.85 to a known active) | **2 / 22** | **AVB6-B-04** `ARRGNLAPLG` (0.868 → CHEMBL4452226); **AVB6-B-06** `GLFGGRGRR` (0.871 → CHEMBL235999) |

The integrated gate **drops those 2** before the CRO order (verified end-to-end through the
`select_to_rfq --fto-gate` CLI: 22 screened → 2 dropped → 20 ship). Artifact:
`research/guangzhou_all_atom/results/fto_novelty_22.json`.

**Borderline cluster (0.81–0.84, shipped but worth a second look):** PDL1-A-03 (0.814),
AVB6-B-05 (0.810), AVB6-B-12 (0.818), AVB6-B-02 (0.836).

## Cutoff calibration (the 0.85 is empirical, not hand-set)

`calibrate_peptide_cutoff.py` measures the **null distribution a genuinely novel peptide produces**:
400 random canonical-AA cyclic peptides (lengths 8–16, matching the panels) scored by nearest-neighbour
Morgan Tanimoto against the 136,730-compound library.

| percentile of novel-peptide null | NN-Tanimoto |
|---|---|
| p50 | 0.696 |
| p90 | 0.775 |
| p95 | 0.800 |
| **p99** | **0.850** |
| max | 0.919 |

**0.85 == ~p99 of the novel-peptide null ⇒ ~1.25% false-flag rate** — a principled separator, not an
arbitrary number. The 2 flagged CRO candidates (0.868, 0.871) sit **above** p99: genuinely unusual
proximity, but **close analogs, not exact re-discoveries**. The engine now reports a calibrated
`structure_tier`: `near_duplicate` (≥0.95) / `close_analog` (0.85–0.95) / `novel` (<0.85). On the 22:
**20 novel, 2 close_analog, 0 near_duplicate** (artifact `results/peptide_novelty_calibration.json`).

## Honest caveats (do not over-read the verdict)

1. **Peptide Tanimoto baseline is elevated but the cutoff accounts for it.** Unrelated peptides score
   ~0.70 median (shared backbone amide repeat), yet a genuinely novel peptide clears 0.85 ~98.75% of
   the time (calibration above). So 0.85 is a calibrated tail threshold, not a floor-hugging guess —
   and the 2 flags are above the p99 tail. The sequence axis would still sharpen borderline calls.
2. **Patent axis is near-blind for de-novo peptides.** Even with the POST fix, none of the 22 resolve
   to a PubChem CID (they are novel), so the structure-indexed patent lookup returns `present=false`
   with no CID — a **weak** signal. Real peptide FTO is **sequence/Markush claim-text** based (not in a
   structure DB) and ultimately needs a **legal FTO opinion**. This gate is a computational pre-filter,
   necessary but not sufficient.
3. **No sequence-labelled known/patent peptide reference is loaded** (binding_affinity_v1's sequence
   column is empty), so the sequence axis did not run on this dataset. It is built + unit-tested and
   activates when such a reference is supplied (e.g. a patent-sequence corpus or display-NGS hits).
4. **Known-actives ≠ patents.** ChEMBL/BindingDB occupancy means "re-discovery of a characterised
   compound," which is a novelty/IP signal but not a patent clearance.

## Tests
`test_drug_novelty_fto.py` (6: MW-validated macrocyclization, cyclic≠linear, self-match=occupied,
distinct-scaffold=novel, sequence identity, fail-open) and `select_to_rfq.py --selftest` /
`test_select_to_rfq.py` (FTO drop / flag-only / fail-open paths). All green (13 passed).

## How to run
```bash
# score a panel (structure axis; add --check-patents for the network patent axis)
python3 drug_novelty_fto.py --panel results/CRO_SEND_avb6_panelB.csv --seq-col Sequence_N_to_C \
    --restrict-tag is_avb6 True --out results/fto_novelty_22.json
# gate a selection before the CRO order (drops occupied, writes <out>.fto.json sidecar)
python3 select_to_rfq.py --selection sel.json --prefix AVB6-B --fto-gate --out panelB.csv
```

## Multi-reference screening (complementary known sets)

`score_candidate_multi(libraries={name: lib})` screens a candidate against **several** known-actives
references and flags it occupied if **any** reference does (conservative FTO policy). Two complementary
references are now wired:

| Reference | Size | Nature | Result on the 22 |
|---|---|---|---|
| ChEMBL/BindingDB (`binding_affinity_v1`) | 136,730 | general known actives | 20 novel, **2 close_analog** (RGD-type αvβ6 binders) |
| **CycPeptMPDB** (`CycPeptMPDB_Peptide_All.csv`) | 8,466 | known **cyclic peptides** (ncAA/N-methyl macrocycles) | **22 novel** (max T 0.74) |

They catch *different* prior art: the 2 ChEMBL close-analogs score only 0.59/0.62 vs CycPeptMPDB (their
neighbours are linear RGD peptides, absent from the cyclic set); and the canonical head-to-tail designs
are structurally distinct from CycPeptMPDB's ncAA-macrocycle space. Net occupancy across both references:
**2/22** (the same two αvβ6 close-analogs). Artifact: `results/fto_novelty_22_cycpeptmpdb.json`.

## Sequence axis — status

Built + unit-tested, but **still lacks a clean 1-letter known/patent peptide corpus**: CycPeptMPDB
sequences are ncAA monomer-lists (not 1-letter), and `approved_cyclic_peptide_drugs.csv` is
metadata-only (no sequence/SMILES). So the sequence axis did not run on the 22. Activating it needs a
1-letter peptide-sequence reference (patent sequence corpus, THPdb, or ChEMBL peptide sequences) — the
real catch for sequence/Markush-style claims the structure axis misses.

## Next steps
- Add a **patent/known peptide-sequence corpus** to activate the sequence axis (the real peptide-FTO
  signal); consider a peptide-tuned Tanimoto cutoff calibrated on the peptide-peptide baseline.
- Make `--fto-gate` the **default** in the production pre-CRO step once the library location is wired
  on dev (fail-open keeps it safe before then).
- Replace the 2 dropped αvβ6 candidates by re-sampling the generator with a novelty constraint, then
  re-screen — closing the loop so the gate feeds generation, not just filters it.
