#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iBBiG — bicluster_comparison
// Compare iBBiG biclustering results against a gold standard or another clustering run using Jaccard Index distance and performance statistics.
// Input: res, binMat
// Container: quay.io/biocontainers/bioconductor-ibbig:1.54.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iBBiG
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate Jaccard Index distance between the clusters across rows, columns, or both
//  * 2. [Core Analysis] Extract detailed performance statistics (accuracy, sensitivity, specificity, PPV, NPV) comparing the results to the gold standard

nextflow.enable.dsl = 2

process BIOC_IBBIG_BICLUSTER_COMPARISON {
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
    .bm_deps <- c("iBBiG")
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
    library(iBBiG)
    
    # Read user inputs from the working directory
    res_file <- if (file.exists("res.rds")) "res.rds" else "res"
    binMat_file <- if (file.exists("binMat.rds")) "binMat.rds" else "binMat"
    
    if (!file.exists(res_file) || !file.exists(binMat_file)) {
      stop("Required input files ('res'/'res.rds' and 'binMat'/'binMat.rds') not found in the working directory.")
    }
    
    res <- readRDS(res_file)
    binMat <- readRDS(binMat_file)
    
    # Stage 1: Calculate Jaccard Index distance between the clusters across rows, columns, or both
    ji_default <- JIdist(res, binMat)
    write.csv(ji_default, file = "JIdist_default.csv", row.names = TRUE)
    
    ji_col_all <- JIdist(res, binMat, margin="col", best=FALSE)
    write.csv(ji_col_all, file = "JIdist_col_all.csv", row.names = TRUE)
    
    ji_col <- JIdist(res, binMat, margin="col")
    write.csv(ji_col, file = "JIdist_col.csv", row.names = TRUE)
    
    ji_row <- JIdist(res, binMat, margin="row")
    write.csv(ji_row, file = "JIdist_row.csv", row.names = TRUE)
    
    ji_both <- JIdist(res, binMat, margin="both")
    write.csv(ji_both, file = "JIdist_both.csv", row.names = TRUE)
    
    # Stage 2: Extract detailed performance statistics comparing the results to the gold standard
    # analyzeClust returns a list, so we bind it into a data.frame before writing to CSV
    ac_default <- analyzeClust(res, binMat)
    write.csv(do.call(rbind, ac_default), file = "analyzeClust_default.csv", row.names = TRUE)
    
    ac_col <- analyzeClust(res, binMat, margin="col")
    write.csv(do.call(rbind, ac_col), file = "analyzeClust_col.csv", row.names = TRUE)
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_IBBIG_BICLUSTER_COMPARISON":',
        paste0('    iBBiG: ', as.character(packageVersion('iBBiG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bicluster_comparison.csv versions.yml
    """
}

workflow BIOC_IBBIG_BICLUSTER_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ res, binMat ] ]

    main:
    BIOC_IBBIG_BICLUSTER_COMPARISON(ch_input)

    emit:
    tables   = BIOC_IBBIG_BICLUSTER_COMPARISON.out.tables
    plots    = BIOC_IBBIG_BICLUSTER_COMPARISON.out.plots
    objects  = BIOC_IBBIG_BICLUSTER_COMPARISON.out.objects
    versions = BIOC_IBBIG_BICLUSTER_COMPARISON.out.versions
}
