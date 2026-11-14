# Batch F — structure-set pointer: JSON where PDB/CIF expected

**Timestamp:** 2026-11-14  
**Inventory:** `docs/20261114_COLDSTART_FAILED_WORKFLOWS_INVENTORY.md` §5  
**Evidence:** coldstart `design-*-bio-*`, `design-optimise-properties-one-pass-pep-*`

---

## Symptom

`protein backbone design` / `peptide structure design` (`ml_training/diffusion_train.nf`, `model_type=protein_diffusion`) fail in TRAIN:

```
ValueError: unrecognized structure-set pointer '…_constraints.json':
expected a directory, a .txt manifest, or a ('.pdb', '.cif', '.mmcif', '.ent') file.
```

`load_structure_set` in `diffusion_trainer.py` is correct — it rejects non-structure pointers. The bug is upstream: the **wrong attachment** was bound to `params.dataset`.

---

## Cases closed by this fix

| Case | Wrong pointer | Co-attached structure |
|------|---------------|------------------------|
| `design-generate-bio-1` | `…_nanobody_constraints.json` | `6Z43.pdb` |
| `design-generate-bio-2` | `…_enzyme_constraints.json` | `1LYZ.pdb` |
| `design-fold-complex-bio-2` | `…_nanobody_constraints.json` | `6Z43.pdb` |
| `design-predict-filter-bio-2` | `…_nanobody_constraints.json` | `6Z43.pdb` |
| `design-optimise-properties-one-pass-pep-0` | `…_peptide_constraints.json` | `1BXL.pdb` |
| `design-optimise-properties-one-pass-pep-1` | `…_peptide_constraints.json` | `1BXL.pdb` |

Not in this class (different failures — leave for other batches):

- `design-fold-complex-bio-0/1` — script compilation error (not structure-set)
- `design-generate-bio-0` / `design-predict-filter-bio-0` — soft-pass / no structure-set error
- `design-predict-filter-bio-1` — generic pipeline fail

---

## Root cause

Cold-start biologics/enzyme/peptide bundles attach both a real structure (`.pdb`) and a design-rules sidecar (`*_constraints.json`).

1. LLM / extractor often sets `dataset` to the constraints filename (salient “constraints” wording in the prompt).
2. `rebindFilenameValues` rewrote that bare name to the file’s `s3://` / dataset ref **without a kind check**.
3. `bindAttachmentsToParams` then **skipped** `dataset` because it already had a value (`isBound`).
4. Batch staged the JSON; `load_structure_set` raised.

`bindAttachmentsToParams` alone already prefers `.pdb` for the protein_diffusion label  
`Structure set (dir/manifest of PDB/mmCIF backbones, …)` — score 10 vs JSON score 0. The failure was the kind-blind rebind + “already bound → skip” interaction.

**Not a trainer bug.** Do not catch-and-continue inside `load_structure_set`.

---

## Fix (root cause)

In `frontend/shared/attachment-binding.ts`:

1. **`resolveAttachedFileForValue`** — map bare names, s3 URIs, dataset ids, and staged `hash_originalname` basenames back to an attachment.
2. **`rebindFilenameValues`** — if the named/URI file fails `scoreBinding` for the param (kind mismatch), **remap** to `bestAttachmentForParam` (the co-attached `.pdb`/`.cif`), else drop.
3. **`bindAttachmentsToParams`** — if a single-file param is already bound to a wrong-kind attachment, treat as unbound and bind the structure file.

Tests: `frontend/shared/attachment-binding.test.ts` — “structure-set pointer — Batch F”.

---

## Verification

```bash
cd frontend && npx vitest run shared/attachment-binding.test.ts
cd frontend && npx tsc --noEmit -p .
```

Live DEV re-run (after sync): the six cases above should no longer show `unrecognized structure-set pointer '…_constraints.json'`. Remaining TRAIN failures would be RFdiffusion/GPU/data issues, not pointer kind.

---

## Remaining blockers (out of Batch F)

| Item | Why still blocked |
|------|-------------------|
| Wrong **workflow** for design prompts | Routing often picks diffusion *training* for “graft CDRs / redesign pocket / optimise peptide” instead of a design/fold/ADMET workflow — binding the PDB unblocks TRAIN input, not product fit |
| `design-fold-complex-bio-0/1` | Script compilation error (separate class) |
| Soft-pass / empty `workflowNames` | Batch A plumbing |
| DEV sync | Not synced until multi-batch lease + PRE_SYNC |
