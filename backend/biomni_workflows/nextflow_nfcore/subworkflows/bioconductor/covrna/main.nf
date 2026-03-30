#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: covRNA
// This package provides the analysis methods fourthcorner and RLQ analysis for large-scale transcripto
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/covRNA/inst/doc/covRNA.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("covRNA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COVRNA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-covrna"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-covrna:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-covrna:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_covrna_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_covrna_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_covrna_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(covRNA)
    library(jsonlite)

    # --- Stat [] ---
    # Key functions: stat, exprs, fData, pData
    ---------------------------------------------------------------------
    statBaca <- stat(ExprSet = Baca, npermut = 999, padjust = "BH", nrcor = 2, exprvar = 1)
    # or
    statBaca <- stat(L = exprs(Baca), R = fData(Baca), Q = pData(Baca), npermut = 999,
                     padjust = "BH", nrcor = 2, exprvar = 1)
    # --- Ord [] ---
    # Key functions: ord
    ---------------------------------------------------------------------
    ordBaca <- ord(Baca)
    # --- Vis [] ---
    # Key functions: vis
    ---------------------------------------------------------------------
    vis(Stat = statBaca, Ord = ordBaca, rangex=1.5, rangey=1.5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_covrna_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_covrna_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_covrna_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COVRNA:", paste0("    covrna: ", packageVersion("covRNA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_covrna_results.csv
    touch ${prefix}_covrna_output.rds
    echo "BIOC_COVRNA:" > versions.yml
    echo "    covrna: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COVRNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COVRNA(ch_input)

    emit:
    results  = BIOC_COVRNA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COVRNA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COVRNA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COVRNA.out.versions  // channel: path(versions.yml)
}
