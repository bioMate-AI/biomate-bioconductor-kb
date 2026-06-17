#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mslp — mslp_consensus_pipeline
// Predict consensus synthetic lethality partners (SLPs) by integrating patient genomic/transcriptomic data and cell line genetic screen data.
// Input: data_mutations_extended.txt, data_CNA.txt, data_RNA_Seq_v2_expression_median.txt, data_RNA_Seq_v2_mRNA_median_Zscores.txt, screen_hit, mut_info
// Container: quay.io/biocontainers/bioconductor-mslp:1.12.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: data.table, doFuture, future, magrittr, mslp
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess patient multi-omics data using pp_tcga
//  * 2. [Core Analysis] Call compensation-based SLPs using comp_slp
//  * 3. [Core Analysis] Call correlation-based SLPs using corr_slp
//  * 4. [Core Analysis] Estimate the importance threshold for correlation SLPs using est_im
//  * 5. [Core Analysis] Merge compensation and correlation SLP results using merge_slp
//  * 6. [Core Analysis] Identify screen-supported SLPs in cell lines using scr_slp
//  * 7. [Core Analysis] Calculate consensus SLPs across cell lines using cons_slp

nextflow.enable.dsl = 2

process BIOC_MSLP_MSLP_CONSENSUS_PIPELINE {
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
    .bm_deps <- c("future", "doFuture", "magrittr", "mslp", "data.table")
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
    
    library(future)
    library(doFuture)
    library(magrittr)
    library(mslp)
    library(data.table)
    
    # 1. Preprocess patient multi-omics data using pp_tcga
    P_mut  <- "data_mutations_extended.txt"
    P_cna  <- "data_CNA.txt"
    P_expr <- "data_RNA_Seq_v2_expression_median.txt"
    P_z    <- "data_RNA_Seq_v2_mRNA_median_Zscores.txt"
    
    res <- pp_tcga(P_mut, P_cna, P_expr, P_z)
    
    # Map preprocessed outputs to the variables expected by downstream functions
    example_z        <- res\$zscore_data
    example_expr     <- res\$expr_data
    example_comp_mut <- res\$mut_data
    example_corr_mut <- res\$mut_data
    
    # Read cell line genetic screen and mutation data from user input files
    read_user_file <- function(base_name) {
      possible_files <- c(base_name, paste0(base_name, ".txt"), paste0(base_name, ".csv"), paste0(base_name, ".tsv"))
      for (f in possible_files) {
        if (file.exists(f)) {
          return(fread(f))
        }
      }
      stop(paste("Required user input file not found:", base_name))
    }
    
    screen_hit <- read_user_file("screen_hit")
    mut_info   <- read_user_file("mut_info")
    
    # 2. Call compensation-based SLPs using comp_slp
    plan(multisession, workers = 2)
    res_comp <- comp_slp(example_z, example_comp_mut)
    saveRDS(res_comp, file = "compSLP_res.rds")
    plan(sequential)
    
    # 3. Call correlation-based SLPs using corr_slp
    plan(multisession, workers = 2)
    res_corr <- corr_slp(example_expr, example_corr_mut)
    saveRDS(res_corr, "corrSLP_res.rds")
    
    im_thresh <- 0.0016
    res_f     <- res_corr[im >= im_thresh]
    plan(sequential)
    
    # 4. Estimate the importance threshold for correlation SLPs using est_im
    plan(multisession, workers = 2)
    common_genes <- intersect(example_corr_mut\$mut_entrez, rownames(example_expr))
    if (length(common_genes) == 0) {
      stop("No common genes found between mutation data and expression matrix.")
    }
    mutgene    <- sample(common_genes, min(5, length(common_genes)))
    nperm      <- 3
    res_random <- lapply(seq_len(nperm), function(x) corr_slp(example_expr, example_corr_mut, mutgene = mutgene))
    im_res     <- est_im(res_random)
    res_f_2    <- res_corr[im >= mean(im_res\$roc_thresh)]
    plan(sequential)
    
    # 5. Merge compensation and correlation SLP results using merge_slp
    plan(multisession, workers = 2)
    res_comp   <- readRDS("compSLP_res.rds")
    res_corr   <- readRDS("corrSLP_res.rds")
    merged_res <- merge_slp(res_comp, res_corr)
    
    # 6. Identify screen-supported SLPs in cell lines using scr_slp
    # Dynamically identify cell lines present in the user's screen and mutation data
    cell_lines <- intersect(unique(screen_hit\$cell_line), unique(mut_info\$cell_line))
    if (length(cell_lines) == 0) {
      cell_lines <- unique(mut_info\$cell_line)
    }
    
    scr_res <- lapply(cell_lines, scr_slp, screen_hit, mut_info, merged_res)
    scr_res[lengths(scr_res) == 0] <- NULL
    scr_res <- rbindlist(scr_res)
    
    # 7. Calculate consensus SLPs across cell lines using cons_slp
    k_res   <- cons_slp(scr_res, merged_res)
    k_res_f <- k_res[kappa_value >= 0.6 & padj <= 0.1]
    plan(sequential)
    
    # Save meaningful results to output files
    fwrite(merged_res, "merged_res.csv")
    fwrite(res_f, "res_f.csv")
    fwrite(res_f_2, "res_f_2.csv")
    fwrite(scr_res, "scr_res.csv")
    fwrite(k_res, "k_res.csv")
    fwrite(k_res_f, "k_res_f.csv")

    writeLines(c(
        '"BIOC_MSLP_MSLP_CONSENSUS_PIPELINE":',
        paste0('    mslp: ', as.character(packageVersion('mslp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mslp_consensus_pipeline.csv versions.yml
    """
}

workflow BIOC_MSLP_MSLP_CONSENSUS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data_mutations_extended.txt, data_CNA.txt, data_RNA_Seq_v2_expression_median.txt, data_RNA_Seq_v2_mRNA_median_Zscores.txt, screen_hit, mut_info ] ]

    main:
    BIOC_MSLP_MSLP_CONSENSUS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MSLP_MSLP_CONSENSUS_PIPELINE.out.tables
    plots    = BIOC_MSLP_MSLP_CONSENSUS_PIPELINE.out.plots
    objects  = BIOC_MSLP_MSLP_CONSENSUS_PIPELINE.out.objects
    versions = BIOC_MSLP_MSLP_CONSENSUS_PIPELINE.out.versions
}
