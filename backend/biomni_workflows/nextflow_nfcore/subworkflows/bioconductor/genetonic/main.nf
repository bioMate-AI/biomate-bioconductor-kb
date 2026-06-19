#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneTonic — genetonic_integration_and_reporting
// Integrate expression data, differential expression results, and functional enrichment results to perform interactive exploration and generate a reproducible HTM
// Input: gse, org.Hs.eg.db, topgoDE_macrophage_IFNg_vs_naive
// Container: quay.io/biocontainers/bioconductor-genetonic:3.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, DESeq2, GeneTonic, ggplot2, igraph, mosdef, org.Hs.eg.db
// Visualizations: enrichment plot
// QC: dispersion/size-factor estimation, low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare the DESeqDataSet (dds) and filter lowly expressed genes
//  * 2. [Core Analysis] Run differential expression analysis to obtain res_de
//  * 3. [Visualization & Output] Perform functional enrichment analysis and convert the output to a GeneTonic-compatible format using shaker functions
//  * 4. [Input & Preparation] Create the annotation data frame mapping gene IDs to symbols
//  * 5. [Core Analysis] Compute aggregated scores (Z-score and aggr_score) for the enrichment results
//  * 6. [Core Analysis] Bundle the components into a GeneTonicList and validate it
//  * 7. [Visualization & Output] Launch the interactive GeneTonic Shiny application or generate an offline HTML report using happy_hour

nextflow.enable.dsl = 2

process BIOC_GENETONIC_GENETONIC_INTEGRATION_AND_REPORTING {
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
    .bm_deps <- c("GeneTonic", "DESeq2", "AnnotationDbi", "org.Hs.eg.db", "ggplot2", "igraph")
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
        library("GeneTonic")
        library("DESeq2")
        library("AnnotationDbi")
        library("org.Hs.eg.db")
        library("ggplot2")
        library("igraph")
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        
        # Read gse (SummarizedExperiment / Gene-level summarized expression data)
        gse_file <- list.files(pattern = "^gse(\\\\.(rds|RData|rds))\$", ignore.case = TRUE)[1]
        if (is.na(gse_file)) {
          gse_file <- "gse"
        }
        if (!file.exists(gse_file)) {
          stop("Required input file 'gse' not found in the working directory.")
        }
        
        if (grepl("\\\\.RData\$", gse_file, ignore.case = TRUE)) {
          env <- new.env()
          load(gse_file, envir = env)
          gse <- env[[names(env)[1]]]
        } else {
          gse <- readRDS(gse_file)
        }
        
        # Read topgoDE_macrophage_IFNg_vs_naive (raw enrichment results)
        topgo_file <- list.files(pattern = "^topgoDE_macrophage_IFNg_vs_naive(\\\\.(rds|csv|tsv|txt|RData))?\$", ignore.case = TRUE)[1]
        if (is.na(topgo_file)) {
          topgo_file <- "topgoDE_macrophage_IFNg_vs_naive"
        }
        if (!file.exists(topgo_file)) {
          stop("Required input file 'topgoDE_macrophage_IFNg_vs_naive' not found in the working directory.")
        }
        
        if (grepl("\\\\.csv\$", topgo_file, ignore.case = TRUE)) {
          topgoDE_macrophage_IFNg_vs_naive <- read.csv(topgo_file, stringsAsFactors = FALSE)
        } else if (grepl("\\\\.tsv\$|\\\\.txt\$", topgo_file, ignore.case = TRUE)) {
          topgoDE_macrophage_IFNg_vs_naive <- read.delim(topgo_file, stringsAsFactors = FALSE)
        } else if (grepl("\\\\.RData\$", topgo_file, ignore.case = TRUE)) {
          env <- new.env()
          load(topgo_file, envir = env)
          topgoDE_macrophage_IFNg_vs_naive <- env[[names(env)[1]]]
        } else {
          topgoDE_macrophage_IFNg_vs_naive <- readRDS(topgo_file)
        }
        
        # ==========================================
        # 2. Prepare DESeqDataSet and Run DE Analysis
        # ==========================================
        
        # Construct DESeqDataSet
        dds_macrophage <- DESeqDataSet(gse, design = ~line + condition)
        rownames(dds_macrophage) <- substr(rownames(dds_macrophage), 1, 15)
        
        # Filter lowly expressed genes
        keep <- rowSums(counts(dds_macrophage) >= 10) >= 6
        dds_macrophage <- dds_macrophage[keep, ]
        
        # Ensure SYMBOL column exists in rowData
        if (!"SYMBOL" %in% colnames(rowData(dds_macrophage))) {
          rowData(dds_macrophage)\$SYMBOL <- mapIds(
            org.Hs.eg.db,
            keys = rownames(dds_macrophage),
            column = "SYMBOL",
            keytype = "ENSEMBL",
            multiVals = "first"
          )
        }
        
        # Run differential expression analysis to obtain res_macrophage_IFNg_vs_naive
        dds_macrophage <- DESeq(dds_macrophage)
        res_macrophage_IFNg_vs_naive <- results(
          dds_macrophage,
          contrast = c("condition", "IFNg", "naive"),
          lfcThreshold = 1,
          alpha = 0.05
        )
        res_macrophage_IFNg_vs_naive\$SYMBOL <- rowData(dds_macrophage)\$SYMBOL
        
        # ==========================================
        # 3. Process Functional Enrichment Results
        # ==========================================
        
        # Extract DE symbols and background IDs
        de_symbols_IFNg_vs_naive <- mosdef::deresult_to_df(res_macrophage_IFNg_vs_naive, FDR = 0.05)\$SYMBOL
        bg_ids <- rowData(dds_macrophage)\$SYMBOL[rowSums(counts(dds_macrophage)) > 0]
        
        # Convert enrichment results to GeneTonic-compatible format
        res_enrich_macrophage <- shake_topGOtableResult(topgoDE_macrophage_IFNg_vs_naive)
        
        # ==========================================
        # 4. Create Annotation Data Frame
        # ==========================================
        
        anno_df <- data.frame(
          gene_id = rownames(dds_macrophage),
          gene_name = mapIds(org.Hs.eg.db, keys = rownames(dds_macrophage), column = "SYMBOL", keytype = "ENSEMBL"),
          stringsAsFactors = FALSE,
          row.names = rownames(dds_macrophage)
        )
        
        # ==========================================
        # 5. Compute Aggregated Scores
        # ==========================================
        
        res_enrich_macrophage <- get_aggrscores(
          res_enrich = res_enrich_macrophage,
          res_de = res_macrophage_IFNg_vs_naive,
          annotation_obj = anno_df,
          aggrfun = mean
        )
        
        # ==========================================
        # 6. Bundle into GeneTonicList and Validate
        # ==========================================
        
        gtl <- GeneTonicList(
          dds = DESeq2::estimateSizeFactors(dds_macrophage),
          res_de = res_macrophage_IFNg_vs_naive,
          res_enrich = res_enrich_macrophage,
          annotation_obj = anno_df
        )
        
        checkup_gtl(gtl)
        
        # ==========================================
        # 7. Generate Visualizations and Reports
        # ==========================================
        
        # 7.1 Enhance Table Plot
        p <- enhance_table(
          res_enrich_macrophage,
          res_macrophage_IFNg_vs_naive,
          n_gs = 30,
          annotation_obj = anno_df,
          chars_limit = 60
        )
        ggsave("enhance_table_plot.pdf", plot = p, width = 12, height = 8)
        
        # 7.2 Alluvial Plot
        pdf("gs_alluvial_plot.pdf", width = 10, height = 8)
        print(gs_alluvial(
          res_enrich = res_enrich_macrophage,
          res_de = res_macrophage_IFNg_vs_naive,
          annotation_obj = anno_df,
          n_gs = 4
        ))
        dev.off()
        
        # 7.3 Enrichment Map
        em <- enrichment_map(
          res_enrich_macrophage,
          res_macrophage_IFNg_vs_naive,
          n_gs = 30,
          color_by = "z_score",
          anno_df
        )
        pdf("enrichment_map.pdf", width = 10, height = 10)
        plot(em)
        dev.off()
        
        # 7.4 Generate Offline HTML Report using happy_hour
        # Dynamically select top gene sets and top DE genes to ensure they exist in the data
        mygenesets <- head(res_enrich_macrophage\$gs_id, 5)
        top_de_genes <- rownames(res_macrophage_IFNg_vs_naive[order(res_macrophage_IFNg_vs_naive\$padj), ])
        mygenes <- head(top_de_genes, 3)
        
        happy_hour(
          dds = dds_macrophage,
          res_de = res_macrophage_IFNg_vs_naive,
          res_enrich = res_enrich_macrophage,
          annotation_obj = anno_df,
          project_id = "genetonic_integration_report",
          mygenesets = mygenesets,
          mygenes = mygenes,
          open_after_creating = FALSE
        )
        
        # ==========================================
        # 8. Save Structured Outputs
        # ==========================================
        
        saveRDS(gtl, "GeneTonicList_output.rds")
        write.csv(as.data.frame(res_enrich_macrophage), "res_enrich_processed.csv", row.names = FALSE)
        write.csv(as.data.frame(res_macrophage_IFNg_vs_naive), "res_de_processed.csv", row.names = TRUE)
        
        message("Pipeline completed successfully. Outputs saved to working directory.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

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
      process = "BIOC_GENETONIC_GENETONIC_INTEGRATION_AND_REPORTING",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GENETONIC_GENETONIC_INTEGRATION_AND_REPORTING":',
        paste0('    GeneTonic: ', as.character(packageVersion('GeneTonic')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genetonic_integration_and_reporting.csv versions.yml
    """
}

workflow BIOC_GENETONIC_GENETONIC_INTEGRATION_AND_REPORTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gse, org.Hs.eg.db, topgoDE_macrophage_IFNg_vs_naive ] ]

    main:
    BIOC_GENETONIC_GENETONIC_INTEGRATION_AND_REPORTING(ch_input)

    emit:
    tables   = BIOC_GENETONIC_GENETONIC_INTEGRATION_AND_REPORTING.out.tables
    plots    = BIOC_GENETONIC_GENETONIC_INTEGRATION_AND_REPORTING.out.plots
    objects  = BIOC_GENETONIC_GENETONIC_INTEGRATION_AND_REPORTING.out.objects
    versions = BIOC_GENETONIC_GENETONIC_INTEGRATION_AND_REPORTING.out.versions
}
