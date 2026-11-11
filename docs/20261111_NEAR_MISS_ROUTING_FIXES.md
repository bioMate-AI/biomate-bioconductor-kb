# Near-miss workflow routing — root causes and fixes (2026-11-11)

Four live near-misses on dev (`d303eca6` / `eaad9163`), reproduced through the real chat API with
the shared fixture and the cold-start demo bundles. Every measurement below is from the live stream
or from offline scoring against `backend/database/galaxy_ai_tools.db`; nothing here was synced to
dev (that is a separate, reviewed step).

## 1. "Design nanobody candidates against this epitope." → `bispecific_antibody_design`

**Live evidence** (dev frontend log, session `nearmiss-nanobody-1794407970`):

```
[GalaxyAssistant] Message: Found workflow: bispecific_antibody_design
[GalaxyAssistant] Optional params (autofilled): [{"name":"format","value":"nanobody_fusion"}]
[GalaxyAssistant] Step 6c-2: text presents "Nanobody Design Against SARS-CoV-2 Spike RBD",
                  not a search candidate for this request — keeping "bispecific_antibody_design"
```

Two separate defects.

### 1a. Wrong workflow — a lexical near-miss the scorer had no axis for

Offline scoring of the live intent (bm25×1.5 is 85–90 % of every term):

| rank | before | score | after | score |
|---|---|---|---|---|
| 1 | antibody_developability | 98.05 | antibody_developability | 98.05 |
| 2 | **bispecific_antibody_design** | **87.50** | Antibody Developability | 73.37 |
| 3 | Antibody Developability | 73.37 | **scfv_antibody_design** | 71.72 |
| 4 | scfv_antibody_design | 71.72 | scfv-pmpnn | 69.98 |
| 5 | *Run Audit Export* (upload-block noise) | 71.20 | profam | 69.22 |

Root causes, both in `backend/lib/galaxy/ai/unified_workflow_search.py`:

* **No therapeutic-format axis.** `bispecific_antibody_design`'s description lists every format it
  can emit ("BiTE, CrossMab, DART, DVD-Ig, Knob-into-Hole, and nanobody fusion"), so it matches the
  words of a request for any ONE of them — while the pipeline itself needs two targets and builds a
  two-arm construct. Fix: step **4d**, `biologic_format_conflict()` — the format a workflow declares
  is read from its NAME, the format a user wants from their request; a mono-specific request vs a
  multi-specific workflow name (or the reverse) costs `_FORMAT_MISMATCH_PENALTY` (25, env-tunable,
  sized like the input-kind penalty because a small bonus cannot move an 85 %-bm25 score).
* **Upload plumbing was part of the query.** `[Uploaded datasets: … dataset_id=<uuid>,
  s3_uri=s3://biomate-nextflow-work/uploads/…]` was tokenised into the FTS query; bucket/path words
  scored real catalog rows ("Run Audit Export" at rank 5). Fix: `strip_plumbing_blocks()` applied
  once at `search()` entry, so FTS, the Pass-0 LLM browse, dense retrieval and the re-rank all see
  the same clean text. `[Attached files: …]` is kept — filenames carry signal.

**Open (reported, not fixed):** the catalog has no nanobody/VHH design workflow. The nearest honest
answers (`scfv_antibody_design`, `scfv-pmpnn` — ProteinMPNN against a target antigen PDB) now rank
3rd/4th, behind two duplicate `antibody_developability` rows whose score comes from the bundle's
provenance sentence ("Expression, affinity and developability are predictions"). Closing that needs
either a nanobody-design workflow in the catalog or an operation-capability axis for design
requests — the latter has no measurement coverage today (2/200 routing-eval queries are biologic
design, both bispecific), so it was not shipped blind.

### 1b. Chat text named a workflow that does not exist

Step 6c-2 correctly refuses to move the card to an invented name, but it left the reply introducing
the card as "**Nanobody Design Against SARS-CoV-2 Spike RBD**" (founder screenshot: "**Nanobody
Fusion Design**"). CLAUDE.md requires the chat name to be the card title exactly. Fix:
`relabelWorkflowHeader()` in `frontend/server/galaxy-assistant.ts` — when the presented name is
neither the card nor a search candidate, the header is relabelled in place to `cardWorkflowName()`,
keeping the " — one-line description". The card is never moved by this.

## 2. "Train a potency predictor on our in-house assay data." → a design workflow

`ML_TRAINING_ROUTING=1` is set on dev, yet the training route never fired. Reproduced
deterministically:

```
detect_training_intent(...)  → True
extract_training_config(...) → ValueError: could not resolve a dataset from the request
route_ml_training_result()   → None   → falls through to the catalog search
```

Root cause: `ai_assistant.generate_workflow_unified` called `route_ml_training_result(user_intent)`
with no data, so the user's **attached** table — the thing the model is to be trained on — was
invisible to the router, which then declined and handed a model-TRAINING request to the catalog
search (the founder's run got scaffold hopping, `input_smiles` = "the compound series to hop"; a
repeat run got `Qsar Rf Model`).

Fix: thread `uploaded_datasets` into the route (`select_training_dataset()` accepts only readable
training tables — csv/tsv/parquet/xlsx/jsonl/h5ad/smi/sdf/txt — so a request with raw reads attached
still falls through exactly as before), read the label column from the request
(`_infer_target_col`: pIC50 → `target_col=pIC50`, not `y`), and name the card after the model asked
for (`_derive_name`: "potency predictor", not "molecular model"). An attached table also wins over a
public alias: "train an hERG classifier" + their `herg.csv` trains on their file.

## 3. Proteomics DE still routed to Chemoproteomics Pulldown

The §4.2 operation-phrase canonicalisation works offline but left only a **1.6-point** margin
(deqms_maxquant_lfq 90.93 vs Chemoproteomics Pulldown 89.34) — less than the Pass-0 LLM re-rank
(up to +3.0) plus the dense bonus (+0.5) can hand back, which is why dev still showed the QC
workflow. Fix: step **9b** — an operation the workflow cannot perform is a disqualifier, not a
missing bonus. When the data shape is known AND processed and the request asks for a differential
test, a workflow whose own text shows no differential capability (`_performs_differential_test`:
canonicalised phrase, "differential" anywhere in name/desc/tools/tags, or a differential tool name
such as deqms/msqrob2/DESeq2) loses `_OPERATION_MISMATCH_PENALTY` (12). Margin after: **13.6**
(90.93 vs 77.34). Gated on a processed shape, so a raw-FASTQ "find the differentially expressed
genes" request keeps its full pipelines.

## 4. "Integrate … with SNF" → a MOFA2 card

`route_multiomics_result` asked `method_selector.recommend()` for a method from the DATA SHAPE and
never looked at the method the user named; with no goal detected (the prompt's "n_clusters=3" has no
word boundary before "cluster") the cascade fell through to its MOFA2 default. Fix: `named_method()`
— exactly one named, runnable method is an instruction; the card runs it and the shape-based pick is
demoted to an alternative with the reasoning kept in the rationale. Two methods named ("MOFA2 or
SNF?") or an unpackaged one (StabMap) leave the selector in charge.

## Measurements

* Offline search eval (`scripts/routing_eval/search_offline_eval.py`, 200 cross-domain routing + 24
  bioc method selection + 20 domain-retag): **routing 0.870, bioc 0.525, retag 0.750, bioc_invalid 1,
  retag_strict 3/4 — identical before and after; zero rows changed.**
* `backend/lib/galaxy/ai/tests/` — failure set byte-identical to HEAD (15 pre-existing, all
  environment: langgraph/LLM deps); +22 new tests in `test_near_miss_routing.py`.
* `ml_training` + `multiomics` suites: 378 passed, 3 skipped.
* `npx tsc --noEmit -p .`: clean. `npx vitest run`: 2957 passed, 1 failed — a sparse-checkout
  artifact (`scripts/routing_replay/cases.json` is not checked out in this worktree).

Not done here: dev sync and live re-verification of the fixes (the reproduction above is of the
BROKEN behaviour on the deployed build).
