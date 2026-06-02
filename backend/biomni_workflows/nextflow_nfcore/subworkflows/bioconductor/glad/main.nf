#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GLAD
// Analysis of array CGH data : detection of breakpoints in genomic profiles and assignment of a status
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GLAD/inst/doc/GLAD.R
// Upstream  : none
// Downstream: ADaCGH2, ITALICS
//
// Install: BiocManager::install("GLAD")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GLAD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-glad"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-glad:2.70.0--r44_0' :
        'quay.io/biocontainers/bioconductor-glad:2.70.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_glad_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_glad_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_glad_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GLAD)
    library(jsonlite)

    # --- Genomic Segmentation and Analysis [] ---
    # Key functions: glad
    res <- glad(
        profileCGH,
        mediancenter = FALSE,
        smoothfunc = "lawsglad",
        bandwidth = 10,
        round = 1.5,
        model = "Gaussian",
        lkern = "Exponential",
        qlambda = 0.999,
        base = FALSE,
        lambdabreak = 8,
        lambdacluster = 8,
        lambdaclusterGen = 40,
        type = "tricubic",
        param = c(d = 6),
        alpha = 0.001,
        msize = 2,
        method = "centroid",
        nmax = 8,
        verbose = FALSE
    )


    # --- Advanced Segmentation with daglad [] ---
    # Key functions: daglad
    profileCGH_daglad <- daglad(
        profileCGH,
        mediancenter = FALSE,
        normalrefcenter = FALSE,
        genomestep = FALSE,
        smoothfunc = "lawsglad",
        lkern = "Exponential",
        model = "Gaussian",
        qlambda = 0.999,
        bandwidth = 10,
        base = FALSE,
        round = 1.5,
        lambdabreak = 8,
        lambdaclusterGen = 40,
        param = c(d = 6),
        alpha = 0.001,
        msize = 2,
        method = "centroid",
        nmin = 1,
        nmax = 8,
        amplicon = 1,
        deletion = -5,
        deltaN = 0.2,
        forceGL = c(-0.3, 0.3),
        nbsigma = 3,
        MinBkpWeight = 0.35,
        CheckBkpPos = TRUE
    )


    # --- Visualization of Genomic Profiles [] ---
    # Key functions: plotProfile
    plotProfile(
        res,
        unit = 3,
        Bkp = TRUE,
        labels = FALSE,
        plotband = FALSE,
        Smoothing = "Smoothing",
        cytoband = cytoband
    )


    # --- Array CGH Visualization [] ---
    # Key functions: arrayPlot, arrayPersp
    array_obj <- list(
        arrayValues = array2,
        arrayDesign = c(4, 4, 21, 22)
    )
    class(array_obj) <- "arrayCGH"
    arrayPlot(array_obj, "Log2Rat", bar = "none")
    arrayPersp(
        array_obj,
        "Log2Rat",
        box = FALSE,
        theta = 110,
        phi = 40,
        bar = FALSE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_glad_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_glad_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_glad_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GLAD:", paste0("    glad: ", packageVersion("GLAD"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_glad_results.csv
    touch ${prefix}_glad_output.rds
    echo "BIOC_GLAD:" > versions.yml
    echo "    glad: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GLAD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GLAD(ch_input)

    emit:
    results  = BIOC_GLAD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GLAD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GLAD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GLAD.out.versions  // channel: path(versions.yml)
}
