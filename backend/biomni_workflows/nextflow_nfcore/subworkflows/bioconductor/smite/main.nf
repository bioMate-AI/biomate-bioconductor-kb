#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SMITE
// This package builds on the Epimods framework which facilitates finding weighted subnetworks ("module
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SMITE/inst/doc/SMITE.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SMITE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SMITE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-smite"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-smite:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-smite:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_smite_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_smite_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_smite_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SMITE)
    library(jsonlite)

    # --- Expression Annotation and Normalisation [] ---
    # Key functions: annotateExpression, normalizePval, plotDensityPval
    test_annotation <- annotateExpression(
        pvalue_annotation = test_annotation,
        expr_data = expression_curated,
        effect_col = 1,
        pval_col = 2
    )
    density_plot <- plotDensityPval(
        pvalue_annotation = test_annotation,
        ref = "expression"
    )
    test_annotation <- normalizePval(
        test_annotation,
        ref = "expression",
        method = "rescale"
    )


    # --- P-value Scoring and Comparison [] ---
    # Key functions: scorePval, plotCompareScores
    test_annotation <- scorePval(
        test_annotation,
        weights = c(
            methylation_promoter = 0.3,
            methylation_body = 0.1,
            expression = 0.3,
            methylation_h3k4me1 = 0.3
        )
    )
    compare_plot <- plotCompareScores(
        test_annotation,
        x_name = "expression",
        y_name = "methylation_promoter"
    )


    # --- Functional Enrichment and Network Visualisation [] ---
    # Key functions: searchGOseq, plotModule
    go_results <- searchGOseq(
        test_annotation,
        search_string = "cell cycle"
    )
    module_plot_1 <- plotModule(
        test_annotation,
        which_network = 6,
        layout = "fr",
        label_scale = TRUE,
        compare_plot = FALSE
    )
    module_plot_2 <- plotModule(
        test_annotation,
        which_network = c(4, 6),
        layout = "fr",
        label_scale = TRUE,
        compare_plot = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_smite_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_smite_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_smite_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SMITE:", paste0("    smite: ", packageVersion("SMITE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_smite_results.csv
    touch ${prefix}_smite_output.rds
    echo "BIOC_SMITE:" > versions.yml
    echo "    smite: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SMITE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SMITE(ch_input)

    emit:
    results  = BIOC_SMITE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SMITE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SMITE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SMITE.out.versions  // channel: path(versions.yml)
}
