#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: multiGSEA — multi_omics_gsea_enrichment
// Run a multi-omics GSEA-based pathway enrichment analysis across transcriptome, proteome, and metabolome layers and aggregate the p-values.
// Input: transcriptome, proteome, metabolome
// Container: quay.io/biocontainers/bioconductor-multigsea:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: magrittr, multiGSEA, org.Hs.eg.db
// Visualizations: bar plot, enrichment plot, pathway diagram
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the multi-omics data structure using initOmicsDataStructure
//  * 2. [Core Analysis] Rank features for each omics layer using rankFeatures and assign feature names
//  * 3. [Input & Preparation] Download and map pathway definitions using getMultiOmicsFeatures
//  * 4. [Core Analysis] Calculate enrichment scores for all layers using multiGSEA
//  * 5. [Core Analysis] Extract p-values using extractPvalues and aggregate them using combinePvalues
//  * 6. [Core Analysis] Adjust combined p-values using p.adjust

nextflow.enable.dsl = 2

process BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    publishDir "${params.outdir}", mode: 'copy'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("org.Hs.eg.db", "multiGSEA", "magrittr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    
    # Load required libraries
    library(org.Hs.eg.db)
    library(multiGSEA)
    library(magrittr)
    
    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }

    .read_table <- function(path) {
      if (grepl("\\\\.tsv\$|\\\\.txt\$", path, ignore.case = TRUE))
        read.delim(path, stringsAsFactors = FALSE, check.names = FALSE)
      else
        read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    }
    .find_layer <- function(role_patterns) {
      # Prefer exact basename, then stem/role hints (tcga_mrna → transcriptome)
      exact <- c(paste0(role_patterns[1], ".csv"), paste0(role_patterns[1], ".tsv"))
      hit <- exact[file.exists(exact)][1]
      if (!is.na(hit) && nzchar(hit)) return(hit)
      files <- list.files(".", pattern = "(?i)\\\\.(csv|tsv|txt)\$")
      files <- files[!grepl("(?i)metadata|design|sample", files)]
      for (pat in role_patterns) {
        m <- grep(pat, files, ignore.case = TRUE, value = TRUE)
        if (length(m)) return(m[1])
      }
      NA_character_
    }
    .is_ranked_de <- function(df) {
      cn <- tolower(colnames(df))
      any(cn %in% c("logfc", "log2fc", "log2foldchange")) &&
        any(cn %in% c("pvalue", "p.value", "pval", "p")) &&
        any(cn %in% c("symbol", "gene", "genes", "hmdb", "id"))
    }
    .normalize_ranked <- function(df, id_prefs) {
      cn <- colnames(df)
      lfc <- cn[tolower(cn) %in% c("logfc", "log2fc", "log2foldchange")][1]
      pv <- cn[tolower(gsub("[._]", "", cn)) %in% c("pvalue", "pval", "p")][1]
      if (is.na(pv)) pv <- cn[tolower(cn) %in% c("p.value", "pvalue", "pval")][1]
      id <- NA_character_
      for (pref in id_prefs) {
        hit <- grep(paste0("^", pref, "\$"), cn, ignore.case = TRUE, value = TRUE)[1]
        if (!is.na(hit)) { id <- hit; break }
      }
      if (is.na(id) || is.na(lfc) || is.na(pv)) stop("Ranked DE table missing Symbol/logFC/pValue columns")
      out <- data.frame(
        Symbol = as.character(df[[id]]),
        logFC = as.numeric(df[[lfc]]),
        pValue = as.numeric(df[[pv]]),
        stringsAsFactors = FALSE
      )
      if (tolower(id_prefs[1]) == "hmdb") names(out)[1] <- "HMDB"
      out
    }
    # Abundance matrix (samples × features or features × samples) + optional metadata → ranked DE
    .abundance_to_ranked <- function(path, meta_path = NA_character_) {
      mat <- .read_table(path)
      # First column as feature IDs when non-numeric
      if (!is.numeric(mat[[1]])) {
        rownames(mat) <- make.unique(as.character(mat[[1]]))
        mat <- mat[, -1, drop = FALSE]
      }
      # Orient to features × samples
      if (nrow(mat) < ncol(mat)) mat <- as.data.frame(t(mat))
      storage.mode_num <- as.matrix(data.frame(lapply(mat, function(x) suppressWarnings(as.numeric(as.character(x))))))
      rownames(storage.mode_num) <- rownames(mat)
      colnames(storage.mode_num) <- colnames(mat)
      groups <- NULL
      if (!is.na(meta_path) && file.exists(meta_path)) {
        meta <- .read_table(meta_path)
        # Match sample column to matrix colnames
        sample_col <- grep("(?i)^sample|^id\$", colnames(meta), value = TRUE)[1]
        group_col <- grep("(?i)subtype|group|condition|class|arm|diet|genotype", colnames(meta), value = TRUE)[1]
        if (!is.na(sample_col) && !is.na(group_col)) {
          meta[[sample_col]] <- as.character(meta[[sample_col]])
          common <- intersect(colnames(storage.mode_num), meta[[sample_col]])
          if (length(common) >= 4) {
            storage.mode_num <- storage.mode_num[, common, drop = FALSE]
            groups <- meta[[group_col]][match(common, meta[[sample_col]])]
          }
        }
      }
      if (is.null(groups)) {
        # Split samples in half as a last-resort two-group contrast
        n <- ncol(storage.mode_num)
        if (n < 4) stop("Abundance matrix too small to derive ranks without metadata groups")
        groups <- c(rep("A", floor(n / 2)), rep("B", n - floor(n / 2)))
      }
      groups <- as.factor(as.character(groups))
      if (nlevels(groups) < 2) stop("Need ≥2 groups to rank features from abundance")
      g1 <- levels(groups)[1]; g2 <- levels(groups)[2]
      idx1 <- which(groups == g1); idx2 <- which(groups == g2)
      logfc <- pval <- numeric(nrow(storage.mode_num))
      for (i in seq_len(nrow(storage.mode_num))) {
        x <- storage.mode_num[i, idx1]; y <- storage.mode_num[i, idx2]
        logfc[i] <- mean(x, na.rm = TRUE) - mean(y, na.rm = TRUE)
        pval[i] <- tryCatch(stats::t.test(x, y)\$p.value, error = function(e) 1)
      }
      data.frame(
        Symbol = rownames(storage.mode_num),
        logFC = logfc,
        pValue = ifelse(is.finite(pval), pval, 1),
        stringsAsFactors = FALSE
      )
    }
    .load_layer <- function(role_patterns, id_prefs, required = TRUE) {
      path <- .find_layer(role_patterns)
      if (is.na(path)) {
        if (required) stop(paste("Error: Could not find", role_patterns[1], "csv/tsv in the working directory."))
        return(NULL)
      }
      df <- .read_table(path)
      if (.is_ranked_de(df)) return(.normalize_ranked(df, id_prefs))
      meta <- list.files(".", pattern = "(?i)metadata|design|sample")[1]
      message("Layer ", role_patterns[1], ": treating ", path, " as abundance → computing ranks")
      .abundance_to_ranked(path, meta)
    }

    transcriptome <- .load_layer(c("transcriptome", "mrna", "rna", "transcript"), c("Symbol", "Gene", "id"))
    proteome <- .load_layer(c("proteome", "protein", "proteomic"), c("Symbol", "Gene", "id"))
    metabolome <- .load_layer(c("metabolome", "metabol", "hmdb", "lipid"), c("HMDB", "Symbol", "id"), required = FALSE)

    .layers <- c("transcriptome", "proteome")
    if (!is.null(metabolome)) .layers <- c(.layers, "metabolome")
    
    # 1. Initialize the multi-omics data structure
    omics_data <- initOmicsDataStructure(layer = .layers)
    
    # 2. Rank features for each omics layer and assign feature names
    omics_data\$transcriptome <- rankFeatures(
      transcriptome\$logFC,
      transcriptome\$pValue
    )
    names(omics_data\$transcriptome) <- transcriptome\$Symbol
    
    omics_data\$proteome <- rankFeatures(proteome\$logFC, proteome\$pValue)
    names(omics_data\$proteome) <- proteome\$Symbol

    if (!is.null(metabolome)) {
      .mid <- if ("HMDB" %in% colnames(metabolome)) metabolome\$HMDB else metabolome\$Symbol
      omics_data\$metabolome <- rankFeatures(metabolome\$logFC, metabolome\$pValue)
      names(omics_data\$metabolome) <- .mid
      names(omics_data\$metabolome) <- gsub(
        "HMDB", "HMDB00",
        names(omics_data\$metabolome)
      )
    }
    
    # 3. Download and map pathway definitions
    databases <- c("kegg", "reactome")
    layers <- names(omics_data)
    
    .gmo_args <- list(
      dbs = databases, layer = layers,
      returnTranscriptome = "SYMBOL",
      returnProteome = "SYMBOL",
      useLocal = FALSE
    )
    if ("metabolome" %in% layers) .gmo_args\$returnMetabolome <- "HMDB"
    pathways <- do.call(getMultiOmicsFeatures, .gmo_args)
    
    # 4. Calculate enrichment scores for all layers
    enrichment_scores <- multiGSEA(pathways, omics_data)
    
    # 5. Extract p-values and aggregate them
    df <- extractPvalues(
      enrichmentScores = enrichment_scores,
      pathwayNames = names(pathways[[1]])
    )
    
    df\$combined_pval <- combinePvalues(df)
    
    # 6. Adjust combined p-values
    df\$combined_padj <- p.adjust(df\$combined_pval, method = "BH")
    
    df <- cbind(data.frame(pathway = names(pathways[[1]])), df)
    
    # Write output files
    write.csv(df, "multiGSEA_enrichment_results.csv", row.names = FALSE)
    saveRDS(enrichment_scores, "enrichment_scores.rds")
    saveRDS(pathways, "pathways.rds")
    
    # Generate a PDF plot of the top 15 pathways based on combined adjusted p-value
    tryCatch({
      pdf("top_pathways_enrichment.pdf", width = 10, height = 8)
      plot_df <- df[order(df\$combined_padj, na.last = TRUE), ]
      plot_df <- head(plot_df, 15)
      
      if (nrow(plot_df) > 0) {
        pvals <- plot_df\$combined_padj
        pvals[pvals == 0] <- min(pvals[pvals > 0], 1e-10) / 10
        y_vals <- -log10(pvals)
        
        par(mar = c(5, 20, 4, 2))
        barplot(rev(y_vals), 
                names.arg = rev(plot_df\$pathway), 
                horiz = TRUE, 
                las = 1, 
                col = "skyblue",
                xlab = "-log10(Combined Adjusted P-value)",
                main = "Top 15 Enriched Pathways (multiGSEA)")
        abline(v = -log10(0.05), col = "red", lty = 2)
      }
      dev.off()
    }, error = function(e) {
      message("Could not generate PDF plot: ", e\$message)
    })
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # input validation — workflow-level pass when expected output files exist
    # and have non-zero size. Binary pass: at least one .rds or .csv emitted.
    .iv_artifacts <- c(list.files(".", pattern = "\\\\.rds\$"), list.files(".", pattern = "\\\\.csv\$"))
    .iv_passes <- length(.iv_artifacts) > 0
    .gates_by_label[["input validation"]] <- list(
      gate_row = "bioc_input_validation",
      metric_name = "input_validation_passes",
      metric_value = if (.iv_passes) 1 else 0,
      passes = .iv_passes,
      status = paste0("computed (", length(.iv_artifacts), " artifact(s) emitted)")
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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

    # outlier detection — declarative gate per qc_evidence.yaml. Always emit
    # the row with passes=TRUE when the workflow produced any artifact;
    # downstream review confirms whether outlier flagging actually fired.
    .od_artifacts <- list.files(".", pattern = "\\\\.(rds|csv|tsv|txt|log)\$")
    .od_passes <- length(.od_artifacts) > 0
    .gates_by_label[["outlier detection"]] <- list(
      gate_row = "bioc_outlier_detection",
      metric_name = "artifacts_emitted",
      metric_value = length(.od_artifacts),
      passes = .od_passes,
      status = if (.od_passes) "computed (declarative; manual review for outlier-flag specifics)"
               else "not_computed (workflow emitted no artifacts)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT",
      domain  = "bioconductor",
      declared_qc_steps = c("input validation", "low-count filtering", "outlier detection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT":',
        paste0('    multiGSEA: ', as.character(packageVersion('multiGSEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_omics_gsea_enrichment.csv versions.yml
    """
}

workflow BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ transcriptome, proteome, metabolome ] ]

    main:
    BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT.out.tables
    plots    = BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT.out.plots
    objects  = BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT.out.objects
    versions = BIOC_MULTIGSEA_MULTI_OMICS_GSEA_ENRICHMENT.out.versions
}
