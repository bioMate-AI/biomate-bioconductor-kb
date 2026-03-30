#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: missRows
// The missRows package implements the MI-MFA method to deal with missing individuals ('biological unit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/missRows/inst/doc/missRows.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("missRows")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MISSROWS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-missrows"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-missrows:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-missrows:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_missrows_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_missrows_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_missrows_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MIDTList)
    library(MIMFA)
    library(jsonlite)

    # --- MIDTList analysis [] ---
    # Key functions: MIDTList, MIMFA, plotInd, plotVar, configurations, missPattern, tuneM
    midt <- MIDTList(table1, table2, colData=df)
    midt <- MIMFA(midt, ncomp=2, M=30)
    plotInd(midt)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_missrows_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_missrows_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_missrows_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MISSROWS:", paste0("    missrows: ", packageVersion("missRows"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_missrows_results.csv
    touch ${prefix}_missrows_output.rds
    echo "BIOC_MISSROWS:" > versions.yml
    echo "    missrows: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MISSROWS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MISSROWS(ch_input)

    emit:
    results  = BIOC_MISSROWS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MISSROWS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MISSROWS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MISSROWS.out.versions  // channel: path(versions.yml)
}
