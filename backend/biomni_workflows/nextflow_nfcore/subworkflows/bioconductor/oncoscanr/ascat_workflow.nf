#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: oncoscanR — ascat_workflow
// Load and analyze CNV data from an ASCAT output file to compute arm-level alterations and HRD/TDplus scores.
// Input: ascat_example.txt, oncoscan_na33.cov
// Container: quay.io/biocontainers/bioconductor-oncoscanr:1.12.0--r45hdfd78af_0
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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
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
