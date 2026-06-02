#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ibh
// This package contains methods for calculating Interaction Based Homogeneity to evaluate fitness of g
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ibh/inst/doc/ibh.R
// Upstream  : simpIntLists, stats, yeastCC
// Downstream: none
//
// Install: BiocManager::install("ibh")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IBH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ibh"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ibh:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ibh:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ibh_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ibh_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ibh_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ibh)
    library(jsonlite)

    # --- Multiple Gene Lists Evaluation [] ---
    # Key functions: ibhForMultipleGeneLists, ibhForMultipleGeneListsBioGRID
    data(ArabidopsisBioGRIDInteractionEntrezId)
    listofGeneList <- list(
        list(839226, 817241, 824340, 832179, 818561, 831145, 838782, 826404), 
        list(832018, 839226, 838824)
    )
    res_multi <- ibhForMultipleGeneLists(
        ArabidopsisBioGRIDInteractionEntrezId, 
        listofGeneList
    )
    res_multi_biogrid <- ibhForMultipleGeneListsBioGRID(
        listofGeneList, 
        organism = "yeast", 
        idType = "UniqueId"
    )


    # --- Cluster Evaluation [] ---
    # Key functions: ibhClusterEval, ibhClusterEvalBioGRID
    data(YeastBioGRIDInteractionUniqueId)
    mock_matrix <- matrix(runif(500), nrow = 50)
    rownames(mock_matrix) <- paste0("YAL", sprintf("%03dC", 1:50))
    d <- dist(mock_matrix, method = "euclidean")
    k <- kmeans(d, 3)
    res_cluster <- ibhClusterEval(
        k$cluster, 
        rownames(mock_matrix), 
        YeastBioGRIDInteractionUniqueId
    )
    res_cluster_biogrid <- ibhClusterEvalBioGRID(
        k$cluster, 
        rownames(mock_matrix), 
        organism = "yeast", 
        idType = "UniqueId"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ibh_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ibh_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ibh_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IBH:", paste0("    ibh: ", packageVersion("ibh"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ibh_results.csv
    touch ${prefix}_ibh_output.rds
    echo "BIOC_IBH:" > versions.yml
    echo "    ibh: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IBH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IBH(ch_input)

    emit:
    results  = BIOC_IBH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IBH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IBH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IBH.out.versions  // channel: path(versions.yml)
}
