---
name: bioconductor-cageminer
description: This package aims to integrate GWAS-derived SNPs and coexpression networks to mine candidate genes associated with a particular phenotype. For that, users must define a set of guide genes, which are known genes involved in the studied phenotype. Additionally, the mined candidates can be given a score that favor candidates that are hubs and/or transcription factors. The scores can then be used to rank and select the top n most promising genes for downstream experiments.
when_to_use: Use when: Mining high-confidence candidate genes with cageminer. Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# cageminer

## Workflows

### Standard Workflow

Integrate GWAS SNPs and coexpression networks to mine and score high-confidence candidate genes.

```r
library(cageminer)
library(GenomicRanges)

# 1. Visualize SNP distribution across chromosomes
plot_snp_distribution(snp_pos)
plot_snp_circos(chr_length, gene_ranges, snp_pos)

# 2. Identify genes close to SNPs
candidates1 <- mine_step1(gene_ranges, snp_pos)

# 3. Infer a gene coexpression network
sft <- BioNERO::SFT_fit(pepper_se, net_type = "signed", cor_method = "pearson")
gcn <- BioNERO::exp2gcn(pepper_se, net_type = "signed", cor_method = "pearson", 
                        module_merging_threshold = 0.8, SFTpower = sft$power)

# 4. Filter candidates in coexpression modules enriched in guide genes
candidates2 <- mine_step2(pepper_se, gcn = gcn, guides = guides$Gene, candidates = candidates1$ID)

# 5. Identify candidates with altered expression in a condition of interest
candidates3 <- mine_step3(pepper_se, candidates = candidates2$candidates, sample_group = "PRR_stress")

# Alternatively, perform steps 2-5 automatically using mine_candidates:
# candidates <- mine_candidates(gene_ranges = gene_ranges, marker_ranges = snp_pos, 
#                               exp = pepper_se, gcn = gcn, guides = guides$Gene, 
#                               sample_group = "PRR_stress")

# 6. Score and prioritize candidates
hubs <- BioNERO::get_hubs_gcn(pepper_se, gcn)
scored <- score_genes(candidates3, hubs$Gene, tfs$Gene_ID)
```
*Note: Inputs are GRanges of SNP and gene coordinates, a SummarizedExperiment of expression data, and a vector of guide genes; output is a ranked data frame of scored candidate genes.*

## When to Use
- To integrate GWAS-derived SNPs with transcriptomic coexpression networks to prioritize candidate genes.
- To identify genes physically close to SNPs using `mine_step1`.
- To find coexpression modules enriched in known guide genes using `mine_step2`.
- To score and rank candidate genes based on their correlation with a condition, hub status, and transcription factor annotation using `score_genes`.

## When NOT to Use
- When you do not have a set of known "guide genes" associated with the phenotype of interest, as `mine_step2` relies on guide gene enrichment.
- When you only have SNP data without matching transcriptomic data.

## Data Requirements
- Gene coordinates and SNP positions stored as `GRanges` or `GRangesList` (for multiple traits) objects.
- Expression data stored as a `SummarizedExperiment` object.
- Guide genes and transcription factors provided as character vectors of gene IDs.

## Key Parameters
- **gene_ranges**: A `GRanges` object containing gene coordinates.
- **snp_pos** / **marker_ranges**: A `GRanges` or `GRangesList` object containing SNP positions.
- **expand_intervals** (TRUE): Logical indicating whether to expand SNP coordinates upstream and downstream.
- **net_type** ("signed"): Network type for GCN inference in `BioNERO::SFT_fit`.
- **cor_method** ("pearson"): Correlation method for GCN inference.
- **sample_group**: The condition of interest in the sample metadata (e.g., "PRR_stress").

## Best Practices
- Use `plot_snp_distribution` and `plot_snp_circos` to visually inspect SNP distributions across chromosomes before running the mining pipeline.
- Use `simulate_windows` to evaluate different sliding window sizes for selecting putative candidates in `mine_step1`.
- Ensure that the same gene IDs are used across the gene ranges, expression data, guide genes, and transcription factor lists.

## Common Pitfalls
- No candidates found in Step 2: Ensure the guide genes are present in the expression dataset and that the coexpression network has well-defined modules.
- Mismatched gene IDs: Verify that gene IDs in `gene_ranges`, `pepper_se`, and `guides` use the exact same nomenclature.

## Alternatives
- `BioNERO` for general gene coexpression network analysis.
- `rtracklayer` for importing genomic coordinates from GFF/GTF files.

## Citations
- Almeida-Silva, F., & Venancio, T. M. (2022). cageminer: an R/Bioconductor package to prioritize candidate genes by integrating genome-wide association studies and gene coexpression networks. in silico Plants, 4(2), diac018.

## References
- Homepage: bioconductor.org/packages/cageminer
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/cageminer/inst/doc/cageminer.html
