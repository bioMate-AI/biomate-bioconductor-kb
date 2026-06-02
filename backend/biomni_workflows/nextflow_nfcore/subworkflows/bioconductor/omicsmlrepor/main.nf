#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OmicsMLRepoR
// This package provides functions to browse the harmonized metadata for large omics databases. This pa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OmicsMLRepoR/inst/doc/Quickstart.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("OmicsMLRepoR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMICSMLREPOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omicsmlrepor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omicsmlrepor:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omicsmlrepor:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omicsmlrepor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omicsmlrepor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omicsmlrepor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OmicsMLRepoR)
    library(jsonlite)

    # --- tree_filter [] ---
    # Key functions: tree_filter, returnSamples, getLongMetaTb, getShortMetaTb
    cmd_sub <- tree_filter(cmd, target_condition, "Alzheimer's disease")
    tree_filter(col = "disease", "Type 2 Diabetes Mellitus") %>%
    filter(sex == "Female") %>%

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omicsmlrepor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omicsmlrepor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omicsmlrepor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMICSMLREPOR:", paste0("    omicsmlrepor: ", packageVersion("OmicsMLRepoR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omicsmlrepor_results.csv
    touch ${prefix}_omicsmlrepor_output.rds
    echo "BIOC_OMICSMLREPOR:" > versions.yml
    echo "    omicsmlrepor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMICSMLREPOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMICSMLREPOR(ch_input)

    emit:
    results  = BIOC_OMICSMLREPOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMICSMLREPOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMICSMLREPOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMICSMLREPOR.out.versions  // channel: path(versions.yml)
}
