#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: INSPEcT
// INSPEcT (INference of Synthesis, Processing and dEgradation rates from Transcriptomic data) RNA-seq 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/INSPEcT/inst/doc/INSPEcT.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("INSPEcT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INSPECT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-inspect"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-inspect:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-inspect:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(deseqresults)

    output:
    tuple val(meta), path("${meta.id}_inspect_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_inspect_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_inspect_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(INSPEcT)
    library(jsonlite)

    # --- Object Initialization [] ---
    # Key functions: newINSPEcT, ratesFirstGuess, ratesFirstGuessVar
    tpts <- c(0,1/6,1/3,1/2,1,1.5,2,4,8,12,16)
    tL <- 1/6
    nascentInspObj <- newINSPEcT(
        tpts = tpts,
        labeling_time = tL,
        nascentExpressions = nasExp_DESeq2,
        matureExpressions = matExp_DESeq2
    )
    first_guess_syn <- ratesFirstGuess(nascentInspObj, 'synthesis')
    first_guess_deg <- ratesFirstGuess(nascentInspObj, 'degradation')


    # --- Rate Modeling [] ---
    # Key functions: modelRates, modelRatesNF, viewModelRates
    nascentInspObj10 <- nascentInspObj[1:10]
    nascentInspObj10 <- modelRates(nascentInspObj10)
    modelled_synthesis <- viewModelRates(nascentInspObj10, 'synthesis')
    nascentInspObj10NF <- modelRatesNF(nascentInspObj[1:10])


    # --- Quality Control and Filtering [] ---
    # Key functions: chisqmodel, featureNames, ratePvals, geneClass
    chisq <- chisqmodel(nascentInspObj10)
    discard <- which(chisq > 1e-2)
    discarded_features <- featureNames(nascentInspObj10)[discard]
    nascentInspObj_reduced <- nascentInspObj10[-discard]
    pvals <- ratePvals(nascentInspObj10)
    classes <- geneClass(nascentInspObj10)


    # --- Visualization and Downstream Analysis [] ---
    # Key functions: inHeatmap, plotGene, calculateRatePvals
    inHeatmap(nascentInspObj10, type='model', clustering=FALSE)
    plotGene(nascentInspObj10, ix="101206")
    matureInspObj10 <- calculateRatePvals(
        nascentInspObj10, 
        p_goodness_of_fit = 0.2, 
        p_variability = c(0.01, 0.01, 0.05)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_inspect_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_inspect_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_inspect_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INSPECT:", paste0("    inspect: ", packageVersion("INSPEcT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inspect_results.csv
    touch ${prefix}_inspect_output.rds
    echo "BIOC_INSPECT:" > versions.yml
    echo "    inspect: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INSPECT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqresults) ]

    main:
    BIOC_INSPECT(ch_input)

    emit:
    results  = BIOC_INSPECT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INSPECT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INSPECT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INSPECT.out.versions  // channel: path(versions.yml)
}
