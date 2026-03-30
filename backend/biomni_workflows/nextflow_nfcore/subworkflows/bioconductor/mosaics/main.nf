#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mosaics
// This package provides functions for fitting MOSAiCS and MOSAiCS-HMM, a statistical framework to anal
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mosaics/inst/doc/mosaics-example.R
// Upstream  : mosaicsExample
// Downstream: none
//
// Install: BiocManager::install("mosaics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOSAICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mosaics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mosaics:2.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mosaics:2.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mosaics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mosaics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mosaics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mosaics)
    library(jsonlite)

    # --- Constructbins [] ---
    # Key functions: constructBins, path
    constructBins( infile=system.file( file.path("extdata","wgEncodeSydhTfbsGm12878Stat1StdAlnRep1_chr22_sorted.bam"), package="mosaicsExample"),
        fileFormat="bam", outfileLoc="./",
        byChr=FALSE, useChrfile=FALSE, chrfile=NULL, excludeChr=NULL,
        PET=FALSE, fragLen=200, binSize=200, capping=0 )
    constructBins( infile=system.file( file.path("extdata","wgEncodeSydhTfbsGm12878InputStdAlnRep1_chr22_sorted.bam"), package="mosaicsExample"),
    # --- Io Readbin [] ---
    # Key functions: readBins
    fileName <- c(
        "wgEncodeSydhTfbsGm12878Stat1StdAlnRep1_chr22_sorted.bam_fragL200_bin200.txt",
        "wgEncodeSydhTfbsGm12878InputStdAlnRep1_chr22_sorted.bam_fragL200_bin200.txt")
    binTFBS <- readBins( type=c("chip","input"), fileName=fileName )
    # --- Io Mosaicsfit [] ---
    # Key functions: mosaicsFit
    fitTFBS <- mosaicsFit( binTFBS, analysisType="IO", bgEst="rMOM" )
    # --- Ts Mosaicspeak [] ---
    # Key functions: mosaicsPeak
    peakTFBS <- mosaicsPeak( fitTFBS, signalModel="2S", FDR=0.05,
    maxgap=200, minsize=50, thres=10 )
    # --- Io Mosaicspeak Export [] ---
    # Key functions: export
    ## export( peakTFBS, type="txt", filename="peakTFBS.txt" )
    ## export( peakTFBS, type="bed", filename="peakTFBS.bed" )
    ## export( peakTFBS, type="gff", filename="peakTFBS.gff" )
    ## export( peakTFBS, type="narrowPeak", filename="peakTFBS.narrowPeak" )
    ## export( peakTFBS, type="broadPeak", filename="peakTFBS.broadPeak" )
    # --- Generatewig [] ---
    # Key functions: generateWig, path
    generateWig( infile=system.file( file.path("extdata","wgEncodeSydhTfbsGm12878Stat1StdAlnRep1_chr22_sorted.bam"), package="mosaicsExample"),
        fileFormat="bam", outfileLoc="./",
        byChr=FALSE, useChrfile=FALSE, chrfile=NULL, excludeChr=NULL,
        PET=FALSE, fragLen=200, span=200, capping=0, normConst=1 )
    # --- Mosaicsfithmm Pre [] ---
    # Key functions: constructBins, path, readBins, mosaicsFit
    constructBins( infile=system.file( file.path("extdata","wgEncodeBroadHistoneGm12878H3k4me3StdAlnRep1_chr22_sorted.bam"), package="mosaicsExample"),
        fileFormat="bam", outfileLoc="./",
        byChr=FALSE, useChrfile=FALSE, chrfile=NULL, excludeChr=NULL,
        PET=FALSE, fragLen=200, binSize=200, capping=0 )
    constructBins( infile=system.file( file.path("extdata","wgEncodeBroadHistoneGm12878ControlStdAlnRep1_chr22_sorted.bam"), package="mosaicsExample"),
    # --- Mosaicsfithmm [] ---
    # Key functions: mosaicsFitHMM
    hmmHM <- mosaicsFitHMM( fitHM, signalModel = "2S",
    	init="mosaics", init.FDR = 0.05, parallel=FALSE, nCore=8 )
    # --- Mosaicspeakhmm [] ---
    # Key functions: mosaicsPeakHMM
    peakHM <- mosaicsPeakHMM( hmmHM, FDR = 0.05, decoding="posterior",
      thres=10, parallel=FALSE, nCore=8 )
    # --- Summit Extractreads [] ---
    # Key functions: extractReads, path
    peakHM <- extractReads( peakHM,
      chipFile=system.file( file.path("extdata","wgEncodeBroadHistoneGm12878H3k4me3StdAlnRep1_chr22_sorted.bam"), package="mosaicsExample"),
      chipFileFormat="bam", chipPET=FALSE, chipFragLen=200,
      controlFile=system.file( file.path("extdata","wgEncodeBroadHistoneGm12878ControlStdAlnRep1_chr22_sorted.bam"), package="mosaicsExample"),
      controlFileFormat="bam", controlPET=FALSE, controlFragLen=200, parallel=FALSE, nCore=8 )
    # --- Summit Findsummit [] ---
    # Key functions: findSummit
    peakHM <- findSummit( peakHM, parallel=FALSE, nCore=8 )
    # --- Postprocess Adjustboundary [] ---
    # Key functions: adjustBoundary
    peakHM <- adjustBoundary( peakHM, parallel=FALSE, nCore=8 )
    peakHM
    head(print(peakHM))
    # --- Postprocess Filterpeak [] ---
    # Key functions: filterPeak
    peakHM <- filterPeak( peakHM, parallel=FALSE, nCore=8 )
    peakHM
    head(print(peakHM))
    # --- Mosaicsrunall [] ---
    # Key functions: mosaicsRunAll
    ##      mosaicsRunAll(
    ##          chipFile="/scratch/eland/STAT1_ChIP_eland_results.txt",
    ##          chipFileFormat="eland_result",
    ##          controlFile="/scratch/eland/STAT1_control_eland_results.txt",
    ##          controlFileFormat="eland_result",
    # --- Ts Readbin [] ---
    # Key functions: readBins, path
    exampleBinData <- readBins( type=c("chip","input","M","GC","N"),
        fileName=c( system.file( file.path("extdata","chip_chr21.txt"), package="mosaicsExample"),
        system.file( file.path("extdata","input_chr21.txt"), package="mosaicsExample"),
        system.file( file.path("extdata","M_chr21.txt"), package="mosaicsExample"),
        system.file( file.path("extdata","GC_chr21.txt"), package="mosaicsExample"),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mosaics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mosaics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mosaics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOSAICS:", paste0("    mosaics: ", packageVersion("mosaics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mosaics_results.csv
    touch ${prefix}_mosaics_output.rds
    echo "BIOC_MOSAICS:" > versions.yml
    echo "    mosaics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOSAICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOSAICS(ch_input)

    emit:
    results  = BIOC_MOSAICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOSAICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOSAICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOSAICS.out.versions  // channel: path(versions.yml)
}
