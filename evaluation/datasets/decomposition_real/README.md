# decomposition_real — REAL (non-synthetic) dependency-graph held-out validation

The out-of-synthetic-generator test set for task decomposition. Every DAG here is parsed
from a **real** artifact whose topology we did **not** design — nf-core/Nextflow channel
graphs, curated `workflow_chains`, and GTN expert tutorials — so a model that only learned
the shapes emitted by `evaluation/local_trial/build_decomp_depgraph.py` cannot ace it by
pattern-matching the generator.

Construction + distribution analysis: `docs/20260912_onprem_llm/20261007_REAL_DECOMP_DATA.md`
Builder: `evaluation/local_trial/build_decomp_real.py` (+ `nf_parse.py` Groovy DAG parser).

## Files
- `decomposition_real.jsonl` — 68 held-out rows (60 sequential / 5 mixed / 3 parallel).
- `score.py` — the `decomposition_v2` scorer, **extended**: node matching now takes the MAX
  token-F1 over `{sub_task}`, `{sub_task∪tool_id}`, `{sub_task∪tool_id∪domain}` variants.
  Required because real gold carries single-word tool nodes (e.g. GTN `FastQC`, `velveth`)
  whose one token is diluted below threshold by the v2 single-bag match. With the fix,
  gold-vs-gold scores **node_f1 = edge_f1 = structure_accuracy = 1.0** across all classes.

## Row schema (identical to `decomposition_v2`)
```
{"id","query","structure","gold_subtasks":[{sub_task,order,depends_on,node_key,tool_id,
  input_types,output_types,domain,role}],"instr","source","unit"}
```
`source` ∈ {`real_nfcore_subworkflow`, `real_workflow_chain`, `real_gtn_tutorial`}.
`unit` = the source-unit identity used for the leakage partition.

## Provenance of the gold edges (no fabrication)
- **nf-core**: node = a process invoked in the named `workflow{ main: … }` block; edge =
  channel wiring `PROC(OTHER.out.x)` / `ch = OTHER.out.y; PROC(ch)`. Versions plumbing
  (`.out.versions`, `ch_versions`) is excluded — it is not a data-flow edge.
- **workflow_chains**: node = a chain step; edge = an explicit `connections[]`
  `{from_step → to_step}` record.
- **GTN**: node = a `{% tool %}` invocation in a `tutorial.md`; sequential edge between
  consecutive distinct tools in the author's hands-on order.
Queries are the real descriptions / user intents with the node labels scrubbed; any row whose
query reduces to a tool-name list (no science left) is dropped, never fabricated.

## Leakage
Source-unit sets are a **hard partition** vs the SFT training rows in
`docs/20260912_onprem_llm/data_pool_v2/decomp_real.jsonl` — `unit_overlap = 0`
(`decomp_real.split.json`). Node (`tool_id`) overlap is reported honestly (chains reuse the
same catalog workflow across different chains; nf-core/GTN nodes are file/tutorial-local).

## Scoring
```
python score.py --gold decomposition_real.jsonl --pred preds.jsonl
# preds.jsonl rows: {"id": <bench id>, "pred": [{sub_task,order,depends_on}, ...]}
```
