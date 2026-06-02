#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cghMCR
// This package provides functions to identify genomic regions of interests based on segmented copy num
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cghMCR/inst/doc/findMCR.R
// Upstream  : limma
// Downstream: none
//
// Install: BiocManager::install("cghMCR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CGHMCR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cghmcr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cghmcr:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cghmcr:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cghmcr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cghmcr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cghmcr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cghMCR)
    library(CNSeg)
    library(MCR)
    library(SGOL)
    library(jsonlite)

    # --- MCR Initialization [] ---
    # Key functions: cghMCR
    cghmcr_obj <- cghMCR(segData, gapAllowed = 500,
                         alteredLow = 0.9, alteredHigh = 0.9,
                         recurrence = 100)


    # --- MCR Identification [] ---
    # Key functions: MCR
    mcrs <- MCR(cghmcr_obj)
    mcr_summary <- mcrs[, c("chromosome", "status", "mcr.start",
                            "mcr.end", "samples")]


    # --- MCR Probe Merging [] ---
    # Key functions: mergeMCRProbes
    mcrs_chr7 <- mcrs[mcrs[, "chromosome"] == "7", ]
    merged_probes <- mergeMCRProbes(mcrs_chr7,
                                    as.data.frame(segData[["data"]]))
    mcr_probes_summary <- merged_probes[, c("chromosome", "status",
                                            "mcr.start", "mcr.end",
                                            "probes")]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cghmcr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cghmcr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cghmcr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CGHMCR:", paste0("    cghmcr: ", packageVersion("cghMCR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cghmcr_results.csv
    touch ${prefix}_cghmcr_output.rds
    echo "BIOC_CGHMCR:" > versions.yml
    echo "    cghmcr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CGHMCR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CGHMCR(ch_input)

    emit:
    results  = BIOC_CGHMCR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CGHMCR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CGHMCR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CGHMCR.out.versions  // channel: path(versions.yml)
}
