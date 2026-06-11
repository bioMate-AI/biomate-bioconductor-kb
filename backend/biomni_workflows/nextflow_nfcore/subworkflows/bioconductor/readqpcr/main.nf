#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ReadqPCR — roche_lc480_loading
// Read raw fluorescence data from Roche LightCycler 480 and merge with sample information.
// Input: LC480_Example.txt, LC480_Example_SampleInfo.txt
// Container: quay.io/biocontainers/bioconductor-readqpcr:1.56.0--r45hdfd78af_0
// R packages: ReadqPCR
// Bioconductor: 3.20 | R: 4.4
// Requires: ReadqPCR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read raw LC480 text file using read.LC480 to create a CyclesSet object
//  * 2. [Input & Preparation] Read additional sample information using read.LC480SampleInfo to create an AnnotatedDataFrame
//  * 3. [Core Analysis] Merge the fluorescence data and sample information using merge

nextflow.enable.dsl = 2

process BIOC_READQPCR_ROCHE_LC480_LOADING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("ReadqPCR")
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
    library(ReadqPCR)
    
    # Define input file paths (must be in the working directory)
    LC480.example <- "LC480_Example.txt"
    LC480.SamInfo <- "LC480_Example_SampleInfo.txt"
    
    # Verify input file existence
    if (!file.exists(LC480.example)) {
      stop("Required input file 'LC480_Example.txt' is missing from the working directory.")
    }
    if (!file.exists(LC480.SamInfo)) {
      stop("Required input file 'LC480_Example_SampleInfo.txt' is missing from the working directory.")
    }
    
    # 1. Read the LC480 files using read.LC480 and read.LC480SampleInfo, then merge
    cycData <- read.LC480(file = LC480.example)
    samInfo <- read.LC480SampleInfo(file = LC480.SamInfo)
    cycData1 <- merge(cycData, samInfo)
    
    # Extract meaningful results
    expression_matrix <- exprs(cycData1)
    well_order_matrix <- tryCatch(exprs.well.order(cycData1), error = function(e) NULL)
    pheno_data <- pData(cycData1)
    
    # Write named output files for the results
    write.csv(expression_matrix, "expression_matrix.csv", row.names = TRUE)
    if (!is.null(well_order_matrix)) {
      write.csv(well_order_matrix, "well_order_matrix.csv", row.names = TRUE)
    }
    write.csv(pheno_data, "pheno_data.csv", row.names = TRUE)
    saveRDS(cycData1, "cycData1.rds")

    writeLines(c(
        '"BIOC_READQPCR_ROCHE_LC480_LOADING":',
        paste0('    ReadqPCR: ', as.character(packageVersion('ReadqPCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_roche_lc480_loading.csv versions.yml
    """
}

workflow BIOC_READQPCR_ROCHE_LC480_LOADING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ LC480_Example.txt, LC480_Example_SampleInfo.txt ] ]

    main:
    BIOC_READQPCR_ROCHE_LC480_LOADING(ch_input)

    emit:
    tables   = BIOC_READQPCR_ROCHE_LC480_LOADING.out.tables
    plots    = BIOC_READQPCR_ROCHE_LC480_LOADING.out.plots
    objects  = BIOC_READQPCR_ROCHE_LC480_LOADING.out.objects
    versions = BIOC_READQPCR_ROCHE_LC480_LOADING.out.versions
}
