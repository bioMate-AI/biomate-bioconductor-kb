#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SigFuge
// Algorithm for testing significance of clustering in RNA-seq data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SigFuge/inst/doc/SigFuge.R
// Upstream  : Rsamtools, prebsdata
// Downstream: none
//
// Install: BiocManager::install("SigFuge")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIGFUGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sigfuge"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sigfuge:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sigfuge:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sigfuge_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sigfuge_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sigfuge_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SigFuge)
    library(ApplyPileupsParam)
    library(GRanges)
    library(IRanges)
    library(PileupFiles)
    library(Rle)
    library(SFfigure)
    library(SFlabels)
    library(SFnormalize)
    library(SFpval)
    library(jsonlite)

    # --- Data Preparation [sigfuge] ---
    # Key functions: sigfuge
    data(sigfuge_example)
    features <- sigfuge_example$features
    grid <- sigfuge_example$grid
    norm_features <- features / rowSums(features)

    # --- Clustering and Significance Testing [sigfuge] ---
    # Key functions: sigfuge
    sf_result <- sigfuge(
        X = norm_features,
        grid = grid,
        nclust = 2
    )

    # --- Visualisation [sigfuge] ---
    # Key functions: sigfugePlot
    sigfugePlot(
        X = norm_features,
        grid = grid,
        class = sf_result$class
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sigfuge_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sigfuge_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sigfuge_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIGFUGE:", paste0("    sigfuge: ", packageVersion("SigFuge"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sigfuge_results.csv
    touch ${prefix}_sigfuge_output.rds
    echo "BIOC_SIGFUGE:" > versions.yml
    echo "    sigfuge: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIGFUGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIGFUGE(ch_input)

    emit:
    results  = BIOC_SIGFUGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIGFUGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIGFUGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIGFUGE.out.versions  // channel: path(versions.yml)
}
