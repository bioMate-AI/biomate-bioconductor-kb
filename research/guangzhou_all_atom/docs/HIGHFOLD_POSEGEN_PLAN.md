# D2 (2ii) — Bound-Pose Generation Plan (HighFold3 / HighFold-MeD / Boltz / Chai-1)

**Date:** 2026-09-27 · **Status:** PLAN + STUB ONLY — no GPU/pose-gen job is launched here.
**Scope:** manufacture *bound-relevant* cyclic peptide–receptor poses for entries that HAVE a target
but LACK an experimental complex structure. This is the second half of D2; the first half (mining
real complexes) is `mine_bound_cyclic_complexes.py`.

**Grounding:** `docs/20260927_CYCLIC_CORPUS_AND_TRAINING_STRATEGY.md` (Part A move #3 — "generate
bound-relevant poses via HighFold3 / HighFold-MeD (native N-Me/D-AA cyclic) or Boltz/Chai-1/AF3;
prioritize anything with a real receptor over more solution conformers") and
`docs/20260927_PEPTIDE_PARALLEL_WORK_PLAN.md` (D2 → M2c target-SFT).

---

## Why this is needed (and why it is second-class to mining)

The generator's target-SFT stage (M2c) needs `p(seq, struct, mod | binding site)` supervision —
a cyclic peptide *in its receptor pocket*. Experimental bound cyclic complexes number only in the
hundreds to low-thousands (see the review note / `--estimate` output). To reach a training-useful
volume we must *predict* bound poses for the large SMILES-only / sequence-only ligand sets that DO
name a target:

- **CycPeptMPDB** (~7,334 unique cyclics) — permeability-labeled, target sometimes named, no complex.
- **BindingDB peptide subset** — has a named target (UniProt) + measured affinity, rarely a structure.

**Honest ranking (committee):** a single real experimental complex outweighs many predicted poses.
Predicted poses are *conformer_provenance = HighFold3 | Boltz1 | Chai1 | AF3* and must be tagged as
such; **never train a bound-geometry head on them without the provenance flag** (blocking fix #3).
They are for *volume + curriculum warm-up*, and only after a confidence filter.

---

## Tool → subset routing

| Ligand subset | Chemistry | Tool (primary) | Why |
|---|---|---|---|
| Canonical cyclic (head-to-tail / disulfide), named protein target | L-AA only | **Boltz-1 / Chai-1** (AF3-class, open weights) | Best receptor-conditioned complex accuracy for canonical chemistry; runs the peptide as a chain in the complex. |
| Disulfide-rich / multi-cyclic canonical | L-AA + SS | **HighFold3** | Purpose-built cyclic-constraint AF-derivative; enforces the SS / head-to-tail geometry AF3-class models get wrong. |
| **N-Me / D-AA / non-canonical cyclic** (our differentiator) | ncAA | **HighFold-MeD** | Only tool that natively models N-methylation + D-amino acids in a cyclic-constrained fold. This is the subset APCyc/RFpeptides can't do and where our IP lives. |
| SMILES-only, no protein target named | — | **NOT pose-gen** → route to solution-conformer (ETKDG / HighFold3-monomer, move #4) | No receptor ⇒ no bound supervision possible; belongs in the AE geometry corpus, not M2c. |

**Confidence gate (before any pose enters the corpus):** keep only poses with model confidence above
threshold (Boltz/Chai `iptm`/`plddt`; HighFold cyclic-RMSD self-consistency). Predicted poses failing
the gate are dropped, not down-weighted — a wrong pocket pose is worse than no pose for SFT.

---

## Spot-GPU execution shape (to be launched separately, NOT here)

Per the program's spot-only discipline (self-terminate + stream to S3; interruption-harmless):

- **Instance:** single `g5.2xlarge` (A10G 24 GB) spot for Boltz-1/Chai-1/HighFold on typical
  receptor+short-peptide complexes; escalate to `g5.4xlarge` / `g6e` only for large receptors
  (> ~800 residues) that OOM at 24 GB. AF3-class complex inference is the memory driver, not the peptide.
- **Isolation:** its OWN spot instance — Lane D pose-gen must NOT contend with Lane M training GPUs
  (`20260927_PEPTIDE_PARALLEL_WORK_PLAN.md` no-GPU-contention guarantee).
- **Job shape:** dead-man's-switch in the user-data preamble; each ligand→pose job writes a single
  `{pose.pdb + confidence.json + provenance}` tuple to `s3://.../cyclic_peptide/bound_poses/<tool>/`
  and self-terminates the batch when the queue drains.
- **Idempotent manifest:** append to the same schema the mining script emits (so mined + generated
  rows share one table), with `provenance` ∈ {HighFold3, HighFold_MeD, Boltz1, Chai1, AF3} and a
  `confidence` field. Never overwrite; additive.

### Throughput / cost estimate (order-of-magnitude, for scoping only)

| Tool | ~min / complex (A10G) | complexes / GPU-hr | spot $/GPU-hr (g5.2xl, us-west-2, hist.) | $ / 1,000 poses |
|---|---:|---:|---:|---:|
| Boltz-1 / Chai-1 | 3–8 | ~10–15 | ~$0.40–0.60 | ~$30–60 |
| HighFold3 (cyclic constr.) | 5–12 | ~6–10 | ~$0.40–0.60 | ~$50–100 |
| HighFold-MeD (ncAA) | 8–15 | ~4–8 | ~$0.40–0.60 | ~$70–150 |

**Budget sketch:** poses for the target-named CycPeptMPDB/BindingDB subset (order ~2–5k ligands with
a resolvable UniProt receptor after filtering) ≈ **~$150–500 of spot GPU + 1–3 spot-days wall-clock**,
Boltz/Chai for canonical + HighFold-MeD for the ncAA slice. Cheap relative to its leverage — but gated
behind the confidence filter and the provenance discipline, and **not** launched until the mining pass
sets the experimental baseline count.

---

## Stub interface (to implement when launched — NOT run here)

```
generate_bound_poses.py                 # (future) driver, mirrors mine_bound_cyclic_complexes schema
  --ligand-table  cycpeptmpdb_targeted.jsonl   # seq/HELM/SMILES + UniProt target + measured label
  --tool          {boltz1|chai1|highfold3|highfold_med}   # routed per subset table above
  --receptor-src  {pdb|alphafold}      # experimental pocket preferred; AF2 model fallback
  --conf-thresh   0.7                  # iptm/plddt gate; below -> drop
  --out-s3        s3://.../cyclic_peptide/bound_poses/<tool>/
  # emits: pose.pdb + confidence.json + manifest row {provenance=<tool>, conformer_provenance=<tool>}
```

Convergence: mined (experimental) + generated (confidence-gated) rows → one `bound_cyclic_corpus`
table → **M2c target-conditioned SFT**. Experimental rows are the held-out *test* anchor
(`conformer_provenance ∈ {crystal,NMR,cryoEM}`); generated rows are train-only warm-up.

## Do-not / discipline
- Do NOT launch any pose-gen job from this doc. This is design + cost scoping only.
- Do NOT let a predicted pose enter a *test* set — experimental only for evaluation.
- Do NOT present improved reconstruction/denoising on predicted poses as evidence of binding
  (carried honest gate from the strategy doc).
