#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpatialCPie — spatial_clustering_and_subclustering
// Perform spatial transcriptomics cluster evaluation across multiple resolutions, visualize cluster transitions and spatial distributions, and perform sub-cluster
// Input: counts.tsv, he_image.jpg, spot_data.tsv
// Container: quay.io/biocontainers/bioconductor-spatialcpie:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialCPie, dplyr, ggplot2, jpeg, purrr, rlang
// Visualizations: cluster plot
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the count matrix, tissue image, and spot coordinates
//  * 2. [Visualization & Output] Preprocess the data by filtering out spots outside the
//  * 3. [Visualization & Output] Run the cluster evaluation and visualization using runCPie
//  * 4. [Visualization & Output] Visualize the cluster transition graph and spatial array
//  * 5. [Visualization & Output] Select specific clusters for sub-clustering and re-run

nextflow.enable.dsl = 2

process BIOC_SPATIALCPIE_SPATIAL_CLUSTERING_AND_SUBCLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("SpatialCPie", "dplyr", "jpeg", "ggplot2", "rlang")
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
    library(SpatialCPie)
    library(dplyr)
    library(jpeg)
    library(ggplot2)
    library(rlang)
    
    # Set seed for reproducibility
    set.seed(42)
    
    # Patch SpatialCPie::runCPie so that it runs headlessly without starting the Shiny gadget
    assignInNamespace(
        ns = "SpatialCPie",
        x = "runCPie",
        value = function(
            counts,
            image = NULL,
            spotCoordinates = NULL,
            margin = "spot",
            resolutions = 2:4,
            assignmentFunction = function(k, x) kmeans(x, centers =  k)\$cluster,
            scoreMultiplier = 1.0
        ) {
            data <- SpatialCPie:::.preprocessData(
                counts,
                coordinates = spotCoordinates,
                margin = margin,
                resolutions = resolutions,
                assignmentFunction = assignmentFunction
            )
            arrayPlots <- lapply(
                setNames(
                    nm = levels(data\$scores\$resolution) %>%
                        purrr::keep(~ . > 1)
                ),
                function(r) {
                    scores <- data\$scores %>% filter(.data\$resolution == r)
                    p <- SpatialCPie:::.arrayPlot(
                        scores = scores %>%
                            select(.data\$spot, .data\$name, .data\$score),
                        coordinates = data\$coordinates,
                        image =
                            if (!is.null(image) && !is.null(data\$coordinates))
                                grid::rasterGrob(
                                    image,
                                    width  = grid::unit(1, "npc"),
                                    height = grid::unit(1, "npc"),
                                    interpolate = TRUE
                                )
                            else NULL,
                        scoreMultiplier = scoreMultiplier,
                        spotOpacity = if (is.null(image)) 1.0 else 0.7
                    ) +
                        ggplot2::guides(
                            fill = ggplot2::guide_legend(title = "Cluster")
                        ) +
                        ggplot2::scale_fill_manual(
                            values = data\$colors,
                            labels = unique(scores\$cluster)
                        )
                }
            )
            list(
                clusters = data\$assignments %>% select(-.data\$name),
                clusterGraph = SpatialCPie:::.clusterGraph(
                    data\$assignments,
                    data\$means,
                    data\$featureName,
                    transitionLabels = TRUE,
                    transitionThreshold = 0.05
                ) +
                    ggplot2::scale_color_manual(values = data\$colors),
                arrayPlot = arrayPlots
            )
        }
    )
    
    # --- Load the count matrix, tissue image, and spot coordinates ---
    counts <- read.table(
        "counts.tsv",
        sep = "\t",
        check.names = FALSE
    )
    
    tissue <- jpeg::readJPEG(
        "he_image.jpg"
    )
    
    spots <- parseSpotFile(
        "spot_data.tsv"
    )
    
    # --- Preprocess the data by filtering out spots outside the ---
    counts <- counts[, which(colnames(counts) %in% rownames(spots))]
    
    repeat {
        d <- dim(counts)
        counts <- counts[rowSums(counts) >= 20, colSums(counts) >= 20]
        if (all(dim(counts) == d)) {
            break
        }
    }
    
    # --- Run the cluster evaluation and visualization using runCPie ---
    result <- runCPie(
        counts,
        image = tissue,
        spotCoordinates = spots
    )
    
    # Save the primary clustering results
    saveRDS(result, "spatial_cpie_result.rds")
    write.csv(result\$clusters, "primary_clusters.csv", row.names = FALSE)
    
    # --- Visualize the cluster transition graph and spatial array ---
    pdf("primary_cluster_graph.pdf", width = 8, height = 6)
    print(result\$clusterGraph)
    dev.off()
    
    pdf("primary_array_plot_resolution_4.pdf", width = 8, height = 8)
    print(result\$arrayPlot\$`4`)
    dev.off()
    
    # --- Select specific clusters for sub-clustering and re-run ---
    subcluster_df <- result\$clusters %>%
        filter(resolution == 4, cluster %in% c(1, 4))
    subcluster <- subcluster_df\$unit
    
    subclusterResult <- runCPie(
        counts = counts[, subcluster],
        image = tissue,
        spotCoordinates = spots
    )
    
    # Save the sub-clustering results
    saveRDS(subclusterResult, "subcluster_result.rds")
    write.csv(subclusterResult\$clusters, "subcluster_assignments.csv", row.names = FALSE)
    
    # Visualize sub-clustering outputs
    pdf("subcluster_graph.pdf", width = 8, height = 6)
    print(subclusterResult\$clusterGraph)
    dev.off()
    
    pdf("subcluster_array_plot_resolution_3.pdf", width = 8, height = 8)
    print(subclusterResult\$arrayPlot\$`3`)
    dev.off()

    writeLines(c(
        '"BIOC_SPATIALCPIE_SPATIAL_CLUSTERING_AND_SUBCLUSTERING":',
        paste0('    SpatialCPie: ', as.character(packageVersion('SpatialCPie')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_clustering_and_subclustering.csv versions.yml
    """
}

workflow BIOC_SPATIALCPIE_SPATIAL_CLUSTERING_AND_SUBCLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.tsv, he_image.jpg, spot_data.tsv ] ]

    main:
    BIOC_SPATIALCPIE_SPATIAL_CLUSTERING_AND_SUBCLUSTERING(ch_input)

    emit:
    tables   = BIOC_SPATIALCPIE_SPATIAL_CLUSTERING_AND_SUBCLUSTERING.out.tables
    plots    = BIOC_SPATIALCPIE_SPATIAL_CLUSTERING_AND_SUBCLUSTERING.out.plots
    objects  = BIOC_SPATIALCPIE_SPATIAL_CLUSTERING_AND_SUBCLUSTERING.out.objects
    versions = BIOC_SPATIALCPIE_SPATIAL_CLUSTERING_AND_SUBCLUSTERING.out.versions
}
