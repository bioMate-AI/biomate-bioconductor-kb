# On-prem dose-selection results (Spark, production config)

Live vLLM runs on the Spark GB10 box, production configuration (reasoning
disabled / `enable_thinking=false`, the deployed on-prem latency setting).
Exact-MTD scorer (`evaluation/local_trial/dose_eval_spark.py`), 0 empties,
per-item receipts included.

- `original_*`  : stock Qwen3.5-9B (`models/base_med`)
- `ours_cpt_*`  : our continued-pretrained 9B (`out/med/fuller_20261005/base_domain`)
- `ours_sft_*`  : CPT + SFT LoRA (`+ out/.../sft`)

| model      | hand outcome | hand fidelity | generated outcome | generated fidelity |
|------------|-------------:|--------------:|------------------:|-------------------:|
| original   | 0.30 | 0.582 | 0.30 | 0.13  |
| ours_cpt   | 0.50 | 0.735 | 0.05 | 0.187 |
| ours_sft   | 0.30 | 0.308 | 0.10 | 0.045 |
