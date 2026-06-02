#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: kebabs
// The package provides functionality for kernel-based analysis of DNA, RNA, and amino acid sequences v
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/kebabs/inst/doc/kebabs.R
// Upstream  : BSgenome, apcluster
// Downstream: procoil
//
// Install: BiocManager::install("kebabs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KEBABS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-kebabs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-kebabs:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-kebabs:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_kebabs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_kebabs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_kebabs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(kebabs)
    library(jsonlite)


    # --- Init [] ---
    # Key functions: set, packageDescription, substr, kebabs
    options(width=70)
    options(useFancyQuotes=FALSE)
    knitr::opts_knit$set(width=70)
    set.seed(0)
    library(kebabs)
    kebabsVersion <- packageDescription("kebabs")$Version
    kebabsDateRaw <- packageDescription("kebabs")$Date
    kebabsDateYear <- as.numeric(substr(kebabsDateRaw, 1, 4))
    kebabsDateMonth <- as.numeric(substr(kebabsDateRaw, 6, 7))
    kebabsDateDay <- as.numeric(substr(kebabsDateRaw, 9, 10))
    kebabsDate <- paste(month.name[kebabsDateMonth], " ",
                         kebabsDateDay, ", ",
                         kebabsDateYear, sep="")

    # --- Eval=false [] ---
    # Key functions: help
    #  help(kebabs)

    ## -------------------------------------------------------------------
    data(TFBS)

    ## -------------------------------------------------------------------
    enhancerFB
    length(enhancerFB)

    # --- Eval=false [] ---
    # Key functions: spectrumKernel, mismatchKernel, gappyPairKernel
    #  ?kbsvm

    ## -------------------------------------------------------------------
    specK2 <- spectrumKernel(k=2)

    ## -------------------------------------------------------------------
    specK2 <- spectrumKernel(k=2, normalized=FALSE)

    ## -------------------------------------------------------------------
    mismK3M1 <- mismatchKernel(k=3, m=1)

    ## -------------------------------------------------------------------
    gappyK1M2 <- gappyPairKernel(k=1, m=2)

    ## -------------------------------------------------------------------

    # --- Eval=false [] ---
    # Key functions: linearKernel, annotationMetadata, gappyPairKernel
    #  km <- linearKernel(erK2)
    #  km
    #  kma <- linearKernel(erK2a)
    #  kma

    ## -------------------------------------------------------------------
    data(CCoil)
    ccseq
    ccannot[1:3]
    head(yCC)
    yCC <- as.numeric(yCC)
    ## delete annotation metadata
    annotationMetadata(ccseq) <- NULL
    annotationMetadata(ccseq)
    gappy <- gappyPairKernel(k=1, m=10)

    # --- Eval=false [] ---
    # Key functions: heatmap, spectrumKernel, specK2, getKernelMatrix
    #  heatmap(km, symm=TRUE)

    ## -------------------------------------------------------------------
    specK2 <- spectrumKernel(k=2)
    km <- specK2(x=enhancerFB)
    km[1:3, 1:3]

    ## -------------------------------------------------------------------
    km <- getKernelMatrix(specK2, x=enhancerFB, selx=c(1, 4, 25, 137, 300))
    km

    ## -------------------------------------------------------------------
    seqs1 <- enhancerFB[1:200]
    seqs2 <- enhancerFB[201:500]
    km <- getKernelMatrix(specK2, x=seqs1, y=seqs2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_kebabs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_kebabs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_kebabs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KEBABS:", paste0("    kebabs: ", packageVersion("kebabs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kebabs_results.csv
    touch ${prefix}_kebabs_output.rds
    echo "BIOC_KEBABS:" > versions.yml
    echo "    kebabs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KEBABS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KEBABS(ch_input)

    emit:
    results  = BIOC_KEBABS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KEBABS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KEBABS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KEBABS.out.versions  // channel: path(versions.yml)
}
