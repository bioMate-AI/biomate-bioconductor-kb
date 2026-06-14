#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: COTAN — gene_coexpression_and_clustering
// Calculate gene-pair co-expression (COEX), calculate Global Differentiation Index (GDI), and establish gene clusters.
// Input: obj
// Container: quay.io/biocontainers/bioconductor-cotan:2.10.3--r45hdfd78af_0
// R packages: COTAN, zeallot
// Bioconductor: 3.20 | R: 4.4
// Requires: COTAN, conflicted, zeallot
// Visualizations: heatmap, cluster plot, UMAP plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Calibrate the COTAN model and calculate the full
//  * 2. [Visualization & Output] Retrieve contingency tables and specific COEX values for
//  * 3. [Visualization & Output] Calculate and store the Global Differentiation Index (GDI)
//  * 4. [Visualization & Output] Plot GDI to identify highly differentiated genes
//  * 5. [Visualization & Output] Generate COEX heatmaps for gene sets
//  * 6. [Visualization & Output] Establish gene clusters based on marker lists
//  * 7. [Visualization & Output] Visualize gene clusters using UMAP

nextflow.enable.dsl = 2

process BIOC_COTAN_GENE_COEXPRESSION_AND_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("COTAN", "zeallot")
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
    library(COTAN)
    library(zeallot)
    
    # Resolve precedence of overloads
    conflicted::conflict_prefer("%<-%", "zeallot")
    
    # Enable multi-processing
    options(parallelly.fork.enable = TRUE)
    
    # -------------------------------------------------------------------------
    # 1. Read User Input
    # -------------------------------------------------------------------------
    # The pipeline expects a cleaned COTAN object named 'obj.rds' or 'cleaned_cotan_obj.rds'
    # in the working directory.
    input_file <- NULL
    possible_files <- c("obj.rds", "cleaned_cotan_obj.rds")
    for (f in possible_files) {
      if (file.exists(f)) {
        input_file <- f
        break
      }
    }
    
    if (is.null(input_file)) {
      # Fallback: search for any RDS file in the working directory
      rds_files <- list.files(pattern = "\\\\.rds\$", ignore.case = TRUE)
      if (length(rds_files) > 0) {
        input_file <- rds_files[1]
      } else {
        stop("Error: Cleaned COTAN object (obj.rds) not found in the working directory.")
      }
    }
    
    message("Reading input COTAN object from: ", input_file)
    obj <- readRDS(input_file)
    
    # -------------------------------------------------------------------------
    # 2. Define Vignette Gene Lists (Filtered for Existing Genes)
    # -------------------------------------------------------------------------
    all_genes <- getGenes(obj)
    
    genesLists <- list(
      "NPGs" = c("Nes", "Vim", "Sox2", "Sox1", "Notch1", "Hes1", "Hes5", "Pax6"),
      "PNGs" = c("Map2", "Tubb3", "Neurod1", "Nefm", "Nefl", "Dcx", "Tbr1"),
      "hk" = c("Calm1", "Cox6b1", "Ppia", "Rpl18", "Cox7c", "Erh", "H3f3a", "Taf1", "Taf2", "Gapdh", "Actb", "Golph3", "Zfr", "Sub1", "Tars", "Amacr")
    )
    # Ensure only genes present in the dataset are used to prevent downstream errors
    genesLists <- lapply(genesLists, function(x) intersect(x, all_genes))
    genesLists <- genesLists[lengths(genesLists) > 0]
    if (length(genesLists) < 2) {
      genesLists <- list(
        "Sample1" = all_genes[1:min(5, length(all_genes))],
        "Sample2" = all_genes[min(6, length(all_genes)):min(10, length(all_genes))]
      )
    }
    
    layersMarkers <- c("Satb2", "Bcl11b", "Vim", "Hes1")
    layersMarkers <- intersect(layersMarkers, all_genes)
    if (length(layersMarkers) == 0) {
      layersMarkers <- all_genes[1:min(4, length(all_genes))]
    }
    
    layersGenes <- list(
      "L1" = c("Reln", "Lhx5"),
      "L2/3" = c("Cux1", "Satb2"),
      "L4" = c("Rorb", "Sox5"),
      "L5/6" = c("Bcl11b", "Fezf2"),
      "Prog" = c("Hes1", "Vim", "Dummy")
    )
    layersGenes <- lapply(layersGenes, function(x) intersect(x, all_genes))
    layersGenes <- layersGenes[lengths(layersGenes) > 0]
    if (length(layersGenes) < 2) {
      layersGenes <- list(
        "Group1" = all_genes[1:min(2, length(all_genes))],
        "Group2" = all_genes[min(3, length(all_genes)):min(4, length(all_genes))]
      )
    }
    
    # -------------------------------------------------------------------------
    # 3. Execute Documented Workflow Steps
    # -------------------------------------------------------------------------
    
    # --- Calibrate the COTAN model and calculate the full ---
    message("Proceeding to COEX estimation...")
    obj <- proceedToCoex( obj, calcCoex = TRUE, optimizeForSpeed = TRUE, cores = 3L, deviceStr = "cuda" )
    
    # --- Retrieve contingency tables and specific COEX values for ---
    message("Retrieving contingency tables and COEX values...")
    g1 <- if ("Satb2" %in% all_genes) "Satb2" else all_genes[1]
    g2 <- if ("Bcl11b" %in% all_genes) "Bcl11b" else all_genes[2]
    
    ct_list <- contingencyTables(obj, g1 = g1, g2 = g2)
    saveRDS(ct_list, file = paste0("contingency_tables_", g1, "_", g2, ".rds"))
    
    coex <- getGenesCoex(obj, zeroDiagonal = FALSE)
    saveRDS(coex, file = "genes_coex_matrix.rds")
    
    # --- Calculate and store the Global Differentiation Index (GDI) ---
    message("Calculating and storing GDI...")
    gdiDF <- calculateGDI(obj, cores = 3L)
    write.csv(gdiDF, file = "genes_GDI_table.csv", row.names = TRUE)
    
    obj <- storeGDI(obj, genesGDI = gdiDF)
    saveRDS(obj, file = "cotan_obj_with_gdi.rds")
    
    # --- Plot GDI to identify highly differentiated genes ---
    message("Generating GDI Plot...")
    pdf("GDI_plot.pdf", width = 8, height = 6)
    print(GDIPlot(obj, genes = genesLists, GDIThreshold = 1.40))
    dev.off()
    
    # --- Generate COEX heatmaps for gene sets ---
    message("Generating COEX Heatmaps...")
    pdf("COEX_heatmaps.pdf", width = 10, height = 8)
    sets_to_plot <- 1L:min(3L, length(genesLists))
    plot(heatmapPlot(obj, genesLists = genesLists, sets = sets_to_plot, cores = 3L))
    
    genesHeatmapPlot( obj, primaryMarkers = layersMarkers, pValueThreshold = 0.0001, symmetric = TRUE, cores = 3L )
    dev.off()
    
    # --- Establish gene clusters based on marker lists ---
    message("Establishing gene clusters...")
    c(gSpace, eigPlot, pcaGenesClDF, treePlot) %<-% establishGenesClusters( obj, groupMarkers = layersGenes, numGenesPerMarker = 25L, kCuts = 5L )
    
    write.csv(pcaGenesClDF, file = "pca_genes_clustering_df.csv", row.names = TRUE)
    
    pdf("gene_clusters_dendrogram_and_eigen.pdf", width = 8, height = 6)
    plot(eigPlot)
    plot(treePlot)
    dev.off()
    
    # --- Visualize gene clusters using UMAP ---
    message("Generating UMAP Plot of gene clusters...")
    colSelection <- vapply(pcaGenesClDF, is.numeric, logical(1L))
    genesUmapPl <- UMAPPlot( pcaGenesClDF[, colSelection, drop = FALSE], clusters = getColumnFromDF(pcaGenesClDF, "hclust"), elements = layersGenes, title = "Genes' clusters UMAP Plot", numNeighbors = 32L, minPointsDist = 0.25 )
    
    pdf("genes_clusters_umap.pdf", width = 8, height = 6)
    plot(genesUmapPl)
    dev.off()
    
    message("Pipeline completed successfully. All outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_COTAN_GENE_COEXPRESSION_AND_CLUSTERING":',
        paste0('    COTAN: ', as.character(packageVersion('COTAN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_coexpression_and_clustering.csv versions.yml
    """
}

workflow BIOC_COTAN_GENE_COEXPRESSION_AND_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ obj ] ]

    main:
    BIOC_COTAN_GENE_COEXPRESSION_AND_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_COTAN_GENE_COEXPRESSION_AND_CLUSTERING.out.tables
    plots    = BIOC_COTAN_GENE_COEXPRESSION_AND_CLUSTERING.out.plots
    objects  = BIOC_COTAN_GENE_COEXPRESSION_AND_CLUSTERING.out.objects
    versions = BIOC_COTAN_GENE_COEXPRESSION_AND_CLUSTERING.out.versions
}
