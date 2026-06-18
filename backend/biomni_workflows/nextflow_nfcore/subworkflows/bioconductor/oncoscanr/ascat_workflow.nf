#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: oncoscanR — ascat_workflow
// Load and analyze CNV data from an ASCAT output file to compute arm-level alterations and HRD/TDplus scores.
// Input: ascat_example.txt, oncoscan_na33.cov
// Container: quay.io/biocontainers/bioconductor-oncoscanr:1.12.0--r45hdfd78af_0
// R packages: GenomicRanges, jsonlite, oncoscanR
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, jsonlite, oncoscanR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load ASCAT file using load_ascat
//  * 2. [Core Analysis] Run the integrated workflow using workflow_oncoscan.ascat

nextflow.enable.dsl = 2

process BIOC_ONCOSCANR_ASCAT_WORKFLOW {
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
    .bm_deps <- c("GenomicRanges", "jsonlite", "oncoscanR")
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
    library(oncoscanR)
    library(jsonlite)
    library(GenomicRanges)
    
    # Load the kit coverage annotation object from the working directory
    # Supports both RDS and RData formats
    oncoscan_na33.cov <- tryCatch({
      readRDS("oncoscan_na33.cov")
    }, error = function(e) {
      env <- new.env()
      load("oncoscan_na33.cov", envir = env)
      env[[names(env)[1]]]
    })
    
    # 1. Load ASCAT file using load_ascat
    ascat.fn <- "ascat_example.txt"
    ascat.segments <- load_ascat(ascat.fn, oncoscan_na33.cov)
    
    # Save the loaded segments to output files
    saveRDS(ascat.segments, "ascat_segments.rds")
    write.csv(as.data.frame(ascat.segments), "ascat_segments.csv", row.names = FALSE)
    
    # 2. Run the integrated workflow using workflow_oncoscan.ascat
    segs.filename <- "ascat_example.txt"
    dat <- workflow_oncoscan.ascat(segs.filename)
    
    # Convert to JSON and write to output file
    json_output <- toJSON(dat, auto_unbox = TRUE, pretty = TRUE)
    writeLines(json_output, "ascat_workflow_output.json")
    
    # Save the workflow output list as an RDS object
    saveRDS(dat, "ascat_workflow_output.rds")

    writeLines(c(
        '"BIOC_ONCOSCANR_ASCAT_WORKFLOW":',
        paste0('    oncoscanR: ', as.character(packageVersion('oncoscanR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ascat_workflow.csv versions.yml
    """
}

workflow BIOC_ONCOSCANR_ASCAT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ascat_example.txt, oncoscan_na33.cov ] ]

    main:
    BIOC_ONCOSCANR_ASCAT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_ONCOSCANR_ASCAT_WORKFLOW.out.tables
    plots    = BIOC_ONCOSCANR_ASCAT_WORKFLOW.out.plots
    objects  = BIOC_ONCOSCANR_ASCAT_WORKFLOW.out.objects
    versions = BIOC_ONCOSCANR_ASCAT_WORKFLOW.out.versions
}
