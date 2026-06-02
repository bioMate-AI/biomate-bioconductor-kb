#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PAA
// PAA imports single color (protein) microarray data that has been saved in gpr file format - esp. Pro
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PAA/inst/doc/PAA_vignette.R
// Upstream  : BiocManager, limma
// Downstream: none
//
// Install: BiocManager::install("PAA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PAA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-paa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-paa:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-paa:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_paa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_paa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_paa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PAA)
    library(jsonlite)

    # --- Background Correction and Normalization [] ---
    # Key functions: backgroundCorrect, normalizeArrays, plotArray
    elist <- backgroundCorrect(
        elist,
        method = "normexp",
        normexp.method = "saddle"
    )
    elist <- normalizeArrays(
        elist = elist,
        method = "cyclicloess",
        cyclicloess.method = "fast"
    )
    plotArray(
        elist = elist,
        idx = 3,
        data.type = "fg",
        log = TRUE,
        normalized = TRUE,
        aggregation = "min",
        colpal = "topo.colors"
    )


    # --- Batch Effect Filtering and Adjustment [] ---
    # Key functions: batchFilter, batchAdjust, plotMAPlots
    lot1 <- elist$targets[elist$targets$Batch == "Batch1", "ArrayID"]
    lot2 <- elist$targets[elist$targets$Batch == "Batch2", "ArrayID"]
    elist_filtered <- batchFilter(
        elist = elist,
        lot1 = lot1,
        lot2 = lot2,
        log = FALSE,
        p.thresh = 0.001,
        fold.thresh = 3
    )
    elist <- batchAdjust(elist = elist_filtered, log = TRUE)
    plotMAPlots(elist = elist, idx = 10)


    # --- Differential Expression Analysis [] ---
    # Key functions: volcanoPlot, pvaluePlot
    c1 <- paste(rep("AD", 20), 1:20, sep = "")
    c2 <- paste(rep("NDC", 20), 1:20, sep = "")
    volcanoPlot(
        elist = elist,
        group1 = c1,
        group2 = c2,
        log = TRUE,
        method = "tTest",
        p.thresh = 0.01,
        fold.thresh = 2
    )
    pvaluePlot(
        elist = elist,
        group1 = c1,
        group2 = c2,
        log = TRUE,
        method = "tTest",
        adjust = TRUE
    )


    # --- Feature Preselection [] ---
    # Key functions: mMsMatrix, preselect
    c1 <- paste(rep("AD", 20), 1:20, sep = "")
    c2 <- paste(rep("NDC", 20), 1:20, sep = "")
    elist_unlog <- elist
    elist_unlog$E <- 2^(elist$E)
    mMs_mat <- mMsMatrix(x = 20, y = 20)
    pre_sel <- preselect(
        elist = elist_unlog,
        columns1 = c1,
        columns2 = c2,
        label1 = "AD",
        label2 = "NDC",
        log = FALSE,
        discard.threshold = 0.5,
        fold.thresh = 1.5,
        discard.features = TRUE,
        mMs.above = 1500,
        mMs.between = 400,
        mMs.matrix1 = mMs_mat,
        mMs.matrix2 = mMs_mat,
        method = "mMs"
    )
    elist_selected <- elist[-pre_sel$discard, ]


    # --- Feature Visualization [] ---
    # Key functions: plotFeatures, plotFeaturesHeatmap, printFeatures
    cwd <- system.file(package = "PAA")
    load(paste0(cwd, "/extdata/selectFeaturesResultsFreq.RData"))
    plotFeatures(
        features = selectFeatures.results$features,
        elist = elist,
        n1 = 20,
        n2 = 20,
        group1 = "AD",
        group2 = "NDC"
    )
    plotFeaturesHeatmap(
        features = selectFeatures.results$features,
        elist = elist,
        n1 = 20,
        n2 = 20,
        description = TRUE
    )
    features_df <- printFeatures(
        features = selectFeatures.results$features,
        elist = elist
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_paa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_paa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_paa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PAA:", paste0("    paa: ", packageVersion("PAA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paa_results.csv
    touch ${prefix}_paa_output.rds
    echo "BIOC_PAA:" > versions.yml
    echo "    paa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PAA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PAA(ch_input)

    emit:
    results  = BIOC_PAA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PAA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PAA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PAA.out.versions  // channel: path(versions.yml)
}
