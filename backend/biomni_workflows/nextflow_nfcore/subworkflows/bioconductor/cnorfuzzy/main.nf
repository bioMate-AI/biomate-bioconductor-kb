#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNORfuzzy
// This package is an extension to CellNOptR.  It contains additional functionality needed to simulate 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNORfuzzy/inst/doc/CNORfuzzy-vignette.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("CNORfuzzy")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNORFUZZY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cnorfuzzy"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cnorfuzzy:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cnorfuzzy:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cnorfuzzy_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cnorfuzzy_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cnorfuzzy_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNORfuzzy)
    library(CNORwrapFuzzy)
    library(CNOlist)
    library(jsonlite)

    # --- Parameter Initialization [] ---
    # Key functions: defaultParametersFuzzy
    data(DreamModel, package = "CellNOptR")
    data(CNOlistDREAM, package = "CellNOptR")
    paramsList <- defaultParametersFuzzy(CNOlistDREAM, DreamModel)
    paramsList$popSize <- 50
    paramsList$maxTime <- 300
    paramsList$maxGens <- 200
    paramsList$stallGenMax <- 50
    paramsList$verbose <- FALSE


    # --- Fuzzy Logic Optimization [] ---
    # Key functions: CNORwrapFuzzy
    allRes <- list()
    for (i in 1:1) {
        Res <- CNORwrapFuzzy(CNOlistToy, ToyModel, paramsList = paramsList)
        allRes[[i]] <- Res
    }


    # --- Multi-run Compilation and Plotting [] ---
    # Key functions: compileMultiRes, plotMeanFuzzyFit
    summary_res <- compileMultiRes(allRes, show = FALSE)
    plotMeanFuzzyFit(
        threshold = 0.1, 
        allFinalMSEs = summary_res$allFinalMSEs, 
        allRes = allRes,
        plotParams = list(cmap_scale = 0.5, cex = 0.9, margin = 0.3)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cnorfuzzy_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cnorfuzzy_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cnorfuzzy_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNORFUZZY:", paste0("    cnorfuzzy: ", packageVersion("CNORfuzzy"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnorfuzzy_results.csv
    touch ${prefix}_cnorfuzzy_output.rds
    echo "BIOC_CNORFUZZY:" > versions.yml
    echo "    cnorfuzzy: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNORFUZZY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNORFUZZY(ch_input)

    emit:
    results  = BIOC_CNORFUZZY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNORFUZZY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNORFUZZY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNORFUZZY.out.versions  // channel: path(versions.yml)
}
