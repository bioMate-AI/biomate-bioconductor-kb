#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowClean
// A quality control tool for flow cytometry data based on compositional data analysis.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowClean/inst/doc/flowClean.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("flowClean")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWCLEAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowclean"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowclean:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowclean:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowclean_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowclean_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowclean_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowClean)
    library(jsonlite)

    # --- Logicle Transformation [] ---
    # Key functions: estimateLogicle, transform
    lgcl <- estimateLogicle(
        synPerturbed.c,
        unname(parameters(synPerturbed.c)$name[5:16])
    )
    synPerturbed.cl <- transform(synPerturbed.c, lgcl)


    # --- Gating and Subsetting [] ---
    # Key functions: rectangleGate, filter, Subset
    rg <- rectangleGate(filterId = "gvb", list("GoodVsBad" = c(0, 9999)))
    idx <- filter(synPerturbed.cl, rg)
    synPerturbed.clean <- Subset(synPerturbed.cl, idx)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowclean_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowclean_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowclean_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWCLEAN:", paste0("    flowclean: ", packageVersion("flowClean"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowclean_results.csv
    touch ${prefix}_flowclean_output.rds
    echo "BIOC_FLOWCLEAN:" > versions.yml
    echo "    flowclean: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWCLEAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWCLEAN(ch_input)

    emit:
    results  = BIOC_FLOWCLEAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWCLEAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWCLEAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWCLEAN.out.versions  // channel: path(versions.yml)
}
