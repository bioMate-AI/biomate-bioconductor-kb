#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mia — taxonomic_agglomeration_and_tree_construction
// Agglomerate microbiome count data at specific taxonomic ranks and construct or update the corresponding phylogenetic tree.
// Input: esophagus.RDS, GlobalPatterns.RDS
// Container: quay.io/biocontainers/bioconductor-mia:1.18.0--r45ha27e39d_0
// R packages: TreeSummarizedExperiment, mia, MultiAssayExperiment, phyloseq, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: TreeSummarizedExperiment, mia, phyloseq
// Visualizations: phylogenetic tree
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read User Input Files
//  * 2. [Input & Preparation] Convert Legacy Phyloseq Object
//  * 3. [Input & Preparation] Inspect Taxonomic Ranks and Labels
//  * 4. [Input & Preparation] Agglomerate Feature Counts
//  * 5. [Input & Preparation] Construct and Update Taxonomic Tree
//  * 6. [Input & Preparation] Save Outputs

nextflow.enable.dsl = 2

process BIOC_MIA_TAXONOMIC_AGGLOMERATION_AND_TREE_CONSTRUCTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("TreeSummarizedExperiment", "mia", "MultiAssayExperiment", "phyloseq", "scater")
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
    library("mia")
    library("phyloseq")
    library("TreeSummarizedExperiment")
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    # Read the esophagus phyloseq object
    esophagus_phyloseq <- readRDS("esophagus.RDS")
    
    # Read the GlobalPatterns TreeSummarizedExperiment object
    tse <- readRDS("GlobalPatterns.RDS")
    
    # ==========================================
    # --- Convert Legacy Phyloseq Object ---
    # ==========================================
    esophagus <- convertFromPhyloseq(esophagus_phyloseq)
    
    # Save converted esophagus object
    saveRDS(esophagus, "esophagus_tse.RDS")
    
    # ==========================================
    # --- Inspect Taxonomic Ranks and Labels ---
    # ==========================================
    colnames(rowData(tse))
    taxonomyRanks(tse)
    rowData(tse)[, taxonomyRanks(tse)]
    
    # Check for empty classifications at Species level
    species_empty_table <- table(taxonomyRankEmpty(tse, "Species"))
    write.csv(as.data.frame(species_empty_table), "species_empty_status.csv", row.names = FALSE)
    
    # Get taxonomy labels
    tax_labels_head <- head(getTaxonomyLabels(tse))
    write.csv(data.frame(TaxonomyLabels = tax_labels_head), "taxonomy_labels_head.csv", row.names = FALSE)
    
    # ==========================================
    # --- Agglomerate Feature Counts ---
    # ==========================================
    # Agglomerate at Family rank without shrinking the tree
    x1 <- agglomerateByRank(tse, rank = "Family")
    
    # Agglomerate at Family rank and shrink the tree
    x2 <- agglomerateByRank(tse, rank = "Family", agglomerateTree = TRUE)
    
    # Store as alternative experiment
    altExp(tse, "family") <- x2
    
    # Agglomerate at Species rank with and without removing empty classifications
    x1 <- agglomerateByRank(tse, rank = "Species", empty.rm = TRUE)
    altExp(tse, "species") <- agglomerateByRank(tse, rank = "Species", empty.rm = FALSE)
    
    # Agglomerate on all available ranks
    tse <- agglomerateByRanks(tse)
    
    # ==========================================
    # --- Construct and Update Taxonomic Tree ---
    # ==========================================
    taxa <- rowData(altExp(tse, "Species"))[, taxonomyRanks(tse)]
    taxa_res <- resolveLoop(as.data.frame(taxa))
    taxa_tree <- toTree(data = taxa_res)
    taxa_tree\$tip.label <- getTaxonomyLabels(altExp(tse, "Species"))
    rowNodeLab <- getTaxonomyLabels(altExp(tse, "Species"), make.unique = FALSE)
    
    altExp(tse, "Species") <- changeTree(
        altExp(tse, "Species"),
        rowTree = taxa_tree,
        rowNodeLab = rowNodeLab
    )
    
    # ==========================================
    # --- Save Outputs ---
    # ==========================================
    # Save the final updated TreeSummarizedExperiment object
    saveRDS(tse, "tse_agglomerated.RDS")
    
    # Save the rowData of the updated Species alternative experiment
    write.csv(as.data.frame(rowData(altExp(tse, "Species"))), "species_rowData.csv", row.names = TRUE)
    
    # Plot and save the constructed taxonomic tree
    pdf("taxonomic_tree.pdf", width = 10, height = 10)
    plot(taxa_tree, show.tip.label = FALSE, main = "Constructed Taxonomic Tree (Species)")
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MIA_TAXONOMIC_AGGLOMERATION_AND_TREE_CONSTRUCTION",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MIA_TAXONOMIC_AGGLOMERATION_AND_TREE_CONSTRUCTION":',
        paste0('    mia: ', as.character(packageVersion('mia')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_taxonomic_agglomeration_and_tree_construction.csv versions.yml
    """
}

workflow BIOC_MIA_TAXONOMIC_AGGLOMERATION_AND_TREE_CONSTRUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ esophagus.RDS, GlobalPatterns.RDS ] ]

    main:
    BIOC_MIA_TAXONOMIC_AGGLOMERATION_AND_TREE_CONSTRUCTION(ch_input)

    emit:
    tables   = BIOC_MIA_TAXONOMIC_AGGLOMERATION_AND_TREE_CONSTRUCTION.out.tables
    plots    = BIOC_MIA_TAXONOMIC_AGGLOMERATION_AND_TREE_CONSTRUCTION.out.plots
    objects  = BIOC_MIA_TAXONOMIC_AGGLOMERATION_AND_TREE_CONSTRUCTION.out.objects
    versions = BIOC_MIA_TAXONOMIC_AGGLOMERATION_AND_TREE_CONSTRUCTION.out.versions
}
