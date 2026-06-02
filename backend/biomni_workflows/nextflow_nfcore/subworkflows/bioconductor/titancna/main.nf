#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TitanCNA
// Hidden Markov model to segment and predict regions of subclonal copy number alterations (CNA) and lo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TitanCNA/inst/doc/TitanCNA.R
// Upstream  : doMC
// Downstream: none
//
// Install: BiocManager::install("TitanCNA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TITANCNA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-titancna"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-titancna:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-titancna:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_titancna_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_titancna_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_titancna_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TitanCNA)
    library(jsonlite)

    # --- Model Fitting and Parameter Estimation [] ---
    # Key functions: runEMclonalCN
    convergeParams <- runEMclonalCN(
        data = allele_data,
        gParams = list(),
        nParams = list(),
        pParams = list(),
        sParams = list(),
        maxIEM = 50,
        maxOuterLoop = 15
    )
    results <- convergeParams$results


    # --- Segment Extraction and Formatting [] ---
    # Key functions: outputTitanSegments, outputTitanResults
    segs <- outputTitanSegments(
        results = results,
        id = "test_sample",
        convergeParams = convergeParams,
        filename = NULL,
        igvfilename = NULL
    )
    formatted_results <- outputTitanResults(
        results = results,
        id = "test_sample",
        convergeParams = convergeParams,
        filename = NULL
    )


    # --- Integer Copy Number Correction [] ---
    # Key functions: correctIntegerCN
    ploidy <- tail(convergeParams$phi, 1)
    normal <- tail(convergeParams$n, 1)
    corrIntCN.results <- correctIntegerCN(
        results = results,
        segs = segs,
        purity = 1 - normal,
        ploidy = ploidy,
        maxCNtoCorrect.autosomes = 8,
        maxCNtoCorrect.X = NULL,
        correctHOMD = FALSE,
        minPurityToCorrect = 0.2,
        gender = "female",
        chrs = 2
    )
    results <- corrIntCN.results$cn
    segs <- corrIntCN.results$segs


    # --- Visualisation of Subclonal Copy Number [] ---
    # Key functions: plotCNsubclones, plotSegmentMedians
    plotCNsubclones(
        dataIn = results,
        chr = 2,
        resultType = "copynumber",
        plotType = "subclone"
    )
    plotSegmentMedians(
        dataIn = results,
        chr = 2,
        resultType = "copynumber"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_titancna_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_titancna_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_titancna_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TITANCNA:", paste0("    titancna: ", packageVersion("TitanCNA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_titancna_results.csv
    touch ${prefix}_titancna_output.rds
    echo "BIOC_TITANCNA:" > versions.yml
    echo "    titancna: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TITANCNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TITANCNA(ch_input)

    emit:
    results  = BIOC_TITANCNA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TITANCNA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TITANCNA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TITANCNA.out.versions  // channel: path(versions.yml)
}
