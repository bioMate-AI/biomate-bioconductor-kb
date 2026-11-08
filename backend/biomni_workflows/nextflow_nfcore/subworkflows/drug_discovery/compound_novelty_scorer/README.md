# compound_novelty_scorer

Patent / FTO-oriented **novelty scoring** for generated molecules. For each query
SMILES it runs an FPSim2 Tanimoto/Morgan nearest-neighbour search against a
prebuilt ChEMBL known-actives fingerprint index and emits a per-molecule verdict:

| Field | Meaning |
|---|---|
| `max_tanimoto` | Nearest-neighbour Tanimoto to the known-actives library |
| `nearest_known_id` | `mol_id` of that nearest known compound |
| `novel` | `true` when `max_tanimoto < novelty_tanimoto_cutoff` (default **0.85**) |
| `status` | `ok`, or `index_unavailable` if the FPSim2 index can't be loaded |

A generated molecule at/above the cutoff is essentially a re-discovery of a known
active and is flagged **not novel**; below it, the scaffold is materially distinct.

## Reuses the existing ChEMBL FPSim2 index

This subworkflow **reuses the same prebuilt FPSim2 `.h5` fingerprint index required
by `fpsim2_chemical_similarity`** (`params.fpsim2_db`), mounted read-only with the
**identical mount pattern** — the index is large and must never be Nextflow-staged.
Build/host it once with that subworkflow's `tools/prepare_fpsim2_db.sh` (→ S3).

**DB registration is a separate dev-side step** — this subworkflow does **not**
register or build the index; it only consumes an already-mounted `.h5`.

## Parameters

| Param | Default | Notes |
|---|---|---|
| `query_smiles` | *(required)* | Comma-separated inline SMILES **or** a SMILES file path |
| `fpsim2_db` | *(required)* | Mounted prebuilt FPSim2 `.h5` known-actives index |
| `novelty_tanimoto_cutoff` | `0.85` | `novel = max_tanimoto < cutoff` (strict) |
| `check_patents` | `false` | **OFF by default.** When true, a coarse SureChEMBL/PubChem patent-presence lookup runs per molecule (network required). The core path needs no network beyond the mounted DB. |

## Output

One `<query_id>_novelty.json` per query (fan-out: one parallel task per molecule),
e.g.:

```json
{
  "query": "CC(=O)Oc1ccccc1C(=O)O",
  "status": "ok",
  "max_tanimoto": 1.0,
  "nearest_known_id": 1,
  "novelty_tanimoto_cutoff": 0.85,
  "novel": false,
  "method": "fpsim2_tanimoto_morgan",
  "patent": { "checked": false }
}
```

## Honesty contract

If FPSim2 is not importable or the `.h5` index cannot be loaded, the workflow
**fails loudly** — it writes an explicit `{"status": "index_unavailable", "reason": ...}`
record and exits non-zero. It **never fabricates** a `max_tanimoto` or a novelty
verdict. The optional patent lookup is best-effort and records its own errors
without corrupting the novelty result.

## Local test

```bash
tests/run_local_test.sh
```

Builds a tiny known-actives DB (aspirin, ibuprofen, …) in a throwaway venv and
asserts a known compound scores `max_tanimoto == 1.0` / `novel = false` while a
clearly-distinct scaffold scores `novel = true`. If FPSim2/RDKit can't be
installed (no network), it falls back to a parse-only + novelty-logic check —
never a fabricated verdict.
