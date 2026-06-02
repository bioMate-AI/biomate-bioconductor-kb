#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: paircompviz
// This package provides visualization of the results from the multiple (i.e. pairwise) comparison test
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/paircompviz/inst/doc/vignette.R
// Upstream  : multcomp, plyr, reshape, rpart, xtable
// Downstream: none
//
// Install: BiocManager::install("paircompviz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PAIRCOMPVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-paircompviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-paircompviz:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-paircompviz:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_paircompviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_paircompviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_paircompviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(paircompviz)
    library(jsonlite)

    # --- Pairwise Comparison and Compression ---
    # Key functions: paircomp
    pc_res <- paircomp(
        InsectSprays$count,
        InsectSprays$spray,
        test = "t",
        compress = TRUE,
        p.adjust.method = "bonferroni"
    )

    # --- Pairwise Comparison with Tukey HSD ---
    # Key functions: paircomp
    aov_res <- aov(Price ~ Type, data = rpart::car90)
    glht_res <- multcomp::glht(
        aov_res,
        linfct = multcomp::mcp(Type = "Tukey")
    )
    pc_tukey <- paircomp(glht_res, compress = FALSE)

    # --- Transitive Reduction of Adjacency Matrix ---
    # Key functions: transReduct
    adj_matrix <- matrix(c(
        0, 0, 0, 0, 0, 0, 0, 0,
        1, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 0, 0, 0, 0, 0, 0,
        1, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1, 0, 0, 0, 0,
        1, 1, 1, 1, 1, 0, 0, 0,
        1, 1, 1, 1, 1, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    ), nrow = 8)
    reduced_matrix <- transReduct(adj_matrix)

    # --- Hasse Diagram Visualization ---
    # Key functions: hasse
    hasse(
        reduced_matrix,
        v = LETTERS[1:8],
        main = "Hasse Diagram of Pairwise Comparisons"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_paircompviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_paircompviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_paircompviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PAIRCOMPVIZ:", paste0("    paircompviz: ", packageVersion("paircompviz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paircompviz_results.csv
    touch ${prefix}_paircompviz_output.rds
    echo "BIOC_PAIRCOMPVIZ:" > versions.yml
    echo "    paircompviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PAIRCOMPVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PAIRCOMPVIZ(ch_input)

    emit:
    results  = BIOC_PAIRCOMPVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PAIRCOMPVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PAIRCOMPVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PAIRCOMPVIZ.out.versions  // channel: path(versions.yml)
}
