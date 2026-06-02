#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: seqArchR
// seqArchR enables unsupervised discovery of _de novo_ clusters with characteristic sequence architect
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/seqArchR/inst/doc/seqArchR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("seqArchR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQARCHR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqarchr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqarchr:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seqarchr:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqarchr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqarchr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqarchr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(seqArchR)
    library(jsonlite)

    # --- Configuration Setup [] ---
    # Key functions: set_config
    seqArchRconfig <- seqArchR::set_config(
      parallelize = FALSE, n_cores = 1, n_runs = 10,
      k_min = 1, k_max = 5, mod_sel_type = "stability",
      bound = 10^-6, chunk_size = 100,
      result_aggl = "ward.D", result_dist = "euclid",
      flags = list(debug = FALSE, time = TRUE,
                   verbose = TRUE, plot = FALSE)
    )


    # --- Sequence Architecture Discovery [] ---
    # Key functions: seqArchR
    seqArchRresult <- readRDS(system.file(
      "extdata", "example_seqArchRresult.rds",
      package = "seqArchR", mustWork = TRUE
    ))


    # --- Feature Extraction and Visualization [] ---
    # Key functions: get_clBasVec_m, viz_bas_vec
    seqArchRresult <- readRDS(system.file(
      "extdata", "example_seqArchRresult.rds",
      package = "seqArchR", mustWork = TRUE
    ))
    i2_bv <- seqArchR::get_clBasVec_m(seqArchRresult, iter = 2)
    seqArchR::viz_bas_vec(
      feat_mat = i2_bv, ptype = c("heatmap", "seqlogo"),
      method = "bits", sinuc_or_dinuc = "dinuc"
    )


    # --- Sequence Clustering Visualization [] ---
    # Key functions: viz_seqs_acgt_mat, seqs_str
    seqArchRresult <- readRDS(system.file(
      "extdata", "example_seqArchRresult.rds",
      package = "seqArchR", mustWork = TRUE
    ))
    positions <- seq(1, 100)
    seqArchR::viz_seqs_acgt_mat(
      seqArchR::seqs_str(seqArchRresult, iter = 2, ord = TRUE),
      pos_lab = positions
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqarchr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqarchr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqarchr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQARCHR:", paste0("    seqarchr: ", packageVersion("seqArchR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqarchr_results.csv
    touch ${prefix}_seqarchr_output.rds
    echo "BIOC_SEQARCHR:" > versions.yml
    echo "    seqarchr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQARCHR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQARCHR(ch_input)

    emit:
    results  = BIOC_SEQARCHR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQARCHR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQARCHR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQARCHR.out.versions  // channel: path(versions.yml)
}
