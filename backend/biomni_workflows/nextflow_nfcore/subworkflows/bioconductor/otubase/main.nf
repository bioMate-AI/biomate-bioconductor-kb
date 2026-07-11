#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: otubase — otu_based_analysis
// Import Mothur OTU files and metadata, generate an abundance table, estimate richness, cluster samples, and subset the dataset.
// Input: sogin.groups, sogin.unique.filter.fn.list, sample_metadata.txt, sogin.fasta
// Container: quay.io/biocontainers/bioconductor-otubase:1.60.0--r45hdfd78af_0
// R packages: OTUbase, vegan
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: cluster plot

nextflow.enable.dsl = 2

process BIOC_OTUBASE_OTU_BASED_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-otubase:1.60.0--r45hdfd78af_0"

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
    .bm_deps <- c("OTUbase", "vegan")
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
    library(OTUbase)
    library(vegan)
    
    # --- Define directory path (working directory where user files ---
    dirPath <- "."
    
    # --- Read OTU data and metadata using readOTUset ---
    soginOTU <- readOTUset(
      dirPath = dirPath,
      level = "0.03",
      samplefile = "sogin.groups",
      fastafile = "sogin.fasta",
      otufile = "sogin.unique.filter.fn.list",
      sampleADF = "sample_metadata.txt"
    )
    
    # Print object summary
    print(soginOTU)
    
    # --- Access sequence and sample IDs ---
    cat("--- Sequence IDs ---\n")
    print(head(id(soginOTU)))
    
    cat("--- Sequences ---\n")
    print(head(sread(soginOTU)))
    
    cat("--- Sample IDs ---\n")
    print(head(sampleID(soginOTU)))
    
    cat("--- Sample Metadata ---\n")
    print(head(sData(soginOTU)))
    
    cat("--- OTU IDs ---\n")
    print(head(otuID(soginOTU)))
    
    # --- Generate OTU abundance table ---
    abundOTU <- abundance(soginOTU, weighted = FALSE, collab = 'Site')
    cat("--- Abundance Table ---\n")
    print(head(abundOTU))
    
    # Save abundance table to CSV
    write.csv(abundOTU, file = "abundance_table.csv", row.names = TRUE)
    
    # --- Estimate richness using vegan::estimateR ---
    estrichOTU <- apply(abundOTU, 2, estimateR)
    cat("--- Richness Estimates ---\n")
    print(estrichOTU)
    
    # Save richness estimates to CSV
    write.csv(estrichOTU, file = "richness_estimates.csv", row.names = TRUE)
    
    # --- Cluster samples (plots a dendrogram, save to PDF) ---
    pdf("sample_clustering.pdf", width = 8, height = 6)
    clusterSamples(soginOTU, distmethod = 'jaccard', clustermethod = 'complete', collab = 'Site')
    dev.off()
    
    # --- Subset the OTU set ---
    # Wrapped in tryCatch to handle cases where user-provided metadata/groups 
    # might not contain these exact sample IDs.
    tryCatch({
      soginReduced <- subOTUset(soginOTU, samples = c("137", "138", "53R", "55R"))
      print(soginReduced)
      saveRDS(soginReduced, file = "sogin_reduced.rds")
    }, error = function(e) {
      warning("Could not subset OTU set with the specified sample IDs: ", e\$message)
    })
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # microbiome prevalence/abundance filtering (Callahan 2017 F1000).
    .pa_kept <- NA_real_
    for (.pa_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .pa_obj <- tryCatch(readRDS(.pa_rds), error = function(e) NULL)
      .pa_mat <- if (is.matrix(.pa_obj) || is.data.frame(.pa_obj)) .pa_obj else NULL
      if (!is.null(.pa_mat) && nrow(.pa_mat) > 50) {
        .pa_m <- suppressWarnings(as.matrix(.pa_mat))
        .pa_prev <- suppressWarnings(apply(.pa_m, 1, function(r) mean(as.numeric(r) > 0, na.rm = TRUE)))
        .pa_kept <- sum(is.finite(.pa_prev) & .pa_prev >= 0.05) / nrow(.pa_m); break
      }
    }
    .gates_by_label[["prevalence/abundance filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "taxa_kept_fraction",
      metric_value = if (is.finite(.pa_kept)) round(.pa_kept, 4) else NA_real_,
      passes = isTRUE(is.finite(.pa_kept) && .pa_kept >= 0.3 && .pa_kept <= 0.7),
      status = if (is.finite(.pa_kept)) "computed (rows w/ >=5% prevalence / total)"
               else "not_computed (no abundance matrix .rds artifact present)"
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
      process = "BIOC_OTUBASE_OTU_BASED_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("prevalence/abundance filtering", "count normalization", "diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_OTUBASE_OTU_BASED_ANALYSIS":',
        paste0('        otubase: ', as.character(packageVersion("otubase")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_otu_based_analysis.csv versions.yml
    """
}

workflow BIOC_OTUBASE_OTU_BASED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sogin.groups, sogin.unique.filter.fn.list, sample_metadata.txt, sogin.fasta ] ]

    main:
    BIOC_OTUBASE_OTU_BASED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_OTUBASE_OTU_BASED_ANALYSIS.out.tables
    plots    = BIOC_OTUBASE_OTU_BASED_ANALYSIS.out.plots
    objects  = BIOC_OTUBASE_OTU_BASED_ANALYSIS.out.objects
    versions = BIOC_OTUBASE_OTU_BASED_ANALYSIS.out.versions
}
