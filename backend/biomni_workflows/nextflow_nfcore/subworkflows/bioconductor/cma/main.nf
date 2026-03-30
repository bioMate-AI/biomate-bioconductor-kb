#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CMA
// This package provides a comprehensive collection of various microarray-based classification algorith
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CMA/inst/doc/CMA_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CMA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CMA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cma"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cma:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cma:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cma_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cma_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cma_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneSelection)
    library(GenerateLearningsets)
    library(jsonlite)

    # --- Cma Vignette.Rnw:400 405 [] ---
    # Key functions: data
    ## data(golub)
    ## golubY <- golub[,1]
    ##
    ## golubX <- as.matrix(golub[,-1])
    ##
    # --- Cma Vignette.Rnw:414 420 [] ---
    # Key functions: GenerateLearningsets, getSlots, show
    ##
    ## loodat <- GenerateLearningsets(y=golubY, method ="LOOCV")
    ## class(loodat)
    ## getSlots(class(loodat))
    ## show(loodat)
    # --- Cma Vignette.Rnw:425 430 [] ---
    # Key functions: GenerateLearningsets
    ##
    ## set.seed(321)
    ## fiveCVdat <- GenerateLearningsets(y=golubY, method = "CV", fold = 5, strat = TRUE)
    ##
    ##
    # --- Cma Vignette.Rnw:437 446 [] ---
    # Key functions: GenerateLearningsets
    ##
    ## set.seed(456)
    ## MCCVdat <- GenerateLearningsets(y=golubY, method = "MCCV", niter = 3,
    ##                                 ntrain = floor(2/3*length(golubY)), strat = TRUE)
    ##
    # --- Cma Vignette.Rnw:456 462 [] ---
    # Key functions: GeneSelection
    ##
    ## varsel_fiveCV <- GeneSelection(X = golubX, y=golubY, learningsets = fiveCVdat, method = "wilcox.test")
    ## varsel_MCCV <- GeneSelection(X = golubX, y=golubY, learningsets = MCCVdat, method = "wilcox.test")
    ## varsel_boot <- GeneSelection(X = golubX, y=golubY, learningsets = bootdat, method = "wilcox.test")
    ##
    # --- Cma Vignette.Rnw:468 476 [] ---
    # Key functions: show, toplist
    ##
    ## show(varsel_fiveCV)
    ## toplist(varsel_fiveCV, iter=1)
    ## seliter <- numeric()
    ## for(i in 1:5)
    # --- Cma Vignette.Rnw:506 511 [] ---
    # Key functions: tune
    ## set.seed(351)
    ## tuningstep <- CMA:::tune(X = golubX, y=golubY, learningsets = fiveCVdat,
    ##                       genesel = varsel_fiveCV, nbgene = 100, classifier = svmCMA,
    ##                       grids = list(cost = c(0.1, 1, 10, 100, 200)),probability=T)
    ##
    # --- Cma Vignette.Rnw:516 520 [] ---
    # Key functions: show, unlist, best
    ##
    ## show(tuningstep)
    ## unlist(best(tuningstep))
    ##
    # --- Cma Vignette.Rnw:537 555 [] ---
    # Key functions: classification
    ##
    ## #class_loo <- classification(X = golubX, y=golubY, learningsets = loodat,
    ## #                      genesel = varsel_loo, nbgene = 100, classifier = svmCMA,
    ## #                      cost = 100)
    ##
    # --- Cma Vignette.Rnw:595 599 [] ---
    # Key functions: roc
    ##
    ## par(mfrow = c(2,2))
    ## for(i in seq(along = result)) roc(result[[i]])
    ##
    # --- Cma Vignette.Rnw:605 609 [] ---
    # Key functions: join, ftable
    ##
    ## totalresult <- join(result)
    ## ftable(totalresult)
    ##
    # --- Cma Vignette.Rnw:618 624 [] ---
    # Key functions: evaluation, show
    ##
    ## av_MCCV <- evaluation(class_MCCV, measure = "average probability")
    ## show(av_MCCV)
    ## boxplot(av_MCCV)
    ## summary(av_MCCV)
    # --- Cma Vignette.Rnw:639 642 [] ---
    # Key functions: evaluation, show
    ## av_obs_MCCV <- evaluation(class_MCCV, measure = "average probability", scheme = "obs")
    ## show(av_obs_MCCV)
    ##
    # --- Cma Vignette.Rnw:648 651 [] ---
    # Key functions: obsinfo
    ##
    ## obsinfo(av_obs_MCCV, threshold = 0.6)
    ##
    # --- Cma Vignette.Rnw:675 685 [] ---
    # Key functions: GenerateLearningsets
    data(khan)
    khanY <- khan[,1]
    khanX <- as.matrix(khan[,-1])
    set.seed(27611)
    fiveCV5iter <- GenerateLearningsets(y=khanY, method = "CV", fold = 5, niter = 5, strat = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cma_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cma_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cma_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CMA:", paste0("    cma: ", packageVersion("CMA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cma_results.csv
    touch ${prefix}_cma_output.rds
    echo "BIOC_CMA:" > versions.yml
    echo "    cma: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CMA(ch_input)

    emit:
    results  = BIOC_CMA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CMA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CMA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CMA.out.versions  // channel: path(versions.yml)
}
