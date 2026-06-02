#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TFBSTools
// TFBSTools is a package for the analysis and manipulation of transcription factor binding sites. It i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TFBSTools/inst/doc/TFBSTools.R
// Upstream  : Biostrings, CNEr, JASPAR2014, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("TFBSTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TFBSTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tfbstools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tfbstools:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tfbstools:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tfbstools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tfbstools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tfbstools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TFBSTools)
    library(jsonlite)


    # --- Code [] ---
    # Key functions: function, doc_date, pkg_ver, set
    code <- function(...) {
        cat(paste(..., sep = "\n"))
    }

    date = "`r doc_date()`"
    pkg = "`r pkg_ver('BiocStyle')`"
    short=TRUE #if short==TRUE, do not echo code chunks
    debug=FALSE
    knitr::opts_chunk$set(echo=!short, warning=debug, message=debug, error=FALSE,
                   cache.path = "cache/",
                   fig.path = "figures/")

    # --- Pfmatrix [] ---
    # Key functions: PFMatrix, name, toPWM, toICM, rowSums, reverseComplement, vertebrates, log2probratio
    library(TFBSTools)
    ## PFMatrix construction; Not all of the slots need to be initialised.
    # --- Tffmread [] ---
    # Key functions: readXMLTFFM, getPosProb, extdata, tffm_first_order.xml, tffm_detailed.xml, suppressMessages, getMatrixSet, species
    xmlFirst <- file.path(system.file("extdata", package="TFBSTools"),
                            "tffm_first_order.xml")
      tffmFirst <- readXMLTFFM(xmlFirst, type="First")
      tffm <- getPosProb(tffmFirst)

      xmlDetail <- file.path(system.file("extdata", package="TFBSTools"),
                             "tffm_detailed.xml")
      tffmDetail <- readXMLTFFM(xmlDetail, type="Detail")
      getPosProb(tffmDetail)
    suppressMessages(library(JASPAR2014))
    opts <- list()
    opts[["species"]] <- 9606
    opts[["name"]] <- "RUNX1"
    opts[["type"]] <- "SELEX"
    opts[["all_versions"]] <- TRUE
    PFMatrixList <- getMatrixSet(JASPAR2014, opts)
    PFMatrixList

    opts2 <- list()

    # --- Operate Database [] ---
    # Key functions: initializeJASPARDB, storeMatrix, deleteMatrixHavingID, file.remove, myMatrixDb.sqlite, toPWM
    db <- "myMatrixDb.sqlite"
    initializeJASPARDB(db, version="2014")
    data("MA0043")
    storeMatrix(db, MA0043)
    deleteMatrixHavingID(db,"MA0043.1")
    file.remove(db)
    pwm <- toPWM(pfm, pseudocounts=0.8)
    pwm

    # --- Icmmatrix Methods [] ---
    # Key functions: toICM, seqLogo
    icm <- toICM(pfm, pseudocounts=0.8, schneider=TRUE)
    icm
    seqLogo(icm)

    # --- Pfmsimi [] ---
    # Key functions: PFMSimilarity, toPWM, PWMSimilarity, prob
    ## one to one comparison
    data(MA0003.2)
    data(MA0004.1)
    pfmSubject <- MA0003.2
    pfmQuery <-  MA0004.1
    PFMSimilarity(pfmSubject, pfmQuery)

    ## one to several comparsion
    PFMSimilarity(pfmList, pfmQuery)

    data(MA0003.2)
    data(MA0004.1)
    pwm1 <- toPWM(MA0003.2, type="prob")
    pwm2 <- toPWM(MA0004.1, type="prob")
    PWMSimilarity(pwm1, pwm2, method="Euclidean")
    PWMSimilarity(pwm1, pwm2, method="Pearson")
    PWMSimilarity(pwm1, pwm2, method="KL")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tfbstools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tfbstools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tfbstools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TFBSTOOLS:", paste0("    tfbstools: ", packageVersion("TFBSTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tfbstools_results.csv
    touch ${prefix}_tfbstools_output.rds
    echo "BIOC_TFBSTOOLS:" > versions.yml
    echo "    tfbstools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TFBSTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TFBSTOOLS(ch_input)

    emit:
    results  = BIOC_TFBSTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TFBSTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TFBSTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TFBSTOOLS.out.versions  // channel: path(versions.yml)
}
