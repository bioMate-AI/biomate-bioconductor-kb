#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: a4
// Umbrella package is available for the entire Automated Affymetrix Array Analysis suite of package.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/a4/inst/doc/a4vignette.R
// Upstream  : ALL, GOstats, MLP, Rgraphviz, nlcv
// Downstream: none
//
// Install: BiocManager::install("a4")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_A4 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-a4"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-a4:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-a4:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_a4_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_a4_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_a4_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(a4)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: data
    library(a4)
    require(ALL)
    data(ALL, package = "ALL")
    # --- Quality control and filtering [] ---
    # Key functions: pData, exprs, featureData, plotCombMultSamples, off, computeLogRatio, interaction, factor
    load(system.file("extdata", "esetExampleTimeCourse.rda", package = "a4"))
      logRatioEset <- computeLogRatio(esetExampleTimeCourse, within = "hours",
        reference = list(var = "compound", level = "DMSO"))
      # re-order
      idx <- order(pData(logRatioEset)$compound, pData(logRatioEset)$hours)
    # --- Seed analysis [] ---
    # Key functions: seed, simulateData, addGeneInfo, intersect, factor, spectralMap, filterVarInt, tTest
    tabLimmaSel <- tabLimma[,c("SYMBOL", "logFC", "AveExpr","P.Value","adj.P.Val", "GENENAME" )]
      tabLimmaSel[, "GENENAME"] <- substr(tabLimmaSel[,"GENENAME"], 1, 38)
      dData <- data.frame(Gene = tabLimmaSel[, 1], tabLimmaSel[,-1],
          stringsAsFactors = FALSE,  row.names = NULL)
      hData <- data.frame(Gene = generateEntrezIdLinks(tabLimma[,"ENTREZID"]))
    # --- Differential expression analysis [] ---
    # Key functions: topTable, xtable, pamClass, rfClass, lassoClass
    resultRF <- rfClass(selBcrAblOrNeg, "mol.biol")
    plot(resultRF, which = 2)
    featResultRF <- topTable(resultRF, n = 15)
    xtable(head(featResultRF$topList),
        caption = "Features selected by Random Forest variable importance.")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_a4_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_a4_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_a4_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_A4:", paste0("    a4: ", packageVersion("a4"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_a4_results.csv
    touch ${prefix}_a4_output.rds
    echo "BIOC_A4:" > versions.yml
    echo "    a4: 0.0.0" >> versions.yml
    """
}


workflow BIOC_A4_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_A4(ch_input)

    emit:
    results  = BIOC_A4.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_A4.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_A4.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_A4.out.versions  // channel: path(versions.yml)
}
