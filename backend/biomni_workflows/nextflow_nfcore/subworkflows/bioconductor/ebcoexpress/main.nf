#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EBcoexpress
// An Empirical Bayesian Approach to Differential Co-Expression Analysis at the Gene-Pair Level
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EBcoexpress/inst/doc/EBcoexpressVignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("EBcoexpress")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EBCOEXPRESS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ebcoexpress"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ebcoexpress:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ebcoexpress:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ebcoexpress_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ebcoexpress_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ebcoexpress_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DC)
    library(FDR)
    library(jsonlite)

    # --- Foo [] ---
    # Key functions: packageDescription
    options(keep.source = TRUE, width = 60)
    foo <- packageDescription("EBcoexpress")
    # --- Packageload [] ---
    # Key functions: ebPatterns
    library(EBcoexpress)
    data(fiftyGenes) # A 50-by-125 expression matrix
    tinyCond <- c(rep(1,100),rep(2,25))
    tinyPat <- ebPatterns(c("1,1","1,2"))
    # --- Dcreation [] ---
    # Key functions: makeMyD
    D <- makeMyD(fiftyGenes, tinyCond, useBWMC=TRUE)
    # --- Initialization [] ---
    # Key functions: initializeHP
    set.seed(3)
    initHP <- initializeHP(D, tinyCond)
    # --- Emruns [] ---
    # Key functions: ebCoexpressZeroStep, ebCoexpressOneStep
    zout <- ebCoexpressZeroStep(D, tinyCond, tinyPat, initHP)
    oout <- ebCoexpressOneStep(D, tinyCond, tinyPat, initHP)
    # --- Emrunsnotrun [] ---
    # Key functions: ebCoexpressFullTCAECM
    ## fout <- ebCoexpressFullTCAECM(D, tinyCond, tinyPat, initHP)
    # --- prior Diagnostic [] ---
    # Key functions: priorDiagnostic
    priorDiagnostic(D, tinyCond, zout, 1)
    # --- Grabbingpairs [] ---
    # Key functions: fun
    ppbDC1 <- 1-result1[,1]
    crit_s <- crit.fun(result1[,1], 0.05)
    kept_s <- ppbDC1[ppbDC1 >= crit_s]
    kept_h <- ppbDC1[ppbDC1 >= 0.95]
    klabs_s <- names(kept_s)
    # --- Moregrabbing [] ---
    # Key functions: DC, thresholding, FDR
    nk_s <- length(kept_s) # No. taken as DC (soft)
    nk_h <- length(kept_h) # No. taken as DC (hard)
    nY_s <- sum(klabs_s %in% TP)
      # Number of TP taken as DC under soft thresholding
    nY_h <- sum(klabs_h %in% TP)
    # --- Rankthem [] ---
    # Key functions: rankMyGenes
    hubs <- rankMyGenes(oout)
    print(hubs)
    # --- Dummy1 [] ---
    # Key functions: ebCoexpressMeta
    ## ebCoexpressMeta(DList, conditionsList, pattern, hpEstsList)
    # --- Dummy2 [] ---
    # Key functions: ebPatterns, ebCoexpressZeroStep, ebCoexpressMeta
    D1 <- D
    D2 <- D
    DList <- list(D1, D2)
    cond1 <- tinyCond
    cond2 <- tinyCond
    # --- Grab20 [] ---
    # Key functions: dimnames
    twentyGeneNames <- dimnames(fiftyGenes)[[1]][c(1:10,26:35)]
    # --- show Network [] ---
    # Key functions: showNetwork
    showNetwork(twentyGeneNames, D, condFocus = 1, gsep = "~",
      layout = "kamada.kawai", seed = 5, vertex.shape="circle",
      vertex.label.cex=1, vertex.color="white", edge.width=2,
      vertex.frame.color="black", vertex.size=20,
      vertex.label.color="black", vertex.label.family="sans")
    # --- Fig4 [] ---
    # Key functions: showPair
    showPair("X1~X2", fiftyGenes, tinyCond, pch=20,
      xlim=c(-4,4), ylim=c(-4,4))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ebcoexpress_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ebcoexpress_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ebcoexpress_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EBCOEXPRESS:", paste0("    ebcoexpress: ", packageVersion("EBcoexpress"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ebcoexpress_results.csv
    touch ${prefix}_ebcoexpress_output.rds
    echo "BIOC_EBCOEXPRESS:" > versions.yml
    echo "    ebcoexpress: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EBCOEXPRESS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EBCOEXPRESS(ch_input)

    emit:
    results  = BIOC_EBCOEXPRESS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EBCOEXPRESS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EBCOEXPRESS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EBCOEXPRESS.out.versions  // channel: path(versions.yml)
}
