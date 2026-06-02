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

    # --- BAM and BED Parsing [Data Preparation] ---
    # Key functions: getbambed
    dirPath <- system.file("extdata", package = "WES.1KG.WUGSC")
    bamFile <- list.files(dirPath, pattern = "*.bam$")
    bamdir <- file.path(dirPath, bamFile)
    sampname <- as.matrix(read.table(file.path(dirPath, "sampname")))
    bedFile <- file.path(dirPath, "chr22_400_to_500.bed")
    chr <- 22
    bambedObj <- getbambed(
        bamdir = bamdir, bedFile = bedFile,
        sampname = sampname, projectname = "CODEX_demo", chr = chr
    )

    # --- Coverage and Genomic Features [Feature Extraction] ---
    # Key functions: getcoverage, getgc, getmapp
    coverageObj <- getcoverage(bambedObj, mapqthres = 20)
    Y <- coverageObj$Y
    ref <- bambedObj$ref
    chr <- bambedObj$chr
    gc <- getgc(chr, ref)
    mapp <- getmapp(chr, ref)

    # --- Quality Control [Filtering] ---
    # Key functions: qc
    sampname <- bambedObj$sampname
    qcObj <- qc(
        Y = Y, sampname = sampname, chr = chr, ref = ref,
        mapp = mapp, gc = gc, cov_thresh = c(20, 4000),
        length_thresh = c(20, 2000), mapp_thresh = 0.9,
        gc_thresh = c(20, 80)
    )
    Y_qc <- qcObj$Y_qc
    sampname_qc <- qcObj$sampname_qc
    gc_qc <- qcObj$gc_qc
    mapp_qc <- qcObj$mapp_qc
    ref_qc <- qcObj$ref_qc

    # --- Normalization [Normalization] ---
    # Key functions: normalize
    normObj <- normalize(Y_qc, gc_qc, K = 1:9)
    Yhat <- normObj$Yhat
    AIC <- normObj$AIC
    BIC <- normObj$BIC
    K <- normObj$K

    # --- CNV Segmentation [Segmentation] ---
    # Key functions: segment
    optK <- K[which.max(BIC)]
    finalcall <- segment(
        Y_qc = Y_qc, Yhat = Yhat, optK = optK, K = K,
        sampname_qc = sampname_qc, ref_qc = ref_qc,
        chr = chr, lmax = 200, mode = "integer"
    )


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
