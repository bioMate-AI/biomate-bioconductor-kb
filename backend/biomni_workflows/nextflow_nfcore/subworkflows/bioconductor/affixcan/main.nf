#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AffiXcan
// Impute a GReX (Genetically Regulated Expression) for a set of genes in a sample of individuals, usin
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/AffiXcan/inst/doc/AffiXcan.html
// Upstream  : MultiAssayExperiment, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("AffiXcan")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFIXCAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-affixcan"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-affixcan:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-affixcan:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_affixcan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_affixcan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_affixcan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Expression)
    library(Validation)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: assays
    suppressMessages(library(MultiAssayExperiment))
    tba <- readRDS(system.file("extdata","training.tba.toydata.rds",
        package="AffiXcan")) ## This is a MultiAssayExperiment object
    names(assays(tba))
    # --- Code Block 3 [] ---
    # Key functions: assays
    suppressMessages(library(SummarizedExperiment))
    load("../data/exprMatrix.RData")
    assays(exprMatrix)$values[,1:5]
    # --- Code Block 4 [] ---
    # Key functions: affiXcanTrain
    suppressMessages(library("AffiXcan"))
    trainingTbaPaths <- system.file("extdata","training.tba.toydata.rds",
        package="AffiXcan")
    data(exprMatrix)
    data(regionAssoc)
    # --- Code Block 7 [] ---
    # Key functions: affiXcanImpute
    testingTbaPaths <- system.file("extdata","testing.tba.toydata.rds",
        package="AffiXcan")
    exprmatrix <- affiXcanImpute(tbaPaths=testingTbaPaths,
        affiXcanTraining=training, scale=TRUE)
    # --- Code Block 8 [] ---
    # Key functions: Expression
    ##
    ## AffiXcan: Imputing Genetically Regulated Expression (GReX)
    ##  --> Computing Principal Components
    ##  --> Imputing GReX values
    ##  Done
    # --- Code Block 9 [] ---
    # Key functions: assays, frame
    grexMatrix <- assays(exprmatrix)$GReX
    as.data.frame(grexMatrix)[,1:5]
    # --- Code Block 10 [] ---
    # Key functions: affiXcanTrain
    trainingTbaPaths <- system.file("extdata","training.tba.toydata.rds",
    package="AffiXcan")
    data(exprMatrix)
    data(regionAssoc)
    data(trainingCovariates)
    # --- Code Block 11 [] ---
    # Key functions: Validation
    ##
    ## AffiXcan: Performing Training With 5 Fold Cross-Validation ( 1 / 5 )
    ##  --> Performing Principal Components Analysis
    # --- Code Block 13 [] ---
    # Key functions: Validation
    ##  --> Imputing GReX Values
    ##  --> Computing Cross-Validated R^2
    ##  Done
    ##
    ## AffiXcan: Performing Training With 5 Fold Cross-Validation ( 2 / 5 )
    # --- Code Block 15 [] ---
    # Key functions: Validation
    ##  --> Imputing GReX Values
    ##  --> Computing Cross-Validated R^2
    ##  Done
    ##
    ## AffiXcan: Performing Training With 5 Fold Cross-Validation ( 3 / 5 )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_affixcan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_affixcan_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_affixcan_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AFFIXCAN:", paste0("    affixcan: ", packageVersion("AffiXcan"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affixcan_results.csv
    touch ${prefix}_affixcan_output.rds
    echo "BIOC_AFFIXCAN:" > versions.yml
    echo "    affixcan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AFFIXCAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AFFIXCAN(ch_input)

    emit:
    results  = BIOC_AFFIXCAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AFFIXCAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AFFIXCAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AFFIXCAN.out.versions  // channel: path(versions.yml)
}
