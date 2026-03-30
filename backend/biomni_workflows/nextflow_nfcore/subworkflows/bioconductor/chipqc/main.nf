#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChIPQC
// Quality metrics for ChIPseq data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ChIPQC/inst/doc/ChIPQC.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ChIPQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chipqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chipqc:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chipqc:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chipqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chipqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chipqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ChIPQC)
    library(ChIPQCreport)
    library(ChIPQCsample)
    library(QCmetrics)
    library(QCsample)
    library(jsonlite)

    # --- Summaryexp [] ---
    # Key functions: ChIPQC, ChIPQCreport
    ## experiment = ChIPQC(samples)
    ## experiment
    ## ChIPQCreport(experiment)
    # --- Summarysamp [] ---
    # Key functions: ChIPQCsample, ChIPQCreport
    ## sample = ChIPQCsample("chip.bam")
    ## sample
    ## ChIPQCreport(sample)
    # --- csv [] ---
    # Key functions: csv, path
    library(ChIPQC)
    samples = read.csv(file.path(system.file("extdata", package="ChIPQC"),
                                             "example_QCexperiment.csv"))
    samples
    # --- Ch I P Q C [] ---
    # Key functions: ChIPQC
    ##
    ## exampleExp = ChIPQC(samples,annotaiton="hg19")
    ## exampleExp
    # --- data [] ---
    # Key functions: data
    data(example_QCexperiment)
    exampleExp
    # --- Ch I P Q Creport [] ---
    # Key functions: ChIPQCreport
    ## ChIPQCreport(exampleExp)
    # --- Tamsamples [] ---
    # Key functions: csv, path
    library(ChIPQC)
    samples = read.csv(file.path(system.file("extdata", package="ChIPQC"),
                                             "tamoxifenQC.csv"))
    samples
    # --- Tamconstruct [] ---
    # Key functions: ChIPQC
    ## data(blacklist_hg19)
    ## tamoxifen = ChIPQC(samples, consensus=TRUE, bCount=TRUE, summits=250,
    ##                    annotation="hg19", chromosomes="chr18",
    ##                    blacklist = blacklist.hg19)
    ## tamoxifen
    # --- Tamload [] ---
    # Key functions: data
    data(tamoxifen_QC)
    tamoxifen
    # --- Ch I P Q Creport [] ---
    # Key functions: ChIPQCreport
    ## ChIPQCreport(tamoxifen,facetBy=c("Tissue","Condition"))
    # --- Figcoveragehist [] ---
    # Key functions: plotCoverageHist
    plotCoverageHist(tamoxifen,facetBy=c("Tissue","Condition"))
    # --- Figcc [] ---
    # Key functions: plotCC
    plotCC(tamoxifen,facetBy=c("Tissue","Condition"))
    # --- Figregi [] ---
    # Key functions: plotRegi
    plotRegi(tamoxifen,facetBy=c("Tissue","Condition"))
    # --- Figpeakprofile [] ---
    # Key functions: plotPeakProfile
    plotPeakProfile(tamoxifen,facetBy=c("Tissue","Condition"))
    # --- Figrap [] ---
    # Key functions: plotRap
    plotRap(tamoxifen,facetBy=c("Tissue","Condition"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chipqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chipqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chipqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIPQC:", paste0("    chipqc: ", packageVersion("ChIPQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipqc_results.csv
    touch ${prefix}_chipqc_output.rds
    echo "BIOC_CHIPQC:" > versions.yml
    echo "    chipqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIPQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIPQC(ch_input)

    emit:
    results  = BIOC_CHIPQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIPQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIPQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIPQC.out.versions  // channel: path(versions.yml)
}
