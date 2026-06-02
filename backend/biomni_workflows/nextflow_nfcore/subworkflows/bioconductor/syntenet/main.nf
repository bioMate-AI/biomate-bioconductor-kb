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
    library(syntenet)
    library(Annotation)
    library(jsonlite)

    # --- Input Processing and Validation [process_input] ---
    # Key functions: fasta2AAStringSetlist, gff2GRangesList, check_input, process_input
    fasta_dir <- system.file("extdata", "sequences", package = "syntenet")
    gff_dir <- system.file("extdata", "annotation", package = "syntenet")
    aastringsetlist <- fasta2AAStringSetlist(fasta_dir)
    grangeslist <- gff2GRangesList(gff_dir)
    data(proteomes)
    data(annotation)
    check_input(proteomes, annotation)
    pdata <- process_input(proteomes, annotation)

    # --- Synteny Network Inference [infer_syntenet] ---
    # Key functions: run_diamond, infer_syntenet, create_species_id_table
    data(proteomes)
    data(annotation)
    pdata <- process_input(proteomes, annotation)
    blast_list <- run_diamond(seq = pdata$seq)
    net <- infer_syntenet(blast_list, pdata$annotation)
    id_table <- create_species_id_table(names(proteomes))

    # --- Network Clustering and Profiling [cluster_network] ---
    # Key functions: cluster_network, phylogenomic_profile, find_GS_clusters
    data(network)
    clusters <- cluster_network(network)
    profiles <- phylogenomic_profile(clusters)
    species_order <- c("vra", "van", "pvu", "gma", "cca", "tpr")
    species_annotation <- data.frame(
        Species = species_order,
        Family = rep("Fabaceae", 6)
    )
    gs_clusters <- find_GS_clusters(profiles, species_annotation)

    # --- Visualization of Profiles and Networks [plot_profiles] ---
    # Key functions: plot_profiles, plot_network
    data(network)
    clusters <- cluster_network(network)
    profiles <- phylogenomic_profile(clusters)
    species_order <- c("vra", "van", "pvu", "gma", "cca", "tpr")
    species_annotation <- data.frame(
        Species = species_order,
        Family = rep("Fabaceae", 6)
    )
    plot_profiles(profiles, species_annotation, cluster_species = species_order)
    plot_network(network, clusters, cluster_id = clusters$Cluster[1:5])

    # --- Phylogeny Reconstruction [infer_microsynteny_phylogeny] ---
    # Key functions: binarize_and_transpose, infer_microsynteny_phylogeny
    data(network)
    clusters <- cluster_network(network)
    profiles <- phylogenomic_profile(clusters)
    bt_mat <- binarize_and_transpose(profiles)
    included <- rownames(bt_mat)[1:min(5, nrow(bt_mat))]
    bt_mat <- bt_mat[rownames(bt_mat) %in% included, ]
    bt_mat <- bt_mat[, colSums(bt_mat) != length(included)]
    phylo <- infer_microsynteny_phylogeny(bt_mat, threads = 1)

    # --- Intraspecies Synteny Detection [intraspecies_synteny] ---
    # Key functions: intraspecies_synteny, parse_collinearity
    data(scerevisiae_annot)
    data(scerevisiae_diamond)
    intra_syn <- intraspecies_synteny(
        scerevisiae_diamond, 
        scerevisiae_annot
    )
    scerevisiae_syn <- parse_collinearity(intra_syn)


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
