# cyclic_peptide_cofold (+ peptide_mmgbsa)

Puts the cyclic-peptide scoring pipeline onto BioMate's AWS Batch executor so it
**parallelizes per peptide**. Two subworkflows, chained:

1. **`structural_biology/cyclic_peptide_cofold`** — Boltz-2 co-folds each
   receptor / cyclic-peptide complex and emits the complex CIF + confidence.
2. **`pharmacology/peptide_mmgbsa`** — OpenMM MM-GBSA scores each folded complex
   and emits a per-peptide binding free energy (dG).

Both are **fan-out** workflows: one process instance per peptide/complex, so
Batch schedules the folds (GPU) and the MM-GBSA scores (CPU) **in parallel**
instead of looping on a single box. This is the whole point of the module.

Ground-truth recipes they are derived from:
`research/guangzhou_all_atom/build_candidates.py` (`boltz_refold`),
`research/guangzhou_all_atom/refold_rerank_driver.sh` (boltz env),
`research/guangzhou_all_atom/peptide_mmgbsa_run.sh` (MM-GBSA).

## Parallelism — how the fan-out is wired

**cofold:** `params.peptides` is a JSON list of `{id, seq}`. The entry workflow
parses it and calls `Channel.fromList(peptides).map { p -> tuple(p.id, p.seq) }`.
`Channel.fromList` emits **one item per peptide**, and each item becomes its own
`COFOLD` task → AWS Batch runs every peptide's fold concurrently.

**mmgbsa:** `params.complexes` is a glob of complex CIFs (typically the cofold
outputs). `Channel.fromPath(params.complexes).map { f -> tuple(f.baseName, f) }`
emits **one item per CIF**, so each complex is scored in its own parallel
`MMGBSA` task.

## cofold — inputs / outputs

| Param | Default | Notes |
|---|---|---|
| `params.peptides` | demo 1-peptide list | JSON list of `{id, seq}`; one parallel fold per element |
| `params.receptor_chains` | demo 1-chain | JSON map `chain_id -> sequence`; **1 OR 2 receptor chains** |
| `params.target` | `demo_target` | metadata label |
| `params.outdir` | `results` | published under `<outdir>/cofold/<id>/` |

Per peptide it writes a Boltz YAML — one `- protein: {id, sequence}` per receptor
chain plus `- protein: {id: P, sequence: <peptide>, cyclic: true}` — then runs:

```
boltz predict in.yaml --out_dir out --use_msa_server --no_kernels --override
```

Outputs (emitted channels, published to `<outdir>/cofold/<id>/`):
`structures` (complex `*.cif`), `confidence` (`confidence_*.json`), and a
`<id>_cofold.json` summary with `complex_iptm` / `iptm` / `confidence_score`
(null, never fabricated, if Boltz does not report one).

**Session-discovered Boltz corrections baked in:** `--no_kernels` (the
cuequivariance ops kernel `ImportError`s otherwise) and `--use_msa_server`
(single-sequence folds error out without an MSA). The boltz env itself is a
py3.11 conda env with conda-forge numpy/scipy + `pip install boltz
cuequivariance-torch`, and conda ToS must be accepted
(`conda tos accept --override-channels --channel .../pkgs/main` and `.../pkgs/r`)
with the env created `--override-channels -c conda-forge` — all pre-baked into
the container image, not done at runtime here.

## mmgbsa — inputs / outputs

| Param | Default | Notes |
|---|---|---|
| `params.complexes` | `results/cofold/**/*.cif` | glob of complex CIFs; one parallel task per CIF |
| `params.charmm_toppar_s3` | `s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/charmm36_toppar` | CHARMM36 toppar (rtf + prm) |
| `params.outdir` | `results` | published under `<outdir>/mmgbsa/<id>/` |

Per complex: split into receptor.pdb (all chains except the shortest) +
peptide.pdb (shortest chain), build 3 PSFs with psfgen (cyclic peptide via
`first='none'`/`last='none'` + head-to-tail `CYCP` patch), OpenMM GBn2 /
CHARMM36m **CPU** minimize + single-point, then
`dG = E_complex - E_receptor - E_ligand`. Emits `<id>_mmgbsa.json`
(`dG_bind_kcal_mol`, component energies, `ligand_ring_closed`, `seq`).

MM-GBSA is a **relative within-target ranking** oracle (Sun PCCP 2019), not an
absolute affinity; entropy is omitted. **Trust only `ring_closed=true` rows.**

## Container requirement

- **cofold → GPU image.** Reuses the Boltz-2 image already used by
  `boltz_structure_prediction`:
  `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest`
  (local fallback `biomate/ai-tools/boltz:latest` via the `NEXTFLOW_USE_AWS`
  ternary). It **must** carry `boltz` + `cuequivariance-torch`.
- **mmgbsa → CPU image.** Reuses
  `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86`
  (local fallback `biomate/biomni-tools:latest`). It **must** carry the
  conda-forge stack `openmm` + `psfgen` + `parmed` + `gemmi`.

No new ECR URIs are invented — both reuse images the existing modules already
reference.

## HONEST gaps

- **Container images are not guaranteed to be built/pushed yet.** The cofold
  image must actually contain a `--no_kernels`-capable boltz + cuequivariance-torch,
  and the mmgbsa image must contain openmm/psfgen/parmed/gemmi. If the current
  `biomni-tools` image lacks that conda stack, a **dedicated MM-GBSA image must
  be built and pushed to ECR before this runs** (peptide_mmgbsa_run.sh provisions
  it via `conda create -c conda-forge openmm psfgen parmed gemmi`). These images
  were **not** built/verified as part of writing these files.
- **ncAA / D-Pro / N-methylation are not expressible in Boltz `sequence:`.**
  Non-canonical residues, D-amino acids and N-methyl backbones are folded as an
  **L-backbone approximation** (standard 20-AA one-letter codes + `cyclic: true`
  only). The macrocycle topology is captured; the exact chemistry of modified
  residues is not. MM-GBSA likewise uses CHARMM36m canonical residues.
- **2-chain receptors (e.g. 9xmm) are heavy to fold.** A large 2-chain receptor
  + peptide co-fold is GPU-time and memory expensive; per-peptide fan-out bounds
  wall-clock but not per-fold cost. In MM-GBSA the receptor's chains are merged
  into one psfgen segment, introducing an artificial bond between the two
  receptor chains — this term is identical in `E_complex` and `E_receptor` and
  **cancels** in the `dG` subtraction, so within-target ranking stays valid, but
  the receptor's absolute internal energy is not physical.
- **Peptide chain id collision.** The peptide uses chain id `P`; if a receptor
  chain already uses `P`, the next free letter is chosen automatically.
- **Not yet registered in the workflow DB or validated end-to-end.** These files
  are Nextflow source only — no run, no DB registration, no E2E was performed.
