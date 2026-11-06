[openai] 21510 chars -> /Users/kky/biomate-review/docs/20260912_onprem_llm/committee_reviews/audit_openai.md

## Executive assessment

Do **not** spend GPU yet. The samples show evidence of a more severe problem than the known fractional-integer bug: some SFT inputs appear physically truncated or malformed, and at least one visible routing label is likely wrong.

Examples:

- The first routing sample ends after `Alphagenome Track Predic` and contains **no `Request:` span at all**. The answer `nf-core/atacseq` is therefore unsupported.
- The second ends at `mass‑spectromet`, and `nf-core/proteomicslfq` is visibly a more plausible choice than `glmsparsenet` from the available request text.
- The third ends in the middle of the candidate list, before the request, and the gold `spillr` is not visible among the candidates.
- The RAG example ends at `3D geno`; among the candidates, `hic`, `hicar`, `cutandrun`, and `atacseq` are all potentially plausible. `atacseq` is not securely grounded by the shown text.

If this truncation is only in the audit display, verify that explicitly from raw JSONL hashes and lengths. If it exists in the training artifacts, it is a P0 dataset-corruption defect.

---

# 1. Data quality defects

## P0: malformed and truncated SFT records

Your current paraphrase code does not protect against pre-existing or post-generation truncation.

`split_request()` accepts any request of 8–1200 **characters**, including:

- `I have label-free mass‑spectromet`
- incomplete sentences,
- clipped structured blocks,
- partial candidate names,
- requests missing the key modality or objective,
- content ending because of a source-field character cap.

It also contradicts its own docstring:

```python
# a trailing structured block after the request is rare; treat rest as request
```

The docstring says suffixes remain verbatim, but the implementation always returns `suffix=""`. Any structured block after `Request:` is paraphrased, not preserved.

Required validation before training:

- Every routing record must contain exactly one parseable request and a complete candidate block.
- Gold must exactly match one and only one candidate after normalization.
- Candidate names must not be truncated.
- Reject suspicious terminal fragments: dangling hyphens, unclosed brackets/quotes, incomplete UTF-8, abrupt alphanumeric endings, or input at a known character cap.
- Validate task-specific required sections with a parser, not `rfind()`.
- Store and compare source length, serialized length, and final rendered length.
- Manually inspect all records at common maximum lengths; spikes at 512/1,000/2,048 characters are strong truncation evidence.

Do not silently “repair” these by generating missing text. Return to the source artifact.

## P0: “grounded in a real artifact” does not imply a correct label

The visible routing examples suggest labels may have been assigned by weak lexical association or source metadata rather than by the actual request.

Specific risks:

- A real workflow can still be the wrong workflow for a real study.
- Paper titles and abstracts often
