#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Basic4Cseq
// Basic4Cseq is an R/Bioconductor package for basic filtering, analysis and subsequent visualization o
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Basic4Cseq/inst/doc/vignette.R
// Upstream  : GenomicAlignments, RCircos, caTools
// Downstream: none
//
// Install: BiocManager::install("Basic4Cseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BASIC4CSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-basic4cseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-basic4cseq:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-basic4cseq:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_basic4cseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_basic4cseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_basic4cseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAString)
    library(Data4Cseq)
    library(jsonlite)

    # --- Createvirtualfragmentlibrary [] ---
    # Key functions: DNAString, createVirtualFragmentLibrary
    testGenome = DNAString("ATCATGAAGTACTACATGGCACCATGT")
    fragmentData = createVirtualFragmentLibrary(chosenGenome = testGenome, firstCutter = "catg",
        secondCutter = "gtac", readLength = 2,  chromosomeName = "test", libraryName = "")
    head(fragmentData)
    # --- create Virtual Fragment Library [] ---
    # Key functions: createVirtualFragmentLibrary
    ## library(BSgenome.Mmusculus.UCSC.mm9)
    ## createVirtualFragmentLibrary(chosenGenome = Mmusculus, firstCutter = "aagctt", secondCutter =
    ##     "catg", readLength = 54,  libraryName = "myFullFetalLiverVFL.csv")
    # --- Loadfetalliverrawdata [] ---
    # Key functions: readGAlignments
    library(GenomicAlignments)
    libraryFile <- system.file("extdata", "vfl_aagctt_catg_mm9_54_vp.csv", package="Basic4Cseq")
    bamFile <- system.file("extdata", "fetalLiverShort.bam", package="Basic4Cseq")
    liverReads <- readGAlignments(bamFile)
    liverReads
    # --- Addpointsofinterest [] ---
    # Key functions: readPointsOfInterestFile
    pointsOfInterestFile <- system.file("extdata", "fetalLiverVP.bed", package="Basic4Cseq")
    liverPoints<-readPointsOfInterestFile(pointsOfInterestFile)
    liverPoints
    # --- Initializeobject [] ---
    # Key functions: Data4Cseq
    liverData = Data4Cseq(viewpointChromosome = "10", viewpointInterval = c(20879870, 20882209),
        readLength = 54, pointsOfInterest = liverPoints, rawReads = liverReads)
    liverData
    # --- Initializeobject [] ---
    # Key functions: rawFragments, readsToFragments
    rawFragments(liverData)<-readsToFragments(liverData, libraryFile)
    liverData
    # --- Initializeobject [] ---
    # Key functions: nearCisFragments, chooseNearCisFragments
    # pick near-cis fragments
    nearCisFragments(liverData)<-chooseNearCisFragments(liverData,
        regionCoordinates = c(20800000, 21100000))
    head(nearCisFragments(liverData))
    # --- Normalizeobject [] ---
    # Key functions: nearCisFragments, normalizeFragmentData
    # normalization of near-cis data
    library("caTools")
    nearCisFragments(liverData)<-normalizeFragmentData(liverData)
    head(nearCisFragments(liverData))
    # --- Qualitycontrol [] ---
    # Key functions: getReadDistribution
    getReadDistribution(liverData, useFragEnds = TRUE, outputName = "")
    # --- Visualizeviewpoint [] ---
    # Key functions: visualizeViewpoint
    ## # This command creates a near-cis plot of the fetal liver's viewpoint data
    ## visualizeViewpoint(liverData, plotFileName = "", mainColour = "blue",
    ##     plotTitle = "Fetal Liver Near-Cis Plot", loessSpan = 0.1, maxY = 6000,
    ##     xAxisIntervalLength = 50000, yAxisIntervalLength = 1000)
    # --- Drawheatmap [] ---
    # Key functions: drawHeatmap
    ## # This command creates a near-cis heatmap plot of the fetal liver data
    ## drawHeatmap(liverData, plotFileName = "", xAxisIntervalLength = 50000, bands = 5)
    # --- Exportwig [] ---
    # Key functions: printWigFile
    ## printWigFile(liverData, wigFileName = "fetalLiver.wig")
    # --- Transinteractions [] ---
    # Key functions: plotTransInteractions
    ## library("RCircos")
    ## transInteractions <- system.file("extdata", "transInteractionData.txt", package="Basic4Cseq")
    ## ideogramData <- system.file("extdata", "RCircos_GRCm38_ideogram.csv", package="Basic4Cseq")
    ## plotTransInteractions(transInteractions, "10", c(20000100, 20001000), ideogramData,
    ##     PlotColor = "blue", expandBands = TRUE, expansionValue = 1000000, plotFileName = "")
    # --- Checkrestrictionenzyme [] ---
    # Key functions: checkRestrictionEnzymeSequence
    ## # The demonstration reads are taken from Stadhouders et al's data,
    ## # but additional cutter sequences have been added manually for demonstration purposes
    ## fetalLiverCutterFile <- system.file("extdata", "fetalLiverCutter.sam", package="Basic4Cseq")
    ## checkRestrictionEnzymeSequence("aagctt", fetalLiverCutterFile, "fetalLiverCutter_filtered.sam")
    # --- Extractbed [] ---
    # Key functions: printBEDFragmentLibrary
    ## printBEDFragmentLibrary(libraryFile, "BEDLibrary_FL_vp.bed")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_basic4cseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_basic4cseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_basic4cseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BASIC4CSEQ:", paste0("    basic4cseq: ", packageVersion("Basic4Cseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basic4cseq_results.csv
    touch ${prefix}_basic4cseq_output.rds
    echo "BIOC_BASIC4CSEQ:" > versions.yml
    echo "    basic4cseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BASIC4CSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BASIC4CSEQ(ch_input)

    emit:
    results  = BIOC_BASIC4CSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BASIC4CSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BASIC4CSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BASIC4CSEQ.out.versions  // channel: path(versions.yml)
}
