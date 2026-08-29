---
license: cc-by-4.0
---
# RealBio Benchmark — workflow_generation

*Part of **RealBio Benchmark**: real-world execution benchmarks for bioinformatics AI agents (see the suite README).*

**Task.** Given a research intent, select the correct analysis category (partition A) OR identify the required key tools (partition B). Both ground truths are standard and catalog-neutral.

**Items.** 40  ·  **Ground-truth field(s).** `{'any': ['expected_category', 'key_tools']}`  ·  **Scoring.** objective (see ../score.py) — no LLM judge required.

Any system can run this benchmark and be scored on the same items. 


