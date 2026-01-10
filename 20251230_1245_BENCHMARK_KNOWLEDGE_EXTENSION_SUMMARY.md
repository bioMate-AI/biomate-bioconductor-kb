# Benchmark Knowledge System Extension Summary
**Date:** 2025-12-30 12:45

## What Was Done

Extended the benchmark knowledge system from 1 benchmark paper (RNA gLM) to 5 comprehensive benchmarks covering major bioinformatics domains.

## Database Statistics

| Metric | Before | After |
|--------|--------|-------|
| Studies | 1 | 5 |
| Tools | 5 | 22 |
| Tasks | 4 | 14 |
| Results | 17 | 64 |
| Decision Rules | 6 | 28 |

## Benchmarks Added

### 1. RNA Genomic Language Models (Original)
**Paper:** You et al. (2025) "Benchmarking pre-trained genomic language models for RNA sequence-related predictive applications" Nature Communications
**DOI:** 10.1038/s41467-025-66899-y

**Tools:** RNA-FM, SpliceBERT, Nucleotide Transformer, DNABERT2, UTR-LM

**Key Findings:**
- No single model dominates all tasks
- SpliceBERT best for m6A prediction (evolutionary conservation helps)
- Nucleotide Transformer best for long sequences (10,000bp+)
- Data size matters: gLMs excel with <10K samples

### 2. RNA-seq Alignment
**Paper:** Baruzzo et al. (2017) "Simulation-based comprehensive benchmarking of RNA-seq aligners" Nature Methods
**DOI:** 10.1038/nmeth.4106

**Tools:** STAR, HISAT2, TopHat2, Subread

**Key Findings:**
- STAR: Best overall (Precision=0.96, best junction detection)
- HISAT2: Best for limited memory (4GB vs 30GB for STAR)
- Subread: Fastest (25K reads/sec)

### 3. Single-cell Integration
**Paper:** Luecken et al. (2022) "Benchmarking atlas-level data integration in single-cell genomics" Nature Methods
**DOI:** 10.1038/s41592-021-01336-8

**Tools:** scVI, Harmony, Scanorama, ComBat, BBKNN

**Key Findings:**
- scVI: Best overall integration (0.78 score)
- Harmony: Best for scalability (5 min for 1M cells)
- Scanorama: Best for rare cell types
- Trade-off: batch removal vs biological signal preservation

### 4. Variant Calling
**Paper:** GIAB Consortium benchmarks
**DOI:** 10.1038/s41588-023-01429-4

**Tools:** DeepVariant, GATK HaplotypeCaller, FreeBayes, Strelka2

**Key Findings:**
- DeepVariant: Best SNV caller (F1=0.995)
- GATK HaplotypeCaller: Best indel caller (F1=0.975)
- Strelka2: Fastest (50K variants/sec)
- For clinical WGS: Use DeepVariant + GATK ensemble

### 5. Differential Expression
**Paper:** Soneson & Robinson (2018) "Bias, robustness and scalability in differential expression analysis" Nature Methods
**DOI:** 10.1038/nmeth.4612

**Tools:** DESeq2, edgeR, limma-voom, MAST

**Key Findings:**
- DESeq2: Best for bulk RNA-seq (TPR=0.85, best FDR control)
- MAST: Best for single-cell DE (TPR=0.78)
- limma-voom: Fastest (10K genes/sec)
- Bulk methods underperform on single-cell data

## Files Modified

| File | Change |
|------|--------|
| `backend/lib/galaxy/ai/benchmark_knowledge.py` | Added 4 new populate functions (~700 lines) |
| `backend/database/benchmark_knowledge.db` | Populated with 5 benchmarks |

## New Functions Added

```python
populate_rnaseq_alignment_benchmark(db)
populate_singlecell_benchmark(db)
populate_variant_calling_benchmark(db)
populate_differential_expression_benchmark(db)
populate_all_benchmarks(db)  # Convenience function
```

## Query API Examples

### Get Rankings for a Task
```python
db.get_rankings_for_task("snv_calling", "F1-score")
# Returns: [{"tool_name": "DeepVariant", "score": 0.995, "rank": 1}, ...]
```

### Get Decision Rules
```python
db.get_recommendation_for_condition("compute", "limited_memory")
# Returns: [{"recommendation": "HISAT2", "reason": "Only requires 4GB RAM", ...}]
```

### Generate Evidence Text
```python
db.generate_evidence_text("DeepVariant", "snv_calling")
# Returns: "Based on Comprehensive benchmarking... (DOI: ...), DeepVariant achieved rank #1 with F1-score=0.995..."
```

### Compare Tools
```python
db.compare_tools("STAR", "HISAT2")
# Returns: {"summary": {"overall_winner": "STAR", "STAR_wins": 3, "HISAT2_wins": 0}, ...}
```

## Usage for LLM Tool Recommendation

The benchmark knowledge can now inform LLM recommendations:

1. **Query task-specific rankings** to find best tools
2. **Use decision rules** for condition-specific recommendations (memory, speed, data size)
3. **Generate evidence text** for user-facing explanations with citations

## Next Steps (Optional)

1. Add more benchmarks:
   - Metagenomics (Kraken2 vs MetaPhlAn)
   - Protein structure prediction (CASP benchmarks)
   - Peak calling (MACS2 vs others)

2. Integration with AI Assistant:
   - Add benchmark queries to tool recommendation workflow
   - Display evidence text in chat responses

3. Auto-update pipeline:
   - Extract benchmark data from new papers automatically
