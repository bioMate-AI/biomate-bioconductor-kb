#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tadar — dar_analysis_and_p_value_moderation
// Read genotype data from a VCF file, calculate Differential Allelic Representation (DAR) between experimental groups, assign DAR values to genomic features (gene
// Input: chr1.vcf.bgz, chr1_genes, chr1_tt
// Container: quay.io/biocontainers/bioconductor-tadar:1.8.0--r45hdfd78af_0
// R packages: limma, tadar, tidyverse
// Bioconductor: 3.20 | R: 4.4
// Requires: limma, tadar, tidyverse
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load genotype data from VCF using readGenotypes()
//  * 2. [Input & Preparation] Define sample groups and count alleles per group using countAlleles()
//  * 3. [Core Analysis] Filter out low-information loci using filterLoci()
//  * 4. [Core Analysis] Normalise allele counts to proportions using countsToProps()
//  * 5. [Input & Preparation] Define experimental contrasts and calculate DAR (origin and region-based) using dar()
//  * 6. [Core Analysis] Convert ranges to region-based intervals using flipRanges()
//  * 7. [Core Analysis] Assign DAR values to genomic features using assignFeatureDar()
//  * 8. [Core Analysis] Moderate DGE p-values using modP()
//  * 9. [Visualization & Output] Visualise DAR along chromosomes using plotChrDar() and plotDarECDF()

nextflow.enable.dsl = 2

process BIOC_TADAR_DAR_ANALYSIS_AND_P_VALUE_MODERATION {
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
    .bm_deps <- c("limma", "tadar", "tidyverse")
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
    library(tidyverse)
    library(limma)
    library(tadar)
    
    # Define input file paths in the working directory
    vcf_file <- "chr1.vcf.bgz"
    genes_file <- "chr1_genes"
    tt_file <- "chr1_tt"
    
    # Helper function to robustly load R objects (RDS or RData) from the working directory
    load_input_object <- function(base_name) {
      # Try reading as RDS directly
      if (file.exists(base_name)) {
        try_rds <- try(readRDS(base_name), silent = TRUE)
        if (!inherits(try_rds, "try-error")) return(try_rds)
        
        try_load <- try({
          env <- new.env()
          load(base_name, envir = env)
          vars <- ls(env)
          if (length(vars) > 0) env[[vars[1]]] else NULL
        }, silent = TRUE)
        if (!inherits(try_load, "try-error") && !is.null(try_load)) return(try_load)
      }
      
      # Try with .rds extension
      rds_path <- paste0(base_name, ".rds")
      if (file.exists(rds_path)) {
        return(readRDS(rds_path))
      }
      
      # Try with .RData extension
      rdata_path <- paste0(base_name, ".RData")
      if (file.exists(rdata_path)) {
        env <- new.env()
        load(rdata_path, envir = env)
        vars <- ls(env)
        if (length(vars) > 0) return(env[[vars[1]]])
      }
      
      stop(paste("Error: Could not find or load input file:", base_name))
    }
    
    # Load user inputs
    if (!file.exists(vcf_file)) {
      stop(paste("Error: VCF file not found in working directory:", vcf_file))
    }
    chr1_genes <- load_input_object(genes_file)
    chr1_tt <- load_input_object(tt_file)
    
    # 1. Load genotype data from VCF
    genotypes <- readGenotypes(file = vcf_file)
    
    # 2. Define sample groups and count alleles per group
    groups <- list(
        group1 = paste0("sample", 1:6),
        group2 = paste0("sample", 7:13)
    )
    
    counts <- countAlleles(genotypes = genotypes, groups = groups)
    
    # 3. Filter out low-information loci
    counts_filt <- filterLoci(counts = counts)
    
    counts_filt_2 <- filterLoci(counts = counts, filter = n_missing == 0)
    
    # 4. Normalise allele counts to proportions
    props <- countsToProps(counts = counts_filt)
    
    # 5. Define experimental contrasts and calculate DAR
    contrasts <- matrix(
        data = c(1, -1),
        dimnames = list(
            Levels = c("group1", "group2"),
            Contrasts = c("group1v2")
        )
    )
    
    contrasts <- makeContrasts(
        group1v2 = group1 - group2,
        levels = names(groups)
    )
    
    region_loci <- 5
    
    dar <- dar(props = props, contrasts = contrasts, region_loci = region_loci)
    
    # 6. Convert ranges to region-based intervals
    dar_regions <- flipRanges(dar = dar, extend_edges = TRUE)
    
    # Verify identical mapping
    identical(dar, flipRanges(dar_regions))
    
    # 7. Assign DAR values to genomic features
    gene_dar <- assignFeatureDar(
        dar = dar,
        features = chr1_genes,
        fill_missing = NA
    )
    
    gene_dar_regions <- assignFeatureDar(dar = dar_regions, features = chr1_genes)
    
    # 8. Moderate DGE p-values
    chr1_tt <- merge(chr1_tt, mcols(gene_dar\$group1v2), sort = FALSE)
    chr1_tt\$darP <- modP(chr1_tt\$PValue, chr1_tt\$dar)
    
    # 9. Visualise DAR along chromosomes
    set.seed(230822)
    foi <- sample(chr1_genes, 1)
    features <- sample(chr1_genes, 20)
    
    # Save chromosome DAR plot to PDF
    pdf("dar_plot_chr1.pdf", width = 10, height = 8)
    plotChrDar(
        dar = dar\$group1v2, dar_val = "region", chr = "1",
        foi = foi, foi_anno = "gene_name", foi_highlight = TRUE,
        features = features, features_anno = "gene_name", features_highlight = TRUE,
        title = "Example plot of DAR along Chromosome 1"
    )
    dev.off()
    
    # Simulate data for ECDF comparison as documented
    set.seed(230704)
    simulate_dar <- function(n, mean) {
        vapply(
            rnorm(n = n, mean = mean),
            function(x) exp(x) / (1 + exp(x)),
            numeric(1)
        )
    }
    gr <- GRanges(
        paste0(rep(seq(1,25), each = 100), ":", seq(1,100)),
        dar_origin = c(simulate_dar(2400, -2), simulate_dar(100, 0.5))
    )
    
    # Save ECDF plots to PDF
    p1 <- plotDarECDF(dar = gr, dar_val = "origin") +
        theme_bw()
    ggsave("dar_ecdf_plot1.pdf", plot = p1, width = 7, height = 5)
    
    p2 <- plotDarECDF(dar = gr, dar_val = "origin", highlight = "25") +
        scale_colour_manual(values = c("TRUE" = "red", "FALSE" = "grey")) +
        theme_bw()
    ggsave("dar_ecdf_plot2.pdf", plot = p2, width = 7, height = 5)
    
    # Save meaningful results to output files
    saveRDS(gene_dar, "gene_dar.rds")
    saveRDS(gene_dar_regions, "gene_dar_regions.rds")
    saveRDS(chr1_tt, "chr1_tt_moderated.rds")
    write.csv(as.data.frame(chr1_tt), "chr1_tt_moderated.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_TADAR_DAR_ANALYSIS_AND_P_VALUE_MODERATION":',
        paste0('    tadar: ', as.character(packageVersion('tadar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dar_analysis_and_p_value_moderation.csv versions.yml
    """
}

workflow BIOC_TADAR_DAR_ANALYSIS_AND_P_VALUE_MODERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chr1.vcf.bgz, chr1_genes, chr1_tt ] ]

    main:
    BIOC_TADAR_DAR_ANALYSIS_AND_P_VALUE_MODERATION(ch_input)

    emit:
    tables   = BIOC_TADAR_DAR_ANALYSIS_AND_P_VALUE_MODERATION.out.tables
    plots    = BIOC_TADAR_DAR_ANALYSIS_AND_P_VALUE_MODERATION.out.plots
    objects  = BIOC_TADAR_DAR_ANALYSIS_AND_P_VALUE_MODERATION.out.objects
    versions = BIOC_TADAR_DAR_ANALYSIS_AND_P_VALUE_MODERATION.out.versions
}
