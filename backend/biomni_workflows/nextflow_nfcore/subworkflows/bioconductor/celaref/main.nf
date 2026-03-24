#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: celaref
// After the clustering step of a single-cell RNAseq experiment, this package aims to suggest labels/ce
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/celaref/inst/doc/celaref_doco.R
// Upstream  : ExperimentHub, Matrix, tidyverse
// Downstream: none
//
// Install: BiocManager::install("celaref")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELAREF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-celaref"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-celaref:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-celaref:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_celaref_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_celaref_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_celaref_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(celaref)
    library(jsonlite)

    # --- load_se_from_files [] ---
    # Key functions: load_se_from_files
    library(celaref)
    counts_filepath.query    <- system.file("extdata", "sim_query_counts.tab",    package = "celaref")
    cell_info_filepath.query <- system.file("extdata", "sim_query_cell_info.tab", package = "celaref")
    # --- toy example1b [] ---
    # Key functions: make_ranking_violin_plot
    make_ranking_violin_plot(de_table.test=de_table.toy_query, de_table.ref=de_table.toy_ref)
    # --- toy example2 [] ---
    # Key functions: make_ref_similarity_names
    make_ref_similarity_names(de_table.toy_query, de_table.toy_ref)
    # --- toy example3 [] ---
    # Key functions: kable
    kable(make_ref_similarity_names(de_table.toy_query, de_table.toy_ref), digits=50)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_celaref_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_celaref_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_celaref_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELAREF:", paste0("    celaref: ", packageVersion("celaref"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_celaref_results.csv
    touch ${prefix}_celaref_output.rds
    echo "BIOC_CELAREF:" > versions.yml
    echo "    celaref: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELAREF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELAREF(ch_input)

    emit:
    results  = BIOC_CELAREF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELAREF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELAREF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELAREF.out.versions  // channel: path(versions.yml)
}
