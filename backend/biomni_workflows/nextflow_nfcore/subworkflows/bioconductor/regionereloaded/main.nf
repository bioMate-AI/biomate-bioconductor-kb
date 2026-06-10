#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regioneReloaded — crosswise_association_clustering
// Perform crosswise permutation tests between multiple genomic region sets, construct and cluster an association or correlation matrix, and visualize the results 
// Input: Alist, Blist, genome
// Container: quay.io/biocontainers/bioconductor-regionereloaded:1.12.0--r45hdfd78af_0
// R packages: GenomicRanges, regioneR, regioneReloaded
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, regioneR, regioneReloaded
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run crosswise permutation tests using crosswisePermTest() to calculate associations. 2. Build the association matrix and perform h

nextflow.enable.dsl = 2

process BIOC_REGIONERELOADED_CROSSWISE_ASSOCIATION_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("GenomicRanges", "regioneR", "regioneReloaded")
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
        library(regioneReloaded)
        library(regioneR)
        library(GenomicRanges)
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input Files
        # -----------------------------------------------------------------------------
        if (file.exists("Alist.rds")) {
          Alist <- readRDS("Alist.rds")
        } else {
          stop("Required input file 'Alist.rds' not found in the working directory.")
        }
        
        if (file.exists("Blist.rds")) {
          Blist <- readRDS("Blist.rds")
        } else {
          Blist <- NULL
        }
        
        if (file.exists("genome.rds")) {
          genome <- readRDS("genome.rds")
        } else {
          stop("Required input file 'genome.rds' not found in the working directory.")
        }
        
        # Ensure Alist is a standard list of GRanges
        Alist <- as.list(Alist)
        
        # Ensure names exist for Alist
        if (is.null(names(Alist))) {
          names(Alist) <- paste0("reg_set_A_", seq_along(Alist))
        }
        
        # Ensure Blist is a standard list of GRanges and has names if provided
        if (!is.null(Blist)) {
          Blist <- as.list(Blist)
          if (is.null(names(Blist))) {
            names(Blist) <- paste0("reg_set_B_", seq_along(Blist))
          }
        }
        
        # -----------------------------------------------------------------------------
        # 2. Run Crosswise Permutation Tests
        # -----------------------------------------------------------------------------
        if (is.null(Blist)) {
          # Run with resampleGenome
          cw_Alien_ReG <- crosswisePermTest(
            Alist = Alist,
            sampling = FALSE,
            mc.cores = 2,
            ranFUN = "resampleGenome",
            evFUN = "numOverlaps",
            genome = genome,
            ntimes = 100
          )
          
          # Run with resampleRegions to generate cw_Alien_ReR
          cw_Alien_ReR <- crosswisePermTest(
            Alist = Alist,
            sampling = FALSE,
            mc.cores = 2,
            ranFUN = "resampleRegions",
            evFUN = "numOverlaps",
            genome = genome,
            ntimes = 100
          )
        } else {
          # Run with resampleGenome
          cw_Alien_ReG <- crosswisePermTest(
            Alist = Alist,
            Blist = Blist,
            sampling = FALSE,
            mc.cores = 2,
            ranFUN = "resampleGenome",
            evFUN = "numOverlaps",
            genome = genome,
            ntimes = 100
          )
          
          # Run with resampleRegions to generate cw_Alien_ReR
          cw_Alien_ReR <- crosswisePermTest(
            Alist = Alist,
            Blist = Blist,
            sampling = FALSE,
            mc.cores = 2,
            ranFUN = "resampleRegions",
            evFUN = "numOverlaps",
            genome = genome,
            ntimes = 100
          )
        }
        
        # -----------------------------------------------------------------------------
        # 3. Build Association Matrices
        # -----------------------------------------------------------------------------
        cw_Alien_ReG <- makeCrosswiseMatrix(cw_Alien_ReG, pvcut = 1)
        cw_Alien_ReR <- makeCrosswiseMatrix(cw_Alien_ReR, pvcut = 1)
        
        # -----------------------------------------------------------------------------
        # 4. Visualization and Clustering (Output to PDF)
        # -----------------------------------------------------------------------------
        pdf("crosswise_association_plots.pdf", width = 10, height = 10)
        
        # Plot initial matrix
        plot(plotCrosswiseMatrix(cw_Alien_ReG))
        
        # Extract hierarchical clustering objects
        modX <- getHClust(cw_Alien_ReG, hctype = "rows")
        modY <- getHClust(cw_Alien_ReG, hctype = "cols")
        
        X <- modX\$labels[modX\$order]
        Y <- modY\$labels[modY\$order]
        ord <- list(X = X, Y = Y)
        
        # Plot clustered association matrices
        p_ReG <- plotCrosswiseMatrix(cw_Alien_ReG, matrix_type = "association", ord_mat = ord)
        p_ReR <- plotCrosswiseMatrix(cw_Alien_ReR, matrix_type = "association", ord_mat = ord)
        plot(p_ReG)
        plot(p_ReR)
        
        # Plot dendrogram
        plot(modX, cex = 0.8)
        
        # Plot correlation matrix
        p_ReG_cor <- plotCrosswiseMatrix(cw_Alien_ReG, matrix_type = "correlation", ord_mat = ord)
        plot(p_ReG_cor)
        
        # Determine valid region set names for downstream plotting
        rs1_name <- names(Alist)[1]
        if (!is.null(Blist)) {
          rs2_name <- names(Blist)[min(2, length(Blist))]
          rs3_name <- names(Blist)[min(3, length(Blist))]
        } else {
          rs2_name <- names(Alist)[min(2, length(Alist))]
          rs3_name <- names(Alist)[min(3, length(Alist))]
        }
        
        # Plot single pairwise permutation test results
        p_sPT0 <- plotSinglePT(cw_Alien_ReG, RS1 = rs1_name, RS2 = rs2_name)
        plot(p_sPT0)
        p_sPT1 <- plotSinglePT(cw_Alien_ReG, RS1 = rs1_name, RS2 = rs3_name)
        plot(p_sPT1)
        
        # Perform and plot dimensionality reduction
        n_clust <- min(6, length(Alist))
        
        plot(plotCrosswiseDimRed(cw_Alien_ReG, nc = n_clust, type = "PCA"))
        p_cdr_hc <- plotCrosswiseDimRed(cw_Alien_ReG, nc = n_clust, type = "PCA", clust_met = "hclust")
        plot(p_cdr_hc)
        
        # Dimensionality reduction with specific region sets highlighted
        lsRegSet <- as.list(names(Alist)[1:min(3, length(Alist))])
        names(lsRegSet) <- unlist(lsRegSet)
        
        plot(plotCrosswiseDimRed(cw_Alien_ReG, nc = n_clust, type = "PCA", listRS = lsRegSet))
        plot(plotCrosswiseDimRed(cw_Alien_ReG, nc = n_clust, type = "PCA", listRS = lsRegSet, ellipse = TRUE, emphasize = TRUE))
        plot(plotCrosswiseDimRed(cw_Alien_ReG, nc = n_clust, type = "tSNE", listRS = lsRegSet, ellipse = TRUE, emphasize = TRUE))
        plot(plotCrosswiseDimRed(cw_Alien_ReG, nc = n_clust, type = "UMAP", listRS = lsRegSet, ellipse = TRUE, emphasize = TRUE))
        
        # Extract silhouette table
        silTable <- plotCrosswiseDimRed(cw_Alien_ReG, nc = n_clust, type = "UMAP", listRS = lsRegSet, return_table = TRUE)
        
        dev.off()
        
        # -----------------------------------------------------------------------------
        # 5. Save Outputs to Disk
        # -----------------------------------------------------------------------------
        write.csv(silTable, "silhouette_table.csv", row.names = FALSE)
        saveRDS(cw_Alien_ReG, "cw_Alien_ReG.rds")
        saveRDS(cw_Alien_ReR, "cw_Alien_ReR.rds")

    writeLines(c(
        '"BIOC_REGIONERELOADED_CROSSWISE_ASSOCIATION_CLUSTERING":',
        paste0('    regioneReloaded: ', as.character(packageVersion('regioneReloaded')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crosswise_association_clustering.csv versions.yml
    """
}

workflow BIOC_REGIONERELOADED_CROSSWISE_ASSOCIATION_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Alist, Blist, genome ] ]

    main:
    BIOC_REGIONERELOADED_CROSSWISE_ASSOCIATION_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_REGIONERELOADED_CROSSWISE_ASSOCIATION_CLUSTERING.out.tables
    plots    = BIOC_REGIONERELOADED_CROSSWISE_ASSOCIATION_CLUSTERING.out.plots
    objects  = BIOC_REGIONERELOADED_CROSSWISE_ASSOCIATION_CLUSTERING.out.objects
    versions = BIOC_REGIONERELOADED_CROSSWISE_ASSOCIATION_CLUSTERING.out.versions
}
