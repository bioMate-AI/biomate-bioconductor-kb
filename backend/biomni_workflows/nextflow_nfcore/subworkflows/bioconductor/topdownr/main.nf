#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: topdownr
// The topdownr package allows automatic and systemic investigation of fragment conditions. It creates 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/topdownr/inst/doc/analysis.R
// Upstream  : BiocStyle, ggplot2, ranger, topdownrdata
// Downstream: topdownrdata
//
// Install: BiocManager::install("topdownr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TOPDOWNR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-topdownr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-topdownr:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-topdownr:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_topdownr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_topdownr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_topdownr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(topdownr)
    library(jsonlite)

    # --- Data Import [topdownr] ---
    # Key functions: readTopDownFiles
    H <- 1.0078250321
    myoglobin <- readTopDownFiles(
        path = topdownrdata::topDownDataPath("myoglobin"),
        type = c("a", "b", "c", "x", "y", "z"),
        adducts = data.frame(
            mass = c(-H, H),
            to = c("c", "z"),
            name = c("cmH", "zpH")
        ),
        modifications = "Met-loss",
        neutralLoss = NULL,
        tolerance = 5e-6,
        conditions = "FilterString"
    )

    # --- Quality Control and Filtering [topdownr] ---
    # Key functions: filterInjectionTime, filterCv, filterIntensity
    myoglobin <- filterInjectionTime(
        myoglobin,
        maxDeviation = log2(3),
        keepTopN = 2
    )
    myoglobin <- filterCv(myoglobin, threshold = 30)
    myoglobin <- filterIntensity(myoglobin, threshold = 0.1)

    # --- Data Aggregation [topdownr] ---
    # Key functions: aggregate, summary
    myoglobin_agg <- aggregate(myoglobin)
    agg_summary <- summary(myoglobin_agg)
    n_fragments <- agg_summary$Fragments

    # --- Condition Selection [topdownr] ---
    # Key functions: bestConditions
    myoglobin_ncb <- as(myoglobin_agg, "NCBSet")
    best_conds <- bestConditions(myoglobin_ncb, n = 3)

    # --- Fragmentation Mapping [topdownr] ---
    # Key functions: fragmentationMap
    sel <- myoglobin_ncb$Mz == 707.3 &
        myoglobin_ncb$AgcTarget == 1e6 &
        (myoglobin_ncb$EtdReagentTarget == 1e7 &
         !is.na(myoglobin_ncb$EtdReagentTarget))
    myoglobin_sub <- myoglobin_ncb[, sel]
    fragmentationMap(
        myoglobin_sub,
        nCombinations = 10,
        labels = seq_len(ncol(myoglobin_sub))
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_topdownr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_topdownr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_topdownr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TOPDOWNR:", paste0("    topdownr: ", packageVersion("topdownr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_topdownr_results.csv
    touch ${prefix}_topdownr_output.rds
    echo "BIOC_TOPDOWNR:" > versions.yml
    echo "    topdownr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TOPDOWNR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TOPDOWNR(ch_input)

    emit:
    results  = BIOC_TOPDOWNR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TOPDOWNR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TOPDOWNR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TOPDOWNR.out.versions  // channel: path(versions.yml)
}
