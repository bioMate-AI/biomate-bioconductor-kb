#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gcapc
// Peak calling for ChIP-seq data with consideration of potential GC bias in sequencing reads. GC bias 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gcapc/inst/doc/gcapc.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("gcapc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GCAPC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gcapc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gcapc:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gcapc:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gcapc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gcapc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gcapc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gcapc)
    library(jsonlite)

    # --- markdown [] ---
    # Key functions: markdown
    BiocStyle::markdown()
    knitr::opts_chunk$set(dev="png",fig.show="hold",
    set.seed(1)
    # --- read5end Coverage [] ---
    # Key functions: read5endCoverage
    cov <- read5endCoverage(bam)
    # --- bind Width [] ---
    # Key functions: bindWidth
    bdw <- bindWidth(cov, range=c(50L,300L), step=10L)
    # --- gc Effects [] ---
    # Key functions: gcEffects
    layout(matrix(1:2,1,2))
    gcb <- gcEffects(cov, bdw, sampling=c(0.25,1), plot=TRUE, model='poisson')
    # --- gcapc Peaks [] ---
    # Key functions: gcapcPeaks
    layout(matrix(1:2,1,2))
    peaks <- gcapcPeaks(cov, gcb, bdw, plot=TRUE, permute=100L)
    peaks <- gcapcPeaks(cov, gcb, bdw, plot=TRUE, permute=50L)
    # --- refine Peaks [] ---
    # Key functions: refinePeaks
    newpeaks <- refinePeaks(cov, gcb, bdw, peaks=peaks, permute=50L)
    plot(newpeaks$es,newpeaks$newes,xlab='old score',ylab='new score')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gcapc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gcapc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gcapc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GCAPC:", paste0("    gcapc: ", packageVersion("gcapc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gcapc_results.csv
    touch ${prefix}_gcapc_output.rds
    echo "BIOC_GCAPC:" > versions.yml
    echo "    gcapc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GCAPC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GCAPC(ch_input)

    emit:
    results  = BIOC_GCAPC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GCAPC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GCAPC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GCAPC.out.versions  // channel: path(versions.yml)
}
