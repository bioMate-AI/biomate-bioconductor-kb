# family_dedup Simulated Wiring A/B (Local, No Production Modifications)

**Date:** 2026-05-20
**Approach:** Call existing recommender for raw FTS output, then apply `prioritize_query_family` externally — produces same numbers as actual wiring patch would, without modifying protected production file.

## Utility

| Metric | Baseline (current prod) | Treatment (wired) | Delta |
|---|---|---|---|
| Top-1 = canonical family | 7/30 (23.3%) | 30/30 (100.0%) | **+23 (+76.7pp)** |

## Time cost (after YAML caches warm)

| Metric | Baseline | Treatment | Δ |
|---|---|---|---|
| mean_ms | 0.08ms | 0.28ms | +0.20ms |
| p50_ms | 0.08ms | 0.23ms | +0.15ms |
| p95_ms | 0.10ms | 0.57ms | +0.47ms |
| p99_ms | 0.10ms | 0.66ms | +0.56ms |
| max_ms | 0.10ms | 0.66ms | +0.56ms |

## Held-out safety (n=10 uncovered families)

| Metric | Value |
|---|---|
| Queries where treatment ≠ baseline | 0/10 |

✅ Zero behavior change on held-out families. Library never fires on uncurated queries.

## Per-query treatment results

| query | expected | top-1 name | hit | latency |
|---|---|---|---|---|
| samtools | samtools | Depad SAM/BAM file | ✓ | 0.57ms |
| bwa | bwa | Map with BWA-MEM | ✓ | 0.66ms |
| picard | picard | BedToIntervalList | ✓ | 0.53ms |
| fastqc | fastqc | FastQC | ✓ | 0.32ms |
| deseq2 | deseq2 | DESeq2 | ✓ | 0.42ms |
| bowtie2 | bowtie2 | Bowtie2 | ✓ | 0.47ms |
| multiqc | multiqc | MultiQC | ✓ | 0.16ms |
| cutadapt | cutadapt | Cutadapt | ✓ | 0.16ms |
| kraken2 | kraken2 | Kraken2 | ✓ | 0.17ms |
| bcftools | bcftools | bcftools view | ✓ | 0.22ms |
| bedtools | bedtools | bedtools Intersect intervals | ✓ | 0.51ms |
| gatk4 | gatk4 | gatk4 MergeMutectStats | ✓ | 0.11ms |
| seqkit | seqkit | seqkit | ✓ | 0.13ms |
| seqtk | seqtk | seqtk_comp | ✓ | 0.17ms |
| augustus | augustus | Augustus | ✓ | 0.10ms |
| maker | maker | Maker | ✓ | 0.12ms |
| prokka | prokka | Prokka | ✓ | 0.12ms |
| bakta | bakta | Bakta | ✓ | 0.07ms |
| mash | mash | MASH | ✓ | 0.23ms |
| mafft | mafft | MAFFT | ✓ | 0.23ms |
| muscle | muscle | MUSCLE | ✓ | 0.12ms |
| tabix | tabix | tabix | ✓ | 0.10ms |
| busco | busco | Busco | ✓ | 0.11ms |
| meme | meme | MEME | ✓ | 0.29ms |
| plink | plink | plink | ✓ | 0.21ms |
| minimap2 | minimap2 | Map with minimap2 | ✓ | 0.26ms |
| snpeff | snpeff | SnpEff | ✓ | 0.54ms |
| macs2 | macs2 | MACS2 | ✓ | 0.26ms |
| trinity | trinity | Trinity | ✓ | 0.46ms |
| emboss | emboss | EMBOSS: needle | ✓ | 0.42ms |
