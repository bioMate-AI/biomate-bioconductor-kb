#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fastseg — vector_matrix_segmentation
// Segment raw numeric vectors or matrices without genomic coordinate metadata.
// Input: data2
// Container: quay.io/biocontainers/bioconductor-fastseg:1.56.0--r45ha27e39d_0
// R packages: fastseg
// Bioconductor: 3.20 | R: 4.4
// Requires: fastseg
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load fastseg package
//  * 2. [Core Analysis] Run segmentation on a vector or matrix using fastseg

nextflow.enable.dsl = 2

process BIOC_FASTSEG_VECTOR_MATRIX_SEGMENTATION {
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
    .bm_deps <- c("fastseg")
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
        
        # 1. Load fastseg package
        library(fastseg)
        
        # 2. Read user input 'data2' from the working directory
        # We support RDS, CSV, TSV, or TXT formats.
        if (file.exists("data2.rds")) {
          data <- readRDS("data2.rds")
        } else if (file.exists("data2.csv")) {
          data <- read.csv("data2.csv", header = TRUE, check.names = FALSE)
        } else if (file.exists("data2.tsv")) {
          data <- read.delim("data2.tsv", header = TRUE, check.names = FALSE)
        } else if (file.exists("data2.txt")) {
          data <- read.table("data2.txt", header = TRUE, check.names = FALSE)
        } else if (file.exists("data2")) {
          data <- tryCatch({
            readRDS("data2")
          }, error = function(e) {
            tryCatch({
              read.csv("data2", header = TRUE, check.names = FALSE)
            }, error = function(e2) {
              read.table("data2", header = TRUE)
            })
          })
        } else {
          stop("Required input file 'data2' (RDS, CSV, TSV, or TXT) not found in the working directory.")
        }
        
        # Ensure 'data' is strictly numeric to prevent character matrix conversion
        if (is.data.frame(data)) {
          data <- as.matrix(data[, sapply(data, is.numeric), drop = FALSE])
        } else if (is.matrix(data)) {
          if (!is.numeric(data)) {
            mode(data) <- "numeric"
          }
        } else if (is.vector(data)) {
          data <- as.numeric(data)
        }
        
        # --- Documented Workflow: Segmentation ---
        # Pass the parsed input directly to fastseg
        res <- fastseg(data)
        print("Segmentation head:")
        print(head(res))
        
        # Save segmentation results
        saveRDS(res, "segmentation_results.rds")
        write.csv(as.data.frame(res), "segmentation_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_FASTSEG_VECTOR_MATRIX_SEGMENTATION":',
        paste0('    fastseg: ', as.character(packageVersion('fastseg')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vector_matrix_segmentation.csv versions.yml
    """
}

workflow BIOC_FASTSEG_VECTOR_MATRIX_SEGMENTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data2 ] ]

    main:
    BIOC_FASTSEG_VECTOR_MATRIX_SEGMENTATION(ch_input)

    emit:
    tables   = BIOC_FASTSEG_VECTOR_MATRIX_SEGMENTATION.out.tables
    plots    = BIOC_FASTSEG_VECTOR_MATRIX_SEGMENTATION.out.plots
    objects  = BIOC_FASTSEG_VECTOR_MATRIX_SEGMENTATION.out.objects
    versions = BIOC_FASTSEG_VECTOR_MATRIX_SEGMENTATION.out.versions
}
