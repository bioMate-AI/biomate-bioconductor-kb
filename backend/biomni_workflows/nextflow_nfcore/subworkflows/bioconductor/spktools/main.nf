#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: spkTools
// The package contains functions that can be used to compare expression measures on different array pl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/spkTools/inst/doc/spkDoc.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("spkTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPKTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spktools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spktools:1.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spktools:1.62.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spktools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spktools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spktools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(spkTools)
    library(jsonlite)

    # --- Density Analysis [] ---
    # Key functions: spkDensity
    label <- "Affymetrix"
    spkDensity(object, spkSlopeOut, cuts=TRUE, label)


    # --- Fold Change and Boxplot Analysis [] ---
    # Key functions: spkBox, plotSpkBox, summarySpkBox
    fc <- 2
    spkBoxOut <- spkBox(object, spkSlopeOut, fc)
    plotSpkBox(spkBoxOut, fc, ylim=c(-1.5, 2.5))
    sbox <- summarySpkBox(spkBoxOut)


    # --- MA Plotting [] ---
    # Key functions: spkMA
    fc <- 2
    label <- "Affymetrix"
    spkMA(object, spkSlopeOut, fc, label=label, ylim=c(-2.5, 2.5))


    # --- Variance and Accuracy Assessment [] ---
    # Key functions: spkVar, spkAccSD, spkPot
    vtmp <- spkVar(object)
    sv <- as.numeric(vtmp[, 2][-nrow(vtmp)])
    bin <- c("Low", "Med", "High")
    bins <- bin[spkSlopeOut$breaks[2, ]]
    AccuracySlope <- round(spkSlopeOut$slopes[-1], digits=2)
    AccuracySD <- round(spkAccSD(object, spkSlopeOut), digits=2)
    pot <- spkPot(
        object, spkSlopeOut, AccuracySlope, AccuracySD,
        precisionQuantile=0.995
    )


    # --- ANOVA and Balance Analysis [] ---
    # Key functions: spkBal, spkAnova
    bals <- round(spkBal(object))
    anv <- round(spkAnova(object), digits=2)
    tab3 <- t(c(anv, bals))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spktools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spktools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spktools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPKTOOLS:", paste0("    spktools: ", packageVersion("spkTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spktools_results.csv
    touch ${prefix}_spktools_output.rds
    echo "BIOC_SPKTOOLS:" > versions.yml
    echo "    spktools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPKTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPKTOOLS(ch_input)

    emit:
    results  = BIOC_SPKTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPKTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPKTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPKTOOLS.out.versions  // channel: path(versions.yml)
}
