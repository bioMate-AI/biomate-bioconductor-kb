#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: openCyto
// This package is designed to facilitate the automated gating methods in sequential way to mimic the m
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/openCyto/inst/doc/HowToWriteCSVTemplate.R
// Upstream  : CytoML, flowWorkspace, flowWorkspaceData, ggcyto
// Downstream: none
//
// Install: BiocManager::install("openCyto")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPENCYTO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-opencyto"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-opencyto:2.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-opencyto:2.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_opencyto_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_opencyto_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_opencyto_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(openCyto)
    library(jsonlite)

    # --- A+/ [] ---
    # Key functions: copy
    this_row <- copy(template_row)
    kable(this_row[, 1:6, with = F])
    # --- A+/ [] ---
    # Key functions: kable
    kable(openCyto:::.preprocess_row(this_row)[, 1:6, with = F])
    # --- A+B+(before) [] ---
    # Key functions: copy
    this_row <- copy(template_row)
    kable(this_row[, 1:6, with = F])
    # --- A+B+(after) [] ---
    # Key functions: kable
    kable(openCyto:::.preprocess_row(this_row)[, 1:6, with = F])
    # --- A+/ [] ---
    # Key functions: copy
    this_row <- copy(template_row)
    kable(this_row[, 1:6, with = F])
    # --- A+/ [] ---
    # Key functions: kable
    kable(openCyto:::.preprocess_row(this_row)[, 1:6, with = F])
    # --- multiPop(before) [] ---
    # Key functions: copy
    this_row <- copy(template_row)
    kable(this_row[, 1:6, with = F])
    # --- multiPop(after) [] ---
    # Key functions: kable
    kable(openCyto:::.preprocess_row(this_row)[, 1:6, with = F])
    # --- multiPop noExpand(before) [] ---
    # Key functions: kable
    kable(this_row[, 1:6, with = F])
    # --- kable [] ---
    # Key functions: kable
    kable(this_row[, 1:6, with = F])
    # --- multiple parents expand [] ---
    # Key functions: kable
    kable(openCyto:::.split_multi_parents(this_row)[, 1:6, with = F])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_opencyto_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_opencyto_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_opencyto_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OPENCYTO:", paste0("    opencyto: ", packageVersion("openCyto"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_opencyto_results.csv
    touch ${prefix}_opencyto_output.rds
    echo "BIOC_OPENCYTO:" > versions.yml
    echo "    opencyto: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OPENCYTO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OPENCYTO(ch_input)

    emit:
    results  = BIOC_OPENCYTO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OPENCYTO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OPENCYTO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OPENCYTO.out.versions  // channel: path(versions.yml)
}
