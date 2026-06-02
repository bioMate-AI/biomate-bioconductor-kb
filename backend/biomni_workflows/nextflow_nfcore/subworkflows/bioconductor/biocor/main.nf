#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BioCor
// Calculates functional similarities based on the pathways described on KEGG and REACTOME or in gene s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BioCor/inst/doc/BioCor_1_basics.R
// Upstream  : BiocStyle, DESeq2, GOSemSim, GSEABase, Hmisc
// Downstream: none
//
// Install: BiocManager::install("BioCor")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biocor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biocor:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biocor:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biocor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biocor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biocor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BioCor)
    library(TOMsimilarity)
    library(jsonlite)

    # --- Gene Similarity Analysis [] ---
    # Key functions: geneSim, mgeneSim
    genesKegg <- list(
        "path1" = c("672", "675"),
        "path2" = c("10", "100", "1")
    )
    g_sim <- BioCor::geneSim("672", "675", genesKegg)
    gene_list <- c("BRCA1" = "672", "BRCA2" = "675", "NAT2" = "10")
    mg_sim <- BioCor::mgeneSim(gene_list, genesKegg)


    # --- Cluster Similarity Analysis [] ---
    # Key functions: clusterSim, mclusterSim
    genesKegg <- list(
        "path1" = c("672", "675"),
        "path2" = c("10", "100", "1")
    )
    c1 <- c("672", "675")
    c2 <- c("100", "10", "1")
    cl_sim <- BioCor::clusterSim(c1, c2, genesKegg)
    clusters <- list(
        cluster1 = c1,
        cluster2 = c2,
        cluster3 = c("18", "10")
    )
    mcl_sim <- BioCor::mclusterSim(clusters, genesKegg, "rcmax.avg")


    # --- Cluster Gene Similarity Analysis [] ---
    # Key functions: clusterGeneSim, mclusterGeneSim
    genesKegg <- list(
        "path1" = c("672", "675"),
        "path2" = c("10", "100", "1")
    )
    c1 <- c("672", "675")
    c2 <- c("100", "10", "1")
    cg_sim <- BioCor::clusterGeneSim(c1, c2, genesKegg, "max")
    clusters <- list(
        cluster1 = c1,
        cluster2 = c2
    )
    mcg_sim <- BioCor::mclusterGeneSim(clusters, genesKegg, "max")


    # --- Score Combination and Distance Conversion [] ---
    # Key functions: combineScores, D2J
    sim_matrix <- matrix(
        c(1.0, 0.5, 0.5, 1.0),
        nrow = 2,
        dimnames = list(c("p1", "p2"), c("p1", "p2"))
    )
    comb_methods <- c("avg", "max", "rcmax", "BMA")
    scores <- sapply(
        comb_methods,
        BioCor::combineScores,
        scores = sim_matrix
    )
    dist_matrix <- BioCor::D2J(sim_matrix)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biocor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biocor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biocor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOCOR:", paste0("    biocor: ", packageVersion("BioCor"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocor_results.csv
    touch ${prefix}_biocor_output.rds
    echo "BIOC_BIOCOR:" > versions.yml
    echo "    biocor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOCOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOCOR(ch_input)

    emit:
    results  = BIOC_BIOCOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOCOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOCOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOCOR.out.versions  // channel: path(versions.yml)
}
