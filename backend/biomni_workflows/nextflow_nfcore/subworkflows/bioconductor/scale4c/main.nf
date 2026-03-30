#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Scale4C
// Scale4C is an R/Bioconductor package for scale-space transformation and visualization of 4C-seq data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Scale4C/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Scale4C")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCALE4C {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scale4c"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scale4c:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scale4c:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scale4c_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scale4c_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scale4c_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(IRanges)
    library(Scale4C)
    library(jsonlite)

    # --- import Basic4 Cseq Data [] ---
    # Key functions: importBasic4CseqData
    csvFile <- system.file("extdata", "liverData.csv", package="Scale4C")
    liverReads <- importBasic4CseqData(csvFile, viewpoint = 21160072,
        viewpointChromosome = "chr10", distance = 1000000)
    head(liverReads)
    # --- Initialiseobject [] ---
    # Key functions: Scale4C
    liverData = Scale4C(rawData = liverReads, viewpoint = 21160072, viewpointChromosome = "chr10")
    liverData
    # --- Addpointsofinterest [] ---
    # Key functions: pointsOfInterest, addPointsOfInterest, csv
    poiFile <- system.file("extdata", "vp.txt", package="Scale4C")
    pointsOfInterest(liverData) <- addPointsOfInterest(liverData,
        read.csv(poiFile, sep = "\t", stringsAsFactor = FALSE))
    head(pointsOfInterest(liverData))
    # --- Plotinflectionpoints01 [] ---
    # Key functions: plotInflectionPoints
    plotInflectionPoints(liverData, 2, fileName = "", plotIP = FALSE)
    # --- Plotinflectionpoints02 [] ---
    # Key functions: plotInflectionPoints
    plotInflectionPoints(liverData, 50, fileName = "", plotIP = FALSE)
    # --- Calculatescalespace [] ---
    # Key functions: scaleSpace, calculateScaleSpace, assay
    scaleSpace(liverData) = calculateScaleSpace(liverData, maxSQSigma = 10)
    head(t(assay(scaleSpace(liverData), 1))[,1:5])
    # --- Calculatefingerprintmap [] ---
    # Key functions: calculateFingerprintMap, singularities, findSingularities
    liverData = calculateFingerprintMap(liverData, maxSQSigma = 10)
    singularities(liverData) = findSingularities(liverData, 1, guessViewpoint = FALSE)
    # --- Adaptsingularities [] ---
    # Key functions: singularities, GRanges, IRanges
    data(liverData)
    tail(singularities(liverData))
    # add viewpoint singularity
    singularities(liverData) = c(singularities(liverData), GRanges("chr10", IRanges(39, 42),
        "*", "sqsigma" = 2000, "left" = 40, "right" = 41, "type" = "peak"))
    # --- Plottesselation [] ---
    # Key functions: plotTesselation
    # use pre-calculated example data with VP and correction
    data(liverDataVP)
    plotTesselation(liverDataVP, fileName = "")
    # --- Outputscalespacetree [] ---
    # Key functions: outputScaleSpaceTree
    head(outputScaleSpaceTree(liverDataVP, useLog = FALSE))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scale4c_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scale4c_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scale4c_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCALE4C:", paste0("    scale4c: ", packageVersion("Scale4C"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scale4c_results.csv
    touch ${prefix}_scale4c_output.rds
    echo "BIOC_SCALE4C:" > versions.yml
    echo "    scale4c: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCALE4C_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCALE4C(ch_input)

    emit:
    results  = BIOC_SCALE4C.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCALE4C.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCALE4C.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCALE4C.out.versions  // channel: path(versions.yml)
}
