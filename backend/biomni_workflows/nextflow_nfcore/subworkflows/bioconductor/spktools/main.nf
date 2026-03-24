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

    # --- Data [] ---
    # Key functions: data
    data(affy)
    object <- affy
    # --- Spkslope [] ---
    # Key functions: spkSlope
    spkSlopeOut <- spkSlope(object, label, pch="+")
    # --- Spkdensity [] ---
    # Key functions: spkDensity
    spkDensity(object, spkSlopeOut, cuts=TRUE, label)
    # --- Spkbox [] ---
    # Key functions: spkBox, plotSpkBox, summarySpkBox
    spkBoxOut <- spkBox(object, spkSlopeOut, fc)
    plotSpkBox(spkBoxOut, fc, ylim=c(-1.5,2.5))
    sbox <- summarySpkBox(spkBoxOut)
    # --- Spkma [] ---
    # Key functions: spkMA
    spkMA(object, spkSlopeOut, fc, label=label, ylim=c(-2.5,2.5))
    # --- Spkvar [] ---
    # Key functions: spkVar, frame
    vtmp <- spkVar(object)
    sv <- as.numeric(vtmp[,2][-nrow(vtmp)])
    bin <- c("Low", "Med", "High")
    bins <- bin[spkSlopeOut$breaks[2,]]
    tab1 <- data.frame(NominalConc=2^spkSlopeOut$breaks[1,],
    # --- Xtable [] ---
    # Key functions: xtable
    library(xtable)
    tab1x <- xtable(tab1)
    print(tab1x)
    # --- Round [] ---
    # Key functions: spkAccSD, spkPot, frame
    AccuracySlope <- round(spkSlopeOut$slopes[-1], digits=2)
    AccuracySD <- round(spkAccSD(object, spkSlopeOut), digits=2)
    pot <- spkPot(object, spkSlopeOut, AccuracySlope, AccuracySD,
                  precisionQuantile=.995)
    PrecisionSD <- round(sbox$madFC[1:3], digits=2)
    # --- Xtable [] ---
    # Key functions: xtable
    tab2x <- xtable(tab2)
    print(tab2x)
    # --- Round [] ---
    # Key functions: spkBal, spkAnova
    bals <- round(spkBal(object))
    anv <- round(spkAnova(object), digits=2)
    tab3 <- t(c(anv,bals))
    # --- Xtable [] ---
    # Key functions: xtable
    tab3x <- xtable(tab3)
    print(tab3x)

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
