#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSALightning — paired_gsa
// Perform permutation-based gene set analysis on paired two-sample expression data.
// Input: expression_matrix.csv, paired_design.csv, gene_sets.gmt
// Container: quay.io/biocontainers/bioconductor-gsalightning:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSALightning
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the paired class vector using positive and negative integers to represent pairs and conditions
//  * 2. [Core Analysis] Run GSALight with tests set to 'paired'

nextflow.enable.dsl = 2

process BIOC_GSALIGHTNING_PAIRED_GSA {
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
    .bm_deps <- c("GSALightning")
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
    library(GSALightning)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    
    # Read expression matrix (genes as rows, samples as columns)
    expression <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    
    # Remove genes with zero sample variance to avoid errors in GSALight()
    expression <- expression[apply(expression, 1, sd) != 0, , drop = FALSE]
    
    # Read paired design metadata
    design <- read.csv("paired_design.csv", stringsAsFactors = FALSE)
    
    # Ensure design metadata is aligned with the columns of the expression matrix
    design <- design[match(colnames(expression), design\$sample_id), ]
    
    # Define the paired class vector using positive and negative integers
    # to represent pairs and conditions.
    if ("fac" %in% colnames(design)) {
      fac <- as.integer(design\$fac)
    } else {
      # Fallback: auto-detect pair and condition columns
      pair_col <- grep("pair", colnames(design), ignore.case = TRUE, value = TRUE)[1]
      cond_col <- grep("cond|sign|direction|treat", colnames(design), ignore.case = TRUE, value = TRUE)[1]
      
      if (is.na(pair_col)) pair_col <- colnames(design)[2]
      if (is.na(cond_col)) cond_col <- colnames(design)[3]
      
      pairs <- as.integer(design[[pair_col]])
      conds <- as.character(design[[cond_col]])
      
      # Map the two unique conditions to 1 and -1
      unique_conds <- unique(conds)
      cond_sign <- ifelse(conds == unique_conds[1], 1, -1)
      fac <- pairs * cond_sign
    }
    
    # Read gene sets from GMT file
    read_gmt <- function(gmt_file) {
      lines <- readLines(gmt_file)
      gsets <- list()
      for (line in lines) {
        parts <- strsplit(line, "\t")[[1]]
        if (length(parts) >= 3) {
          genes <- parts[3:length(parts)]
          genes <- genes[genes != "" & !is.na(genes)]
          gsets[[parts[1]]] <- genes
        }
      }
      return(gsets)
    }
    targetGenes <- read_gmt("gene_sets.gmt")
    
    # -----------------------------------------------------------------------------
    # 2. Run GSALight with tests set to 'paired'
    # -----------------------------------------------------------------------------
    
    GSALightResultsPaired <- GSALight(
      eset = expression, 
      fac = fac, 
      gs = targetGenes, 
      nperm = 1000, 
      tests = 'paired', 
      method = 'maxmean', 
      restandardize = TRUE, 
      minsize = 10, 
      rmGSGenes = 'gene', 
      verbose = FALSE
    )
    
    # -----------------------------------------------------------------------------
    # 3. Write Outputs
    # -----------------------------------------------------------------------------
    
    # Save results table as CSV
    write.csv(GSALightResultsPaired, "GSALightResultsPaired.csv", row.names = TRUE)
    
    # Save results object as RDS
    saveRDS(GSALightResultsPaired, "GSALightResultsPaired.rds")
    
    # Generate and save diagnostic p-value histogram plot
    pdf("p_value_histogram.pdf", width = 7, height = 5)
    col_name <- "p-value:up-regulated in positives"
    if (col_name %in% colnames(GSALightResultsPaired)) {
      hist(
        GSALightResultsPaired[, col_name],
        main = "P-value Distribution (Up-regulated in Positives)",
        xlab = "p-value",
        col = "skyblue",
        breaks = 20
      )
    } else {
      hist(
        GSALightResultsPaired[, 1],
        main = "P-value Distribution",
        xlab = "p-value",
        col = "skyblue",
        breaks = 20
      )
    }
    dev.off()

    writeLines(c(
        '"BIOC_GSALIGHTNING_PAIRED_GSA":',
        paste0('    GSALightning: ', as.character(packageVersion('GSALightning')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paired_gsa.csv versions.yml
    """
}

workflow BIOC_GSALIGHTNING_PAIRED_GSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, paired_design.csv, gene_sets.gmt ] ]

    main:
    BIOC_GSALIGHTNING_PAIRED_GSA(ch_input)

    emit:
    tables   = BIOC_GSALIGHTNING_PAIRED_GSA.out.tables
    plots    = BIOC_GSALIGHTNING_PAIRED_GSA.out.plots
    objects  = BIOC_GSALIGHTNING_PAIRED_GSA.out.objects
    versions = BIOC_GSALIGHTNING_PAIRED_GSA.out.versions
}
