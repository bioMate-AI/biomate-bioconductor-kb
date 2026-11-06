# Immune training publication

The immune work is published in `bioMate-AI/biomate`.

- Original training branch: `audit-fix-immune-llm`, commit `94165c62a`.
- Published training branch: `codex/immune-training-publish`, commit `da4187e1d6ef1c6f6ef65ca75f24741ee997d55d`.
- Review documentation and durable all-collected source snapshots: `integration/dev-test`, under `docs/20260912_all_collected_training/`.

GitHub rejected the original training history because `research/immune_llm_baseline/data/ccle/tpm.csv.gz` is 241,530,115 bytes, exceeding its 100 MB file limit. With user authorization, a separate publication copy was created with that path removed from history. A tree comparison verified this is the only file difference between the original and published training tips. The original local working branch and its Git dataset object were preserved. No force push was used.

The publication copy has rewritten commit identifiers; do not treat it as a fast-forward continuation of the original branch. For new published development, start from `codex/immune-training-publish`. Dataset availability must be supplied separately; this publication does not establish an external dataset location.

The commit includes inference, multi-omic audit scripts, continuation scripts, and evaluation documents. Seven changed Python files passed syntax checks; the shell continuation script passed `bash -n`, and the staged diff passed whitespace validation. These checks are not scientific validation or proof of full-scale training completion.

Unrelated frontend work and Nextflow cache cleanup were not included.
