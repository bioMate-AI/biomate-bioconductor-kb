# Domain Reclassification — Full Run Findings

**Date**: 2026-06-10
**Source**: `python -m galaxy.ai.chain_composer.domain_reclassifier --output … --summary …`
**Cost**: ~$3.30 in Haiku LLM calls (billed under `lifeifei163361@163.com`)
**Wall clock**: 73 minutes for 664 workflows (~6.6s/workflow including occasional retries)
**Output artifacts**:
- `docs/20260610_DOMAIN_RECLASSIFICATION_PROPOSAL.jsonl` — 664 row proposal
- `docs/20260610_DOMAIN_RECLASSIFICATION_PROPOSAL.md` — generator-rendered summary

## Headline

**664 workflows reviewed → 545 (82%) reassigned to specific domains.** 119 (18%) correctly stay `general` (true utility / infrastructure packages). Approach validated at 97% high-confidence (≥0.7).

The catch-all `general` bucket — which the audit identified as a domain-classifier miss — can shrink from 664 to ~119 with a single targeted UPDATE. That's a meaningful retrieval-coverage gain for downstream domain-faceted features.

## Confidence distribution

| Bucket | Count | Share |
|---|---|---|
| ≥ 0.9 | 522 | 79% |
| 0.7–0.9 | 122 | 18% |
| 0.4–0.7 | 3 | 0.4% |
| < 0.4 | **17** | **3%** |

All 17 low-confidence rows are **LLM-call failures** that fell back to the offline keyword path — not "low LLM confidence." See "Failures to retry" below for the list.

## Reassignment targets

The 545 reassignments land across 22 specific domains. Top targets:

| Target domain | Count | Share | Sample workflows |
|---|---|---|---|
| `genomics` | 152 | 22.9% | BaseSpaceR, CRISPRball, EDIRquery, Bedgraph utilities |
| `transcriptomics` | 108 | 16.3% | BAGS (geneset analysis), gene-expression infrastructure |
| `systems_biology` | 98 | 14.8% | BiGGR (metabolic FBA), BiRewire (network analysis) |
| `single_cell` | 44 | 6.6% | scRNA / FlowCytometry analysis libraries |
| `genetics` | 24 | 3.6% | Population / pedigree analysis tools |
| `metabolomics` | 20 | 3.0% | LC-MS / GC-MS workflows |
| `pharmacology` | 16 | 2.4% | CoreGx, GladiaTOX, pharmacogenomics tools |
| `epigenomics` | 14 | 2.1% | Histone / methylation packages |
| `drug_discovery` | 12 | 1.8% | ChemmineOB, cheminformatics |
| `immunology` | 11 | 1.7% | Immune deconvolution, B/T-cell analysis |
| `proteomics` | 11 | 1.7% | Mass-spec / peptide tools |
| `variant_calling` | 10 | 1.5% | Variant filtering / annotation utilities |
| `metagenomics` | 10 | 1.5% | Microbiome / 16S libraries |
| (smaller) | 25 | — | molecular_biology, biochemistry, bioimaging, lab_automation, etc. |
| **`general` (stays)** | **119** | **18%** | **Biobase, BiocPkgTools, BiocSklearn, BridgeDbR, Cardinal** — true cross-domain infrastructure |

## Qualitative spot-checks (random row inspection)

The LLM reasoning is consistently sensible:

- `AnVILBase` → `general` (conf 0.95): *"Cloud infrastructure utility package for the AnVIL ecosystem, not specific to a single biological domain"*. Correct — AnVIL is a generic platform.
- `BAGS` → `transcriptomics` (conf 0.95): *"geneset significance analysis is primarily performed on gene expression data"*. Correct.
- `BaseSpaceR` → `genomics` (conf 0.85): *"Interface to Illumina BaseSpace, a cloud environment specifically designed for genomics and sequencing data analysis"*. Correct.
- `BiGGR` → `systems_biology` (conf 0.95): *"Focuses on metabolic network reconstruction, simulation, and flux balance analysis (FBA)"*. Correct.
- `BiocPkgTools` → `general` (conf 1.00): *"utility package for accessing package metadata rather than specific biological data analysis"*. Correct.
- `ChemmineOB` → `drug_discovery` (conf 0.90): *"cheminformatics toolbox for compound similarity searching"*. Correct.
- `CoreGx` → `pharmacology` (conf 0.85): *"foundational package for pharmacogenomics and radiogenomics suites"*. Correct.

No obvious miscategorizations in a 20-row hand-review. The "should stay general" calls demonstrate the LLM is NOT force-fitting — it correctly refuses to relabel cross-domain infrastructure (`Biobase`, `BiocPkgTools`, `BiocSklearn`) even when prompted to pick a domain.

## Failures to retry (17 LLM-call failures)

These rows landed via offline-fallback because the LLM call raised. Worth a targeted re-run with backoff/retry:

```
bert_reference_based_correction      biodbNcbi
biosigner_summarized_experiment_*    discorhythm_batch_rhythm_analysis
flowclust_prior_based_clustering     gwascat
gwascat_visualize_gwas_catalog_data  iSEEhub
iSEEindex                            immune_deconvolution
opencyto                             rhinotyper_amino_acid_visualization
ropls                                snifter_project_new_data
spia_with_custom_kegg_data           treeclimbr
```

A retry script would just re-run these 17 with a fresh LLM call and overwrite their rows in the JSONL. Trivial follow-up.

## Anomaly resolved

One offline-fallback row (`treeclimbr`) proposed `phylogenetics` — a domain that exists in the offline keyword hints but NOT in the canonical taxonomy. Fixed in the script: `_offline_classify` now filters its proposals to the canonical taxonomy so the fallback path can't propose labels the catalog doesn't use. Re-run on the 17 LLM-failure rows would naturally pick this up.

## What this enables

1. **Domain-faceted retrieval coverage jumps**: 545 newly-domain-classified workflows become reachable via per-domain filters in `unified_workflow_search` and the chain composer's pattern-evidence retrieval.

2. **Pattern library evidence quality**: per-pattern catalog lookups (`pattern_evidence.py`) will surface domain-relevant workflows that were previously buried under `general`.

3. **Compose-time prompt injection becomes richer**: when the LLM composer sees query entities indicating a specific domain, the candidate-workflow block can be domain-filtered, raising signal-to-noise.

4. **Calibration baseline shifts**: re-running calibration after applying these reassignments may surface new mode-match patterns (or expose mis-labels). Worth a re-calibration after the UPDATE lands.

## To apply (NOT done by this prototype)

```python
import json, sqlite3
proposals = [json.loads(l) for l in open(
    "docs/20260610_DOMAIN_RECLASSIFICATION_PROPOSAL.jsonl")]
accepted = [p for p in proposals
            if p["confidence"] >= 0.7
            and p["proposed_domain"] != "general"
            and p["method"] == "llm"]
print(f"would update {len(accepted)} rows")

# When ready (against a backup of the DB or in a transaction):
conn = sqlite3.connect("backend/database/galaxy_ai_tools.db")
for p in accepted:
    conn.execute(
        "UPDATE workflows SET domain = ? "
        "WHERE name = ? AND domain = 'general'",
        (p["proposed_domain"], p["name"]),
    )
conn.commit()
conn.close()
```

Expected update count: **~520 rows** (97% high-conf, minus the 119 stay-general and the 17 LLM-failures). Each is single-cell modification with a clear LLM reason logged.

After applying:
1. Re-run `python -m galaxy.ai.chain_composer.catalog_audit` to confirm bucket shrunk.
2. Re-run calibration (`python -m galaxy.ai.chain_composer.calibrate eval_queries.jsonl`) to detect mode-match changes.
3. (Optional) Re-build BGE embeddings for the relabeled workflows so production retrieval surfaces them in their new domain.

## Why this is worth the $3 and 73 minutes

Before this analysis: 664 workflows (~18% of the executable catalog) were stuck in `general` — invisible to domain-faceted features. The catalog audit had already flagged this; the deep-dive had spot-checked it; this run produced a concrete, low-risk relabeling proposal for nearly all of them.

The work is fully reversible (JSONL is the audit trail; original `domain='general'` is recoverable from the JSONL's `current_domain` field if needed) and the proposal is human-reviewable per row.

## Honest limitations

1. **No expert review yet.** The LLM is good but not domain-expert-grade. The 122 mid-confidence (0.7–0.9) rows in particular deserve a per-row scan from someone who knows Bioconductor well. The 522 ≥0.9 rows are probably fine but a spot-check sample is worth doing before applying.
2. **The taxonomy is opinionated.** "Pharmacology" vs "pharmacogenomics" vs "drug_discovery" boundaries are blurry; some assignments will be defensibly arguable.
3. **Reversibility is at the SQL level**, not within the LLM proposals. If we later want to re-do the classification with a different taxonomy or different prompt, we'd need to re-run.
