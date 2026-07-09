#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RankProd — metabolomics_rank_sum
// Identify differentially expressed metabolites from LC/MS data using the Rank Sum method.
// Input: metabolite_intensity_matrix.tsv, class_labels.txt
// Container: quay.io/biocontainers/bioconductor-rankprod:3.36.0--r45hdfd78af_0
// R packages: RankProd, vsn
// Bioconductor: 3.20 | R: 4.4
// Requires: RankProd, vsn
// Visualizations: plot (ggplot/base)
// QC: variance-stabilizing normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize and stabilize variance of the intensity matrix (e.g., using vsn)
//  * 2. [Core Analysis] Run RankProducts with calculateProduct=FALSE to perform Rank Sum analysis
//  * 3. [Core Analysis] Extract significant metabolites using topGene

nextflow.enable.dsl = 2

process BIOC_RANKPROD_METABOLOMICS_RANK_SUM {
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
    .bm_deps <- c("RankProd", "vsn")
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
    library(RankProd)
    library(vsn)
    
    # 1. Read User Input Files
    if (!file.exists("metabolite_intensity_matrix.tsv")) {
      stop("Error: 'metabolite_intensity_matrix.tsv' not found in the working directory.")
    }
    if (!file.exists("class_labels.txt")) {
      stop("Error: 'class_labels.txt' not found in the working directory.")
    }
    
    # Read the basepeak intensity matrix (metabolites as rows, samples as columns)
    apples.data <- as.matrix(read.delim("metabolite_intensity_matrix.tsv", row.names = 1, header = TRUE, check.names = FALSE))
    
    # Read the class labels vector
    apples.cl <- as.numeric(scan("class_labels.txt", quiet = TRUE))
    
    # Validate that the number of class labels matches the number of samples (columns)
    if (length(apples.cl) != ncol(apples.data)) {
      stop(paste("Error: Number of class labels (", length(apples.cl), 
                 ") does not match the number of columns in the intensity matrix (", ncol(apples.data), ").", sep=""))
    }
    
    # 2. Normalize and stabilize variance of the intensity matrix using vsn
    apples.data.exp <- vsn(apples.data)
    apples.data.vsn <- exprs(apples.data.exp)
    
    # 3. Run RankProducts with calculateProduct=FALSE to perform Rank Sum analysis
    # (Reproducing the documented code faithfully)
    RS.apples<-RankProducts(apples.data.vsn, apples.cl,
                            gene.names = rownames(apples.data.vsn), 
                            calculateProduct = FALSE, rand=123)
    
    # 4. Extract significant metabolites using topGene
    # (Reproducing the documented code faithfully)
    RS.tables <- topGene(RS.apples,cutoff = 0.05, method = "pfp",
                         gene.names = rownames(apples.data.vsn))
    
    selected <- which(RS.apples\$pfp[,1]<= 0.05)
    
    # 5. Write meaningful output files
    # Save the complete Rank Sum analysis object
    saveRDS(RS.apples, file = "rank_sum_results.rds")
    
    # Save tables of significant metabolites
    if (!is.null(RS.tables\$Table1)) {
      write.csv(RS.tables\$Table1, file = "significant_metabolites_up.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Message="No significant up-regulated metabolites found"), file = "significant_metabolites_up.csv", row.names = FALSE)
    }
    
    if (!is.null(RS.tables\$Table2)) {
      write.csv(RS.tables\$Table2, file = "significant_metabolites_down.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Message="No significant down-regulated metabolites found"), file = "significant_metabolites_down.csv", row.names = FALSE)
    }
    
    # Save the names of selected metabolites
    selected_names <- rownames(apples.data.vsn)[selected]
    writeLines(selected_names, con = "selected_metabolites.txt")
    
    # Generate and save diagnostic plots
    pdf("rank_sum_plots.pdf", width = 8, height = 8)
    tryCatch({
      plotRP(RS.apples, cutoff = 0.05)
    }, error = function(e) {
      warning("Could not generate the plot: ", e\$message)
    })
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to 'rank_sum_results.rds', 'significant_metabolites_up.csv', 'significant_metabolites_down.csv', 'selected_metabolites.txt', and 'rank_sum_plots.pdf'.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # VSN — DESeqTransform / vsd matrix; mean-SD slope ≤ 0.5 (vsn::meanSdPlot).
    .vsn_slope <- NA_real_
    for (.vsn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .vsn_obj <- tryCatch(readRDS(.vsn_rds), error = function(e) NULL)
      .vsn_mat <- NULL
      if (!is.null(.vsn_obj)) {
        if (inherits(.vsn_obj, "DESeqTransform") || inherits(.vsn_obj, "SummarizedExperiment")) {
          .vsn_mat <- tryCatch(assay(.vsn_obj), error = function(e) NULL)
        } else if (is.matrix(.vsn_obj)) { .vsn_mat <- .vsn_obj }
      }
      if (!is.null(.vsn_mat) && nrow(.vsn_mat) > 100) {
        .vsn_rmean <- suppressWarnings(rowMeans(.vsn_mat, na.rm = TRUE))
        .vsn_rsd <- suppressWarnings(apply(.vsn_mat, 1, sd, na.rm = TRUE))
        .vsn_ok <- is.finite(.vsn_rmean) & is.finite(.vsn_rsd)
        if (sum(.vsn_ok) > 50) {
          .vsn_fit <- tryCatch(lm(.vsn_rsd[.vsn_ok] ~ .vsn_rmean[.vsn_ok]), error = function(e) NULL)
          if (!is.null(.vsn_fit)) { .vsn_slope <- round(abs(coef(.vsn_fit)[2]), 4); break }
        }
      }
    }
    .gates_by_label[["variance-stabilizing normalization"]] <- list(
      gate_row = "bioc_vsn_normalization",
      metric_name = "mean_sd_slope_after_vsn",
      metric_value = .vsn_slope,
      passes = isTRUE(is.finite(.vsn_slope) && .vsn_slope <= 0.5),
      status = if (is.finite(.vsn_slope)) "computed (lm slope row-SD ~ row-mean)"
               else "not_computed (no DESeqTransform/vsd .rds present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_RANKPROD_METABOLOMICS_RANK_SUM",
      domain  = "bioconductor",
      declared_qc_steps = c("variance-stabilizing normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RANKPROD_METABOLOMICS_RANK_SUM":',
        paste0('    RankProd: ', as.character(packageVersion('RankProd')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metabolomics_rank_sum.csv versions.yml
    """
}

workflow BIOC_RANKPROD_METABOLOMICS_RANK_SUM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metabolite_intensity_matrix.tsv, class_labels.txt ] ]

    main:
    BIOC_RANKPROD_METABOLOMICS_RANK_SUM(ch_input)

    emit:
    tables   = BIOC_RANKPROD_METABOLOMICS_RANK_SUM.out.tables
    plots    = BIOC_RANKPROD_METABOLOMICS_RANK_SUM.out.plots
    objects  = BIOC_RANKPROD_METABOLOMICS_RANK_SUM.out.objects
    versions = BIOC_RANKPROD_METABOLOMICS_RANK_SUM.out.versions
}
