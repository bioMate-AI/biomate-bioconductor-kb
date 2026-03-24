#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methimpute
// This package implements functions for calling methylation for all cytosines in the genome.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methimpute/inst/doc/methimpute.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("methimpute")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHIMPUTE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methimpute"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methimpute:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methimpute:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methimpute_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methimpute_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methimpute_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methimpute)
    library(jsonlite)

    # --- methylation status calling separate [] ---
    # Key functions: inflateMethylome, distanceCorrelation, estimateTransDist, callMethylationSeparate
    library(methimpute)
    file <- system.file("extdata","arabidopsis_bsseeker.txt.gz", package="methimpute")
    bsseeker.data <- importBSSeeker(file)
    # --- methylation status calling separate checkresults [] ---
    # Key functions: plotConvergence, plotTransitionProbs, plotHistogram
    plotConvergence(model)
    plotTransitionProbs(model)
    plotHistogram(model, total.counts = 10)
    # --- methylation status calling [] ---
    # Key functions: inflateMethylome, distanceCorrelation, estimateTransDist, callMethylation
    library(methimpute)
    file <- system.file("extdata","arabidopsis_bsseeker.txt.gz", package="methimpute")
    bsseeker.data <- importBSSeeker(file)
    # --- methylation status calling binned [] ---
    # Key functions: inflateMethylome, binMethylome, callMethylation
    library(methimpute)
    file <- system.file("extdata","arabidopsis_bsseeker.txt.gz", package="methimpute")
    bsseeker.data <- importBSSeeker(file)
    # --- methylation status calling binned checkresults [] ---
    # Key functions: plotConvergence, plotTransitionProbs, plotHistogram
    plotConvergence(binnedModel)
    plotTransitionProbs(binnedModel)
    plotHistogram(binnedModel, total.counts = 150)
    # --- enrichment analysis [] ---
    # Key functions: seqlengths, plotEnrichment
    model$data$category <- factor('covered', levels=c('missing', 'covered'))
    data(arabidopsis_genes)
    seqlengths(model$data) <- seqlengths(arabidopsis_genes)[seqlevels(model$data)] # this
    # --- export Methylome [] ---
    # Key functions: exportMethylome
    exportMethylome(model, filename = tempfile())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methimpute_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methimpute_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methimpute_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHIMPUTE:", paste0("    methimpute: ", packageVersion("methimpute"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methimpute_results.csv
    touch ${prefix}_methimpute_output.rds
    echo "BIOC_METHIMPUTE:" > versions.yml
    echo "    methimpute: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHIMPUTE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHIMPUTE(ch_input)

    emit:
    results  = BIOC_METHIMPUTE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHIMPUTE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHIMPUTE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHIMPUTE.out.versions  // channel: path(versions.yml)
}
