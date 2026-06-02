#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pipeComp
// A simple framework to facilitate the comparison of pipelines involving various steps and parameters.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pipeComp/inst/doc/pipeComp.R
// Upstream  : BiocStyle, ComplexHeatmap, S4Vectors, edgeR, ggplot2
// Downstream: none
//
// Install: BiocManager::install("pipeComp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PIPECOMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pipecomp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pipecomp:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pipecomp:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pipecomp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pipecomp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pipecomp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pipeComp)
    library(PipelineDefinition)
    library(jsonlite)

    # --- Pipeline Execution [] ---
    # Key functions: runPipeline
    datasets <- list(ds1 = 1:3, ds2 = c(5, 10, 15))
    alternatives <- list(meth1 = c("log", "sqrt"), meth2 = "cumsum")
    tmpdir1 <- paste0(tempdir(), "/")
    res <- runPipeline(datasets, alternatives, my_pip,
                       output.prefix = tmpdir1)


    # --- Results Aggregation [] ---
    # Key functions: readPipelineResults, aggregatePipelineResults
    ds <- list.files(tmpdir1, pattern = "evaluation\\.rds",
                     full.names = TRUE)
    names(ds) <- basename(ds)
    res1 <- readPipelineResults(resfiles = ds)
    res_agg <- aggregatePipelineResults(res1)


    # --- Performance Visualization [] ---
    # Key functions: plotElapsed, evalHeatmap
    plotElapsed(res, agg.by = FALSE)
    evalHeatmap(res, what = c("mean", "max"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pipecomp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pipecomp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pipecomp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PIPECOMP:", paste0("    pipecomp: ", packageVersion("pipeComp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pipecomp_results.csv
    touch ${prefix}_pipecomp_output.rds
    echo "BIOC_PIPECOMP:" > versions.yml
    echo "    pipecomp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PIPECOMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PIPECOMP(ch_input)

    emit:
    results  = BIOC_PIPECOMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PIPECOMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PIPECOMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PIPECOMP.out.versions  // channel: path(versions.yml)
}
