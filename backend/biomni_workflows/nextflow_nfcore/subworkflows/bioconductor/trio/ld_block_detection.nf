#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: trio — ld_block_detection
// Compute pairwise linkage disequilibrium (LD) measures and identify LD blocks in genotype data.
// Input: genotype_matrix.txt
// Container: quay.io/biocontainers/bioconductor-trio:3.48.0--r45hdfd78af_0
// R packages: trio
// Bioconductor: 3.20 | R: 4.4
// Requires: trio
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute pairwise D' and r2 values using getLD
//  * 2. [Core Analysis] Estimate LD blocks using findLDblocks

nextflow.enable.dsl = 2

process BIOC_TRIO_LD_BLOCK_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("trio")
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
    
    # Load required library
    library(trio)
    
    # ----------------------------------------------------------------------
    # Stage 0: Read User Input
    # ----------------------------------------------------------------------
    input_file <- "genotype_matrix.txt"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Read the genotype matrix robustly
    df <- read.table(input_file, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
    
    # If the first column contains non-numeric identifiers (e.g., individual IDs),
    # use them as row names.
    if (!is.numeric(df[[1]])) {
      rownames(df) <- df[[1]]
      df <- df[-1]
    }
    
    LDdata <- as.matrix(df)
    
    # ----------------------------------------------------------------------
    # Stage 1: Compute pairwise D' and r2 values using getLD
    # ----------------------------------------------------------------------
    ld.out <- getLD(LDdata, asMatrix=TRUE)
    
    # ----------------------------------------------------------------------
    # Stage 2: Estimate LD blocks using findLDblocks
    # ----------------------------------------------------------------------
    blocks <- findLDblocks(LDdata)
    
    ld.out2 <- getLD(LDdata, addVarN=TRUE)
    
    blocks2 <- findLDblocks(ld.out2)
    
    # ----------------------------------------------------------------------
    # Stage 3: Save Outputs
    # ----------------------------------------------------------------------
    # Save LD matrices
    if (!is.null(ld.out\$Dprime)) {
      write.csv(ld.out\$Dprime, "ld_out_Dprime.csv", row.names = TRUE)
    }
    if (!is.null(ld.out\$rSquare)) {
      write.csv(ld.out\$rSquare, "ld_out_rSquare.csv", row.names = TRUE)
    }
    
    # Save block objects as RDS
    saveRDS(blocks, "blocks.rds")
    saveRDS(blocks2, "blocks2.rds")
    
    # Save block assignments as CSV
    if (!is.null(blocks\$blocks)) {
      blocks_df <- data.frame(SNP = names(blocks\$blocks), Block = blocks\$blocks)
      write.csv(blocks_df, "blocks_assignments.csv", row.names = FALSE)
    }
    if (!is.null(blocks2\$blocks)) {
      blocks2_df <- data.frame(SNP = names(blocks2\$blocks), Block = blocks2\$blocks)
      write.csv(blocks2_df, "blocks2_assignments.csv", row.names = FALSE)
    }
    
    # Optional: Plot LD blocks if plotting is supported for the block object
    tryCatch({
      pdf("ld_blocks_plot.pdf")
      plot(blocks)
      dev.off()
    }, error = function(e) {
      # Silently ignore if plotting is not supported or fails
    })
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_TRIO_LD_BLOCK_DETECTION":',
        paste0('    trio: ', as.character(packageVersion('trio')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ld_block_detection.csv versions.yml
    """
}

workflow BIOC_TRIO_LD_BLOCK_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genotype_matrix.txt ] ]

    main:
    BIOC_TRIO_LD_BLOCK_DETECTION(ch_input)

    emit:
    tables   = BIOC_TRIO_LD_BLOCK_DETECTION.out.tables
    plots    = BIOC_TRIO_LD_BLOCK_DETECTION.out.plots
    objects  = BIOC_TRIO_LD_BLOCK_DETECTION.out.objects
    versions = BIOC_TRIO_LD_BLOCK_DETECTION.out.versions
}
