#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: seqArchRplus
// seqArchRplus facilitates downstream analyses of promoter sequence architectures/clusters identified 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/seqArchRplus/inst/doc/seqArchRplus.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("seqArchRplus")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQARCHRPLUS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqarchrplus"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqarchrplus:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seqarchrplus:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqarchrplus_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqarchrplus_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqarchrplus_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(seqArchRplus)
    library(jsonlite)

    # --- Cluster Reassignment and Refinement [] ---
    # Key functions: curate_clusters
    seqArchR_curated_clusts <- curate_clusters(
        sname = "RAL28_10_to_12h",
        use_aggl = "complete",
        use_dist = "euclid",
        seqArchR_result = seqArchR_result,
        iter = 5,
        regularize = TRUE,
        topn = 50,
        use_cutk = 5,
        need_change = list(c(2)),
        change_to = list(c(1)),
        final = FALSE,
        dir_path = NULL
    )


    # --- Final Cluster Curation [] ---
    # Key functions: curate_clusters
    seqArchR_curated_clusts <- curate_clusters(
        sname = "RAL28_10_to_12h",
        use_aggl = "complete",
        use_dist = "euclid",
        seqArchR_result = seqArchR_result,
        iter = 5,
        pos_lab = NULL,
        regularize = FALSE,
        topn = 50,
        use_cutk = 5,
        need_change = list(c(2)),
        change_to = list(c(1)),
        final = TRUE,
        dir_path = NULL
    )


    # --- Sequence Logo Generation [] ---
    # Key functions: per_cluster_seqlogos
    seqlogos_oneplot_pl <- per_cluster_seqlogos(
        sname = "RAL28_10_to_12h",
        seqs = raw_seqs,
        clusts = unord_clusts,
        pos_lab = -45:45,
        bits_yax = "auto",
        strand_sep = FALSE,
        one_plot = TRUE,
        txt_size = 12,
        dir_path = NULL
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqarchrplus_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqarchrplus_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqarchrplus_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQARCHRPLUS:", paste0("    seqarchrplus: ", packageVersion("seqArchRplus"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqarchrplus_results.csv
    touch ${prefix}_seqarchrplus_output.rds
    echo "BIOC_SEQARCHRPLUS:" > versions.yml
    echo "    seqarchrplus: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQARCHRPLUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQARCHRPLUS(ch_input)

    emit:
    results  = BIOC_SEQARCHRPLUS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQARCHRPLUS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQARCHRPLUS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQARCHRPLUS.out.versions  // channel: path(versions.yml)
}
