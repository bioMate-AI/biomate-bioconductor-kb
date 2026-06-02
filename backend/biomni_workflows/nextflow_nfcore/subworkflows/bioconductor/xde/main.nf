#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: XDE
// Multi-level model for cross-study detection of differential gene expression.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/XDE/inst/doc/XDE.R
// Upstream  : GeneMeta, siggenes
// Downstream: none
//
// Install: BiocManager::install("XDE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XDE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-xde"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-xde:2.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-xde:2.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_xde_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_xde_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_xde_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(XDE)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data, class
    library(XDE)
    data(expressionSetList)
    xlist <- expressionSetList
    class(xlist)
    # --- Covariate [] ---
    # Key functions: all, varLabels
    stopifnot(all(sapply(xlist, function(x, label){ label %in% varLabels(x)}, label="adenoVsquamous")))
    # --- Empiricalstart [] ---
    # Key functions: new, empiricalStart, firstMcmc
    ## params <- new("XdeParameter", esetList=xlist, phenotypeLabel="adenoVsquamous", one.delta=FALSE)
    ## empirical <- empiricalStart(xlist, phenotypeLabel="adenoVsquamous")
    ## firstMcmc(params) <- empirical
    # --- Burnin [] ---
    # Key functions: iterations, burnin, xde
    ## iterations(params) <- 3
    ## burnin(params) <- TRUE
    ## fit <- xde(params, xlist)
    # --- Moreiterations [] ---
    # Key functions: iterations, xde
    ## iterations(params) <- 2
    ## fit2 <- xde(params, xlist, fit)
    # --- Firstmcmc [] ---
    # Key functions: firstMcmc, lastMcmc, xde
    ## firstMcmc(params) <- lastMcmc(fit)
    ## seed(params) <- seed(fit)
    ## fit2 <- xde(params, xlist)
    # --- Runmoreiterations [] ---
    # Key functions: burnin, iterations, output, thin, directory, xde
    ## burnin(params) <- FALSE
    ## iterations(params) <- 2000
    ## output(params)[c("potential", "acceptance",
    ## 		 "diffExpressed",
    ## 		 "nu", ##"DDelta",
    # --- Savexmcmc [] ---
    # Key functions: calculatePosteriorAvg, calculateBayesianEffectSize, q
    ## ##this function should work
    ## postAvg <- calculatePosteriorAvg(xmcmc, NCONC=2, NDIFF=1)
    ## save(postAvg, file="~/madman/Rpacks/XDE/inst/logFiles/postAvg.rda")
    ## ##put browser in .standardizedDelta to fix tau2R, ...
    ## BES <- calculateBayesianEffectSize(xmcmc)
    # --- Loadobject [] ---
    # Key functions: data
    data(xmcmc, package="XDE")
    # --- Savedparams [] ---
    # Key functions: output
    output(xmcmc)[2:22][output(xmcmc)[2:22] == 1]
    # --- Extractc2 [] ---
    # Key functions: file
    pathToLogFiles <- system.file("logFiles", package="XDE")
    xmcmc@directory <- pathToLogFiles
    c2 <- xmcmc$c2
    # --- ts [] ---
    # Key functions: ts
    par(las=1)
    plot.ts(c2, ylab="c2", xlab="iterations", plot.type="single")
    # --- Retrievelogs [] ---
    # Key functions: output, getLogs, eval
    getLogs <- function(object){
    	params <- output(object)[output(object) == 1]
    	params <- params[!(names(params) %in% c("nu", "phi", "DDelta", "delta", "sigma2", "diffExpressed"))]
    	names(params)
    }
    # --- Bayesianeffectsize [] ---
    # Key functions: bayesianEffectSize, calculateBayesianEffectSize
    ## bayesianEffectSize(xmcmc) <- calculateBayesianEffectSize(xmcmc)
    # --- Bes [] ---
    # Key functions: path
    load(file.path(pathToLogFiles, "BES.rda"))
    load(file.path(pathToLogFiles, "postAvg.rda"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_xde_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_xde_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_xde_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_XDE:", paste0("    xde: ", packageVersion("XDE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xde_results.csv
    touch ${prefix}_xde_output.rds
    echo "BIOC_XDE:" > versions.yml
    echo "    xde: 0.0.0" >> versions.yml
    """
}


workflow BIOC_XDE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_XDE(ch_input)

    emit:
    results  = BIOC_XDE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_XDE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_XDE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_XDE.out.versions  // channel: path(versions.yml)
}
