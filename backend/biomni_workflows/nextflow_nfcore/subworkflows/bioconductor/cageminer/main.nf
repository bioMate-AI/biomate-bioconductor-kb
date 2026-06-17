#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cageminer — candidate_gene_mining_and_prioritization
// Integrate GWAS SNPs and coexpression networks to mine and score high-confidence candidate genes.
// Input: gene_ranges.gr, snp_pos.gr, pepper_se.rds, guides.tsv, tfs.tsv
// Container: quay.io/biocontainers/bioconductor-cageminer:1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BioNERO, GenomicRanges, IRanges, SummarizedExperiment, cageminer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Visualize SNP distribution across chromosomes using plot_snp_distribution and plot_snp_circos
//  * 2. [Core Analysis] Identify genes close to SNPs using mine_step1
//  * 3. [Core Analysis] Infer a gene coexpression network using BioNERO::SFT_fit and BioNERO::exp2gcn
//  * 4. [Core Analysis] Filter candidates in coexpression modules enriched in guide genes using mine_step2
//  * 5. [Core Analysis] Identify candidates with altered expression in a condition of interest using mine_step3 (or perform steps 2-5 automatically using 
//  * 6. [Core Analysis] Score and prioritize candidates using score_genes

nextflow.enable.dsl = 2

process BIOC_CAGEMINER_CANDIDATE_GENE_MINING_AND_PRIORITIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("cageminer", "BioNERO", "GenomicRanges")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(cageminer)
    library(BioNERO)
    library(GenomicRanges)
    
    # Set seed for reproducibility
    set.seed(123)
    
    # ----------------------------------------------------------------------
    # Stage 0: Read User Input Files
    # ----------------------------------------------------------------------
    
    # Read GRanges of gene coordinates
    gene_ranges <- readRDS("gene_ranges.gr")
    
    # Read GRanges of SNP positions
    snp_pos <- readRDS("snp_pos.gr")
    
    # Read SummarizedExperiment of RNA-seq expression data
    pepper_se <- readRDS("pepper_se.rds")
    
    # Read Table of guide genes
    guides <- read.table("guides.tsv", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # Read Table of transcription factors
    tfs <- read.table("tfs.tsv", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # Dynamically construct chr_length from gene_ranges and snp_pos to avoid hardcoding
    all_chrs <- unique(c(as.character(seqnames(gene_ranges)), as.character(seqnames(snp_pos))))
    chr_ends <- sapply(all_chrs, function(chr) {
      max_gene <- if(any(seqnames(gene_ranges) == chr)) max(end(gene_ranges[seqnames(gene_ranges) == chr])) else 0
      max_snp <- if(any(seqnames(snp_pos) == chr)) max(end(snp_pos[seqnames(snp_pos) == chr])) else 0
      max(max_gene, max_snp, 1000000) # Default to at least 1MB if empty
    })
    chr_length <- GenomicRanges::GRanges(
      seqnames = all_chrs,
      ranges = IRanges::IRanges(start = 1, end = chr_ends)
    )
    
    # ----------------------------------------------------------------------
    # Stage 1: Visualize SNP distribution across chromosomes
    # ----------------------------------------------------------------------
    
    pdf("snp_distribution.pdf", width = 8, height = 6)
    plot_snp_distribution(snp_pos)
    dev.off()
    
    pdf("snp_circos.pdf", width = 7, height = 7)
    plot_snp_circos(chr_length, gene_ranges, snp_pos)
    dev.off()
    
    # ----------------------------------------------------------------------
    # Stage 2: Identify genes close to SNPs (Step 1)
    # ----------------------------------------------------------------------
    
    candidates1 <- mine_step1(gene_ranges, snp_pos)
    
    # Save Step 1 candidates
    write.csv(as.data.frame(candidates1), "candidates_step1.csv", row.names = FALSE)
    
    pdf("window_simulation.pdf", width = 8, height = 6)
    simulate_windows(gene_ranges, snp_pos)
    dev.off()
    
    # ----------------------------------------------------------------------
    # Stage 3: Infer a gene coexpression network using BioNERO
    # ----------------------------------------------------------------------
    
    sft <- BioNERO::SFT_fit(pepper_se, net_type = "signed", cor_method = "pearson")
    
    # Robustness check: if SFT power estimation fails, default to a standard power of 12
    if (is.null(sft\$power) || is.na(sft\$power)) {
      sft\$power <- 12
    }
    
    gcn <- BioNERO::exp2gcn(pepper_se, net_type = "signed", cor_method = "pearson", 
                            module_merging_threshold = 0.8, SFTpower = sft\$power)
    
    # Save GCN object
    saveRDS(gcn, "gcn.rds")
    
    # ----------------------------------------------------------------------
    # Stage 4: Filter candidates in coexpression modules (Step 2)
    # ----------------------------------------------------------------------
    
    candidates2 <- mine_step2(pepper_se, gcn = gcn, guides = guides\$Gene, candidates = candidates1\$ID)
    
    # Save Step 2 candidates and enrichment results
    write.table(candidates2\$candidates, "candidates_step2_list.txt", row.names = FALSE, col.names = FALSE, quote = FALSE)
    write.csv(candidates2\$enrichment, "candidates_step2_enrichment.csv", row.names = FALSE)
    
    # ----------------------------------------------------------------------
    # Stage 5: Identify candidates with altered expression (Step 3)
    # ----------------------------------------------------------------------
    
    candidates3 <- mine_step3(pepper_se, candidates = candidates2\$candidates, sample_group = "PRR_stress")
    
    # Save Step 3 candidates
    write.csv(candidates3, "candidates_step3.csv", row.names = FALSE)
    
    # Perform steps 2-5 automatically using mine_candidates
    candidates <- mine_candidates(gene_ranges = gene_ranges, marker_ranges = snp_pos, 
                                  exp = pepper_se, gcn = gcn, guides = guides\$Gene, 
                                  sample_group = "PRR_stress")
    
    # Save automatically mined candidates
    write.csv(candidates, "candidates_automatic.csv", row.names = FALSE)
    
    # ----------------------------------------------------------------------
    # Stage 6: Score and prioritize candidates
    # ----------------------------------------------------------------------
    
    hubs <- BioNERO::get_hubs_gcn(pepper_se, gcn)
    write.csv(hubs, "gcn_hubs.csv", row.names = FALSE)
    
    scored <- score_genes(candidates, hubs\$Gene, tfs\$Gene_ID)
    
    # Save final prioritized and scored candidates
    write.csv(scored, "prioritized_candidates.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_CAGEMINER_CANDIDATE_GENE_MINING_AND_PRIORITIZATION":',
        paste0('    cageminer: ', as.character(packageVersion('cageminer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_candidate_gene_mining_and_prioritization.csv versions.yml
    """
}

workflow BIOC_CAGEMINER_CANDIDATE_GENE_MINING_AND_PRIORITIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_ranges.gr, snp_pos.gr, pepper_se.rds, guides.tsv, tfs.tsv ] ]

    main:
    BIOC_CAGEMINER_CANDIDATE_GENE_MINING_AND_PRIORITIZATION(ch_input)

    emit:
    tables   = BIOC_CAGEMINER_CANDIDATE_GENE_MINING_AND_PRIORITIZATION.out.tables
    plots    = BIOC_CAGEMINER_CANDIDATE_GENE_MINING_AND_PRIORITIZATION.out.plots
    objects  = BIOC_CAGEMINER_CANDIDATE_GENE_MINING_AND_PRIORITIZATION.out.objects
    versions = BIOC_CAGEMINER_CANDIDATE_GENE_MINING_AND_PRIORITIZATION.out.versions
}
