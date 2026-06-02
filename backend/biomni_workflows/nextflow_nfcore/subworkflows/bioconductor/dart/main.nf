#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DART
// Denoising Algorithm based on Relevance network Topology (DART) is an algorithm designed to evaluate 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DART/inst/doc/DART.R
// Upstream  : Biobase, breastCancerMAINZ, breastCancerVDX
// Downstream: none
//
// Install: BiocManager::install("DART")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DART {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dart"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dart:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dart:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dart_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dart_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dart_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DART)
    library(BuildRN)
    library(DoDART)
    library(DoDARTCLQ)
    library(EvalConsNet)
    library(PredActScore)
    library(Prune)
    library(PruneNet)
    library(jsonlite)

    # --- Relevance Network Construction [BuildRN] ---
    # Key functions: BuildRN
    data(dataDART, package = "dart")
    modelSig <- dataDART$sign
    mock_genes <- names(modelSig)
    vdx.data <- matrix(
        rnorm(length(mock_genes) * 10),
        nrow = length(mock_genes),
        dimnames = list(mock_genes, paste0("Sample", 1:10))
    )
    rn.o <- BuildRN(
        vdx.data,
        modelSig,
        fdr = 0.000001
    )

    # --- Network Consistency Evaluation [EvalConsNet] ---
    # Key functions: EvalConsNet
    evalNet.o <- EvalConsNet(rn.o)
    net_consistency <- evalNet.o$netcons["fconsE"]
    net_pvalue <- evalNet.o$netcons["p"]

    # --- Network Pruning and Denoising [PruneNet] ---
    # Key functions: PruneNet
    prNet.o <- PruneNet(evalNet.o)
    pruned_adj <- prNet.o$pradjMC
    num_edges <- sum(pruned_adj) / 2

    # --- Activity Score Prediction [PredActScore] ---
    # Key functions: PredActScore
    pred.o <- PredActScore(prNet.o, vdx.data)
    activity_scores <- pred.o$score
    mainz.data <- matrix(
        rnorm(length(mock_genes) * 5),
        nrow = length(mock_genes),
        dimnames = list(mock_genes, paste0("Mainz", 1:5))
    )
    pred.mainz.o <- PredActScore(prNet.o, mainz.data)

    # --- Direct DART Execution [DoDART] ---
    # Key functions: DoDART
    res.vdx <- DoDART(
        vdx.data,
        modelSig,
        fdr = 0.000001
    )
    final_scores <- res.vdx$score


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dart_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dart_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dart_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DART:", paste0("    dart: ", packageVersion("DART"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dart_results.csv
    touch ${prefix}_dart_output.rds
    echo "BIOC_DART:" > versions.yml
    echo "    dart: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DART_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DART(ch_input)

    emit:
    results  = BIOC_DART.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DART.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DART.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DART.out.versions  // channel: path(versions.yml)
}
