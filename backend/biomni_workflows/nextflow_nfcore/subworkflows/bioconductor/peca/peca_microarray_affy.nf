#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PECA — peca_microarray_affy
// Identify differential gene expression from Affymetrix microarray probe-level data.
// Input: SpikeIn133
// Container: quay.io/biocontainers/bioconductor-peca:1.42.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PECA, affy
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Subset or prepare the AffyBatch object
//  * 2. [Core Analysis] Run PECA on the AffyBatch object using PECA_AffyBatch

nextflow.enable.dsl = 2

process BIOC_PECA_PECA_MICROARRAY_AFFY {
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
    .bm_deps <- c("PECA", "affy")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(PECA)
    library(affy)
    
    # Read the user input file 'SpikeIn133' from the working directory.
    # We handle cases where it might be saved as an RDS or RData file, with or without extension.
    input_path <- "SpikeIn133"
    if (file.exists(input_path)) {
      SpikeIn133 <- tryCatch({
        readRDS(input_path)
      }, error = function(e) {
        env <- new.env()
        load(input_path, envir = env)
        if (exists("SpikeIn133", envir = env)) {
          get("SpikeIn133", envir = env)
        } else {
          get(ls(env)[1], envir = env)
        }
      })
    } else if (file.exists("SpikeIn133.rds")) {
      SpikeIn133 <- readRDS("SpikeIn133.rds")
    } else if (file.exists("SpikeIn133.RData")) {
      env <- new.env()
      load("SpikeIn133.RData", envir = env)
      if (exists("SpikeIn133", envir = env)) {
        SpikeIn133 <- env\$SpikeIn133
      } else {
        SpikeIn133 <- env[[ls(env)[1]]]
      }
    } else {
      stop("Required input file 'SpikeIn133' not found in the working directory.")
    }
    
    # 1. Subset or prepare the AffyBatch object
    data <- SpikeIn133[,c(1,15,29,2,16,30)]
    
    # 2. Run PECA on the AffyBatch object using PECA_AffyBatch
    results <- PECA_AffyBatch(normalize="true", affy=data)
    
    # Write meaningful results to output files
    write.csv(results, file = "peca_results.csv", row.names = TRUE)
    saveRDS(results, file = "peca_results.rds")

    writeLines(c(
        '"BIOC_PECA_PECA_MICROARRAY_AFFY":',
        paste0('    PECA: ', as.character(packageVersion('PECA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peca_microarray_affy.csv versions.yml
    """
}

workflow BIOC_PECA_PECA_MICROARRAY_AFFY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SpikeIn133 ] ]

    main:
    BIOC_PECA_PECA_MICROARRAY_AFFY(ch_input)

    emit:
    tables   = BIOC_PECA_PECA_MICROARRAY_AFFY.out.tables
    plots    = BIOC_PECA_PECA_MICROARRAY_AFFY.out.plots
    objects  = BIOC_PECA_PECA_MICROARRAY_AFFY.out.objects
    versions = BIOC_PECA_PECA_MICROARRAY_AFFY.out.versions
}
