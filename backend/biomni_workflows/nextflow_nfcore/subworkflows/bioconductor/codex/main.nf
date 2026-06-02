#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CODEX
// A normalization and copy number variation calling procedure for whole exome DNA sequencing data. COD
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CODEX/inst/doc/CODEX_vignettes.R
// Upstream  : devtools
// Downstream: iCNV
//
// Install: BiocManager::install("CODEX")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CODEX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-codex"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-codex:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-codex:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_codex_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_codex_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_codex_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CODEX)
    library(jsonlite)

    # --- Install1 [] ---
    # Key functions: requireNamespace, packages
    ## ## try http:// if https:// URLs are not supported
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install("CODEX")
    # --- Install2 [] ---
    # Key functions: packages, install_github
    ## install.packages("devtools")
    ## library(devtools)
    ## install_github("yuchaojiang/CODEX/package")
    # --- Bambedobj1 [] ---
    # Key functions: files, path, getbambed
    library(CODEX)
    library(WES.1KG.WUGSC) # Load Toy data from the 1000 Genomes Project.
    dirPath <- system.file("extdata", package = "WES.1KG.WUGSC")
    bamFile <- list.files(dirPath, pattern = '*.bam$')
    bamdir <- file.path(dirPath, bamFile)
    # --- Coverageobj1 [] ---
    # Key functions: getcoverage
    coverageObj <- getcoverage(bambedObj, mapqthres = 20)
    Y <- coverageObj$Y; readlength <- coverageObj$readlength
    # --- Gcmapp1 [] ---
    # Key functions: getgc, getmapp
    gc <- getgc(chr, ref)
    mapp <- getmapp(chr, ref)
    # --- Qcobj1 [] ---
    # Key functions: qc
    qcObj <- qc(Y, sampname, chr, ref, mapp, gc, cov_thresh = c(20, 4000),
        length_thresh = c(20, 2000), mapp_thresh = 0.9, gc_thresh = c(20, 80))
    Y_qc <- qcObj$Y_qc; sampname_qc <- qcObj$sampname_qc; gc_qc <- qcObj$gc_qc
    mapp_qc <- qcObj$mapp_qc; ref_qc <- qcObj$ref_qc; qcmat <- qcObj$qcmat
    # --- Normobj1 [] ---
    # Key functions: normalize
    normObj <- normalize(Y_qc, gc_qc, K = 1:9)
    Yhat <- normObj$Yhat; AIC <- normObj$AIC; BIC <- normObj$BIC
    RSS <- normObj$RSS; K <- normObj$K
    # --- Normobj2 [] ---
    # Key functions: normalize2
    ## normObj <- normalize2(Y_qc, gc_qc, K = 1:9, normal_index=seq(1,45,2))
    ## Yhat <- normObj$Yhat; AIC <- normObj$AIC; BIC <- normObj$BIC
    ## RSS <- normObj$RSS; K <- normObj$K
    # --- Choiceofk [] ---
    # Key functions: choiceofK
    ## choiceofK(AIC, BIC, RSS, K, filename = paste(projectname, "_", chr,
    ##     "_choiceofK", ".pdf", sep = ""))
    # --- Segment1 [] ---
    # Key functions: segment
    optK = K[which.max(BIC)]
    finalcall <- segment(Y_qc, Yhat, optK = optK, K = K, sampname_qc,
        ref_qc, chr, lmax = 200, mode = "integer")
    finalcall
    # --- Segment2 [] ---
    # Key functions: image
    ## write.table(finalcall, file = paste(projectname, '_', chr, '_', optK,
    ##             '_CODEX_frac.txt', sep=''), sep='\t', quote=FALSE, row.names=FALSE)
    ## save.image(file = paste(projectname, '_', chr, '_image', '.rda', sep=''),
    ##      compress='xz')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_codex_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_codex_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_codex_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CODEX:", paste0("    codex: ", packageVersion("CODEX"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_codex_results.csv
    touch ${prefix}_codex_output.rds
    echo "BIOC_CODEX:" > versions.yml
    echo "    codex: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CODEX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CODEX(ch_input)

    emit:
    results  = BIOC_CODEX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CODEX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CODEX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CODEX.out.versions  // channel: path(versions.yml)
}
