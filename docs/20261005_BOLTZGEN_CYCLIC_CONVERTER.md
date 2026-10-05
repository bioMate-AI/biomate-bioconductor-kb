# BoltzGen Cyclic Converter — Verified API, Encoding, and Validation Status

**Date:** 2026-10-05 · For the Path-A BoltzGen cyclic fine-tune (fine-tune BoltzGen's generative
design head on our cyclic + non-canonical co-complexes). This documents the data-converter work:
the **verified** BoltzGen data API, the encoding rules, and the honest validation status.

## Verified BoltzGen data API (confirmed on a live g4dn install, run `boltzgen-convert-20261005T102020Z`)
```
boltzgen.data.parse.mmcif.parse_mmcif(
    path, mols=None, moldir=None, use_assembly=True, use_original_res_idx=False) -> ParsedStructure
# ParsedStructure.structure is the Structure.
boltzgen.data.data.Structure{atoms,bonds,residues,chains,interfaces,mask,coords,ensemble}
    .dump(Path)/.load(Path)
boltzgen.data.data.Record{id,structure,chains,interfaces,templates}.dump/.load
boltzgen.data.data.Manifest{records}.dump/.load
boltzgen.data.const.chirality_type_ids = {CHI_TETRAHEDRAL_CW:1, CHI_TETRAHEDRAL_CCW:2, ...}  # D vs L
```
Training is launched (separately) via `python src/boltzgen/resources/main.py <config> pretrained=boltzgen1_structuretrained_small.ckpt`.

## Training-data target format (for the fine-tune)
`targets/{manifest.json, records/*.json, structures/*.npz}` + a CCD `mols/` dir. One example =
Record(json) + Structure(npz) [+ per-chain MSA npz].

## Encoding rules (from `bound_cyclic_v1/bound_cyclic_manifest.jsonl`: pdb_id, pep_chain, peptide_seq
with `X`=ncAA, seq_len, cyclization_type)
- **head-to-tail** → set `chains['cyclic_period'] = seq_len` on the peptide chain + add the closing
  C(last res)→N(first res) bond to `Structure.bonds`.
- **disulfide / sidechain** → keep `cyclic_period=0`; the SG–SG (or sidechain) bond is parsed from the
  CIF — verify it survives.
- **non-canonical (ncAA / N-methyl / D-AA)** → `parse_mmcif` already represents them as CCD components
  with the residue `modified` flag and atom chirality from the CCD mol; **requires the CCD mols dir**.

## VERIFIED Structure schema (numpy structured arrays — dumped from a live parse, run `convert4`)
```
chains  : name, mol_type, entity_id, sym_id, asym_id, atom_idx, atom_num, res_idx, res_num, cyclic_period
          # chain name is `name` (BoltzGen RENAMES chains, e.g. 'A1' — NOT the original PDB letter);
          # cyclic_period field confirmed present; a chain's residues = res_idx..res_idx+res_num
residues: name, res_type, res_idx, atom_idx, atom_num, atom_center, atom_disto, is_standard, is_present
          # NO 'modified' field -> ncAA/N-methyl/D-AA = is_standard==False; a residue's atoms = atom_idx..+atom_num
atoms   : name, coords, is_present, bfactor, plddt
          # NO per-atom chirality field -> D vs L is carried by the residue CCD `name` (e.g. DAL), which round-trips
bonds   : chain_1, chain_2, res_1, res_2, atom_1, atom_2, type   # row0 type=1 (covalent)
```
`parse_mmcif` returns `ParsedStructure`; the Structure is **`ParsedStructure.data`** (not `.structure`).

## PASS/FAIL — NON-VACUOUS encoding asserts (samples from bound_cyclic_v1, CCD mols resolved)
| sample | cyclization | ncAA | pep chain (res_num) | ncAA count (is_standard=F) | counts | names (chirality) | cyclic_period | C→N bond | status |
|---|---|---|---|---|---|---|---|---|---|
| 11MG | disulfide | yes | **found** (idx 3) | 4 | ✓ | ✓ | n/a | n/a | **PASS** |
| 1BY5 | sidechain_backbone | yes | **found** (idx 9) | 3 | ✓ | ✓ | n/a | n/a | **PASS** |
| 1BCK | head_to_tail | yes | **found** (idx 1) | 8 | — | — | — | — | blocked → **fixed** |
| 3AV9 | head_to_tail | no | **found** (idx 16) | 0 | — | — | — | — | blocked → **fixed** |

**Confirmed working (non-vacuously):**
- **Peptide-chain identification by `res_num == seq_len`** — all 4 matched the correct short chain (not None). The earlier vacuous-PASS (PDB-letter match) is resolved.
- **ncAA detection via `is_standard==False`** — nnc = 8 / 0 / 4 / 3, matching the manifest `X` content.
- **Round-trip counts + residue-CCD-name (chirality) preservation** — PASS on the disulfide + sidechain samples.
- **cyclic_period in-place set** — works (no error; it's an in-place array edit on the frozen dataclass).

**One bug found + fixed:** head-to-tail failed on `FrozenInstanceError: cannot assign to field 'bonds'`
— `Structure` is a **frozen dataclass**, so appending the closing C→N bond via `struct.bonds = …` is
rejected. Fixed with `object.__setattr__(struct, "bonds", …)`. (The in-place `cyclic_period` edit is fine.)

**Remaining: one short confirming run** of the head-to-tail path with the frozen-dataclass fix
(cyclic_period persists, appended C→N bond persists = `len(bonds)+1`), then this table is fully green.
The non-head-to-tail path is already green non-vacuously. Command:
`python boltzgen_cyclic_convert.py --validate <pep.cif> --moldir mols/ --seq-len <N> --cyclization head-to-tail`

## ⚠️ The blocker that must be satisfied: the CCD `mols` dir
`parse_mmcif(moldir=…)` needs per-residue pickles (`ALA.pkl`, `MET.pkl`, …). It is **not** auto-present.
Source (from the BoltzGen README / HF org):
- **`mols.zip` from `https://huggingface.co/datasets/boltzgen/inference-data`** → unzip → pass as `moldir`; or
- `boltzgen download <artifacts>` (the `artifacts` arg is **positional and required** — `boltzgen download`
  bare errors; confirm the exact artifact name that includes the CCD on the instance).

## Validation status — HONEST
**Not yet green-lit.** Two cloud runs were spent and both failed on environment issues, not converter logic:
1. Run 1 (`…T102020Z`): `parse_mmcif` failed — `mols/` was empty (`FileNotFoundError: …/ALA.pkl`). It
   *did* capture the real API (above).
2. Run 2 (`convert2-…T102902Z`): failed on (a) a trivial Python `global` bug (fixed) and (b) the CCD
   mols still not sourced (`boltzgen download` needs an artifact arg; my spec-yaml probe used wrong keys).

I stopped at the **3-instance budget** rather than launch a 4th (cost guardrail). The converter
(`boltzgen_cyclic_convert.py`) is written against the verified API with runtime schema discovery and a
built-in `--validate <cif> --moldir <dir>` that dumps the real `chains/residues/atoms/bonds` field
names and round-trips. The structured-array **sub-field names** (chain-name, cyclic_period, atom-name,
residue-modified) are discovered at runtime and still need pinning from that validator's schema dump.

## Exact remaining step (one ~$0.50 run)
On an instance (or box) with BoltzGen installed:
1. Get the CCD mols: `huggingface-cli download boltzgen/inference-data mols.zip --repo-type dataset && unzip mols.zip -d mols/` (or the right `boltzgen download` artifact).
2. `python boltzgen_cyclic_convert.py --validate <sample.cif> --moldir mols/` → read the schema dump,
   pin the sub-field names in `set_cyclic`/`_add_headtail_bond`, finalize the closing-bond index math,
   re-run on ≥5 samples (incl. one ncAA), confirm: cyclic_period persists, closing bond present,
   `modified` set on ncAA residues, D-AA chirality preserved, atom/residue counts match.

## Files
- `research/guangzhou_all_atom/boltzgen_cyclic_convert.py` — converter (verified API; validation pending).
- Cloud runs: `s3://knowledge-datasets-1759951976/cyclic_peptide/runs/boltzgen-convert*` (logs + api_introspect.txt).
