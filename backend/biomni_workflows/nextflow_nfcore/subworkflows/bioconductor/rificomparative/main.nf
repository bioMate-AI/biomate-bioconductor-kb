#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rifiComparative
// 'rifiComparative' is a continuation of rifi package. It compares two conditions output of rifi using
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rifiComparative/inst/doc/rifiComparative.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("rifiComparative")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIFICOMPARATIVE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rificomparative"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rificomparative:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rificomparative:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rificomparative_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rificomparative_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rificomparative_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rifiComparative)
    library(jsonlite)

    # --- Penalty Estimation and Fragmentation [] ---
    # Key functions: penalties, fragment_HL, fragment_inty
    pen_list <- penalties(df_comb)
    penalties_df <- pen_list[[1]]
    pen_HL <- pen_list[[2]]
    pen_int <- pen_list[[3]]
    penalties_df <- fragment_HL(
        probe = penalties_df,
        cores = 2,
        pen = pen_HL[[1]][[9]],
        pen_out = pen_HL[[1]][[10]]
    )
    fragment_int <- fragment_inty(
        probe = penalties_df,
        cores = 2,
        pen = pen_int[[1]][[9]],
        pen_out = pen_int[[1]][[10]]
    )


    # --- Comparative Statistics and Annotation [] ---
    # Key functions: statistics, adjusting_HLToInt, gff3_preprocess
    stats_res <- statistics(data = fragment_int)
    stats_df_comb <- stats_res[[1]]
    data(annot_g)
    df_adjusted <- adjusting_HLToInt(
        data = stats_df_comb,
        annotation = annot_g[[1]]
    )
    gff_path <- system.file("extdata", "gff_synechocystis_6803.gff.gz",
                            package = "rifiComparative")
    gff_preprocessed <- gff3_preprocess(path = gzfile(gff_path))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rificomparative_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rificomparative_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rificomparative_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RIFICOMPARATIVE:", paste0("    rificomparative: ", packageVersion("rifiComparative"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rificomparative_results.csv
    touch ${prefix}_rificomparative_output.rds
    echo "BIOC_RIFICOMPARATIVE:" > versions.yml
    echo "    rificomparative: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RIFICOMPARATIVE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RIFICOMPARATIVE(ch_input)

    emit:
    results  = BIOC_RIFICOMPARATIVE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RIFICOMPARATIVE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RIFICOMPARATIVE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RIFICOMPARATIVE.out.versions  // channel: path(versions.yml)
}
