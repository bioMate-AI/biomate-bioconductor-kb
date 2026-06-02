#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pepStat
// Statistical analysis of peptide microarrays
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pepStat/inst/doc/pepStat.R
// Upstream  : Pviz, pepDat
// Downstream: none
//
// Install: BiocManager::install("pepStat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PEPSTAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pepstat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pepstat:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pepstat:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(phyloseq)

    output:
    tuple val(meta), path("${meta.id}_pepstat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pepstat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pepstat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pepStat)
    library(jsonlite)


    # --- Include=false [] ---
    # Key functions: set, makePeptideSet, plotArrayImage, plotArrayResiduals, create_db, pepDat, empty
    library(knitr)
    opts_chunk$set(tidy=FALSE)

    ## ----loading-libraries, message=FALSE-----------------------------------------
    library(pepDat)
    library(pepStat)

    ## ----read-data----------------------------------------------------------------
    mapFile <- system.file("extdata/mapping.csv", package = "pepDat")
    dirToParse <- system.file("extdata/gpr_samples", package = "pepDat")

    # --- Summarize Peptide Set [] ---
    # Key functions: summarizePeptides
    psSet <- summarizePeptides(pSet, summary = "mean", position = pep_custom)

    # --- Normalize Array [] ---
    # Key functions: normalizeArray
    pnSet <- normalizeArray(psSet)

    # --- Sliding Mean [] ---
    # Key functions: slidingMean
    psmSet <- slidingMean(pnSet, width = 9)

    ## ----slidingMean-splitbyclade-------------------------------------------------
    psmSetAg <- slidingMean(pnSet, width = 9, split.by.clade = FALSE)

    # --- Make Calls [] ---
    # Key functions: makeCalls, treatment
    calls <- makeCalls(psmSet, freq = TRUE, group = "treatment",
                         cutoff = .1, method = "FDR", verbose = TRUE)

    ## ----makeCalls-aggregate------------------------------------------------------
    callsAg <- makeCalls(psmSetAg, freq = TRUE, group = "treatment",
                         cutoff = .1, method = "FDR")

    # --- Restab [] ---
    # Key functions: restab, plot_inter, plot_clade
    summary <- restab(psmSet, calls)
    head(summary)

    ## ----plot-inter, fig.height=4, message=FALSE----------------------------------
    library(Pviz)
    summaryAg <- restab(psmSetAg, callsAg)
    plot_inter(summaryAg)

    ## ----plot-clade, fig.height=4-------------------------------------------------
    plot_clade(summary, clade=c("A", "M", "CRF01"), from = 300, to = 520)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pepstat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pepstat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pepstat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PEPSTAT:", paste0("    pepstat: ", packageVersion("pepStat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pepstat_results.csv
    touch ${prefix}_pepstat_output.rds
    echo "BIOC_PEPSTAT:" > versions.yml
    echo "    pepstat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PEPSTAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(phyloseq) ]

    main:
    BIOC_PEPSTAT(ch_input)

    emit:
    results  = BIOC_PEPSTAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PEPSTAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PEPSTAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PEPSTAT.out.versions  // channel: path(versions.yml)
}
