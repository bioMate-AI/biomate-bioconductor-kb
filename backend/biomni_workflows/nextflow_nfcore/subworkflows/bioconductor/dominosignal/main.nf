#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dominoSignal — domino_signaling_analysis
// Perform cell-cell communication and intracellular TF activation analysis from scRNA-seq data using a Domino object.
// Input: scenic_regulon.csv, scenic_auc.csv, complex_input.csv, gene_input.csv, interaction_input.csv, protein_input.csv, pbmc3k_sce.rds
// Container: quay.io/biocontainers/bioconductor-dominosignal:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, SingleCellExperiment, circlize, dominoSignal, plyr
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load and format SCENIC regulons
//  * 2. [Visualization & Output] Transpose and clean SCENIC AUC matrix
//  * 3. [Visualization & Output] Load and parse CellPhoneDB database files into an rl_map
//  * 4. [Visualization & Output] Extract counts, z-scores, and cluster labels from
//  * 5. [Visualization & Output] Initialize the Domino object
//  * 6. [Visualization & Output] Finalize the Domino network
//  * 7. [Visualization & Output] Access results using dom_* functions and write to CSV
//  * 8. [Visualization & Output] Visualize using heatmaps, network plots, and circos plots

nextflow.enable.dsl = 2

process BIOC_DOMINOSIGNAL_DOMINO_SIGNALING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("dominoSignal", "plyr", "circlize", "ComplexHeatmap", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
      library(SummarizedExperiment)
  library(dominoSignal)
    library(plyr)
    library(circlize)
    library(ComplexHeatmap)
    library(grid)
    
    # Set seed for reproducibility
    set.seed(42)
    
    # --- Load and format SCENIC regulons ---
    regulons <- read.csv("scenic_regulon.csv")
    regulons <- regulons[-1:-2, ]
    colnames(regulons) <- c(
        "TF", "MotifID", "AUC", "NES", "MotifSimilarityQvalue", "OrthologousIdentity",
        "Annotation", "Context", "TargetGenes", "RankAtMax"
    )
    regulon_list <- create_regulon_list_scenic(regulons = regulons)
    
    # --- Transpose and clean SCENIC AUC matrix ---
    auc <- read.table("scenic_auc.csv",
        header = TRUE, row.names = 1,
        stringsAsFactors = FALSE, sep = ","
    )
    auc_in <- as.data.frame(t(auc))
    rownames(auc_in) <- gsub("\\\\.\\\\.\\\\.\$", "", rownames(auc_in))
    
    # --- Load and parse CellPhoneDB database files into an rl_map ---
    complexes <- read.csv("complex_input.csv", stringsAsFactors = FALSE)
    genes <- read.csv("gene_input.csv", stringsAsFactors = FALSE)
    interactions <- read.csv("interaction_input.csv", stringsAsFactors = FALSE)
    proteins <- read.csv("protein_input.csv", stringsAsFactors = FALSE)
    
    rl_map <- create_rl_map_cellphonedb(
        genes = genes,
        proteins = proteins,
        interactions = interactions,
        complexes = complexes,
        database_name = "CellPhoneDB_v4.0"
    )
    
    # Optional: Append manual interactions
    col_int_df <- data.frame(
        "int_pair" = "a11b1 complex & COLA1_HUMAN",
        "name_A" = "a11b1 complex", "uniprot_A" = "P05556,Q9UKX5", "gene_A" = "ITB1,ITA11", "type_A" = "R",
        "name_B" = "COLA1_HUMAN", "uniprot_B" = "P02452,P08123", "gene_B" = "COL1A1,COL1A2", "type_B" = "L",
        "annotation_strategy" = "manual", "source" = "manual", "database_name" = "manual"
    )
    rl_map_append <- rbind(col_int_df, rl_map)
    
    # --- Extract counts, z-scores, and cluster labels from ---
    pbmc <- readRDS("pbmc3k_sce.rds")
    counts = assay(pbmc, "counts")
    logcounts = assay(pbmc, "logcounts")
    logcounts = logcounts[rowSums(logcounts) > 0, ]
    z_scores = t(scale(t(logcounts)))
    clusters = factor(pbmc\$cell_type)
    names(clusters) = colnames(pbmc)
    
    # --- Initialize the Domino object ---
    pbmc_dom <- create_domino(
        rl_map = rl_map,
        features = auc_in,
        counts = counts,
        z_scores = z_scores,
        clusters = clusters,
        tf_targets = regulon_list,
        use_clusters = TRUE,
        use_complexes = TRUE,
        remove_rec_dropout = FALSE
    )
    
    # --- Finalize the Domino network ---
    pbmc_dom <- build_domino(
        dom = pbmc_dom,
        min_tf_pval = .001,
        max_tf_per_clust = 25,
        max_rec_per_tf = 25,
        rec_tf_cor_threshold = .25,
        min_rec_percentage = 0.1
    )
    
    # Save the built domino object
    saveRDS(pbmc_dom, "pbmc_domino_built.rds")
    
    # Assign to 'dom' to match the second part of the documented code
    dom <- pbmc_dom
    
    # --- Access results using dom_* functions and write to CSV ---
    write.csv(data.frame(Cluster = dom_clusters(dom)), "dom_clusters.csv", row.names = FALSE)
    
    count_matrix <- dom_counts(dom)
    write.csv(as.matrix(count_matrix[1:min(100, nrow(count_matrix)), 1:min(100, ncol(count_matrix))]), "dom_counts_subset.csv")
    
    z_matrix <- dom_zscores(dom)
    write.csv(as.matrix(z_matrix[1:min(100, nrow(z_matrix)), 1:min(100, ncol(z_matrix))]), "dom_zscores_subset.csv")
    
    activation_matrix <- dom_tf_activation(dom)
    write.csv(as.matrix(activation_matrix), "dom_tf_activation.csv")
    
    dom_database(dom)
    db_matrix <- dom_database(dom, name_only = FALSE)
    write.csv(db_matrix, "dom_database_map.csv")
    
    de_matrix <- dom_de(dom)
    write.csv(de_matrix, "dom_de_pvals.csv")
    
    cor_matrix <- dom_correlations(dom)
    write.csv(cor_matrix, "dom_correlations.csv")
    
    complex_links <- dom_linkages(dom, link_type = "complexes")
    incoming_links <- dom_linkages(dom, link_type = "incoming-ligand", by_cluster = TRUE)
    
    tryCatch({
        dc_tfs <- dom_network_items(dom, "dendritic_cell", return = "features")
        write.csv(data.frame(TF = dc_tfs), "dendritic_cell_tfs.csv", row.names = FALSE)
    }, error = function(e) {
        message("Could not extract network items for dendritic_cell: ", e\$message)
    })
    
    signal_matrix <- dom_signaling(dom)
    write.csv(signal_matrix, "dom_signaling_matrix.csv")
    
    tryCatch({
        dc_matrix <- dom_signaling(dom, "dendritic_cell")
        write.csv(dc_matrix, "dom_dendritic_cell_signaling.csv")
    }, error = function(e) {
        message("Could not extract signaling matrix for dendritic_cell: ", e\$message)
    })
    
    dom_info(dom)
    
    # --- Visualize using heatmaps, network plots, and circos plots ---
    pdf("domino_visualizations.pdf", width = 10, height = 8)
    
    # Heatmaps and Networks on pbmc_dom
    tryCatch({
        feat_heatmap(pbmc_dom,
            norm = TRUE, bool = FALSE, use_raster = FALSE,
            row_names_gp = grid::gpar(fontsize = 4)
        )
    }, error = function(e) { message("feat_heatmap failed: ", e\$message) })
    
    tryCatch({
        signaling_network(pbmc_dom, edge_weight = 0.5, max_thresh = 3)
    }, error = function(e) { message("signaling_network failed: ", e\$message) })
    
    tryCatch({
        gene_network(pbmc_dom, clust = "dendritic_cell", layout = "grid")
    }, error = function(e) { message("gene_network dendritic_cell failed: ", e\$message) })
    
    tryCatch({
        gene_network(pbmc_dom,
            clust = "dendritic_cell", OutgoingSignalingClust = "CD14_monocyte",
            layout = "grid"
        )
    }, error = function(e) { message("gene_network dendritic_cell with outgoing failed: ", e\$message) })
    
    tryCatch({
        incoming_signaling_heatmap(pbmc_dom, rec_clust = "dendritic_cell", max_thresh = 2.5, use_raster = FALSE)
    }, error = function(e) { message("incoming_signaling_heatmap dendritic_cell failed: ", e\$message) })
    
    tryCatch({
        circos_ligand_receptor(pbmc_dom, receptor = "CD74")
    }, error = function(e) { message("circos_ligand_receptor CD74 failed: ", e\$message) })
    
    # Heatmaps and Networks on dom
    tryCatch({
        cor_heatmap(dom, title = "PBMC R-TF Correlations", column_names_gp = grid::gpar(fontsize = 8))
    }, error = function(e) { message("cor_heatmap failed: ", e\$message) })
    
    tryCatch({
        cor_heatmap(dom, bool = TRUE, bool_thresh = 0.25)
    }, error = function(e) { message("cor_heatmap bool failed: ", e\$message) })
    
    tryCatch({
        cor_heatmap(dom, bool = FALSE, mark_connections = TRUE)
    }, error = function(e) { message("cor_heatmap mark_connections failed: ", e\$message) })
    
    receptors <- c("CSF1R", "CSF3R", "CCR7", "FCER2")
    tfs <- c("PAX5", "JUNB", "FOXJ3", "FOSB")
    tryCatch({
        cor_heatmap(dom, feats = tfs, recs = receptors)
    }, error = function(e) { message("cor_heatmap subset failed: ", e\$message) })
    
    tryCatch({
        cor_heatmap(dom, cluster_rows = FALSE, cluster_columns = FALSE, column_title = "Heatmap Without Clustering", column_names_gp = grid::gpar(fontsize = 4))
    }, error = function(e) { message("cor_heatmap no clustering failed: ", e\$message) })
    
    tryCatch({
        feat_heatmap(dom, min_thresh = 0.1, max_thresh = 0.6, norm = TRUE, bool = FALSE, use_raster = FALSE)
    }, error = function(e) { message("feat_heatmap custom thresholds failed: ", e\$message) })
    
    tryCatch({
        incoming_signaling_heatmap(dom, "CD8_T_cell")
    }, error = function(e) { message("incoming_signaling_heatmap CD8_T_cell failed: ", e\$message) })
    
    tryCatch({
        incoming_signaling_heatmap(dom, "CD8_T_cell", clusts = c("CD14_monocyte", "CD16_monocyte"))
    }, error = function(e) { message("incoming_signaling_heatmap CD8_T_cell subset failed: ", e\$message) })
    
    tryCatch({
        signaling_heatmap(dom)
    }, error = function(e) { message("signaling_heatmap failed: ", e\$message) })
    
    tryCatch({
        signaling_heatmap(dom, scale = "sqrt")
    }, error = function(e) { message("signaling_heatmap sqrt failed: ", e\$message) })
    
    tryCatch({
        signaling_heatmap(dom, normalize = "rec_norm")
    }, error = function(e) { message("signaling_heatmap rec_norm failed: ", e\$message) })
    
    tryCatch({
        gene_network(dom, clust = "CD16_monocyte", OutgoingSignalingClust = "CD14_monocyte")
    }, error = function(e) { message("gene_network CD16_monocyte failed: ", e\$message) })
    
    tryCatch({
        gene_network(dom, clust = "CD16_monocyte", OutgoingSignalingClust = "CD14_monocyte", lig_scale = 25, layout = "sphere")
    }, error = function(e) { message("gene_network CD16_monocyte sphere failed: ", e\$message) })
    
    tryCatch({
        gene_network(dom, clust = "CD16_monocyte", OutgoingSignalingClust = "CD14_monocyte", cols = c(CD1D = "violet", LILRB2 = "violet", FOSB = "violet"), lig_scale = 10)
    }, error = function(e) { message("gene_network CD16_monocyte custom cols failed: ", e\$message) })
    
    tryCatch({
        signaling_network(dom)
    }, error = function(e) { message("signaling_network dom failed: ", e\$message) })
    
    tryCatch({
        signaling_network(dom, showOutgoingSignalingClusts = "CD14_monocyte", scale = "none", norm = "none", layout = "fr", scale_by = "none", edge_weight = 2, vert_scale = 10)
    }, error = function(e) { message("signaling_network CD14_monocyte failed: ", e\$message) })
    
    cols <- c("red", "orange", "green", "blue", "pink", "purple", "slategrey", "firebrick", "hotpink")
    names(cols) <- dom_clusters(dom, labels = FALSE)
    tryCatch({
        circos_ligand_receptor(dom, receptor = "CD74", cell_colors = cols)
    }, error = function(e) { message("circos_ligand_receptor CD74 custom colors failed: ", e\$message) })
    
    tryCatch({
        cor_scatter(dom, "FOSB", "CD74")
    }, error = function(e) { message("cor_scatter FOSB CD74 failed: ", e\$message) })
    
    dev.off()
    
    message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DOMINOSIGNAL_DOMINO_SIGNALING_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DOMINOSIGNAL_DOMINO_SIGNALING_ANALYSIS":',
        paste0('    dominoSignal: ', as.character(packageVersion('dominoSignal')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_domino_signaling_analysis.csv versions.yml
    """
}

workflow BIOC_DOMINOSIGNAL_DOMINO_SIGNALING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ scenic_regulon.csv, scenic_auc.csv, complex_input.csv, gene_input.csv, interaction_input.csv, protein_input.csv, pbmc3k_sce.rds ] ]

    main:
    BIOC_DOMINOSIGNAL_DOMINO_SIGNALING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DOMINOSIGNAL_DOMINO_SIGNALING_ANALYSIS.out.tables
    plots    = BIOC_DOMINOSIGNAL_DOMINO_SIGNALING_ANALYSIS.out.plots
    objects  = BIOC_DOMINOSIGNAL_DOMINO_SIGNALING_ANALYSIS.out.objects
    versions = BIOC_DOMINOSIGNAL_DOMINO_SIGNALING_ANALYSIS.out.versions
}
