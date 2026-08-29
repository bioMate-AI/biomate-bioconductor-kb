---
license: cc-by-4.0
---
# RealBio Benchmark — protocol_thresholds

*Part of **RealBio Benchmark**: real-world execution benchmarks for bioinformatics AI agents (see the suite README).*

**Task.** Given a sequencing protocol and a generic QC threshold, decide whether the sample is biologically VALID and whether it should PASS or FAIL — vs the naive universal-threshold action.

**Items.** 100  ·  **Ground-truth field(s).** `['ground_truth', 'expected_correct_action']`  ·  **Scoring.** objective (see ../score.py) — no LLM judge required.

Any system can run this benchmark and be scored on the same items. 


