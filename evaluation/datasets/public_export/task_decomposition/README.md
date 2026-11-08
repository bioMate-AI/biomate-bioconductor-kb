# task_decomposition (RealBio)

Decompose a multi-part request into an ordered sub-task DAG. Measures **parallel-vs-sequential structure**
(the routing signal), balanced across parallel / sequential / mixed cases.

- **Data:** `data.jsonl` — `{id, query, structure(parallel|sequential|mixed), gold_subtasks:[{sub_task,order,depends_on}]}`.
- **Predict:** `run_baseline.py task_decomposition --model <m>` → JSON list `[{sub_task,order,depends_on}]`.
- **Score:** `score.py task_decomposition results/<m>/task_decomposition.jsonl` →
  `structure_accuracy` (does predicted parallel/sequential/mixed match gold) + `subtask_count_coverage`.
