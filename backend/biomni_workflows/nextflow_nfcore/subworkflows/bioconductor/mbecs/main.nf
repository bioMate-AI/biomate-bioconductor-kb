#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MBECS
// The Microbiome Batch Effect Correction Suite (MBECS) provides a set of functions to evaluate and mit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MBECS/inst/doc/mbecs_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MBECS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MBECS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mbecs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mbecs:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mbecs:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mbecs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mbecs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mbecs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MBECS)
    library(jsonlite)

    # --- Batch Effect Correction [] ---
    # Key functions: mbecCorrection, mbecRunCorrections
    mbec.obj <- mbecCorrection(
        mbec.obj,
        model.vars = c("batch", "group"),
        method = "bat",
        type = "clr"
    )
    mbec.obj <- mbecRunCorrections(
        mbec.obj,
        model.vars = c("batch", "group"),
        method = c("ruv3", "rbe", "bmc", "pn", "svd"),
        type = "clr"
    )


    # --- Exploratory Data Analysis and Visualisation [] ---
    # Key functions: mbecRLE, mbecPCA, mbecBox, mbecHeat
    rle.plot <- mbecRLE(
        input.obj = mbec.obj,
        model.vars = c("batch", "group"),
        type = "clr",
        return.data = FALSE
    )
    pca.plot <- mbecPCA(
        input.obj = mbec.obj,
        model.vars = c("batch", "group"),
        type = "clr",
        pca.axes = c(1, 2),
        return.data = FALSE
    )
    box.plot <- mbecBox(
        input.obj = mbec.obj,
        method = "TOP",
        n = 2,
        model.var = "batch",
        type = "clr",
        return.data = FALSE
    )
    heat.plot <- mbecHeat(
        input.obj = mbec.obj,
        method = "TOP",
        n = 10,
        model.vars = c("batch", "group"),
        center = TRUE,
        scale = TRUE,
        type = "clr",
        return.data = FALSE
    )


    # --- Variance Assessment [] ---
    # Key functions: mbecModelVariance, mbecVarianceStatsPlot, mbecPVCAStatsPlot
    lm.variance <- mbecModelVariance(
        input.obj = mbec.obj,
        model.vars = c("batch", "group"),
        method = "lm",
        type = "cor",
        label = "svd"
    )
    lm.plot <- mbecVarianceStatsPlot(lm.variance)
    pvca.variance <- mbecModelVariance(
        input.obj = mbec.obj,
        model.vars = c("batch", "group"),
        method = "pvca",
        type = "cor",
        label = "rbe"
    )
    pvca.plot <- mbecPVCAStatsPlot(pvca.variance)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mbecs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mbecs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mbecs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MBECS:", paste0("    mbecs: ", packageVersion("MBECS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mbecs_results.csv
    touch ${prefix}_mbecs_output.rds
    echo "BIOC_MBECS:" > versions.yml
    echo "    mbecs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MBECS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MBECS(ch_input)

    emit:
    results  = BIOC_MBECS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MBECS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MBECS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MBECS.out.versions  // channel: path(versions.yml)
}
