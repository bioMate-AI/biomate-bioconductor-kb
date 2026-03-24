#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: clippda
// Methods for the nalysis of data from clinical proteomic profiling studies. The focus is on the studi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/clippda/inst/doc/clippda.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("clippda")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLIPPDA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clippda"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clippda:1.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clippda:1.56.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clippda_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clippda_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clippda_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ZvaluescasesVcontrolsPlots)
    library(ZvaluesfrommultinomPlots)
    library(jsonlite)

    # --- Liverdata [] ---
    # Key functions: data
    data(liverdata)
    data(liverRawData)
    data(liver_pheno)
    liverdata[1:4,]
    liverRawData[1:4,]
    # --- replicates [] ---
    # Key functions: replicates
    no.peaks <- 53
    no.replicates <- 2
    checkNo.replicates(liverRawData,no.peaks,no.replicates)
    # --- Preprocrepeatedpeakdata [] ---
    # Key functions: preProcRepeatedPeakData
    threshold <- 0.80
    Data <- preProcRepeatedPeakData(liverRawData, no.peaks, no.replicates, threshold)
    # --- Difference [] ---
    # Key functions: setdiff
    setdiff(unique(liverRawData$SampleTag),unique(liverdata$SampleTag))
    setdiff(unique(Data$SampleTag),unique(liverdata$SampleTag))
    # --- Spectrumfilter [] ---
    # Key functions: spectrumFilter
    TAGS <- spectrumFilter(Data,threshold,no.peaks)$SampleTag
    NewRawData2 <- Data[Data$SampleTag %in% TAGS,]
    dim(Data)
    dim(liverdata)
    dim(NewRawData2)
    # --- Coherencepeaks [] ---
    # Key functions: mostSimilarTwo
    Mat1 <- matrix(liverRawData[liverRawData$SampleTag == 25,]$Intensity,53,3)
    Mat2 <-matrix(liverRawData[liverRawData$SampleTag == 40,]$Intensity,53,4)
    sort(mostSimilarTwo(cor(log2(Mat1))))
    sort(mostSimilarTwo(cor(log2(Mat2))))
    # --- Confirmpreprocessing [] ---
    # Key functions: setdiff
    names(NewRawData2)
    dim(NewRawData2)
    names(liverdata)
    dim(liverdata)
    setdiff(NewRawData2$SampleTag,liverdata$SampleTag)
    # --- Sampleclustereddata [] ---
    # Key functions: sampleClusteredData
    JUNK_DATA <- sampleClusteredData(NewRawData2,no.peaks)
    head(JUNK_DATA)[,1:5]
    # --- Extractcomponetsofeset [] ---
    # Key functions: proteomicsExprsData, proteomicspData
    head(proteomicsExprsData(OBJECT))
    head(proteomicspData(OBJECT))
    # --- Zplots 1 [] ---
    # Key functions: ZvaluescasesVcontrolsPlots
    probs=seq(0,1,0.01) # provide hypothetical proportions of cases vs controls
    ZvaluescasesVcontrolsPlots(probs)
    # --- Zplots 2 [] ---
    # Key functions: ZvaluesfrommultinomPlots
    nsim=10000;nobs=300;proposeddesign=c(1,2,1,7);balanceddesign=c(1,1,1,1)
    ZvaluesfrommultinomPlots(nsim, nobs, proposeddesign, balanceddesign)
    # --- Biologicalparameters [] ---
    # Key functions: sampleSizeParameters, fisherInformation, sampleSize
    intraclasscorr  <-  0.60
    signifcut <- 0.05
    Data=OBJECT
    sampleSizeParameters(Data, intraclasscorr, signifcut)
    Z <- as.vector(fisherInformation(Data)[2,2])/2
    # --- Contourplot [] ---
    # Key functions: frame, sampleSizeContourPlots
    m <- 2
    DIFF <- seq(0.1,0.50,0.01)
    VAR <- seq(0.2,4,0.1)
    beta <- c(0.90,0.80,0.70)
    alpha <-  1 - c(0.001, 0.01,0.05)/2
    # --- Scatterplot [] ---
    # Key functions: sampleSize3DscatterPlots
    Z <- 2.460018
    m <- 2
    DIFF <- seq(0.1,0.50,0.01)
    VAR <- seq(0.2,4,0.1)
    beta <- c(0.90,0.80,0.70)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clippda_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clippda_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clippda_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLIPPDA:", paste0("    clippda: ", packageVersion("clippda"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clippda_results.csv
    touch ${prefix}_clippda_output.rds
    echo "BIOC_CLIPPDA:" > versions.yml
    echo "    clippda: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLIPPDA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLIPPDA(ch_input)

    emit:
    results  = BIOC_CLIPPDA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLIPPDA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLIPPDA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLIPPDA.out.versions  // channel: path(versions.yml)
}
