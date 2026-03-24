#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TrajectoryUtils
// Implements low-level utilities for single-cell trajectory analysis, primarily intended for re-use in
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TrajectoryUtils/inst/doc/overview.R
// Upstream  : BiocStyle, knitr
// Downstream: slingshot, TSCAN
//
// Install: BiocManager::install("TrajectoryUtils")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRAJECTORYUTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-trajectoryutils"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-trajectoryutils:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-trajectoryutils:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_trajectoryutils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_trajectoryutils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_trajectoryutils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PseudotimeOrdering)
    library(jsonlite)

    # --- Guessmstroots [] ---
    # Key functions: guessMSTRoots
    ---------------------------------------------------------------------
    guessMSTRoots(mst, method="maxstep")
    guessMSTRoots(mst, method="minstep")
    # --- Definemstpaths [] ---
    # Key functions: defineMSTPaths
    ---------------------------------------------------------------------
    defineMSTPaths(mst, roots=c("1"))
    defineMSTPaths(mst, roots=c("2"))
    # --- Splitbybranches [] ---
    # Key functions: splitByBranches
    ---------------------------------------------------------------------
    splitByBranches(mst)
    # --- Matrix [] ---
    # Key functions: rnorm, PseudotimeOrdering
    ---------------------------------------------------------------------
    # Make up a matrix of pseudotime orderings.
    ncells <- 200
    npaths <- 5
    orderings <- matrix(rnorm(1000), ncells, npaths)
    # --- Sample [] ---
    # Key functions: sample, cellData
    ---------------------------------------------------------------------
    pto$cluster <- sample(LETTERS[1:5], ncells, replace=TRUE)
    cellData(pto)
    # --- Pathdata [] ---
    # Key functions: pathData
    ---------------------------------------------------------------------
    pathData(pto)$description <- sprintf("PATH-%i", seq_len(npaths))
    pathData(pto)
    # --- Pathstat [] ---
    # Key functions: pathStat, runif, pathStatNames
    ---------------------------------------------------------------------
    pathStat(pto, "confidence") <- matrix(runif(1000), ncells, npaths)
    pathStatNames(pto)
    # --- Summary [] ---
    # Key functions: averagePseudotime
    ---------------------------------------------------------------------
    summary(averagePseudotime(pto))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_trajectoryutils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_trajectoryutils_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_trajectoryutils_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRAJECTORYUTILS:", paste0("    trajectoryutils: ", packageVersion("TrajectoryUtils"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trajectoryutils_results.csv
    touch ${prefix}_trajectoryutils_output.rds
    echo "BIOC_TRAJECTORYUTILS:" > versions.yml
    echo "    trajectoryutils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRAJECTORYUTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRAJECTORYUTILS(ch_input)

    emit:
    results  = BIOC_TRAJECTORYUTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRAJECTORYUTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRAJECTORYUTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRAJECTORYUTILS.out.versions  // channel: path(versions.yml)
}
