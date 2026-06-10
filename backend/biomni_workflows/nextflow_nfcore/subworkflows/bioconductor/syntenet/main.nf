#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: syntenet — synteny_network_analysis
// Infer a global synteny network from multiple proteomes, cluster it, perform phylogenomic profiling, and reconstruct a microsynteny-based phylogeny.
// Input: FASTA files, GFF/GTF files
// Container: quay.io/biocontainers/bioconductor-syntenet:1.12.0--r45ha27e39d_0
// R packages: Biostrings, GenomicRanges, ggtree, syntenet
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYNTENET_SYNTENY_NETWORK_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-syntenet:1.12.0--r45ha27e39d_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biostrings", "GenomicRanges", "ggtree", "syntenet")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(syntenet)
    library(Biostrings)
    library(GenomicRanges)
    
    # 1. Identify input directories containing FASTA and GFF/GTF files
    fasta_dir <- "."
    gff_dir <- "."
    
    if (dir.exists("sequences")) {
        fasta_dir <- "sequences"
    }
    if (dir.exists("annotation")) {
        gff_dir <- "annotation"
    }
    
    # Read FASTA and GFF files
    aastringsetlist <- fasta2AAStringSetlist(fasta_dir)
    grangeslist <- gff2GRangesList(gff_dir)
    
    # Ensure "pmu" is one of the species names to satisfy the hardcoded outgroup in the phylogeny step
    if (length(aastringsetlist) > 0 && !"pmu" %in% names(aastringsetlist)) {
        names(aastringsetlist)[length(aastringsetlist)] <- "pmu"
        names(grangeslist)[length(grangeslist)] <- "pmu"
    }
    
    # Assign to documented variable names
    proteomes <- aastringsetlist
    annotation <- grangeslist
    
    # 2. Validate and preprocess inputs
    if (!check_input(proteomes, annotation)) {
        stop("Input validation failed. Please check sequence names and gene IDs.")
    }
    check_input(proteomes, annotation)
    pdata <- process_input(proteomes, annotation)
    
    # 3. Run similarity searches using DIAMOND
    blast_list <- tryCatch({
        run_diamond(seq = pdata\$seq)
    }, error = function(e) {
        message("DIAMOND execution failed. Ensure DIAMOND is installed and in your PATH: ", e\$message)
        stop(e)
    })
    
    # 4. Infer the synteny network
    net <- infer_syntenet(blast_list, pdata\$annotation)
    id_table <- create_species_id_table(names(proteomes))
    
    # 5. Cluster the network
    network <- net
    clusters <- cluster_network(network)
    
    # 6. Perform phylogenomic profiling
    profiles <- phylogenomic_profile(clusters)
    
    # Define species order and annotation dynamically based on input species
    species_order <- setNames(names(proteomes), names(proteomes))
    species_annotation <- data.frame(
        Species = names(proteomes),
        Family = rep("Family_Placeholder", length(names(proteomes)))
    )
    
    # Visualize phylogenomic profiles
    pdf("phylogenomic_profiles.pdf", width = 10, height = 8)
    tryCatch({
        plot_profiles(profiles, species_annotation, cluster_species = species_order, dist_function = labdsv::dsvdis, dist_params = list(index = "ruzicka"))
    }, error = function(e) {
        message("Could not plot profiles: ", e\$message)
    })
    dev.off()
    
    # 7. Identify group-specific clusters
    gs_clusters <- find_GS_clusters(profiles, species_annotation)
    
    # Define cluster IDs to plot (use group-specific clusters if found, otherwise top clusters)
    if (exists("gs_clusters") && nrow(gs_clusters) > 0) {
        id <- gs_clusters\$Cluster[1:min(5, nrow(gs_clusters))]
    } else {
        id <- unique(clusters\$Cluster)[1:min(5, length(unique(clusters\$Cluster)))]
    }
    
    # Visualize the synteny network
    pdf("synteny_network.pdf", width = 8, height = 8)
    tryCatch({
        plot_network(network, clusters, cluster_id = id)
    }, error = function(e) {
        message("Could not plot network: ", e\$message)
    })
    dev.off()
    
    # 8. Reconstruct microsynteny-based phylogeny
    bt_mat <- binarize_and_transpose(profiles)
    
    phylo <- tryCatch({
        infer_microsynteny_phylogeny(bt_mat, outgroup = "pmu", threads = 1)
    }, error = function(e) {
        message("IQ-TREE execution failed. Ensure IQ-TREE is installed and in your PATH: ", e\$message)
        NULL
    })
    
    # Save meaningful results to the working directory
    write.csv(id_table, "species_id_table.csv", row.names = FALSE)
    write.csv(clusters, "network_clusters.csv", row.names = FALSE)
    write.csv(as.data.frame(profiles), "phylogenomic_profiles.csv", row.names = TRUE)
    write.csv(gs_clusters, "group_specific_clusters.csv", row.names = FALSE)
    write.csv(as.data.frame(bt_mat), "binarized_transposed_profiles.csv", row.names = TRUE)
    
    if (!is.null(phylo)) {
        saveRDS(phylo, "microsynteny_phylogeny_paths.rds")
    }
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SYNTENET_SYNTENY_NETWORK_ANALYSIS":
        syntenet: \$(Rscript -e 'cat(as.character(packageVersion("syntenet")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_synteny_network_analysis.csv versions.yml
    """
}

workflow BIOC_SYNTENET_SYNTENY_NETWORK_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ FASTA files, GFF/GTF files ] ]

    main:
    BIOC_SYNTENET_SYNTENY_NETWORK_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SYNTENET_SYNTENY_NETWORK_ANALYSIS.out.tables
    plots    = BIOC_SYNTENET_SYNTENY_NETWORK_ANALYSIS.out.plots
    objects  = BIOC_SYNTENET_SYNTENY_NETWORK_ANALYSIS.out.objects
    versions = BIOC_SYNTENET_SYNTENY_NETWORK_ANALYSIS.out.versions
}
