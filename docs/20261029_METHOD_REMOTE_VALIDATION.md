# Remote integration validation — 29 October 2026

All reported runs below executed CPU-only on existing EC2 Spot worker `i-0dace5be00919a762`, in isolated temporary directories with GPU visibility disabled. No mining environment was modified and no new instance was launched.

| Suite | Result | SSM command |
|---|---|---|
| Synthetic eligibility guards | 14 passed | `36c18166-6c30-4312-9e52-8680b88fe54e` |
| Mining measurement, merge and launcher contracts | 19 passed in 0.09 s | `7a2783e5-ea69-4f09-a4f1-7e345d9854ed` |
| Hybrid adapters, policy mathematics, conditional knowledge parents, orchestrator and budget harness | 50 passed in 12.18 s | `22357335-62cf-429e-a1bd-3b1fb07e9b84` |

The last suite emitted one test-only warning about converting a gradient-carrying tensor to a scalar in an assertion. Earlier attempts failed on missing isolated dependencies and one missing packaged predecessor module; these were corrected before the passing run. The A6 helper also correctly rejected macOS metadata sidecars as unexpected result files; rebuilding the archive without sidecars preserved its strict scientific grid check.

Evidence logs are under `s3://biomate-nextflow-work/cyclic_peptide/allatom/codex_takeover_20261029/`, in `paper1_review/`, `k2_contract_qa_v1/` and `method_qa_v5/`. A6 independently processed 160 baseline/control records in `method_qa_v3/`; its output is retained as `20261029_TRACK_E_A6_PROPOSED.json`, not a frozen registration. See `20261029_TRACK_E_A6_REVIEW.md` for the failed copy-seed control and missing analyses.

These tests establish software contracts using synthetic examples and small test policies. They do not validate a real mined catalogue, demonstrate ChemFM learning, verify real-model checkpoint recovery, or measure knowledge-on improvement. The real-model M1, qualified knowledge snapshot, prospective configuration freeze and reconciled Spot budget remain outstanding. Resume currently needs an independent cumulative deadline and complete run-identity validation before acceptance.

The scoped source PR includes predecessor modules needed to review these changes because the remote integration branch lacks this research subtree. It excludes raw mined corpora, model weights and private patent material. Runtime research assets and the full extraction stack are not packaged; launchers are included for prospective failure-handling review, not as a certified turnkey deployment.
