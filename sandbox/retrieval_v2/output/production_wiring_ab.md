# family_dedup Production Wiring A/B (Local, Pre-Dev-Sync)

**Date:** 2026-05-20
**Patched file:** `backend/lib/galaxy/ai/workflow_ops/autofix/tool_parameter_recommender.py`
**Flag:** `BIOMATE_FAMILY_PRIORITIZE=1`
**Eval limit per query:** 5 results
**Internal fetch_limit when flag on:** 5 × 10 = 50

## Utility

| Metric | Baseline (flag OFF) | Treatment (flag ON) | Delta |
|---|---|---|---|
| Top-1 = canonical family | 7/30 (23.3%) | 30/30 (100.0%) | **+23 hits (+76.7pp)** |

## Time cost

| Metric | Baseline | Treatment | Δ |
|---|---|---|---|
| mean_ms | 4.95ms | 8.53ms | +3.58ms |
| p50_ms | 5.41ms | 4.13ms | -1.29ms |
| p95_ms | 9.66ms | 35.93ms | +26.27ms |
| p99_ms | 10.53ms | 42.12ms | +31.59ms |
| max_ms | 10.53ms | 42.12ms | +31.59ms |

## Held-out safety

| Metric | Value |
|---|---|
| Held-out families | 10 |
| Queries where treatment ≠ baseline | 0 |

✅ Zero behavior change on held-out — library never fires on uncovered families.

## Per-query (treatment)

| query | expected | top-1 name | hit | latency |
|---|---|---|---|---|
| samtools | samtools | Depad SAM/BAM file | ✓ | 42.12ms |
| bwa | bwa | Map with BWA-MEM | ✓ | 15.74ms |
| picard | picard | BedToIntervalList | ✓ | 8.30ms |
| fastqc | fastqc | FastQC | ✓ | 2.66ms |
| deseq2 | deseq2 | DESeq2 | ✓ | 6.71ms |
| bowtie2 | bowtie2 | Bowtie2 | ✓ | 5.92ms |
| multiqc | multiqc | MultiQC | ✓ | 0.79ms |
| cutadapt | cutadapt | Cutadapt | ✓ | 0.89ms |
| kraken2 | kraken2 | Kraken2 | ✓ | 2.90ms |
| bcftools | bcftools | bcftools view | ✓ | 1.49ms |
| bedtools | bedtools | bedtools Intersect intervals | ✓ | 11.42ms |
| gatk4 | gatk4 | gatk4 MergeMutectStats | ✓ | 2.76ms |
| seqkit | seqkit | seqkit | ✓ | 4.06ms |
| seqtk | seqtk | seqtk_comp | ✓ | 6.78ms |
| augustus | augustus | Augustus | ✓ | 2.47ms |
| maker | maker | Maker | ✓ | 3.96ms |
| prokka | prokka | Prokka | ✓ | 3.88ms |
| bakta | bakta | Bakta | ✓ | 0.20ms |
| mash | mash | MASH | ✓ | 13.37ms |
| mafft | mafft | MAFFT | ✓ | 12.60ms |
| muscle | muscle | MUSCLE | ✓ | 4.19ms |
| tabix | tabix | tabix | ✓ | 1.97ms |
| busco | busco | Busco | ✓ | 5.65ms |
| meme | meme | MEME | ✓ | 23.94ms |
| plink | plink | plink | ✓ | 13.32ms |
| minimap2 | minimap2 | Map with minimap2 | ✓ | 15.61ms |
| snpeff | snpeff | SnpEff | ✓ | 3.83ms |
| macs2 | macs2 | MACS2 | ✓ | 1.45ms |
| trinity | trinity | Trinity | ✓ | 35.93ms |
| emboss | emboss | EMBOSS: needle | ✓ | 1.15ms |
