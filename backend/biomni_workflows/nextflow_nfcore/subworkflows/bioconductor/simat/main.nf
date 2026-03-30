#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SIMAT
// This package provides a pipeline for analysis of GC-MS data acquired in selected ion monitoring (SIM
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SIMAT/inst/doc/SIMAT-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SIMAT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIMAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-simat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-simat:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-simat:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_simat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_simat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_simat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SIMAT)
    library(jsonlite)

    # --- Packageload [] ---
    # Key functions: data
    # load the package
    library(SIMAT)
    # load the extracted data from a CDF file of a SIM run
    data(Run)
    # load the target table information
    # --- Examinerun [] ---
    # Key functions: frame
    # check the names of different fields in Run
    names(Run)
    # show some values for the the first three fields
    head(as.data.frame(Run[c("rt", "sc", "tic")]))
    # see what is included in the scan information for the first scan
    # --- Plottic [] ---
    # Key functions: plotTIC
    # plot the TIC of the selected Run
    plotTIC(Run = Run)
    # --- Examinetargettable [] ---
    # Key functions: frame
    # check the name of included fields
    names(target.table)
    # check the first lines of the target.table
    head(as.data.frame(target.table[c("compound", "numFrag")]))
    # check the contents of the ms field
    # --- Examinelibrary [] ---
    # Key functions: frame
    # check the name of included fields
    names(Library)
    # check the first lines of Library
    head(as.data.frame(Library[c("rt", "ri", "compound")]))
    # check the contents of the ms and sp fields related to the mass and intensity
    # --- Gettarget [] ---
    # Key functions: getTarget, frame
    # get targets info using target table and provided library
    Targets <- getTarget(Method = "library", Library = Library,
                        target.table = target.table)
    # check the fields of Targets
    names(Targets)
    # --- Getpeak [] ---
    # Key functions: getPeak, runPeaks
    # get the peaks for this run corresponding to Targets
    runPeaks <- getPeak(Run = Run, Targets = Targets)
    # check the length of runPeaks (number of targets)
    length(runPeaks)
    # check the fields for each peak
    # --- Ploteic [] ---
    # Key functions: peak, plotEIC
    # plot the EIC of the first peak (target) on the list
    plotEIC(peakEIC = runPeaks[[1]][[1]])
    # --- Getri [] ---
    # Key functions: getRI, calibRI, getPeak
    # create the RI calibration function
    calibRI <- getRI(RItable)
    # calculate the RI of an RT = 12.32min
    calibRI(12.32)
    # get the peaks for this run corresponding to Targets using RI calibration
    # --- Getpeakscore [] ---
    # Key functions: getPeakScore
    # find the similarity score of the found targets
    Scores <- getPeakScore(runPeaks = runPeaks, plot = TRUE)
    # check the value of scores
    print(Scores)
    # --- Optfrag [] ---
    # Key functions: optFrag
    # get the optimized version of the target list
    optTargets <- optFrag(Library = Library, target.table = target.table,
                          forceOpt = TRUE)
    # check the fragments of the first target
    # the mass of fragments

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_simat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_simat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_simat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIMAT:", paste0("    simat: ", packageVersion("SIMAT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simat_results.csv
    touch ${prefix}_simat_output.rds
    echo "BIOC_SIMAT:" > versions.yml
    echo "    simat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIMAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIMAT(ch_input)

    emit:
    results  = BIOC_SIMAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIMAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIMAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIMAT.out.versions  // channel: path(versions.yml)
}
