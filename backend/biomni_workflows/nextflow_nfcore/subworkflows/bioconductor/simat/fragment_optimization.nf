#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SIMAT — fragment_optimization
// Optimize the selection of target fragments using a background library to avoid overlapping peaks prior to conducting a SIM experiment.
// Input: Library, target.table
// Container: quay.io/biocontainers/bioconductor-simat:1.42.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SIMAT
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the target table and background library
//  * 2. [Core Analysis] Run the fragment optimization algorithm using optFrag to select the best fragments for the targets of interest

nextflow.enable.dsl = 2

process BIOC_SIMAT_FRAGMENT_OPTIMIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("SIMAT")
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
    library(SIMAT)
    
    # 1. Load the target table and background library from user input files
    if (file.exists("Library.rds")) {
      Library <- readRDS("Library.rds")
    } else if (file.exists("Library")) {
      Library <- readRDS("Library")
    } else {
      stop("Error: Background library file ('Library' or 'Library.rds') not found in the working directory.")
    }
    
    if (file.exists("target.table.rds")) {
      target.table <- readRDS("target.table.rds")
    } else if (file.exists("target.table")) {
      target.table <- readRDS("target.table")
    } else {
      stop("Error: Target table file ('target.table' or 'target.table.rds') not found in the working directory.")
    }
    
    # 2. Run the fragment optimization algorithm using optFrag to select the best fragments
    optTargets <- optFrag(Library = Library, target.table = target.table, forceOpt = TRUE)
    
    # 3. Save the results
    # Save the complete optimized targets object as RDS
    saveRDS(optTargets, "optTargets.rds")
    
    # Create a summary data frame for CSV export
    opt_df <- data.frame(
      compound = if (!is.null(optTargets\$compound)) optTargets\$compound else seq_along(optTargets\$ms),
      stringsAsFactors = FALSE
    )
    
    if (!is.null(optTargets\$rt)) {
      opt_df\$rt <- optTargets\$rt
    }
    if (!is.null(optTargets\$ri)) {
      opt_df\$ri <- optTargets\$ri
    }
    if (!is.null(optTargets\$ms)) {
      opt_df\$ms <- sapply(optTargets\$ms, paste, collapse = ",")
    }
    if (!is.null(optTargets\$sp)) {
      opt_df\$sp <- sapply(optTargets\$sp, paste, collapse = ",")
    }
    
    write.csv(opt_df, "optimized_targets.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SIMAT_FRAGMENT_OPTIMIZATION":',
        paste0('    SIMAT: ', as.character(packageVersion('SIMAT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fragment_optimization.csv versions.yml
    """
}

workflow BIOC_SIMAT_FRAGMENT_OPTIMIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Library, target.table ] ]

    main:
    BIOC_SIMAT_FRAGMENT_OPTIMIZATION(ch_input)

    emit:
    tables   = BIOC_SIMAT_FRAGMENT_OPTIMIZATION.out.tables
    plots    = BIOC_SIMAT_FRAGMENT_OPTIMIZATION.out.plots
    objects  = BIOC_SIMAT_FRAGMENT_OPTIMIZATION.out.objects
    versions = BIOC_SIMAT_FRAGMENT_OPTIMIZATION.out.versions
}
