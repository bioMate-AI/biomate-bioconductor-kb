# decomposition_v2 — dependency-graph task-decomposition benchmark

Held-out benchmark that measures whether a plan recovers the right **dependency DAG**
(nodes + edges + parallel/sequential/mixed topology), replacing the coarse 4-class
`structure_accuracy` of `evaluation/datasets/public_export/task_decomposition`.

Motivation and construction: `docs/20260912_onprem_llm/20261006_DECOMP_DATA_AND_BENCHMARK.md`
Root-cause analysis it addresses: `docs/20260912_onprem_llm/20261006_DECOMPOSITION_ERROR_ANALYSIS.md`

## Files
- `decomposition_v2.jsonl` — 165 rows, balanced 55 parallel / 55 sequential / 55 mixed.
- `score.py` — node-F1 + edge-F1 + per-class structure scorer (+ label-free WCC / parallel-width diagnostics).

## Row schema
```
{
  "id": "decv2_<structure>_<i>",
  "query": "<natural-language request, built from REAL catalog workflow descriptions, tool-name-free>",
  "structure": "parallel" | "sequential" | "mixed",
  "gold_subtasks": [ {"sub_task": <real workflow name>, "order": N, "depends_on": [orders],
                      "tool_id": <primary tool>, "input_types": [...], "output_types": [...],
                      "domain": <d>, "role": "root|prep|step|analysis"}, ... ],
  "instr": "<same instruction string as the public_export decomposition eval>"
}
```
Gold DAGs: **parallel** = I/O-disjoint distinct-domain roots (all `depends_on=[]`);
**sequential** = `out_types(A) ∩ in_types(B) ≠ ∅` chain; **mixed** = two independent
per-domain prep→analysis pairs, partition `{2,2}` (two parallel 2-chains).

## Scoring
Prediction = the model's raw answer, a JSON list of `{sub_task, order, depends_on}`.
```
python score.py --gold decomposition_v2.jsonl --pred preds.jsonl
# preds.jsonl rows: {"id": <bench id>, "pred": [ {sub_task,order,depends_on}, ... ]}
```
- `node_f1` — sub-tasks recovered (token-overlap match to gold sub_task / domain / tool_id).
- `edge_f1` — dependency edges recovered on matched nodes.
- `structure_accuracy` + `by_class` — 4-class shape match, reported per parallel/sequential/mixed.
- `wcc_count_match`, `parallel_width_match` — label-free topology diagnostics carried over from the error analysis.

Leakage: every workflow used here is held out from the SFT rows in
`docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.jsonl` (disjoint name sets; proof in
`decomp_depgraph.split.json`, overlap = 0).
