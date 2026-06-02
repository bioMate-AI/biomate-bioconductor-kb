#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: simPIC
// simPIC is a package for simulating single-cell ATAC-seq count data. It provides a user-friendly, wel
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/simPIC/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("simPIC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIMPIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-simpic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-simpic:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-simpic:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_simpic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_simpic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_simpic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PIC_counting)
    library(jsonlite)

    # --- Load saved R data object [] ---
    # Key functions: simPICestimate, simPICsimulate
    suppressPackageStartupMessages({
    library(simPIC)
    set.seed(12)
    # --- P I C_counting [] ---
    # Key functions: PIC_counting
    pic_mat <- PIC_counting(
    # --- sim P I Cget [] ---
    # Key functions: simPICget
    simPICget(sim.params, "nPeaks")
    # --- sim P I Cgetparameters [] ---
    # Key functions: simPICgetparameters, setsimPICparameters
    Set multiple parameters at once (using a list)
    sim.params <- setsimPICparameters(sim.params,
    update = list(nPeaks = 8000, nCells = 500)
    # --- Load saved R data object [] ---
    # Key functions: typeof, newsimPICcount, simPICestimate
    count <- readRDS(system.file("extdata", "test.rds", package = "simPIC"))
    class(count)
    typeof(count)
    # --- sim P I Csimulate [] ---
    # Key functions: simPICsimulate
    sim <- simPICsimulate(new, nCells = 1000)
    sim <- simPICsimulate(new, nCells =1000, pm.distr = "gamma")
    # --- counts [] ---
    # Key functions: counts
    counts(sim)[1:5, 1:5]
    head(rowData(sim))
    head(colData(sim))
    # --- sim P I Csimulate [] ---
    # Key functions: simPICsimulate, simPICcompare
    sim1 <- simPICsimulate(nPeaks = 20000, nCells = 1000)
    sim2 <- simPICsimulate(nPeaks = 20000, nCells = 1000)
    comparison <- simPICcompare(list(real = sim1, simPIC = sim2))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_simpic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_simpic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_simpic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIMPIC:", paste0("    simpic: ", packageVersion("simPIC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simpic_results.csv
    touch ${prefix}_simpic_output.rds
    echo "BIOC_SIMPIC:" > versions.yml
    echo "    simpic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIMPIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIMPIC(ch_input)

    emit:
    results  = BIOC_SIMPIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIMPIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIMPIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIMPIC.out.versions  // channel: path(versions.yml)
}
