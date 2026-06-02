#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: syntenet
// syntenet can be used to infer synteny networks from whole-genome protein sequences and analyze them.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/syntenet/inst/doc/syntenet.R
// Upstream  : ggtree
// Downstream: none
//
// Install: BiocManager::install("syntenet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYNTENET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-syntenet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-syntenet:1.8.1--r44_0' :
        'quay.io/biocontainers/bioconductor-syntenet:1.8.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_syntenet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_syntenet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_syntenet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Annotation)
    library(jsonlite)

    # --- Annotation [] ---
    # Key functions: Annotation
    data(proteomes)
    head(proteomes)
    Annotation (ranges)
    # --- fasta2 A A String Setlist [] ---
    # Key functions: fasta2AAStringSetlist
    fasta_dir <- system.file("extdata", "sequences", package = "syntenet")
    dir(fasta_dir) # see the contents of the directory
    aastringsetlist <- fasta2AAStringSetlist(fasta_dir)
    # --- gff2 G Ranges List [] ---
    # Key functions: gff2GRangesList
    gff_dir <- system.file("extdata", "annotation", package = "syntenet")
    dir(gff_dir) # see the contents of the directory
    grangeslist <- gff2GRangesList(gff_dir)
    # --- check_input [] ---
    # Key functions: check_input
    check_input(proteomes, annotation)
    # --- process_input [] ---
    # Key functions: process_input
    pdata <- process_input(proteomes, annotation)
    # --- run_diamond [] ---
    # Key functions: run_diamond
    data(blast_list)
    if(diamond_is_installed()) {
    blast_list <- run_diamond(seq = pdata$seq)
    # --- infer_syntenet [] ---
    # Key functions: infer_syntenet
    net <- infer_syntenet(blast_list, pdata$annotation)
    head(net)
    # --- create species id table [] ---
    # Key functions: create_species_id_table
    id_table <- create_species_id_table(names(proteomes))
    # --- cluster_network [] ---
    # Key functions: cluster_network
    data(network)
    head(network)
    clusters <- cluster_network(network)
    # --- phylogenomic profile [] ---
    # Key functions: phylogenomic_profile
    profiles <- phylogenomic_profile(clusters)
    head(profiles)
    # --- set Names [] ---
    # Key functions: setNames, plot_profiles
    species_order <- setNames(
    c(
    c(
    # --- find GS clusters [] ---
    # Key functions: find_GS_clusters
    gs_clusters <- find_GS_clusters(profiles, species_annotation)
    head(gs_clusters)
    nrow(gs_clusters)
    # --- plot_profiles [] ---
    # Key functions: plot_profiles
    idx <- rownames(profiles) %in% gs_clusters$Cluster
    plot_profiles(
    # --- plot_network [] ---
    # Key functions: plot_network
    plot_network(network, clusters, cluster_id = id)
    genes <- unique(c(network$node1, network$node2))
    gene_df <- data.frame(
    # --- binarize_and_transpose [] ---
    # Key functions: binarize_and_transpose
    bt_mat <- binarize_and_transpose(profiles)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_syntenet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_syntenet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_syntenet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SYNTENET:", paste0("    syntenet: ", packageVersion("syntenet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_syntenet_results.csv
    touch ${prefix}_syntenet_output.rds
    echo "BIOC_SYNTENET:" > versions.yml
    echo "    syntenet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SYNTENET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SYNTENET(ch_input)

    emit:
    results  = BIOC_SYNTENET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SYNTENET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SYNTENET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SYNTENET.out.versions  // channel: path(versions.yml)
}
