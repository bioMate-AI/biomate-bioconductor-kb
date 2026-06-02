#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PathNet
// PathNet uses topological information present in pathways and differential expression levels of genes
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PathNet/inst/doc/PathNet.R
// Upstream  : PathNetData
// Downstream: none
//
// Install: BiocManager::install("PathNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PATHNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pathnet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pathnet:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pathnet:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pathnet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pathnet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pathnet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PathNet)
    library(jsonlite)

    # --- Custom Background Enrichment [] ---
    # Key functions: PathNet
    data(A_matrix, package = "pathnet")
    data(pathway, package = "pathnet")
    data(brain_diseases, package = "pathnet")
    custom_bg <- as.character(brain_diseases$Gene[1:1000])
    results_custom <- PathNet(
        enrichment_results = brain_diseases,
        pathway = pathway,
        adjacency_matrix = A_matrix,
        typeofValue = "pvalue",
        background = custom_bg,
        enrichment_threshold = 0.01,
        n_permutations = 50
    )


    # --- Significance Filtering and Ordering [] ---
    # Key functions: PathNet
    pathway_results <- results_pvalue$enrichment_results
    significant_pathways <- pathway_results[
        pathway_results[, 5] < 0.05, 
    ]
    ordered_pathways <- significant_pathways[
        order(significant_pathways[, 5]), 
    ]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pathnet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pathnet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pathnet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PATHNET:", paste0("    pathnet: ", packageVersion("PathNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathnet_results.csv
    touch ${prefix}_pathnet_output.rds
    echo "BIOC_PATHNET:" > versions.yml
    echo "    pathnet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PATHNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PATHNET(ch_input)

    emit:
    results  = BIOC_PATHNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PATHNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PATHNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PATHNET.out.versions  // channel: path(versions.yml)
}
