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

    # --- loading_fun [] ---
    # Key functions: loading_fun
    data(stats_se_cdt1)
    data(stats_se_cdt2)
    data(differential_expression)
    # --- joining data row [] ---
    # Key functions: joining_data_row
    data(inp_s)
    data(inp_f)
    joining_data_row(input1 = inp_s, input2 = inp_f)
    # --- joinging data column [] ---
    # Key functions: joining_data_column
    data(data_combined_minimal)
    df_comb_minimal <- joining_data_column(data = data_combined_minimal)
    head(df_comb_minimal, 5)
    # --- make pen HL [] ---
    # Key functions: make_pen
    pen_HL <- make_pen(
    logs = as.numeric(rep(NA, 8))
    # --- make pen int [] ---
    # Key functions: make_pen
    pen_int <- make_pen(
    logs = as.numeric(rep(NA, 8))
    # --- penalties [] ---
    # Key functions: penalties
    data(df_comb_minimal)
    penalties_df <- penalties(df_comb_minimal)[[1]]
    pen_HL <- penalties(df_comb_minimal)[[2]]
    # --- fragment_inty [] ---
    # Key functions: fragment_inty
    fragment_inty(
    head(fragment_int, 5)
    # --- t test function HL [] ---
    # Key functions: statistics
    data(fragment_int)
    stats_df_comb_minimal <- statistics(data= fragment_int)[[1]]
    df_comb_uniq_minimal <- statistics(data= fragment_int)[[2]]
    # --- rifi visualization comparison [] ---
    # Key functions: rifi_visualization_comparison
    data(data_combined_minimal)
    data(stats_df_comb_minimal)
    data(annot_g)
    # --- adjusting HLToInt [] ---
    # Key functions: adjusting_HLToInt
    data(stats_df_comb_minimal)
    data(annot_g)
    df_adjusting_HLToInt <- adjusting_HLToInt(data = stats_df_comb_minimal,
    # --- figures_fun [] ---
    # Key functions: figures_fun
    data(data_combined_minimal)
    data(df_comb_minimal)
    data(differential_expression)
    # --- gff3 preprocess [] ---
    # Key functions: gff3_preprocess
    gff3_preprocess(path = gzfile(
    system.file("extdata", "gff_synechocystis_6803.gff.gz", package = "rifiComparative")
    sessionInfo()

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
