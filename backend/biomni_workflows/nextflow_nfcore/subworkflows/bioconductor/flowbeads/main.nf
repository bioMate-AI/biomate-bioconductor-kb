#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowBeads
// This package extends flowCore to provide functionality specific to bead data. One of the goals of th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowBeads/inst/doc/HowTo-flowBeads.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("flowBeads")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWBEADS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowbeads"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowbeads:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowbeads:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowbeads_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowbeads_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowbeads_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BeadFlowFrame)
    library(Fluorochromes)
    library(jsonlite)

    # --- Mef [] ---
    # Key functions: xtable, Fluorochromes
    library(xtable)
    data(dakomef)
    print(xtable(dakomef,
                 caption=
                 "
    # --- Loadbeads [] ---
    # Key functions: BeadFlowFrame
    ## beads1 <- BeadFlowFrame(fcs.filename=system.file('extdata', 'beads1.fcs', package='flowBeads'),
    ##                         bead.filename=system.file('extdata', 'dakomef.csv', package='flowBeads'))
    ## beads2 <- BeadFlowFrame(fcs.filename=system.file('extdata', 'beads2.fcs', package='flowBeads'),
    ##                         bead.filename=system.file('extdata', 'dakomef.csv', package='flowBeads'))
    # --- Fastloadbeads [] ---
    # Key functions: data
    data(beads1)
    data(beads2)
    # --- Beads2 [] ---
    # Key functions: getDate, getParams, getMEFparams
    length(beads1)
    getDate(beads1)
    getParams(beads1)
    getMEFparams(beads1)
    # --- Gatebeads [] ---
    # Key functions: gateBeads
    gbeads1 <- gateBeads(beads1)
    gbeads2 <- gateBeads(beads2)
    # --- Howto Flowbeads.Rnw:249 250 [] ---
    # Key functions: getClusteringStats
    getClusteringStats(gbeads1)[,,1]
    # --- Howto Flowbeads.Rnw:253 255 [] ---
    # Key functions: getClusteringStats
    beads1.mean.fi.APC <- getClusteringStats(gbeads1)['mean.fi','APC',]
    beads2.mean.fi.APC <- getClusteringStats(gbeads2)['mean.fi','APC',]
    # --- Howto Flowbeads.Rnw:263 265 [] ---
    # Key functions: getMEFtransform
    mef.transform <- getMEFtransform(gbeads1)
    names(mef.transform)
    # --- Plotmefrepeatability [] ---
    # Key functions: getTransformFunction, getMEFtransform, fun
    old.par <- par(no.readonly=T)
    par(mfrow=c(1,2))
    plot(getTransformFunction(beads1)(beads1.mean.fi.APC),
         getTransformFunction(beads2)(beads2.mean.fi.APC),
         xlim=c(0,5),
    # --- Tomef [] ---
    # Key functions: toMEF
    ## toMEF(gbeads1, flow.data)
    # --- Howto Flowbeads.Rnw:326 328 [] ---
    # Key functions: relativeNormalise
    relative.transforms <- relativeNormalise(gbeads1, gbeads2)
    names(relative.transforms)
    # --- Howto Flowbeads.Rnw:331 335 [] ---
    # Key functions: getTransformFunction, getClusteringStats, fun
    fun <- relative.transforms$APC$fun
    mfi1 <- getTransformFunction(gbeads1)(getClusteringStats(gbeads1)['mean.fi','APC',])
    mfi2 <- getTransformFunction(gbeads2)(getClusteringStats(gbeads2)['mean.fi','APC',])
    fun.mfi1 <- fun(mfi1)
    # --- Generatereport [] ---
    # Key functions: generateReport
    ## generateReport(gbeads1, output.file='report.html')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowbeads_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowbeads_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowbeads_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWBEADS:", paste0("    flowbeads: ", packageVersion("flowBeads"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowbeads_results.csv
    touch ${prefix}_flowbeads_output.rds
    echo "BIOC_FLOWBEADS:" > versions.yml
    echo "    flowbeads: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWBEADS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWBEADS(ch_input)

    emit:
    results  = BIOC_FLOWBEADS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWBEADS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWBEADS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWBEADS.out.versions  // channel: path(versions.yml)
}
