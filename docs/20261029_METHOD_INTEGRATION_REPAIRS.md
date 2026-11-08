# Method integration repairs — 29 October 2026

Status: implementation written and statically reviewed; new remote tests have not run. This is engineering progress, not evidence of scientific performance or completed study acceptance.

The implementation follows the branch plan's reuse/modify/new split: ChemFM supplies the causal atom-SMILES backbone; the existing strict PeptideCLM implementation supplies optional frozen retrieval embeddings. The architecture's knowledge integration, constraints and controlled preference loop remain the study's focus. No new backbone pretraining or 3D coordinate generator is introduced.

## Implemented

- Pinned adaptation LoRA is safely merged into the pretrained base before creating fresh preference-training adapters and optimizer state. The merged base supplies the frozen preference reference; restore rejects a different initialization identity.
- The runner validates and loads a reviewed initial retrieval store with explicit source, document, compound, scaffold and target exclusions. Source policy can admit reviewed external knowledge while excluding held-out benchmark families. Training-score names are frozen separately.
- Fingerprint, frozen-encoder and hybrid retrieval reuse the existing index code. Retrieved rows retain metadata, and embeddings are cached rather than regenerated for unchanged entries. Encoder assets and reused implementation files enter run identity.
- Mixed known/unknown parent pools preserve knowledge applicability for mapped parents while checking all known parents for forbidden evidence. Unknown parents receive no invented metadata.
- The learning-stall gate observes every search round, including rounds without preference pairs. Missing-pair rounds are labelled as such rather than reported as measured zero KL.
- No-retrieval and no-monitor ablations are wired. No-monitor disables the Goodhart monitor while retaining learning-stall control.
- Checkpoints preserve retrieval and stopping state. Matching completed results return without repeating held-out scoring. Expired run deadlines still fail closed before returning a prior result.

## Validation and remaining work

Synthetic regression fixtures cover the changed interfaces, including a tiny randomly initialized PEFT model for adaptation/reference equivalence. Execute them only on approved AWS Spot compute using `hybrid/ec2/qa_integration.sh`; no tests, fitting or model inference were run locally. The prepared CPU suite is separate from real-model M1 and scientific evaluation.

Remaining acceptance requires remote regression success, real-model checkpoint/restore checks, eligible frozen knowledge and retrieval inputs, reviewed experiment manifests and verified budget headroom. The earlier M1–M5 predictor's neural memory is not thereby fused into the causal generator. Prefix constraints are not a general molecular-feasibility proof, and current study outputs cannot establish knowledge benefit without the registered comparisons.
