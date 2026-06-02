#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: metaMS
// MS-based metabolomics data processing and compound annotation pipeline.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/metaMS/inst/doc/runGC.R
// Upstream  : metaMSdata
// Downstream: none
//
// Install: BiocManager::install("metaMS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METAMS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metams"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metams:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metams:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metams_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metams_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metams_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DB)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: metaSetting
    library(metaMS)
    data(FEMsettings)
    TSQXLS.GC
    metaSetting(TSQXLS.GC, "PeakPicking")
    # --- Data [] ---
    # Key functions: files, runGC
    ## library(metaMSdata)
    ## data(threeStdsDB)        ## provides DB
    ##
    ## cdfdir <- system.file("extdata", package = "metaMSdata")
    # --- Rungc [] ---
    # Key functions: runGC
    ## result <- runGC(xset = GCset, settings = TSQXLS.GC, DB = DB)
    # --- Peakdetection [] ---
    # Key functions: peakDetection, metaSetting
    ## GCset <- peakDetection(cdffiles,
    ##                        settings = metaSetting(TSQXLS.GC, "PeakPicking"),
    ##                        convert2list = TRUE, nSlaves = 2)
    # --- Lapply [] ---
    # Key functions: metaSetting
    ## allSamples <- lapply(GCset, runCAMERA, chrom = "GC",
    ##                      settings = metaSetting(TSQXLS.GC, "CAMERA"))
    # --- Plotpseudospectrum [] ---
    # Key functions: plotPseudoSpectrum
    plotPseudoSpectrum(allSamples.msp[[1]][[26]])
    # --- Db [] ---
    # Key functions: DB, matchSamples2DB, metaSetting
    DB.treated <- treat.DB(DB)
    allSam.matches <-
        matchSamples2DB(allSamples.msp, DB = DB.treated,
                        settings = metaSetting(TSQXLS.GC, "match2DB"),
                        quick = FALSE)
    # --- Matchexpspec [] ---
    # Key functions: matchExpSpec
    matchExpSpec(allSamples.msp[[1]][[4]], DB.treated,
                 DB.treated = TRUE, plotIt = TRUE)
    # --- Lapply [] ---
    # Key functions: matchSamples2Samples, metaSetting
    allSamples.msp.scaled <- lapply(allSamples.msp, treat.DB,
                                    isMSP = FALSE)
    allSam.matches <-
    # --- Getfeatureinfo [] ---
    # Key functions: getFeatureInfo
    features.df <- getFeatureInfo(stdDB = DB, allMatches = allSam.matches,
                                  sampleList = allSamples.msp)
    features.df[, c(1:3, ncol(features.df) - 2:0)]
    # --- Constructexppseudospectra [] ---
    # Key functions: constructExpPseudoSpectra, getAnnotationMat
    PseudoSpectra <- constructExpPseudoSpectra(allMatches = allSam.matches,
                                               standardsDB = DB)
    ann.df <- getAnnotationMat(exp.msp = allSamples.msp, pspectra = PseudoSpectra,
                               allMatches = allSam.matches)
    ann.df
    # --- Sweep [] ---
    # Key functions: sweep
    ann.df2 <- sweep(ann.df, 1, sapply(PseudoSpectra,
                                       function(x) max(x$pspectrum[, 2])),
                     FUN = "*")
    ann.df2
    # --- Data [] ---
    # Key functions: createSTDdbGC
    ## data(threeStdsNIST)                       ## provides smallDB
    ## DB <- createSTDdbGC(threeStdsInfo, TSQXLS.GC, extDB = smallDB,
    ##                     nSlaves = 2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metams_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metams_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metams_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METAMS:", paste0("    metams: ", packageVersion("metaMS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metams_results.csv
    touch ${prefix}_metams_output.rds
    echo "BIOC_METAMS:" > versions.yml
    echo "    metams: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METAMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METAMS(ch_input)

    emit:
    results  = BIOC_METAMS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METAMS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METAMS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METAMS.out.versions  // channel: path(versions.yml)
}
