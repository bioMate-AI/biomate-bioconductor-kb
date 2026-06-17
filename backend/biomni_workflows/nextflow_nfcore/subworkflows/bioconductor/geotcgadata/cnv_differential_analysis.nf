#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeoTcgaData — cnv_differential_analysis
// Identify genes with differential copy number variations between groups.
// Input: aa, sampleGroup
// Container: quay.io/biocontainers/bioconductor-geotcgadata:2.10.0--r45hdfd78af_0
// R packages: GeoTcgaData
// Bioconductor: 3.20 | R: 4.4
// Requires: GeoTcgaData
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare the copy number score matrix and sample groups
//  * 2. [Core Analysis] Run differential_CNV to extract differential CNV genes

nextflow.enable.dsl = 2

process BIOC_GEOTCGADATA_CNV_DIFFERENTIAL_ANALYSIS {
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
    .bm_deps <- c("GeoTcgaData")
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
    
    # Load required library
    library(GeoTcgaData)
    
    # 1. Prepare the copy number score matrix and sample groups
    # Read 'aa' (matrix of gene-level copy number scores)
    if (file.exists("aa.rds")) {
      aa <- readRDS("aa.rds")
    } else if (file.exists("aa.csv")) {
      aa <- as.matrix(read.csv("aa.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("aa.tsv")) {
      aa <- as.matrix(read.delim("aa.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("aa")) {
      aa <- tryCatch({
        as.matrix(read.csv("aa", row.names = 1, check.names = FALSE))
      }, error = function(e) {
        readRDS("aa")
      })
    } else {
      stop("Error: Required input file 'aa' (matrix of gene-level copy number scores) not found in the working directory.")
    }
    
    # Read 'sampleGroup' (vector of sample group assignments)
    if (file.exists("sampleGroup.rds")) {
      sampleGroup <- readRDS("sampleGroup.rds")
    } else if (file.exists("sampleGroup.csv")) {
      sg_df <- read.csv("sampleGroup.csv", header = FALSE, stringsAsFactors = FALSE)
      if (ncol(sg_df) == 1) {
        sampleGroup <- sg_df[[1]]
      } else {
        sampleGroup <- sg_df[[2]]
        names(sampleGroup) <- sg_df[[1]]
      }
    } else if (file.exists("sampleGroup.txt")) {
      sampleGroup <- readLines("sampleGroup.txt")
    } else if (file.exists("sampleGroup")) {
      sampleGroup <- tryCatch({
        readLines("sampleGroup")
      }, error = function(e) {
        readRDS("sampleGroup")
      })
    } else {
      stop("Error: Required input file 'sampleGroup' (vector of sample group assignments) not found in the working directory.")
    }
    
    # Ensure aa is a matrix
    if (!is.matrix(aa)) {
      aa <- as.matrix(aa)
    }
    
    # Ensure sampleGroup is a vector
    if (is.list(sampleGroup) || is.data.frame(sampleGroup)) {
      sampleGroup <- unlist(sampleGroup)
    }
    sampleGroup <- as.character(sampleGroup)
    
    # 2. Run differential_CNV to extract differential CNV genes
    diffCnv <- differential_CNV(aa, sampleGroup)
    
    # Write outputs
    write.csv(as.data.frame(diffCnv), "diffCnv_results.csv", row.names = TRUE)
    saveRDS(diffCnv, "diffCnv_results.rds")

    writeLines(c(
        '"BIOC_GEOTCGADATA_CNV_DIFFERENTIAL_ANALYSIS":',
        paste0('    GeoTcgaData: ', as.character(packageVersion('GeoTcgaData')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnv_differential_analysis.csv versions.yml
    """
}

workflow BIOC_GEOTCGADATA_CNV_DIFFERENTIAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ aa, sampleGroup ] ]

    main:
    BIOC_GEOTCGADATA_CNV_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GEOTCGADATA_CNV_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = BIOC_GEOTCGADATA_CNV_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = BIOC_GEOTCGADATA_CNV_DIFFERENTIAL_ANALYSIS.out.objects
    versions = BIOC_GEOTCGADATA_CNV_DIFFERENTIAL_ANALYSIS.out.versions
}
