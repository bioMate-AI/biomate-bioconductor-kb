#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MCbiclust — scoring_independent_samples
// Score samples in a dataset based on a known bicluster pattern using PointScore.
// Input: CCLE.mito, CCLE.hicor.genes, CCLE.groups
// Container: quay.io/biocontainers/bioconductor-mcbiclust:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MCbiclust
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify the locations of the two differently regulated gene groups
//  * 2. [Core Analysis] Calculate PointScore using PointScoreCalc

nextflow.enable.dsl = 2

process BIOC_MCBICLUST_SCORING_INDEPENDENT_SAMPLES {
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
    .bm_deps <- c("MCbiclust")
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
    library(MCbiclust)
    
    # Helper function to robustly read user input files from the working directory
    read_input <- function(filename, expected_type = "auto") {
      extensions <- c("", ".rds", ".csv", ".txt")
      found_file <- NULL
      for (ext in extensions) {
        test_path <- paste0(filename, ext)
        if (file.exists(test_path)) {
          found_file <- test_path
          break
        }
      }
      
      if (is.null(found_file)) {
        stop(paste("Error: Required input file", filename, "not found in the working directory."))
      }
      
      message("Reading input file: ", found_file)
      
      # If it is an RDS file, read it directly
      if (grepl("\\\\.rds\$", found_file, ignore.case = TRUE)) {
        return(readRDS(found_file))
      }
      
      # Fallback parsing based on expected type
      if (expected_type == "matrix") {
        df <- read.csv(found_file, row.names = 1, check.names = FALSE)
        return(as.matrix(df))
      } else if (expected_type == "vector") {
        lines <- readLines(found_file)
        num_lines <- suppressWarnings(as.numeric(lines))
        if (!any(is.na(num_lines))) {
          return(num_lines)
        }
        return(lines)
      } else if (expected_type == "list") {
        tryCatch({
          return(readRDS(found_file))
        }, error = function(e) {
          df <- read.csv(found_file, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
          lst <- lapply(df, function(x) x[!is.na(x) & x != ""])
          return(lst)
        })
      }
      
      # Default fallback
      tryCatch(readRDS(found_file), error = function(e) {
        tryCatch(as.matrix(read.csv(found_file, row.names = 1, check.names = FALSE)), error = function(e2) {
          readLines(found_file)
        })
      })
    }
    
    # 1. Read the user input files
    CCLE.mito <- read_input("CCLE.mito", "matrix")
    CCLE.hicor.genes <- read_input("CCLE.hicor.genes", "vector")
    CCLE.groups <- read_input("CCLE.groups", "list")
    
    # Ensure CCLE.hicor.genes is numeric if it represents indices
    if (is.character(CCLE.hicor.genes)) {
      num_val <- suppressWarnings(as.numeric(CCLE.hicor.genes))
      if (!any(is.na(num_val))) {
        CCLE.hicor.genes <- num_val
      }
    }
    
    # 2. Identify the locations of the two differently regulated gene groups
    gene.loc1 <- which(row.names(CCLE.mito[CCLE.hicor.genes,]) %in% CCLE.groups[[1]])
    gene.loc2 <- which(row.names(CCLE.mito[CCLE.hicor.genes,]) %in% CCLE.groups[[2]])
    
    # 3. Calculate PointScore using PointScoreCalc
    CCLE.ps <- PointScoreCalc(CCLE.mito[CCLE.hicor.genes,], gene.loc1, gene.loc2)
    
    # 4. Save the meaningful results
    output_df <- data.frame(
      Sample = names(CCLE.ps),
      PointScore = CCLE.ps,
      stringsAsFactors = FALSE
    )
    
    write.csv(output_df, "CCLE_pointscore.csv", row.names = FALSE)
    saveRDS(CCLE.ps, "CCLE_pointscore.rds")
    
    message("Workflow completed successfully. Outputs saved to 'CCLE_pointscore.csv' and 'CCLE_pointscore.rds'.")

    writeLines(c(
        '"BIOC_MCBICLUST_SCORING_INDEPENDENT_SAMPLES":',
        paste0('    MCbiclust: ', as.character(packageVersion('MCbiclust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scoring_independent_samples.csv versions.yml
    """
}

workflow BIOC_MCBICLUST_SCORING_INDEPENDENT_SAMPLES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CCLE.mito, CCLE.hicor.genes, CCLE.groups ] ]

    main:
    BIOC_MCBICLUST_SCORING_INDEPENDENT_SAMPLES(ch_input)

    emit:
    tables   = BIOC_MCBICLUST_SCORING_INDEPENDENT_SAMPLES.out.tables
    plots    = BIOC_MCBICLUST_SCORING_INDEPENDENT_SAMPLES.out.plots
    objects  = BIOC_MCBICLUST_SCORING_INDEPENDENT_SAMPLES.out.objects
    versions = BIOC_MCBICLUST_SCORING_INDEPENDENT_SAMPLES.out.versions
}
