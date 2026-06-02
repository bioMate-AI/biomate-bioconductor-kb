#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sparrow
// Provides a unified interface to a variety of GSEA techniques from different bioconductor packages. R
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sparrow/inst/doc/sparrow.R
// Upstream  : ComplexHeatmap, circlize, dplyr, edgeR, ggplot2
// Downstream: none
//
// Install: BiocManager::install("sparrow")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPARROW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sparrow"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sparrow:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sparrow:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sparrow_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sparrow_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sparrow_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sparrow)
    library(jsonlite)

    # --- Linear model fit (limma) [] ---
    # Key functions: lmFit, topTable
    fit <- lmFit(vm, vm$design) %>%
    contrasts.fit(cm) %>%
    tt <- topTable(fit, 'BvH', n=Inf, sort.by='none')
    # --- Custom ggplot2 visualization [] ---
    # Key functions: inner_join, ggplot, geom_boxplot, geom_jitter, facet_grid

    # --- Theme set analysis [] ---
    # Key functions: theme_set, exampleExpressionSet, getMSigGeneSetDb, geneSets, seas, logFC, inner_join, arrange
    select(entrez_id, logFC, t, pval=P.Value, padj=adj.P.Val) %>%
    inner_join(lfc, by='entrez_id', suffix=c('.tt', '.mg'))
    all.equal(comp$t.tt, comp$t.mg)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sparrow_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sparrow_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sparrow_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPARROW:", paste0("    sparrow: ", packageVersion("sparrow"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sparrow_results.csv
    touch ${prefix}_sparrow_output.rds
    echo "BIOC_SPARROW:" > versions.yml
    echo "    sparrow: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPARROW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPARROW(ch_input)

    emit:
    results  = BIOC_SPARROW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPARROW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPARROW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPARROW.out.versions  // channel: path(versions.yml)
}
