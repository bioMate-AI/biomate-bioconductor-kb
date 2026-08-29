---
license: cc-by-4.0
---
# RealBio Benchmark — pbpk_benchmark

*Part of **RealBio Benchmark**: real-world execution benchmarks for bioinformatics AI agents (see the suite README).*

**Task.** Given a compound (SMILES), dose and route, predict PK; reference = published clinical PK values.

**Items.** 15  ·  **Ground-truth field(s).** `reference`  ·  **Scoring.** objective (see ../score.py) — no LLM judge required.

Any system can run this benchmark and be scored on the same items. 

**Attribution.** Reference PK values from published clinical pharmacology sources (per-item 'reference').
