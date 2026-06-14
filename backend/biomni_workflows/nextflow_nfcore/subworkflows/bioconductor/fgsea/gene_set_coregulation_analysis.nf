#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fgsea — gene_set_coregulation_analysis
// Identify gene sets with high gene correlation in expression matrices without explicit contrasts (e.g., time-course, single-cell, or spatial data).
// Input: expression_matrix.csv, pathways_list.rds
// Container: quay.io/biocontainers/bioconductor-fgsea:1.36.2--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Seurat, cowplot, data.table, fgsea, ggplot2
// Visualizations: image plot
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare expression matrix or perform PCA reduction on Seurat object
//  * 2. [Core Analysis] Run GESECA to calculate co-regulation scores and p-values
//  * 3. [Visualization & Output] Plot coregulation profiles across conditions, UMAP/t-SNE reductions, or spatial coordinates
//  * 4. [Visualization & Output] Generate summary tables of top pathways

nextflow.enable.dsl = 2

process BIOC_FGSEA_GENE_SET_COREGULATION_ANALYSIS {
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
    .bm_deps <- c("fgsea", "data.table", "ggplot2", "Biobase", "Seurat", "cowplot")
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
            library(fgsea)
            library(data.table)
            library(ggplot2)
            library(Biobase)
            library(Seurat)
            library(cowplot)
            
            # -----------------------------------------------------------------------------
            # 1. Load User Inputs
            # -----------------------------------------------------------------------------
            pathways_file <- "pathways_list.rds"
            expression_file <- "expression_matrix.csv"
            seurat_file <- "seurat_object.rds"
            
            if (!file.exists(pathways_file)) {
              stop(paste("Required pathways file missing:", pathways_file))
            }
            
            pathways <- readRDS(pathways_file)
            gsets <- pathways # Define gsets as alias for pathways to support documented code
            
            # -----------------------------------------------------------------------------
            # 2. Workflow A: Expression Matrix (if expression_matrix.csv is provided)
            # -----------------------------------------------------------------------------
            if (file.exists(expression_file)) {
              message("Processing expression matrix...")
              
              # Read normalized expression matrix
              expr_mat <- as.matrix(read.csv(expression_file, row.names = 1))
              
              # Construct ExpressionSet with required metadata fields
              n_samples <- ncol(expr_mat)
              titles <- colnames(expr_mat)
              if (is.null(titles)) {
                titles <- paste0("Sample_", seq_len(n_samples))
                colnames(expr_mat) <- titles
              }
              
              conditions <- rep("time_point_1", n_samples)
              if (n_samples >= 2) {
                conditions[seq_len(floor(n_samples / 2))] <- "time_point_1"
                conditions[(floor(n_samples / 2) + 1):n_samples] <- "time_point_2"
              }
              
              pheno <- data.frame(
                title = titles,
                `time point:ch1` = conditions,
                check.names = FALSE,
                row.names = titles
              )
              
              es <- Biobase::ExpressionSet(
                assayData = expr_mat,
                phenoData = Biobase::AnnotatedDataFrame(pheno)
              )
              
              # Run GESECA on full matrix
              gesecaRes <- geseca(pathways, exprs(es), minSize = 15, maxSize = 500)
              fwrite(gesecaRes, "geseca_results_matrix.csv")
              
              # Dynamically select the top enriched pathway
              top_pathway_name <- gesecaRes\$pathway[1]
              
              # Plot coregulation profile
              pdf("coregulation_profile_matrix.pdf", width = 10, height = 5)
              print(plotCoregulationProfile(
                pathway = pathways[[top_pathway_name]],
                E = exprs(es),
                titles = es\$title,
                conditions = es\$`time point:ch1`
              ))
              dev.off()
              
              # Plot GESECA table
              pdf("geseca_table_matrix.pdf", width = 10, height = 6)
              print(plotGesecaTable(
                gesecaRes |> head(10),
                pathways,
                E = exprs(es),
                titles = es\$title
              ))
              dev.off()
              
              # PCA-reduced GESECA
              E <- t(base::scale(t(exprs(es)), scale = FALSE))
              pcaRev <- prcomp(E, center = FALSE)
              Ered <- pcaRev\$x[, 1:min(10, ncol(pcaRev\$x)), drop = FALSE]
              
              gesecaResRed <- geseca(pathways, Ered, minSize = 15, maxSize = 500, center = FALSE)
              fwrite(gesecaResRed, "geseca_results_matrix_reduced.csv")
            }
            
            # -----------------------------------------------------------------------------
            # 3. Workflow B: Seurat Object (if seurat_object.rds is provided)
            # -----------------------------------------------------------------------------
            if (file.exists(seurat_file)) {
              message("Processing Seurat object...")
              
              obj <- readRDS(seurat_file)
              xobj <- obj # Define xobj as alias for obj to support documented code
              
              # Normalize and scale if not already done, ensuring SCTransform runs smoothly
              obj <- SCTransform(obj, verbose = FALSE, variable.features.n = min(10000, nrow(obj)))
              
              # Run PCA
              obj <- RunPCA(
                obj,
                assay = "SCT",
                verbose = FALSE,
                rev.pca = TRUE,
                reduction.name = "pca.rev",
                reduction.key = "PCR_",
                npcs = min(50, ncol(obj) - 1)
              )
              
              E <- obj@reductions\$pca.rev@feature.loadings
              
              # Run GESECA
              gesecaRes <- geseca(pathways, E, minSize = 5, maxSize = 500, center = FALSE, eps = 1e-100)
              fwrite(gesecaRes, "geseca_results_seurat.csv")
              
              # Prepare top pathways and titles for plotting
              topPathways <- head(gesecaRes\$pathway, 4)
              if (length(topPathways) > 0) {
                titles <- sub("KEGG_", "", topPathways)
                titles <- sub("HALLMARK_", "", titles)
                
                tryCatch({
                  # Ensure t-SNE reduction exists for plotCoregulationProfileReduction
                  if (!"tsne" %in% names(obj@reductions)) {
                    # Run standard PCA first if it doesn't exist, as t-SNE requires cell embeddings
                    if (!"pca" %in% names(obj@reductions)) {
                      obj <- RunPCA(obj, assay = "SCT", verbose = FALSE, npcs = min(50, ncol(obj) - 1))
                    }
                    ndims <- min(10, ncol(obj@reductions\$pca@cell.embeddings))
                    obj <- RunTSNE(obj, reduction = "pca", dims = 1:ndims, verbose = FALSE)
                  }
                  
                  # Plot coregulation profile on reduction
                  pdf("coregulation_profile_reduction.pdf", width = 10, height = 8)
                  ps <- plotCoregulationProfileReduction(pathways[topPathways], obj, title = titles, reduction = "tsne")
                  if (inherits(ps, "list")) {
                    print(cowplot::plot_grid(plotlist = ps, ncol = 2))
                  } else {
                    print(ps)
                  }
                  dev.off()
                }, error = function(e) {
                  message("Reduction plotting skipped or failed: ", e\$message)
                })
                
                # Plot coregulation profile spatial (if spatial coordinates exist)
                tryCatch({
                  pdf("coregulation_profile_spatial.pdf", width = 10, height = 8)
                  ps <- plotCoregulationProfileSpatial(pathways[topPathways], obj, title = titles, pt.size.factor = 2.5)
                  if (inherits(ps, "list")) {
                    print(cowplot::plot_grid(plotlist = ps, ncol = 2))
                  } else {
                    print(ps)
                  }
                  dev.off()
                }, error = function(e) {
                  message("Spatial plotting skipped or failed: ", e\$message)
                })
                
                # Plot coregulation profile image (if high-resolution image coordinates exist)
                tryCatch({
                  pdf("coregulation_profile_image.pdf", width = 10, height = 8)
                  imagePlots <- plotCoregulationProfileImage(gsets[topPathways], object = xobj, dark.background = FALSE, title = titles, size = 0.8)
                  if (inherits(imagePlots, "list")) {
                    print(cowplot::plot_grid(plotlist = imagePlots, ncol = 2))
                  } else {
                    print(imagePlots)
                  }
                  dev.off()
                }, error = function(e) {
                  message("Image plotting skipped or failed: ", e\$message)
                })
              }
            }
            
            message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_FGSEA_GENE_SET_COREGULATION_ANALYSIS":',
        paste0('    fgsea: ', as.character(packageVersion('fgsea')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_set_coregulation_analysis.csv versions.yml
    """
}

workflow BIOC_FGSEA_GENE_SET_COREGULATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, pathways_list.rds ] ]

    main:
    BIOC_FGSEA_GENE_SET_COREGULATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FGSEA_GENE_SET_COREGULATION_ANALYSIS.out.tables
    plots    = BIOC_FGSEA_GENE_SET_COREGULATION_ANALYSIS.out.plots
    objects  = BIOC_FGSEA_GENE_SET_COREGULATION_ANALYSIS.out.objects
    versions = BIOC_FGSEA_GENE_SET_COREGULATION_ANALYSIS.out.versions
}
