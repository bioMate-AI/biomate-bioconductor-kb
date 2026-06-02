#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: condiments
// This package encapsulate many functions to conduct a differential topology analysis. It focuses on a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/condiments/inst/doc/condiments.R
// Upstream  : RColorBrewer, dplyr, ggplot2, knitr, slingshot
// Downstream: none
//
// Install: BiocManager::install("condiments")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CONDIMENTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-condiments"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-condiments:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-condiments:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_condiments_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_condiments_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_condiments_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(condiments)
    library(jsonlite)

    # --- Packages [] ---
    # Key functions: set
    --------------------------------------------------
    library(knitr)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("toy_dataset", package = "condiments")
    df <- toy_dataset$sd
    # --- Ggplot [] ---
    # Key functions: ggplot, aes, geom_point, scale_color_brewer
    ---------------------------------------------------------------------
    p <- ggplot(df, aes(x = Dim1, y = Dim2, col = conditions)) +
      geom_point() +
      scale_color_brewer(type = "qual")
    p
    # --- Ggplot [] ---
    # Key functions: ggplot, aes, geom_point, geom_path, scale_color_brewer, facet_wrap, guides
    ---------------------------------------------------------------------
    p <- ggplot(df, aes(x = Dim1, y = Dim2, col = conditions)) +
      geom_point(alpha = .5) +
      geom_point(data = toy_dataset$mst, size = 2) +
      geom_path(data = toy_dataset$mst, aes(group = lineages), size = 1.5) +
    # --- Imbalance Score [] ---
    # Key functions: imbalance_score, select
    ---------------------------------------------------------------------
    scores <- imbalance_score(Object = df %>% select(Dim1, Dim2) %>% as.matrix(),
                              conditions = df$conditions)
    df$scores <- scores$scores
    df$scaled_scores <- scores$scaled_scores
    # --- Ggplot [] ---
    # Key functions: ggplot, aes, geom_point, scale_color_viridis_c
    ---------------------------------------------------------------------
    ggplot(df, aes(x = Dim1, y = Dim2, col = scores)) +
      geom_point() +
      scale_color_viridis_c(option = "C")
    # --- Ggplot [] ---
    # Key functions: ggplot, aes, geom_point
    ---------------------------------------------------------------------
    ggplot(df, aes(x = Dim1, y = Dim2, col = cl)) +
      geom_point()
    # --- Matrix [] ---
    # Key functions: slingshot, topologyTest
    ---------------------------------------------------------------------
    rd <- as.matrix(df[, c("Dim1", "Dim2")])
    sds <- slingshot(rd, df$cl)
    ## Takes ~1m30s to run
    top_res <- topologyTest(sds = sds, conditions = df$conditions)
    # --- Ggplot [] ---
    # Key functions: ggplot, aes, geom_point, geom_path, slingCurves, arrange
    ---------------------------------------------------------------------
    ggplot(df, aes(x = Dim1, y = Dim2, col = cl)) +
      geom_point() +
      geom_path(data =  slingCurves(sds, as.df = TRUE) %>% arrange(Order),
                aes(group = Lineage), col = "black", size = 2)
    # --- Slingpseudotime [] ---
    # Key functions: slingPseudotime, frame, mutate, pivot_longer, starts_with
    ---------------------------------------------------------------------
    psts <- slingPseudotime(sds) %>%
      as.data.frame() %>%
      mutate(cells = rownames(.),
             conditions = df$conditions) %>%
    # --- Progressiontest [] ---
    # Key functions: progressionTest
    ---------------------------------------------------------------------
    prog_res <- progressionTest(sds, conditions = df$conditions, global = TRUE, lineages = TRUE)
    knitr::kable(prog_res)
    # --- Slingcurveweights [] ---
    # Key functions: slingCurveWeights, ggplot, aes, geom_density, scale_fill_brewer, labs
    ---------------------------------------------------------------------
    df$weight_1 <- slingCurveWeights(sds, as.probs = TRUE)[, 1]
    ggplot(df, aes(x = weight_1, fill = conditions)) +
      geom_density(alpha = .5) +
      scale_fill_brewer(type = "qual") +

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_condiments_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_condiments_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_condiments_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CONDIMENTS:", paste0("    condiments: ", packageVersion("condiments"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_condiments_results.csv
    touch ${prefix}_condiments_output.rds
    echo "BIOC_CONDIMENTS:" > versions.yml
    echo "    condiments: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CONDIMENTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CONDIMENTS(ch_input)

    emit:
    results  = BIOC_CONDIMENTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CONDIMENTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CONDIMENTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CONDIMENTS.out.versions  // channel: path(versions.yml)
}
