# DisambigCard wire — production verification + gate sensitivity finding

Date: 2026-06-12
Branch: `bioc/v2-qc-audit-panel`
Deploy: commit `e7a2bad34` + build-stub `16ecf146` → live on dev at sync 20:31:12

## What was tested

`frontend/client/src/components/chat-message.tsx` was wired to render
`WorkflowDisambiguationCard` when the backend returns
`workflow_type === 'disambiguation'` with a `candidates` list (see
`backend/lib/galaxy/ai/ai_assistant.py:3515-3529`).

### Layer-by-layer verification

| Layer | Test | Result |
|---|---|---|
| Bundle on dev | `curl https://dev-public.biomate.ai/assets/index-DTbNuGp1.js \| grep WorkflowDisambiguation` | ✅ 2 matches — code shipped |
| Component RTL tests | task #41 (DisambigCard v2 port) | ✅ pass |
| Backend disambig emission on dev | 4 ambiguous queries via `/api/ai_assistant/generate_workflow` | ❌ **never triggered** |

### Queries tried (all returned `workflow_type='nextflow'`, no candidates)

1. `"DESeq2 or edgeR differential expression"` → resolves to `nf-core/differentialabundance`
2. `"differential expression analysis"` → resolves to `noiseq_differential_expression_analysis`
3. `"compare DESeq2 edgeR limma for RNA-seq"` → resolves to `nf-core/rnaseq`
4. `"scRNA-seq differential expression"` → resolves to `nf-core/rnaseq`

## Root cause

The disambig gate in `ai_assistant.py:3515` requires **all three** of:

```python
match_type != 'high_confidence'  # i.e. < 12.0 score
≥ 2 candidates scoring ≥ 6.0
gap between candidate 1 and 2 < 3.0
```

BGE dense retrieval (`unified_workflow_search.py`) almost always produces
a clear winner with `score >= 12.0`, which short-circuits to high-confidence
and bypasses the gate entirely. The gate functions correctly but its
operating point is too strict to fire in normal use.

## Conclusion

- **The wire is correct and shipped.** Code is in the deployed bundle;
  unit tests cover the render path.
- **The disambig path is reachable but rarely fires.** This is a separate
  router-tuning issue, not a UI gap.

## Next step (separate task — not Wave 1-1)

Decide whether to loosen the disambig gate:

1. Drop the `score >= 6` floor (anything with `match_type != 'high_confidence'`
   and `≥ 2 candidates` triggers disambig).
2. Raise the high-confidence cutoff above `12.0` so the bioc consensus
   queries (which currently score ~14) fall into the disambig band.
3. Force disambig when example queries explicitly enumerate alternatives
   (e.g. the `bulk_rnaseq_consensus_de_bioc` query text mentions edgeR /
   limma / DSS — the router could honour that as a disambig signal).

Option 3 best matches the bioconductor handoff intent. Tracking outside
the v2 closure plan.
