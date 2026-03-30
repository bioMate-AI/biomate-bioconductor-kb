#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hiReadsProcessor
// hiReadsProcessor contains set of functions which allow users to process LM-PCR products sequenced us
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hiReadsProcessor/inst/doc/Tutorial.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("hiReadsProcessor")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HIREADSPROCESSOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hireadsprocessor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hireadsprocessor:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hireadsprocessor:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hireadsprocessor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hireadsprocessor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hireadsprocessor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SeqFolder)
    library(jsonlite)

    # --- Seqfolder [] ---
    # Key functions: SeqFolder
    ---------------------------------------------------------------------
    seqProps <- read.SeqFolder(runData, seqfilePattern = ".+fna.gz$")
    seqProps
    # --- Findbarcodes [] ---
    # Key functions: findBarcodes
    ---------------------------------------------------------------------
    seqProps <- findBarcodes(seqProps, sector = "all", showStats = TRUE)
    seqProps
    seqProps$sectors
    # --- Load [] ---
    # Key functions: path
    ---------------------------------------------------------------------
    load(file.path(system.file("data", package = "hiReadsProcessor"),
                   "FLX_seqProps.RData"))
    # --- Samplesummary [] ---
    # Key functions: sampleSummary
    ---------------------------------------------------------------------
    sampleSummary(seqProps)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hireadsprocessor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hireadsprocessor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hireadsprocessor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HIREADSPROCESSOR:", paste0("    hireadsprocessor: ", packageVersion("hiReadsProcessor"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hireadsprocessor_results.csv
    touch ${prefix}_hireadsprocessor_output.rds
    echo "BIOC_HIREADSPROCESSOR:" > versions.yml
    echo "    hireadsprocessor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HIREADSPROCESSOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HIREADSPROCESSOR(ch_input)

    emit:
    results  = BIOC_HIREADSPROCESSOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HIREADSPROCESSOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HIREADSPROCESSOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HIREADSPROCESSOR.out.versions  // channel: path(versions.yml)
}
