#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FitHiC
// Fit-Hi-C is a tool for assigning statistical confidence estimates to intra-chromosomal contact maps 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FitHiC/inst/doc/fithic.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("FitHiC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FITHIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fithic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fithic:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fithic:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fithic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fithic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fithic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FitHiC)
    library(jsonlite)

    # --- Table formatting and display [] ---
    # Key functions: FitHiC, kable
    library("FitHiC")
    fragsfile <- system.file("extdata", "fragmentLists/Duan_yeast_EcoRI.gz",
    intersfile <- system.file("extdata", "contactCounts/Duan_yeast_EcoRI.gz",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fithic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fithic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fithic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FITHIC:", paste0("    fithic: ", packageVersion("FitHiC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fithic_results.csv
    touch ${prefix}_fithic_output.rds
    echo "BIOC_FITHIC:" > versions.yml
    echo "    fithic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FITHIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FITHIC(ch_input)

    emit:
    results  = BIOC_FITHIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FITHIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FITHIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FITHIC.out.versions  // channel: path(versions.yml)
}
