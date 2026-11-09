# Learned knowledge identity and multi-round parent protocol — 30 October 2026

## Implementation changes

Three source-audit findings required repairs before a real-source study:

1. A configuration dictionary did not bind mutable runtime parent identities or source exclusions. `LearnedKnowledgeInputs` now fingerprints the actual parent indexes, evidence bundle, task, architecture, source policies, exclusions and runtime flags. Calls, memory validation and configuration exports reject drift; exports are detached copies. The study flag remains outside the exported method identity so the same real-model smoke interface can certify the study configuration, but is bound within the live provider.
2. Frozen-reference tensors could previously be replaced by finite tensors of the correct shape during checkpoint loading. `LearnedKnowledgeBridge` now hashes actual initial reference projector and attention state, retains the expected identity privately, and checks checkpoint contents before copying bridge weights. The checkpoint's own digest assertion is insufficient. Legitimate trained-policy restoration requires the same reference initialization, dtype and parameters. Whole-composite loading still requires caller prevalidation; the generator performs bridge validation before loading its own adapter state.
3. The loop adds generated molecules to its retrieval history. Such molecules lack approved frozen knowledge mappings, so a later round could abort when selecting one as a parent. Bundle-backed off/null/on runs now use `frozen_parent_pool_v1`: a shared ordered pool selected only by reviewed mapping metadata, task scope and source/compound/scaffold/target exclusions. Online generated molecules remain scored and logged but cannot become parents. Evidence availability does not filter the pool. Learned-on retains its requirement for eligible evidence rather than silently falling back.

The parent pool is included in the learned interface through a wrapper without mutating the underlying provider configuration. The interface is bound into frozen-manifest checks, full-model M1 evidence, run identity, generator checkpoints and outputs. Unknown parents remain rejected by the provider.

## Scientific interpretation

This fixed-pool protocol isolates learned conditioning while holding eligible chemical inputs fixed. It intentionally disables retrieval ranking of parent candidates. Retrieval benefit requires a separate prespecified comparison; the off/null/on contrasts cannot establish it. Null/on runs require identical adapter and bridge initialization. Source-qualified context, chemically valid generation parents and evaluation-independent evidence are separate qualifications.

The manuscript and Figure 1 now describe typed feature projection, residual evidence cross-attention, the independently frozen initial reference branch and joint adapter/bridge optimization. Existing scientific result values are unchanged. The full-size checkpoint and real-evidence study remain unmeasured.

Two primary-source structure joins were established in `20261030_REAL_EVIDENCE_READINESS.md`: AfCycDesign/9CDZ:B and grazoprevir/CCD SUE. Neither is promoted into an approved generation catalogue. The first has zero N-methyl amides in the existing library, outside current C; the second is an explicitly qualified peptidomimetic context candidate. Patent recovery candidates remain excluded pending exact molecular topology, assay linkage and split clearance; this code repair does not change that status.

## Remote synthetic validation

Run `knowledge-integrity-r9` uses one c6i.xlarge Spot instance, `i-05de4eafb272be319`, launched 2026-10-30T14:19:36Z. The source-only archive SHA-256 is `3905aa7aa683585b887f39186ef5b0bff0f197f45eae58eba043f5ab7cfeb3b7`; its 80-file source manifest hash is `4470b62a9e46ecc67d93e5a96700ceb1a42f4d39056e041c9bce790d6b7f91a6`.

The run has a 25-minute boot shutdown, 20-minute QA timeout and 30-minute operator deadline (14:49:36Z). Spot price is capped at USD 0.10/hour and the encrypted 40 GB volume deletes on termination. This eighth reserved half-hour window since r2 brings the conservative compute-only reservation to USD 0.40; EBS/network/storage are separate and final billing remains unreconciled. It is within the existing additional USD 1 synthetic CPU QA scope. No corpus extraction, pretrained weights or scientific training were launched.

Remote result: **308 passed, zero failures/errors/skips** (243 hybrid/orchestrator tests, 16 literature-semantic tests and 49 patent-repair tests). QA and bootstrap exited 0; dependency checks passed. Eleven warnings are preserved in the logs, including expected synthetic PEFT checkpoint/configuration warnings and a NumPy deprecation warning. These are software results, not full-checkpoint acceptance or scientific efficacy. Evidence is retained in `20261030_knowledge_integrity_qa_r9/`. All tests executed on AWS; local work was limited to source/document editing, source packaging and figure rendering. EC2 subsequently returned `terminated` for the exact instance ID and an empty volume list for the run tag; both API responses are retained. No QA instance or volume remains.
