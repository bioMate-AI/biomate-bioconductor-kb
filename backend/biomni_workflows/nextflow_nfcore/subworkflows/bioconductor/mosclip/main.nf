#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MOSClip
// Topological pathway analysis tool able to integrate multi-omics data. It finds survival-associated m
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MOSClip/inst/doc/mosclip_vignette.R
// Upstream  : MultiAssayExperiment, kableExtra
// Downstream: none
//
// Install: BiocManager::install("MOSClip")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOSCLIP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mosclip"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mosclip:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mosclip:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mosclip_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mosclip_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mosclip_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MOSClip)
    library(jsonlite)

    # --- Availableomicmethods [] ---
    # Key functions: availableOmicMethods
    ---------------------------------------------------------------------
    availableOmicMethods()
    # --- Multipathwaymodulereport [] ---
    # Key functions: multiPathwayModuleReport
    ---------------------------------------------------------------------
    moduleSummary <- multiPathwayModuleReport(moduleSurv)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mosclip_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mosclip_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mosclip_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOSCLIP:", paste0("    mosclip: ", packageVersion("MOSClip"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mosclip_results.csv
    touch ${prefix}_mosclip_output.rds
    echo "BIOC_MOSCLIP:" > versions.yml
    echo "    mosclip: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOSCLIP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOSCLIP(ch_input)

    emit:
    results  = BIOC_MOSCLIP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOSCLIP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOSCLIP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOSCLIP.out.versions  // channel: path(versions.yml)
}
