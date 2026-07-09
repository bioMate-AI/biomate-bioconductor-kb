#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MIRit — paired_integration_workflow
// Perform differential expression, functional enrichment, target retrieval, and correlation-based integration for paired miRNA and gene expression data.
// Input: geneCounts, mirnaCounts, meta
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: ggpubr, MIRit
// Bioconductor: 3.20 | R: 4.4
// Requires: MIRit, ggpubr
// Visualizations: volcano plot, correlation plot, MDS plot, bar plot, dot plot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load expression matrices and prepare metadata
//  * 2. [Input & Preparation] Create a MirnaExperiment object
//  * 3. [Visualization & Output] Visualize expression variability using MDS plots
//  * 4. [Core Analysis] Perform differential expression for genes and miRNAs
//  * 5. [Visualization & Output] Access and visualize differential expression results
//  * 6. [Core Analysis] Perform functional enrichment analysis (ORA and GSEA)
//  * 7. [Core Analysis] Retrieve predicted and validated miRNA targets
//  * 8. [Core Analysis] Perform correlation-based integration
//  * 9. [Visualization & Output] Extract and visualize integrated miRNA-target pairs

nextflow.enable.dsl = 2

process BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW {
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
    .bm_deps <- c("ggpubr", "MIRit")
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
        library(MIRit)
        library(ggpubr)
        
        # Helper function to read user input files robustly (supporting RDS, CSV, TSV, TXT)
        read_input <- function(base_name) {
          rds_path <- paste0(base_name, ".rds")
          csv_path <- paste0(base_name, ".csv")
          tsv_path <- paste0(base_name, ".tsv")
          txt_path <- paste0(base_name, ".txt")
        
          if (file.exists(rds_path)) {
            return(readRDS(rds_path))
          } else if (file.exists(csv_path)) {
            if (base_name == "meta") {
              return(read.csv(csv_path, check.names = FALSE))
            }
            return(as.matrix(read.csv(csv_path, row.names = 1, check.names = FALSE)))
          } else if (file.exists(tsv_path)) {
            if (base_name == "meta") {
              return(read.delim(tsv_path, check.names = FALSE))
            }
            return(as.matrix(read.delim(tsv_path, row.names = 1, check.names = FALSE)))
          } else if (file.exists(txt_path)) {
            if (base_name == "meta") {
              return(read.table(txt_path, header = TRUE, check.names = FALSE))
            }
            return(as.matrix(read.table(txt_path, header = TRUE, row.names = 1, check.names = FALSE)))
          } else {
            stop(paste("Required input file not found for:", base_name))
          }
        }
        
        # 1. Load expression matrices and prepare metadata
        geneCounts <- read_input("geneCounts")
        mirnaCounts <- read_input("mirnaCounts")
        meta <- read_input("meta")
        
        # Align metadata columns to match the documented code's expectations
        if ("condition" %in% colnames(meta) && !"disease" %in% colnames(meta)) {
          meta\$disease <- meta\$condition
        }
        
        # Dynamically determine the contrast from the actual condition levels
        unique_diseases <- unique(meta\$disease)
        if (length(unique_diseases) < 2) {
          stop("At least two conditions are required in the metadata.")
        }
        contrast_str <- paste0(unique_diseases[1], "-", unique_diseases[2])
        
        # Ensure patient column exists for the paired design formula (~ disease + patient)
        if (!"patient" %in% colnames(meta)) {
          n_samples <- nrow(meta)
          meta\$patient <- paste0("Sample_", rep(seq_len(n_samples / 2), length.out = n_samples))
        }
        
        # 2. Create a MirnaExperiment object
        experiment <- MirnaExperiment(mirnaExpr = mirnaCounts,
                                      geneExpr = geneCounts,
                                      samplesMetadata = meta,
                                      pairedSamples = TRUE)
        
        # 3. Visualize expression variability using MDS plots
        pdf("mds_plots.pdf", width = 10, height = 5)
        geneMDS <- plotDimensions(experiment,
                                  assay = "genes",
                                  condition = "disease",
                                  title = "MDS plot for genes")
        mirnaMDS <- plotDimensions(experiment,
                                   assay = "microRNA",
                                   condition = "disease",
                                   title = "MDS plot for miRNAs")
        print(ggpubr::ggarrange(geneMDS, mirnaMDS,
                          nrow = 1, labels = "AUTO", common.legend = TRUE))
        dev.off()
        
        # 4. Perform differential expression for genes and miRNAs
        model <- ~ disease + patient
        experiment <- performGeneDE(experiment,
                                    group = "disease",
                                    contrast = contrast_str,
                                    design = model,
                                    pCutoff = 0.01)
        experiment <- performMirnaDE(experiment,
                                     group = "disease",
                                     contrast = contrast_str,
                                     design = model,
                                     pCutoff = 0.01)
        
        # 5. Access and visualize differential expression results
        deGenes <- geneDE(experiment)
        deMirnas <- mirnaDE(experiment)
        
        write.csv(deGenes, "de_genes.csv", row.names = TRUE)
        write.csv(deMirnas, "de_mirnas.csv", row.names = TRUE)
        
        pdf("volcano_plots.pdf", width = 10, height = 5)
        geneVolcano <- plotVolcano(experiment,
                                   assay = "genes",
                                   title = "Gene differential expression")
        mirnaVolcano <- plotVolcano(experiment,
                                    assay = "microRNA",
                                    title = "miRNA differential expression")
        print(ggpubr::ggarrange(geneVolcano, mirnaVolcano,
                          nrow = 1, labels = "AUTO", common.legend = TRUE))
        dev.off()
        
        # Dynamically plot top differentially expressed genes instead of hardcoded features
        if (nrow(deGenes) > 0) {
          top_genes <- rownames(deGenes)[seq_len(min(4, nrow(deGenes)))]
          pdf("de_barplot.pdf", width = 8, height = 6)
          print(plotDE(experiment,
                 features = top_genes,
                 graph = "barplot", linear = FALSE))
          dev.off()
        }
        
        # 6. Perform functional enrichment analysis (ORA and GSEA)
        supportedOrganisms("Reactome")
        
        # Wrap enrichment in tryCatch to handle potential offline/API issues gracefully
        tryCatch({
          ora <- enrichGenes(experiment,
                             method = "ORA",
                             database = "GO",
                             organism = "Homo sapiens")
          
          pdf("ora_dotplot.pdf", width = 8, height = 6)
          print(enrichmentDotplot(ora\$downregulated, title = "Depleted functions"))
          dev.off()
        }, error = function(e) {
          message("ORA enrichment failed: ", e\$message)
        })
        
        tryCatch({
          set.seed(1234)
          gse <- enrichGenes(experiment,
                             method = "GSEA",
                             database = "KEGG",
                             organism = "Homo sapiens")
          
          gse_res <- enrichmentResults(gse)
          write.csv(gse_res, "gsea_results.csv", row.names = FALSE)
          
          # Dynamically plot the top enriched pathway instead of a hardcoded one
          if (nrow(gse_res) > 0) {
            top_pathway <- gse_res\$pathway[1]
            pdf("gsea_plot.pdf", width = 8, height = 6)
            print(gseaPlot(gse, top_pathway, rankingMetric = TRUE))
            dev.off()
          }
        }, error = function(e) {
          message("GSEA enrichment failed: ", e\$message)
        })
        
        # 7. Retrieve predicted and validated miRNA targets & 8. Perform correlation-based integration
        tryCatch({
          experiment <- getTargets(experiment)
          experiment <- mirnaIntegration(experiment, test = "correlation")
          partial <- mirnaIntegration(experiment, test = "correlation",
                                      partial = TRUE, pCutoff = 1)
          
          # 9. Extract and visualize integrated miRNA-target pairs
          integrationResults <- integration(experiment)
          write.csv(integrationResults, "integration_results.csv", row.names = FALSE)
          print(head(integrationResults))
          
          # Dynamically plot top correlated pairs instead of hardcoded features
          if (nrow(integrationResults) > 0) {
            pdf("correlation_plots.pdf", width = 10, height = 5)
            
            pair1_mirna <- integrationResults\$microRNA[1]
            pair1_gene <- integrationResults\$Target[1]
            cor1 <- plotCorrelation(experiment,
                                    mirna = pair1_mirna,
                                    gene = pair1_gene,
                                    condition = "disease")
            
            if (nrow(integrationResults) > 1) {
              pair2_mirna <- integrationResults\$microRNA[2]
              pair2_gene <- integrationResults\$Target[2]
              cor2 <- plotCorrelation(experiment,
                                      mirna = pair2_mirna,
                                      gene = pair2_gene,
                                      condition = "disease")
              print(ggpubr::ggarrange(cor1, cor2, nrow = 1,
                                labels = "AUTO", common.legend = TRUE))
            } else {
              print(cor1)
            }
            dev.off()
          }
        }, error = function(e) {
          message("Target retrieval or integration failed (possibly due to offline environment or API limits): ", e\$message)
        })
        
        # Save the final experiment object
        saveRDS(experiment, "mirna_experiment.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW":',
        paste0('    MIRit: ', as.character(packageVersion('MIRit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paired_integration_workflow.csv versions.yml
    """
}

workflow BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneCounts, mirnaCounts, meta ] ]

    main:
    BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW.out.tables
    plots    = BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW.out.plots
    objects  = BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW.out.objects
    versions = BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW.out.versions
}
