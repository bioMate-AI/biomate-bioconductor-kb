#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: switchBox
// The package offer different classifiers based on comparisons of pair of features (TSP), using variou
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/switchBox/inst/doc/switchBox.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("switchBox")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SWITCHBOX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-switchbox"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-switchbox:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-switchbox:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_switchbox_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_switchbox_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_switchbox_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CalculateSignedScore)
    library(Classify)
    library(KTSP)
    library(Statistics)
    library(Train)
    library(jsonlite)

    # --- Traindata [] ---
    # Key functions: data
    ### Load the example data for the TRAINING set
    data(trainingData)
    # --- Testdata [] ---
    # Key functions: data
    ### Load the example data for the TEST set
    data(testingData)
    # --- Ktsp [] ---
    # Key functions: KTSP
    ### Train a classifier from the top 4 best genes
    ### according to Wilcoxon filtering function
    classifier <- SWAP.Train.KTSP(matTraining, trainingGroup,
    			      FilterFunc=SWAP.Filter.Wilcoxon, featureNo=4)
    ### Show the classifier
    # --- Function [] ---
    # Key functions: sample, random10
    ### An alternative filtering function selecting 20 random features
    random10 <- function(situation, data) { sample(rownames(data), 10) }
    random10(trainingGroup, matTraining)
    # --- Function [] ---
    # Key functions: test, topRttest
    ### An alternative filtering function based on a t-test
    topRttest <- function(situation, data, quant = 0.75) {
    	out <- apply(data, 1, function(x, ...) t.test(x ~ situation)$statistic )
    	names(out[ abs(out) > quantile(abs(out), quant) ])
    }
    # --- Ktsp [] ---
    # Key functions: KTSP
    ### Train with t-test and krange
    classifier <- SWAP.Train.KTSP(matTraining, trainingGroup,
    			      FilterFunc = topRttest, quant = 0.9, krange=c(15:30) )
    ### Show the classifier
    classifier
    # --- Ktsp [] ---
    # Key functions: KTSP, Statistics
    ### Train a classifier
    classifier <- SWAP.Train.KTSP(matTraining, trainingGroup,
    			      FilterFunc = NULL, krange=2:8)
    ### Compute the statistics using the default parameters:
    ### counting the signed TSP votes
    # --- Statistics [] ---
    # Key functions: Statistics
    ### Compute
    ktspStatSum <- SWAP.KTSP.Statistics(inputMat = matTraining,
        classifier = classifier, CombineFunc=sum)
    ### Show statistics obtained using the sum
    head(ktspStatSum$statistics)
    # --- Character [] ---
    # Key functions: heatmap
    ## ### Make a heatmap showing the individual TSPs votes
    ## colorForRows <- as.character(1+as.numeric(trainingGroup))
    ## heatmap(1*ktspStatThreshold$comparisons, scale="none",
    ##     margins = c(10, 5), cexCol=0.5, cexRow=0.5,
    ##     labRow=trainingGroup, RowSideColors=colorForRows)
    # --- Fig1 [] ---
    # Key functions: heatmap
    ### Make a heatmap showing the individual TSPs votes
    colorForRows <- as.character(1+as.numeric(trainingGroup))
    heatmap(1*ktspStatThreshold$comparisons, scale="none",
        margins = c(10, 5), cexCol=0.85, cexRow=1,
        labRow=trainingGroup, RowSideColors=colorForRows)
    # --- Classify [] ---
    # Key functions: Classify
    ### Show the classifier
    classifier
    ### Apply the classifier to the TRAINING set
    trainingPrediction <- SWAP.KTSP.Classify(matTraining, classifier)
    ### Show
    # --- Sum [] ---
    # Key functions: Classify
    ### Usr a CombineFunc based on  sum(x) > 5.5
    trainingPrediction <- SWAP.KTSP.Classify(matTraining, classifier,
    					 DecisionFunc = function(x) sum(x) > 5.5 )
    ### Show
    str(trainingPrediction)
    # --- Classify [] ---
    # Key functions: Classify
    ### Classify one sample
    testPrediction <- SWAP.KTSP.Classify(matTesting[ , 1, drop=FALSE], classifier)
    ### Show
    testPrediction
    # --- Sum [] ---
    # Key functions: Classify
    ### APlly the classifier using sum(x)  > 5.5
    testPrediction <- SWAP.KTSP.Classify(matTesting, classifier,
    				     DecisionFunc = function(x) sum(x) > 5.5 )
    ### Resubstitution performance in the TEST set
    table(testPrediction, testingGroup)
    # --- Calculatesignedscore [] ---
    # Key functions: CalculateSignedScore
    ### Compute the scores using all features for all possible pairs
    scores <- SWAP.CalculateSignedScore(matTraining,  trainingGroup, FilterFunc=NULL)
    ### Show scores
    class(scores)
    dim(scores$score)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_switchbox_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_switchbox_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_switchbox_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SWITCHBOX:", paste0("    switchbox: ", packageVersion("switchBox"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_switchbox_results.csv
    touch ${prefix}_switchbox_output.rds
    echo "BIOC_SWITCHBOX:" > versions.yml
    echo "    switchbox: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SWITCHBOX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SWITCHBOX(ch_input)

    emit:
    results  = BIOC_SWITCHBOX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SWITCHBOX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SWITCHBOX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SWITCHBOX.out.versions  // channel: path(versions.yml)
}
