---
license: cc-by-4.0
---
# RealBio Benchmark — cross_domain_routing

*Part of **RealBio Benchmark**: real-world execution benchmarks for bioinformatics AI agents (see the suite README).*

**Task.** Given a natural-language analysis request, name the single correct WORKFLOW that should run it (targets are public nf-core pipeline names where applicable). Credit for acceptable_alts.

**Items.** 200  ·  **Ground-truth field(s).** `correct_workflow`  ·  **Scoring.** objective (see ../score.py) — no LLM judge required.

Any system can run this benchmark and be scored on the same items. Targets are public workflow names (mostly nf-core), so this is a real, catalog-neutral routing task any system can attempt.


