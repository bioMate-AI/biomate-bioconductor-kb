#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IsoformSwitchAnalyzeR
// Analysis of alternative splicing and isoform switches with predicted functional consequences (e.g. g
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IsoformSwitchAnalyzeR/inst/doc/IsoformSwitchAnalyzeR.R
// Upstream  : VennDiagram
// Downstream: none
//
// Install: BiocManager::install("IsoformSwitchAnalyzeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOFORMSWITCHANALYZER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-isoformswitchanalyzer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-isoformswitchanalyzer:2.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-isoformswitchanalyzer:2.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_isoformswitchanalyzer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_isoformswitchanalyzer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_isoformswitchanalyzer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IsoformSwitchAnalyzeR)
    library(jsonlite)

    # --- Filtering and Part 1 Analysis [] ---
    # Key functions: subsetSwitchAnalyzeRlist, isoformSwitchAnalysisPart1
    data("exampleSwitchList")
    exampleSwitchList <- subsetSwitchAnalyzeRlist(
        switchAnalyzeRlist = exampleSwitchList,
        subset = abs(exampleSwitchList$isoformFeatures$dIF) > 0.4
    )
    exampleSwitchList <- isoformSwitchAnalysisPart1(
        switchAnalyzeRlist   = exampleSwitchList,
        outputSequences      = FALSE,
        prepareForWebServers = FALSE
    )


    # --- Functional Consequences and Part 2 Analysis [] ---
    # Key functions: isoformSwitchAnalysisPart2, extractSwitchSummary
    exampleSwitchList <- isoformSwitchAnalysisPart2(
        switchAnalyzeRlist        = exampleSwitchList,
        n                         = 10,
        removeNoncodinORFs        = TRUE,
        pathToCPC2resultFile      = system.file(
            "extdata/cpc2_result.txt", package = "IsoformSwitchAnalyzeR"
        ),
        pathToPFAMresultFile      = system.file(
            "extdata/pfam_results.txt", package = "IsoformSwitchAnalyzeR"
        ),
        pathToIUPred2AresultFile  = system.file(
            "extdata/iupred2a_result.txt.gz", package = "IsoformSwitchAnalyzeR"
        ),
        pathToSignalPresultFile   = system.file(
            "extdata/signalP_results.txt", package = "IsoformSwitchAnalyzeR"
        ),
        outputPlots               = FALSE
    )
    summary_df <- extractSwitchSummary(exampleSwitchList)


    # --- Visualization and Enrichment Analysis [] ---
    # Key functions: switchPlot, extractSwitchOverlap, extractConsequenceSummary
    data("exampleSwitchListAnalyzed")
    switchPlot(
        exampleSwitchListAnalyzed,
        gene='ZAK',
        condition1 = 'COAD_ctrl',
        condition2 = 'COAD_cancer'
    )
    overlap <- extractSwitchOverlap(
        exampleSwitchListAnalyzed,
        filterForConsequences=TRUE,
        plotIsoforms = FALSE
    )
    conseq_summary <- extractConsequenceSummary(
        exampleSwitchListAnalyzed,
        consequencesToAnalyze='all',
        plotGenes = FALSE,
        asFractionTotal = FALSE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_isoformswitchanalyzer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_isoformswitchanalyzer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_isoformswitchanalyzer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISOFORMSWITCHANALYZER:", paste0("    isoformswitchanalyzer: ", packageVersion("IsoformSwitchAnalyzeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isoformswitchanalyzer_results.csv
    touch ${prefix}_isoformswitchanalyzer_output.rds
    echo "BIOC_ISOFORMSWITCHANALYZER:" > versions.yml
    echo "    isoformswitchanalyzer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISOFORMSWITCHANALYZER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISOFORMSWITCHANALYZER(ch_input)

    emit:
    results  = BIOC_ISOFORMSWITCHANALYZER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISOFORMSWITCHANALYZER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISOFORMSWITCHANALYZER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISOFORMSWITCHANALYZER.out.versions  // channel: path(versions.yml)
}
