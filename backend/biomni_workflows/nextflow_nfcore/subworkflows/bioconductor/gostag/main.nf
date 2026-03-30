#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: goSTAG
// Gene lists derived from the results of genomic analyses are rich in biological information. For inst
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/goSTAG/inst/doc/goSTAG.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("goSTAG")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GOSTAG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gostag"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gostag:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gostag:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gostag_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gostag_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gostag_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(goSTAG)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data( goSTAG_example_gene_lists )
    head( lapply( goSTAG_example_gene_lists, head ) )
    # --- Loadgoterms [] ---
    # Key functions: loadGOTerms
    ---------------------------------------------------------------------
    go_terms_mouse <- loadGOTerms( species = "mouse", domain = "MF", min_num_genes = 10 )
    # --- Performgoenrichment [] ---
    # Key functions: performGOEnrichment
    ---------------------------------------------------------------------
    enrichment_matrix <- performGOEnrichment( goSTAG_example_gene_lists, go_terms )
    head(enrichment_matrix)
    # --- Performhierarchicalclustering [] ---
    # Key functions: performHierarchicalClustering
    ---------------------------------------------------------------------
    hclust_results <- performHierarchicalClustering( enrichment_matrix )
    hclust_results
    # --- Groupclusters [] ---
    # Key functions: groupClusters
    ---------------------------------------------------------------------
    clusters <- groupClusters( hclust_results_euclidean )
    lapply( head( clusters ), head )
    # --- Annotateclusters [] ---
    # Key functions: annotateClusters
    ---------------------------------------------------------------------
    cluster_labels <- annotateClusters( clusters )
    head( cluster_labels )
    # --- Plotheatmap [] ---
    # Key functions: plotHeatmap
    ---------------------------------------------------------------------
    plotHeatmap( enrichment_matrix, hclust_results_euclidean, clusters, cluster_labels )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gostag_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gostag_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gostag_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GOSTAG:", paste0("    gostag: ", packageVersion("goSTAG"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gostag_results.csv
    touch ${prefix}_gostag_output.rds
    echo "BIOC_GOSTAG:" > versions.yml
    echo "    gostag: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GOSTAG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GOSTAG(ch_input)

    emit:
    results  = BIOC_GOSTAG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GOSTAG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GOSTAG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GOSTAG.out.versions  // channel: path(versions.yml)
}
