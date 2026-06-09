# Chain Composer — Live LLM Findings (Run 1)

**Date**: 2026-06-08
**Model**: whatever `default_llm()` resolves to from the user env (Anthropic per `BIOMATE_INTENT_MODEL` defaults)
**Worktree**: `agent-aaf4e393b5ea5b614` at commit `f1606fea4` + this doc
**Setup**: `set -a && . backend/.env && set +a && PYTHONPATH=backend/lib`

Three queries, three illustrative outcomes. Results recorded verbatim from one CLI run; not cherry-picked.

## Query 1 — workflow hallucination caught by verifier

**Query**: `validate biomarkers from a TCGA discovery cohort on UK Biobank using GRCh38`

**Result**: `source=llm`, mode=`upfront`, confidence=0.96

**Emitted plan** (rationale named `discovery_then_validation` pattern):
1. `TCGAbiolinks_download` → 2. `biomarker_feature_selection` → 3. `ukb_data_extraction` → 4. `confirmatory_survival_analysis` (plus a cross-edge 2→4)

**Verifier**: `ok=False`, 4 `unknown_workflow` errors — **none of the 4 workflow names exist in the catalog**. The LLM hallucinated plausible names.

**Revision loop did not improve**: source stays `llm` not `llm_revised`. The retry also hallucinated (same error count, so the acceptance gate `re_errors < errors` rejected it).

**Root cause**: the prompt shows the LLM the relevant *patterns* and similar *curated chains*, but **not the actual workflow catalog**. The LLM has no way to know which names are real, so it invents semantically-correct-sounding names. This is the prototype's most important missing piece.

## Query 2 — clean LLM output, no revision needed

**Query**: `robust differential expression with DESeq2, edgeR, and limma on tumor vs normal RNA-seq`

**Result**: `source=llm`, mode=`upfront`, confidence=1.00

**Emitted plan** (rationale named `multi_method_consensus` pattern):
1. `nf-core/rnaseq` → 2. `BIOC_ExpHunterSuite`

**Verifier**: `ok=True`, zero errors.

Both workflows are real catalog entries. `BIOC_ExpHunterSuite` is the right canonical Bioconductor package for ensemble DE — the LLM picked it correctly. Pattern-selection and grounding both worked.

## Query 3 — verifier + revision loop succeeded

**Query**: `multi-omics RNA-seq plus ATAC-seq integration on mouse brain mm10`

**Result**: `source=llm_revised`, mode=`upfront`, confidence=1.00

**Emitted plan** (rationale named `multi_omics_integration` pattern):
1. `nf-core/rnaseq` → 3. `BIOC_plyranges`
2. `nf-core/atacseq` → 3. `BIOC_plyranges`
3. → 4. `BIOC_nullranges`

**Verifier on first attempt**: had errors.
**Revision pass**: produced the plan above with all real workflows. `re_errors < errors` triggered acceptance. Source flipped to `llm_revised`.

This is the design working as intended — LLM emits an imperfect plan, verifier flags issues, LLM revises with feedback, accepted.

## What this confirms about the design

1. **Pattern library is doing its job.** All three queries correctly identified the right shape (`discovery_then_validation`, `multi_method_consensus`, `multi_omics_integration`).
2. **The verifier catches hallucination cleanly** — every fake workflow name was flagged. The structural check (does this name exist in `workflows.name` or in any curated chain's step list) is sufficient for this class of error.
3. **The revision loop helps when the LLM has any nearby ground truth** — Query 3 worked because the curated chains in the prompt contained real Bioconductor package names the LLM could draw on.
4. **The revision loop cannot rescue cases where the LLM has zero ground truth** — Query 1's domain (TCGA/UK Biobank biomarker validation) has no representative curated chains in the catalog, so the LLM had no real workflow names to anchor on and revision retried the same kind of hallucination.

## The missing piece (next increment)

**Workflow retrieval into the prompt.** Same BM25 infrastructure, different table. Retrieve top-K from `workflows.name + description + domain` and inject as a "CANDIDATE WORKFLOWS — use only these names" block alongside patterns and chains. This should:

- Eliminate hallucination in queries like Query 1 by giving the LLM a closed set of real names to pick from.
- Make Query 2 even more robust by exposing `BIOC_DESeq2`, `BIOC_edgeR`, `BIOC_limma` as explicit alternatives to the curated `BIOC_ExpHunterSuite`.
- Make Query 3 less reliant on revision by giving the LLM real workflow candidates on the first pass.

Implementation: a `retrieve_workflows(query, top_k=8, entity_terms=...)` function in `retrieval.py`, called by `compose_chain`, prompt block in `_build_prompt`.

## What we should NOT do based on these results

- **Don't tighten the verifier to reject more aggressively.** It already catches hallucination correctly; adding more rules without LLM context would just produce more empty stubs.
- **Don't add a second revision pass.** Diminishing returns; if the first revision fails the LLM is fundamentally missing context that more retries won't fix. Better to spend the budget on getting the prompt right the first time (i.e., workflow retrieval).
- **Don't auto-promote `llm_revised` to L1 curated chains yet.** Query 3's plan looks right but hasn't been executed against real data — premature to call it learned. Add this only after we have a successful-run telemetry signal.

## Open questions

1. **Cost per call**: Query 1 ran ~1-2 LLM calls (NER + compose + maybe revision). Query 3 ran 3-4 (NER + compose + revision). At Sonnet/Opus rates this is plausibly ~$0.02–0.10/query. Worth instrumenting before wiring to production.
2. **Latency**: each compose call felt ~3-8 seconds. Acceptable for a planning step that happens once per chat turn; would be unacceptable per-keystroke.
3. **Should NER share the compose model?** Right now both use `default_llm()`. NER is cheap and could use Haiku/Flash; compose benefits from larger context. Worth splitting.

## Status

Findings doc only. No code changes since `f1606fea4`. Workflow retrieval is the proposed next increment.
