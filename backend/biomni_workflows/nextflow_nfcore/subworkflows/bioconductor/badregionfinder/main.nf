#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BadRegionFinder
// BadRegionFinder is a package for identifying regions with a bad, acceptable and good coverage in seq
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BadRegionFinder/inst/doc/BadRegionFinder.R
// Upstream  : biomaRt
// Downstream: none
//
// Install: BiocManager::install("BadRegionFinder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BADREGIONFINDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-badregionfinder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-badregionfinder:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-badregionfinder:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_badregionfinder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_badregionfinder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_badregionfinder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BadRegionFinder)
    library(jsonlite)

    # --- 10 [] ---
    # Key functions: useMart
    library(biomaRt)
    mart = useMart(biomart="ENSEMBL_MART_ENSEMBL",host="grch37.ensembl.org",
                   path="/biomart/martservice",dataset="hsapiens_gene_ensembl")
    mart
    # --- 11 [] ---
    # Key functions: reportBadRegionsSummary
    badCoverageSummary <- reportBadRegionsSummary(threshold1, threshold2, percentage1,
                                                  percentage2, coverage_indicators_2, mart, "")
    badCoverageSummary
    # --- 12 [] ---
    # Key functions: reportBadRegionsDetailed
    coverage_indicators_temp <- reportBadRegionsDetailed(threshold1, threshold2, percentage1,
                                                         percentage2, coverage_indicators_2, "",
                                                         samples, "")
    coverage_indicators_temp[[2]]
    # --- 13 [] ---
    # Key functions: reportBadRegionsGenes
    badCoverageOverview <- reportBadRegionsGenes(threshold1, threshold2, percentage1, percentage2,
                                                 badCoverageSummary, "")
    badCoverageOverview
    # --- 13 [] ---
    # Key functions: plotSummary
    plotSummary(threshold1, threshold2, percentage1, percentage2, badCoverageSummary, "")
    # --- 14 [] ---
    # Key functions: plotDetailed
    plotDetailed(threshold1, threshold2, percentage1, percentage2, coverage_indicators_temp, "")
    # --- 15 [] ---
    # Key functions: plotSummaryGenes
    plotSummaryGenes(threshold1, threshold2, percentage1, percentage2, badCoverageOverview, "")
    # --- 16 [] ---
    # Key functions: determineQuantiles
    quantiles <- c(0.5)
    coverage_summary2 <- determineQuantiles(coverage_summary, quantiles, "")
    coverage_summary2[[2]]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_badregionfinder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_badregionfinder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_badregionfinder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BADREGIONFINDER:", paste0("    badregionfinder: ", packageVersion("BadRegionFinder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_badregionfinder_results.csv
    touch ${prefix}_badregionfinder_output.rds
    echo "BIOC_BADREGIONFINDER:" > versions.yml
    echo "    badregionfinder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BADREGIONFINDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BADREGIONFINDER(ch_input)

    emit:
    results  = BIOC_BADREGIONFINDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BADREGIONFINDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BADREGIONFINDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BADREGIONFINDER.out.versions  // channel: path(versions.yml)
}
