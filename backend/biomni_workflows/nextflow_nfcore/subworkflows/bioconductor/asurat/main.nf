#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ASURAT — multifaceted_sign_analysis
// Perform single-cell RNA-seq preprocessing, functional sign creation from databases, sign-by-sample matrix generation, clustering, and multifaceted visualization
// Input: counts_matrix.csv, database.rda
// Container: quay.io/biocontainers/bioconductor-asurat:1.14.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ASURAT, AnnotationDbi, Rtsne, Seurat, SingleCellExperiment, SummarizedExperiment, dplyr, ggplot2, org.Hs.eg.db, scales
// Visualizations: heatmap, violin plot
// QC: clustering QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare SingleCellExperiment object and add metadata using add_metadata
//  * 2. [Core Analysis] Perform quality control filtering on genes and cells using remove_variables, remove_samples, and remove_variables_second
//  * 3. [Core Analysis] Normalize and center expression data
//  * 4. [Core Analysis] Compute gene expression correlation matrix
//  * 5. [Input & Preparation] Load databases and define functional gene sets using remove_signs
//  * 6. [Core Analysis] Cluster gene sets into strongly/variably correlated groups using cluster_genesets
//  * 7. [Input & Preparation] Create signs using create_signs and filter redundant or manual signs using remove_signs_redundant and remove_signs_manually
//  * 8. [Core Analysis] Generate sign-by-sample matrices (SSMs) using makeSignMatrix
//  * 9. [Core Analysis] Perform dimensional reduction (t-SNE) and cluster cells (using Seurat)
//  * 10. [Core Analysis] Identify significant signs using compute_sepI_all and genes
//  * 11. [Visualization & Output] Visualize results using multifaceted heatmaps with plot_multiheatmaps and violin plots

nextflow.enable.dsl = 2

process BIOC_ASURAT_MULTIFACETED_SIGN_ANALYSIS {
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
    .bm_deps <- c("ASURAT", "AnnotationDbi", "org.Hs.eg.db", "Rtsne", "Seurat", "dplyr", "scales", "ggplot2", "SummarizedExperiment")
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
    library(ASURAT)
    library(SummarizedExperiment)
    library(AnnotationDbi)
    library(org.Hs.eg.db)
    library(Rtsne)
    library(Seurat)
    library(dplyr)
    library(scales)
    library(ggplot2)
    
    # 1. Prepare SingleCellExperiment object and add metadata
    # Read raw single-cell RNA-seq read count matrix from working directory
    counts_matrix <- read.csv("counts_matrix.csv", row.names = 1, check.names = FALSE)
    pbmc_counts <- as.matrix(counts_matrix)
    
    pbmc <- SingleCellExperiment(
      assays = list(counts = pbmc_counts),
      rowData = data.frame(gene = rownames(pbmc_counts)),
      colData = data.frame(cell = colnames(pbmc_counts))
    )
    
    pbmc <- add_metadata(sce = pbmc, mitochondria_symbol = "^MT-")
    
    # 2. Perform quality control filtering on genes and cells
    pbmc <- remove_variables(sce = pbmc, min_nsamples = 10)
    pbmc <- remove_samples(sce = pbmc, min_nReads = 5000, max_nReads = 20000, min_nGenes = 100, max_nGenes = 1e+10, min_percMT = 0, max_percMT = 10)
    pbmc <- remove_variables_second(sce = pbmc, min_meannReads = 0.05)
    
    # 3. Normalize and center expression data
    assay(pbmc, "logcounts") <- log(assay(pbmc, "counts") + 1)
    mat <- assay(pbmc, "logcounts")
    assay(pbmc, "centered") <- sweep(mat, 1, apply(mat, 1, mean), FUN = "-")
    sname <- "logcounts"
    altExp(pbmc, sname) <- SummarizedExperiment(list(counts = assay(pbmc, sname)))
    
    dictionary <- AnnotationDbi::select(org.Hs.eg.db::org.Hs.eg.db, key = rownames(pbmc), columns = "ENTREZID", keytype = "SYMBOL")
    dictionary <- dictionary[!duplicated(dictionary\$SYMBOL), ]
    rowData(pbmc)\$geneID <- dictionary\$ENTREZID
    
    # 4. Compute gene expression correlation matrix
    set.seed(1)
    nrand_samples <- min(1000, ncol(pbmc))
    mat <- t(as.matrix(assay(pbmc, "centered")))
    ids <- sample(rownames(mat), nrand_samples, prob = NULL)
    cormat <- cor(mat[ids, ], method = "spearman")
    
    # 5. Load databases and define functional gene sets
    load("database.rda")
    
    # Create custom-built (CB) cell type-related database
    d <- list(human_CO[["cell"]], human_MSigDB[["cell"]])
    res <- do.call("rbind", d)
    human_CB <- list(cell = res)
    
    pbmcs <- list(CB = pbmc, GO = pbmc, KG = pbmc)
    metadata(pbmcs\$CB) <- list(sign = human_CB[["cell"]])
    metadata(pbmcs\$GO) <- list(sign = human_GO[["BP"]])
    metadata(pbmcs\$KG) <- list(sign = human_KEGG[["pathway"]])
    
    pbmcs\$CB <- remove_signs(sce = pbmcs\$CB, min_ngenes = 2, max_ngenes = 1000)
    pbmcs\$GO <- remove_signs(sce = pbmcs\$GO, min_ngenes = 2, max_ngenes = 1000)
    pbmcs\$KG <- remove_signs(sce = pbmcs\$KG, min_ngenes = 2, max_ngenes = 1000)
    
    # 6. Cluster gene sets into strongly/variably correlated groups
    set.seed(1)
    pbmcs\$CB <- cluster_genesets(sce = pbmcs\$CB, cormat = cormat, th_posi = 0.30, th_nega = -0.30)
    set.seed(1)
    pbmcs\$GO <- cluster_genesets(sce = pbmcs\$GO, cormat = cormat, th_posi = 0.30, th_nega = -0.30)
    set.seed(1)
    pbmcs\$KG <- cluster_genesets(sce = pbmcs\$KG, cormat = cormat, th_posi = 0.20, th_nega = -0.20)
    
    # 7. Create signs and filter redundant or manual signs
    pbmcs\$CB <- create_signs(sce = pbmcs\$CB, min_cnt_strg = 2, min_cnt_vari = 2)
    pbmcs\$GO <- create_signs(sce = pbmcs\$GO, min_cnt_strg = 4, min_cnt_vari = 4)
    pbmcs\$KG <- create_signs(sce = pbmcs\$KG, min_cnt_strg = 3, min_cnt_vari = 3)
    
    pbmcs\$GO <- remove_signs_redundant(sce = pbmcs\$GO, similarity_matrix = human_GO\$similarity_matrix\$BP, threshold = 0.70, keep_rareID = TRUE)
    keywords <- "Covid|COVID"
    pbmcs\$KG <- remove_signs_manually(sce = pbmcs\$KG, keywords = keywords)
    
    # 8. Generate sign-by-sample matrices (SSMs)
    pbmcs\$CB <- makeSignMatrix(sce = pbmcs\$CB, weight_strg = 0.5, weight_vari = 0.5)
    pbmcs\$GO <- makeSignMatrix(sce = pbmcs\$GO, weight_strg = 0.5, weight_vari = 0.5)
    pbmcs\$KG <- makeSignMatrix(sce = pbmcs\$KG, weight_strg = 0.5, weight_vari = 0.5)
    
    # 9. Perform dimensional reduction (t-SNE) and cluster cells
    pca_dims <- c(30, 30, 50)
    tsne_dims <- c(2, 2, 3)
    for(i in seq_along(pbmcs)){
      set.seed(1)
      mat <- t(as.matrix(assay(pbmcs[[i]], "counts")))
      res <- Rtsne::Rtsne(mat, dim = tsne_dims[i], pca = TRUE, initial_dims = pca_dims[i])
      reducedDim(pbmcs[[i]], "TSNE") <- res[["Y"]]
    }
    
    resolutions <- c(0.20, 0.20, 0.10)
    ds <- list(seq_len(20), seq_len(20), seq_len(20))
    for(i in seq_along(pbmcs)){
      surt <- Seurat::as.Seurat(pbmcs[[i]], counts = "counts", data = "counts")
      mat <- as.matrix(assay(pbmcs[[i]], "counts"))
      surt[["SSM"]] <- Seurat::CreateAssayObject(counts = mat)
      Seurat::DefaultAssay(surt) <- "SSM"
      surt <- Seurat::ScaleData(surt, features = rownames(surt))
      surt <- Seurat::RunPCA(surt, features = rownames(surt))
      surt <- Seurat::FindNeighbors(surt, reduction = "pca", dims = ds[[i]])
      surt <- Seurat::FindClusters(surt, resolution = resolutions[i])
      temp <- Seurat::as.SingleCellExperiment(surt)
      colData(pbmcs[[i]])\$seurat_clusters <- colData(temp)\$seurat_clusters
    }
    
    # Infer cell cycle phases using Seurat functions
    surt <- Seurat::as.Seurat(pbmcs\$CB, counts = "counts", data = "counts")
    mat <- as.matrix(assay(altExp(pbmcs\$CB), "counts"))
    surt[["GEM"]] <- Seurat::CreateAssayObject(counts = mat)
    Seurat::DefaultAssay(surt) <- "GEM"
    surt <- Seurat::ScaleData(surt, features = rownames(surt))
    surt <- Seurat::RunPCA(surt, features = rownames(surt))
    surt <- Seurat::CellCycleScoring(surt, s.features = Seurat::cc.genes\$s.genes, g2m.features = Seurat::cc.genes\$g2m.genes)
    temp <- Seurat::as.SingleCellExperiment(surt)
    colData(pbmcs\$CB)\$Phase <- colData(temp)\$Phase
    
    # 10. Identify significant signs and genes
    for(i in seq_along(pbmcs)){
      set.seed(1)
      labels <- colData(pbmcs[[i]])\$seurat_clusters
      pbmcs[[i]] <- compute_sepI_all(sce = pbmcs[[i]], labels = labels, nrand_samples = 200)
    }
    
    # Identify significant genes using Seurat FindAllMarkers
    set.seed(1)
    surt <- Seurat::as.Seurat(pbmcs\$CB, counts = "counts", data = "counts")
    mat <- as.matrix(assay(altExp(pbmcs\$CB), "counts"))
    surt[["GEM"]] <- Seurat::CreateAssayObject(counts = mat)
    Seurat::DefaultAssay(surt) <- "GEM"
    surt <- Seurat::SetIdent(surt, value = "seurat_clusters")
    res <- Seurat::FindAllMarkers(surt, only.pos = TRUE, min.pct = 0.50, logfc.threshold = 0.50)
    metadata(pbmcs\$CB)\$marker_genes\$all <- res
    
    # 11. Multifaceted analysis and visualization
    # Significant signs selection
    marker_signs <- list()
    keywords <- "MESENCHYMAL|LIMB|PANCREAS"
    for(i in seq_along(pbmcs)){
      marker_signs[[i]] <- metadata(pbmcs[[i]])\$marker_signs\$all
      marker_signs[[i]] <- marker_signs[[i]][!grepl(keywords, marker_signs[[i]]\$Description), ]
      marker_signs[[i]] <- dplyr::group_by(marker_signs[[i]], Ident_1)
      marker_signs[[i]] <- dplyr::slice_max(marker_signs[[i]], sepI, n = 2)
      marker_signs[[i]] <- dplyr::slice_min(marker_signs[[i]], Rank, n = 1)
    }
    
    # Significant genes selection
    marker_genes_CB <- metadata(pbmcs\$CB)\$marker_genes\$all
    marker_genes_CB <- dplyr::group_by(marker_genes_CB, cluster)
    marker_genes_CB <- dplyr::slice_min(marker_genes_CB, p_val_adj, n = 2)
    marker_genes_CB <- dplyr::slice_max(marker_genes_CB, avg_log2FC, n = 1)
    
    # Prepare ssm_list
    sces_sub <- list() ; ssm_list <- list()
    for(i in seq_along(pbmcs)){
      sces_sub[[i]] <- pbmcs[[i]][rownames(pbmcs[[i]]) %in% marker_signs[[i]]\$SignID, ]
      ssm_list[[i]] <- assay(sces_sub[[i]], "counts")
    }
    names(ssm_list) <- c("SSM_cell", "SSM_function", "SSM_pathway")
    
    # Prepare gem_list
    expr_sub <- altExp(pbmcs\$CB, "logcounts")
    expr_sub <- expr_sub[rownames(expr_sub) %in% marker_genes_CB\$gene]
    gem_list <- list(GeneExpr = assay(expr_sub, "counts"))
    
    # Prepare ssmlabel_list
    labels <- list() ; ssmlabel_list <- list()
    for(i in seq_along(pbmcs)){
      tmp <- colData(sces_sub[[i]])\$seurat_clusters
      labels[[i]] <- data.frame(label = tmp)
      n_groups <- length(unique(tmp))
      if(i == 1){
        labels[[i]]\$color <- scales::hue_pal()(n_groups)[tmp]
      }else if(i == 2){
        labels[[i]]\$color <- scales::brewer_pal(palette = "Set1")(n_groups)[tmp]
      }else if(i == 3){
        labels[[i]]\$color <- scales::brewer_pal(palette = "Set2")(n_groups)[tmp]
      }
      ssmlabel_list[[i]] <- labels[[i]]
    }
    names(ssmlabel_list) <- c("Label_cell", "Label_function", "Label_pathway")
    
    # Prepare gemlabel_list
    label_CC <- data.frame(label = colData(pbmcs\$CB)\$Phase, color = NA)
    gemlabel_list <- list(CellCycle = label_CC)
    
    # Plot multifaceted heatmaps
    pdf("multifaceted_heatmaps.pdf", width = 12, height = 10)
    set.seed(1)
    plot_multiheatmaps(ssm_list = ssm_list, gem_list = gem_list, ssmlabel_list = ssmlabel_list, gemlabel_list = gemlabel_list, nrand_samples = 100, show_row_names = TRUE, title = "PBMC")
    dev.off()
    
    # Plot violin plots
    pdf("violin_plots.pdf", width = 8, height = 6)
    # Violin plot for sign score
    labels <- colData(pbmcs\$CB)\$seurat_clusters
    variable <- "GO:0042100-V"
    if (!(variable %in% rownames(pbmcs\$GO))) {
      variable <- rownames(pbmcs\$GO)[1]
    }
    description <- "B cell proliferation"
    subsce <- pbmcs\$GO[which(rownames(pbmcs\$GO) == variable), ]
    df_violin <- as.data.frame(t(as.matrix(assay(subsce, "counts"))))
    p1 <- ggplot2::ggplot() +
      ggplot2::geom_violin(ggplot2::aes(x = as.factor(labels), y = df_violin[, 1], fill = labels), trim = FALSE, size = 0.5) +
      ggplot2::geom_boxplot(ggplot2::aes(x = as.factor(labels), y = df_violin[, 1]), width = 0.15, alpha = 0.6) +
      ggplot2::labs(title = paste0(variable, " \n ", description), x = "Cluster (cell type)", y = "Sign score") +
      ggplot2::theme_classic(base_size = 20) +
      ggplot2::theme(legend.position = "none") +
      ggplot2::scale_fill_hue()
    print(p1)
    
    # Violin plot for gene expression
    vname <- "CD79A"
    sub_expr <- altExp(pbmcs\$CB, "logcounts")
    if (!(vname %in% rownames(sub_expr))) {
      vname <- rownames(sub_expr)[1]
    }
    sub_expr <- sub_expr[rownames(sub_expr) == vname, ]
    df_gene <- as.data.frame(t(assay(sub_expr, "counts")))
    p2 <- ggplot2::ggplot() +
      ggplot2::geom_violin(ggplot2::aes(x = as.factor(labels), y = df_gene[, 1], fill = labels), trim = FALSE, size = 0.5) +
      ggplot2::geom_boxplot(ggplot2::aes(x = as.factor(labels), y = df_gene[, 1]), width = 0.15, alpha = 0.6) +
      ggplot2::labs(title = vname, x = "Cluster (cell type)", y = "Normalized expression") +
      ggplot2::theme_classic(base_size = 20) +
      ggplot2::theme(legend.position = "none") +
      ggplot2::scale_fill_hue()
    print(p2)
    dev.off()
    
    # Save final RDS objects and tables
    saveRDS(pbmcs, "pbmcs_analyzed.rds")
    for (i in seq_along(pbmcs)) {
      write.csv(metadata(pbmcs[[i]])\$marker_signs\$all, paste0("marker_signs_", names(pbmcs)[i], ".csv"), row.names = FALSE)
    }
    write.csv(metadata(pbmcs\$CB)\$marker_genes\$all, "marker_genes_CB.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_ASURAT_MULTIFACETED_SIGN_ANALYSIS":',
        paste0('    ASURAT: ', as.character(packageVersion('ASURAT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multifaceted_sign_analysis.csv versions.yml
    """
}

workflow BIOC_ASURAT_MULTIFACETED_SIGN_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv, database.rda ] ]

    main:
    BIOC_ASURAT_MULTIFACETED_SIGN_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ASURAT_MULTIFACETED_SIGN_ANALYSIS.out.tables
    plots    = BIOC_ASURAT_MULTIFACETED_SIGN_ANALYSIS.out.plots
    objects  = BIOC_ASURAT_MULTIFACETED_SIGN_ANALYSIS.out.objects
    versions = BIOC_ASURAT_MULTIFACETED_SIGN_ANALYSIS.out.versions
}
