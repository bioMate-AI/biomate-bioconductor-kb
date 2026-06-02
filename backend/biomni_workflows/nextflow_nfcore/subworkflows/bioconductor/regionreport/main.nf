#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: regionReport
// Generate HTML or PDF reports to explore a set of regions such as the results from annotation-agnosti
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/regionReport/inst/doc/bumphunterExample.R
// Upstream  : GenomicRanges, RefManageR, bumphunter, derfinder, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("regionReport")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGIONREPORT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regionreport"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regionreport:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-regionreport:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_regionreport_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regionreport_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regionreport_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- 'Findregions' [] ---
    # Key functions: unlist
    ## Load bumphunter
    library("bumphunter")
    ## Create data from the vignette
    pos <- list(
        pos1 = seq(1, 1000, 35),
    # --- 'Buildgranges' [] ---
    # Key functions: GRanges, IRanges, seqlengths, getChromInfoFromUCSC
    library("GenomicRanges")
    ## Build GRanges with sequence lengths
    regions <- GRanges(
        seqnames = tab$table$chr,
        IRanges(start = tab$table$start, end = tab$table$end),
    # --- 'Reproducibility' [] ---
    # Key functions: time, session_info
    ## Date generated:
    Sys.time()
    ## Time spent making this page:
    proc.time()
    ## R and packages info:

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regionreport_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regionreport_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regionreport_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGIONREPORT:", paste0("    regionreport: ", packageVersion("regionReport"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regionreport_results.csv
    touch ${prefix}_regionreport_output.rds
    echo "BIOC_REGIONREPORT:" > versions.yml
    echo "    regionreport: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGIONREPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_REGIONREPORT(ch_input)

    emit:
    results  = BIOC_REGIONREPORT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGIONREPORT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGIONREPORT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGIONREPORT.out.versions  // channel: path(versions.yml)
}
