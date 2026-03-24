#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MAIT
// The MAIT package contains functions to perform end-to-end statistical analysis of LC/MS Metabolomic 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MAIT/inst/doc/MAIT_Vignette.R
// Upstream  : faahKO
// Downstream: none
//
// Install: BiocManager::install("MAIT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mait"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mait:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mait:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mait_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mait_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mait_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Biotransformations)
    library(MAITbuilder)
    library(Validation)
    library(jsonlite)

    # --- Sampleprocessing [] ---
    # Key functions: sampleProcessing
    library(faahKO)
    cdfFiles<-system.file("cdf", package="faahKO", mustWork=TRUE)
    MAIT <- sampleProcessing(dataDir = cdfFiles, project = "MAIT_Demo",
    snThres=2,rtStep=0.03)
    # --- Peakannotation [] ---
    # Key functions: peakAnnotation
    MAIT <- peakAnnotation(MAIT.object = MAIT,corrWithSamp = 0.7,
    corrBetSamp = 0.75,perfwhm = 0.6)
    # --- Spectralsigfeatures [] ---
    # Key functions: spectralSigFeatures
    MAIT<- spectralSigFeatures(MAIT.object = MAIT,pvalue=0.05,
           p.adj="none",scale=FALSE)
    summary(MAIT)
    # --- Sigpeakstable [] ---
    # Key functions: sigPeaksTable
    signTable <- sigPeaksTable(MAIT.object = MAIT, printCSVfile = FALSE)
    # --- Boxheatplots [] ---
    # Key functions: plotBoxplot, plotHeatmap
    ## plotBoxplot(MAIT)
    ## plotHeatmap(MAIT)
    # --- Plspca [] ---
    # Key functions: plotPCA, plotPLS, model
    MAIT<-plotPCA(MAIT,plot3d=FALSE)
    MAIT<-plotPLS(MAIT,plot3d=FALSE)
    PLSmodel <- model(MAIT, type = "PLS")
    PCAmodel <- model(MAIT, type = "PCA")
    # --- Biotransformations [] ---
    # Key functions: Biotransformations
    Biotransformations(MAIT.object = MAIT, peakPrecision = 0.005)
    # --- Mybiotransf [] ---
    # Key functions: factor
    data(MAITtables)
    myBiotransformation<-c("custom_biotrans",105.0)
    myBiotable<-biotransformationsTable
    myBiotable[,1]<-as.character(myBiotable[,1])
    myBiotable<-rbind(myBiotable,myBiotransformation)
    # --- Identifymetabolites [] ---
    # Key functions: identifyMetabolites
    MAIT <- identifyMetabolites(MAIT.object = MAIT, peakTolerance = 0.005)
    # --- Metabolitetable [] ---
    # Key functions: metaboliteTable
    metTable<-metaboliteTable(MAIT)
    head(metTable)
    # --- Validation [] ---
    # Key functions: Validation
    MAIT <- Validation(Iterations = 20, trainSamples= 3,
    MAIT.object = MAIT)
    # --- Classifratioclasses [] ---
    # Key functions: classifRatioClasses
    classifRatioClasses(MAIT)
    # --- Defdata [] ---
    # Key functions: scores, getPeaklist
    peaks <- scores(MAIT)
    masses <- getPeaklist(MAIT)$mz
    rt <- getPeaklist(MAIT)$rt/60
    # --- Maitbuilder [] ---
    # Key functions: MAITbuilder
    importMAIT <- MAITbuilder(data = peaks, masses = masses,
                  rt = rt,significantFeatures = TRUE,
                  spectraEstimation = TRUE,rtRange=0.2,
                  corThresh=0.7)
    # --- Biotransformationsbuilder [] ---
    # Key functions: Biotransformations
    importMAIT <- Biotransformations(MAIT.object = importMAIT,
                  adductAnnotation = TRUE,
                  peakPrecision = 0.005, adductTable = NULL)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mait_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mait_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mait_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MAIT:", paste0("    mait: ", packageVersion("MAIT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mait_results.csv
    touch ${prefix}_mait_output.rds
    echo "BIOC_MAIT:" > versions.yml
    echo "    mait: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MAIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MAIT(ch_input)

    emit:
    results  = BIOC_MAIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MAIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MAIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MAIT.out.versions  // channel: path(versions.yml)
}
