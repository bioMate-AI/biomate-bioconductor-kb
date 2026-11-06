# Guangzhou peptide-first model research

- [Survey](docs/SURVEY.md): peptide models, shared-backbone feasibility, other drug modalities, research gaps and 26 primary-source references.
- [Implementation plan](docs/PLAN.md): baseline qualification, data, modeling and prospective evaluation.
- `evaluate.py`: working RDKit chemical-identity audit for peptide or small-molecule attempts.
- `results/smoke_audit.json`: software fixture result, not generated-drug performance.

Run with an environment containing RDKit and pytest:

```bash
python -m pytest --confcutdir=research/guangzhou_all_atom -o addopts='' research/guangzhou_all_atom/tests -q
python research/guangzhou_all_atom/evaluate.py research/guangzhou_all_atom/tests/smoke_attempts.json --training-smiles research/guangzhou_all_atom/tests/smoke_training.smi --output research/guangzhou_all_atom/results/smoke_audit.json
```

Verification: all 9 focused tests passed; the CLI fixture audit completed successfully.

The local interpreter used is `/Users/kky/opt/anaconda3/envs/biomni_e1/bin/python`, with RDKit 2025.03.6. The fixture has six attempts, five valid graphs and three unique valid graphs. It includes a failed attempt, a duplicate linear peptide, and two atom orderings of the same cyclic dipeptide.

Input is JSON with a non-empty `attempts` array; each entry has a unique string `sample_id` and `smiles` (null for failure). Optional `failure_reason` is retained for invalid records. Supply complete unfiltered attempts. A training reference is optional, one SMILES per line. If absent, novelty is unknown; invalid or empty supplied references fail explicitly.

This first component preserves stereochemistry, charges, isotopes and covalent topology when comparing identity. It strips atom maps and removable explicit hydrogens, and does not normalize tautomers or salt parents. It reports unspecified stereo and disconnected structures separately. Fingerprint similarity is a descriptive diagnostic, not calibrated uncertainty. It does not validate requested peptide closure, 3D poses, synthesis, binding, safety or efficacy.

An isolated AWS baseline run has now been launched; see [dataset collection and training start](docs/DATA_COLLECTION_AND_START.md) and the run status files for verified progress. The original fixture audit remains a software test, not model performance.
