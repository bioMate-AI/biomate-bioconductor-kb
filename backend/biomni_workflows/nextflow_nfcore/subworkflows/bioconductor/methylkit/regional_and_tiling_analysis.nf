#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylKit — regional_and_tiling_analysis
// Summarize and analyze methylation levels over tiling windows or predefined genomic regions (e.g., promoters).
// Input: file.list, gene.obj$promoters
// Container: quay.io/biocontainers/bioconductor-methylkit:1.36.0--r45ha27e39d_0
// R packages: GenomicRanges, methylKit
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, methylKit
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read methylation call files with a relaxed coverage threshold
//  * 2. [Visualization & Output] Summarize counts over tiling windows
//  * 3. [Visualization & Output] Summarize counts over predefined genomic regions (promoters)

nextflow.enable.dsl = 2

process BIOC_METHYLKIT_REGIONAL_AND_TILING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "methylKit")
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
    library(methylKit)
    library(GenomicRanges)
    
    # 1. Read the user input files from the working directory
    if (file.exists("file.list.rds")) {
      file.list <- readRDS("file.list.rds")
    } else if (file.exists("file.list")) {
      file.list <- as.list(readLines("file.list"))
    } else {
      stop("Error: 'file.list' or 'file.list.rds' not found in the working directory.")
    }
    
    # Ensure file.list is a list of character paths
    file.list <- as.list(as.character(unlist(file.list)))
    
    if (file.exists("gene.obj.rds")) {
      gene.obj <- readRDS("gene.obj.rds")
    } else if (file.exists("promoters.rds")) {
      gene.obj <- list(promoters = readRDS("promoters.rds"))
    } else {
      stop("Error: 'gene.obj.rds' or 'promoters.rds' not found in the working directory.")
    }
    
    # Dynamically generate sample.id and treatment vectors based on the number of input files
    n_files <- length(file.list)
    n_test <- ceiling(n_files / 2)
    n_ctrl <- floor(n_files / 2)
    
    sample_ids <- as.list(c(paste0("test", seq_len(n_test)), if(n_ctrl > 0) paste0("ctrl", seq_len(n_ctrl)) else NULL))
    treatment_vec <- c(rep(1, n_test), rep(0, n_ctrl))
    
    # 2. Reconstruct the standard myobj with default/high coverage threshold (needed for regionCounts)
    myobj = methRead(file.list,
               sample.id=sample_ids,
               assembly="hg18",
               treatment=treatment_vec,
               context="CpG",
               mincov = 10
               )
    
    # 3. Execute the documented workflow steps exactly as specified
    myobj_lowCov = methRead(file.list,
               sample.id=sample_ids,
               assembly="hg18",
               treatment=treatment_vec,
               context="CpG",
               mincov = 3
               )
    
    tiles = tileMethylCounts(myobj_lowCov,win.size=1000,step.size=1000,cov.bases = 10)
    
    promoters = regionCounts(myobj,gene.obj\$promoters)
    
    # 4. Write named output files for the meaningful results
    saveRDS(tiles, "tiles.rds")
    saveRDS(promoters, "promoters.rds")
    
    # Export data frames of the summarized counts for the first sample as CSVs
    if (length(tiles) > 0) {
      write.csv(as.data.frame(tiles[[1]]), "tiles_sample1.csv", row.names = FALSE)
    }
    if (length(promoters) > 0) {
      write.csv(as.data.frame(promoters[[1]]), "promoters_sample1.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_METHYLKIT_REGIONAL_AND_TILING_ANALYSIS":',
        paste0('    methylKit: ', as.character(packageVersion('methylKit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regional_and_tiling_analysis.csv versions.yml
    """
}

workflow BIOC_METHYLKIT_REGIONAL_AND_TILING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.list, gene.obj$promoters ] ]

    main:
    BIOC_METHYLKIT_REGIONAL_AND_TILING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHYLKIT_REGIONAL_AND_TILING_ANALYSIS.out.tables
    plots    = BIOC_METHYLKIT_REGIONAL_AND_TILING_ANALYSIS.out.plots
    objects  = BIOC_METHYLKIT_REGIONAL_AND_TILING_ANALYSIS.out.objects
    versions = BIOC_METHYLKIT_REGIONAL_AND_TILING_ANALYSIS.out.versions
}
