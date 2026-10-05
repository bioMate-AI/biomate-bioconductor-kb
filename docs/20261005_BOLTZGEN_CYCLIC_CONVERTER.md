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
