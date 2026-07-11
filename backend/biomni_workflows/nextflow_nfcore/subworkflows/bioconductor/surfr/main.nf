#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SurfR — surfr_surface_protein_pipeline
// Identify surface protein-coding genes from custom RNA-seq count data using SurfR, performing differential gene expression, surfaceome prediction, functional enr
// Input: counts.csv, coldata.csv
// Container: 1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SurfR
// Visualizations: PCA plot, enrichment plot
// QC: diagnostic MA/PCA QC
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SURFR_SURFR_SURFACE_PROTEIN_PIPELINE {
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
    .bm_deps <- c("SurfR")
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
    library(SurfR)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    # Read counts and coldata
    counts_raw <- read.csv("counts.csv", check.names = FALSE)
    coldata_raw <- read.csv("coldata.csv", check.names = FALSE)
    
    # Set row names for counts (using 'gene_id' or first column)
    if ("gene_id" %in% colnames(counts_raw)) {
      rownames(counts_raw) <- counts_raw\$gene_id
      counts_raw\$gene_id <- NULL
    } else {
      rownames(counts_raw) <- counts_raw[, 1]
      counts_raw <- counts_raw[, -1, drop = FALSE]
    }
    
    # Set row names for coldata (using 'sample' or first column)
    if ("sample" %in% colnames(coldata_raw)) {
      rownames(coldata_raw) <- coldata_raw\$sample
    } else {
      rownames(coldata_raw) <- coldata_raw[, 1]
    }
    
    # Align samples between counts and coldata
    common_samples <- intersect(colnames(counts_raw), rownames(coldata_raw))
    if (length(common_samples) == 0) {
      stop("No common samples found between counts.csv and coldata.csv")
    }
    
    counts <- as.matrix(counts_raw[, common_samples, drop = FALSE])
    coldata <- coldata_raw[common_samples, , drop = FALSE]
    coldata\$condition <- as.factor(coldata\$condition)
    
    # Determine experimental groups
    cond_levels <- levels(coldata\$condition)
    if (length(cond_levels) < 2) {
      stop("At least two conditions are required in coldata.csv for DGE analysis")
    }
    CTRL <- cond_levels[1]
    TEST <- cond_levels[2]
    Nreplica <- min(table(coldata\$condition))
    
    # ==========================================
    # --- Differential Gene Expression (DGE) ---
    # ==========================================
    
    df_dge <- DGE(
      expression = counts,
      metadata = coldata,
      Nreplica = Nreplica,
      design = "~condition",
      condition = "condition",
      alpha = 0.05,
      TEST = TEST,
      CTRL = CTRL,
      output_tsv = FALSE
    )
    
    # Remove NA values from DGE results
    df_dge <- df_dge[!is.na(df_dge\$padj), ]
    write.csv(df_dge, "dge_results.csv", row.names = FALSE)
    
    # ==========================================
    # --- Surface Protein Identification ---
    # ==========================================
    
    # Select significant DEGs (fallback to top 50 by p-value if none are significant)
    fdr_GeneID <- df_dge[df_dge\$padj < 0.05, "GeneID"]
    if (length(fdr_GeneID) == 0) {
      warning("No genes met the padj < 0.05 threshold. Using top 50 genes by p-value instead.")
      fdr_GeneID <- df_dge\$GeneID[order(df_dge\$pvalue)[1:min(50, nrow(df_dge))]]
    }
    
    # Identify Surface Proteins (SP)
    SP <- tryCatch({
      Gene2SProtein(genes = fdr_GeneID, input_type = "gene_name", output_tsv = FALSE, Surfy_version = "new")
    }, error = function(e) {
      warning("Surface protein identification failed: ", e\$message)
      data.frame()
    })
    
    write.csv(SP, "surface_proteins.csv", row.names = FALSE)
    
    # ==========================================
    # --- Functional Enrichment & Annotation ---
    # ==========================================
    
    dfList <- list(Dataset = df_dge)
    
    # Run enrichment analysis (wrapped in tryCatch to handle potential network/server issues)
    Enrich <- tryCatch({
      Enrichment(
        dfList,
        enrich.databases = c("GO_Biological_Process_2021", "KEGG_2021_Human"),
        p_adj = 0.05,
        logFC = 0.5
      )
    }, error = function(e) {
      warning("Enrichment analysis failed (possibly due to network issues): ", e\$message)
      NULL
    })
    
    # Annotate gene list with pathway identifiers
    annotated <- tryCatch({
      Annotate_SPID(df_dge, "WikiPathway_2021_Human")
    }, error = function(e) {
      warning("Annotation failed: ", e\$message)
      data.frame(GeneID = character(), Annotation = character())
    })
    write.csv(annotated, "annotated_pathways.csv", row.names = FALSE)
    
    # ==========================================
    # --- Visualization & Diagnostics ---
    # ==========================================
    
    # 1. PCA Plot
    cpm_matrix <- apply(counts, 2, function(x) (x / sum(x)) * 1e6)
    pdf("pca_plot.pdf", width = 7, height = 6)
    tryCatch({
      SurfR::plotPCA(
        matrix = cpm_matrix,
        metadata = coldata,
        dims = c(1, 2),
        color.by = "condition",
        shape.by = "condition",
        label = FALSE,
        main = "PCA Plot"
      )
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("PCA Plot failed:", e\$message))
    })
    dev.off()
    
    # 2. Splot (Almen Classification)
    pdf("splot_classification.pdf", width = 7, height = 5)
    if (!is.null(SP) && nrow(SP) > 0 && "Membranome.Almen.main-class" %in% colnames(SP)) {
      tryCatch({
        Splot(SP, group.by = "Membranome.Almen.main-class", main = "Almen Class Distribution")
      }, error = function(e) {
        plot.new()
        text(0.5, 0.5, paste("Splot failed:", e\$message))
      })
    } else {
      plot.new()
      text(0.5, 0.5, "No Surface Proteins available for Splot")
    }
    dev.off()
    
    # 3. Enrichment Barplots
    pdf("enrichment_plots.pdf", width = 8, height = 6)
    if (!is.null(Enrich) && !is.null(Enrich\$Dataset)) {
      # Upregulated pathways
      tryCatch({
        Enrichment_barplot(
          Enrich\$Dataset,
          enrich.databases = c("GO_Biological_Process_2021", "KEGG_2021_Human"),
          p_adj = 0.05,
          num_term = 5,
          cond = "UP"
        )
      }, error = function(e) {
        plot.new()
        text(0.5, 0.5, "No significant upregulated enrichment terms found")
      })
      
      # Downregulated pathways
      tryCatch({
        Enrichment_barplot(
          Enrich\$Dataset,
          enrich.databases = c("GO_Biological_Process_2021", "KEGG_2021_Human"),
          p_adj = 0.05,
          num_term = 5,
          cond = "DOWN"
        )
      }, error = function(e) {
        plot.new()
        text(0.5, 0.5, "No significant downregulated enrichment terms found")
      })
    } else {
      plot.new()
      text(0.5, 0.5, "Enrichment data unavailable")
    }
    dev.off()
    
    cat("Pipeline completed successfully.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SURFR_SURFR_SURFACE_PROTEIN_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SURFR_SURFR_SURFACE_PROTEIN_PIPELINE":',
        paste0('    SurfR: ', as.character(packageVersion('SurfR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_surfr_surface_protein_pipeline.csv versions.yml
    """
}

workflow BIOC_SURFR_SURFR_SURFACE_PROTEIN_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SURFR_SURFR_SURFACE_PROTEIN_PIPELINE(ch_input)

    emit:
    tables   = BIOC_SURFR_SURFR_SURFACE_PROTEIN_PIPELINE.out.tables
    plots    = BIOC_SURFR_SURFR_SURFACE_PROTEIN_PIPELINE.out.plots
    objects  = BIOC_SURFR_SURFR_SURFACE_PROTEIN_PIPELINE.out.objects
    versions = BIOC_SURFR_SURFR_SURFACE_PROTEIN_PIPELINE.out.versions
}
